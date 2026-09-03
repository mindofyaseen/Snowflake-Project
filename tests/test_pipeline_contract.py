from __future__ import annotations

"""
test_pipeline_contract.py
~~~~~~~~~~~~~~~~~~~~~~~~~
Credential-free contract and behavioral tests for the CareMatch pipeline.

Covers:
1. Generator nurse counts: 500 initial, 550 incremental.
2. Production batch-ID and S3 key functions (imported from src.generate_healthcare_data).
3. Snowflake idempotent load contract (FORCE regex, COPY INTO presence).
4. dbt deduplication contract (QUALIFY, ROW_NUMBER, PARTITION BY nurse_id, ORDER BY DESC).
5. dbt source uniqueness and credential-free dbt parse validation.
6. Fivetran behavioral API tests (success, failure, timeout, transient error, missing vars, paused state).
7. Hightouch behavioral API tests (success, failure, timeout, transient error, missing vars, request not found, cancelled).
"""

import csv
import os
import pathlib
import re
import subprocess
import tempfile
import unittest
import urllib.error
from datetime import date
from typing import Any, Dict, List, Optional
from unittest.mock import MagicMock

ROOT = pathlib.Path(__file__).resolve().parents[1]

# Import actual production functions
from src.generate_healthcare_data import (
    build_s3_raw_key,
    generate,
    sanitize_batch_id,
)
from scripts.saas_sync import sync_fivetran, sync_hightouch


class InitialLoad500NursesTest(unittest.TestCase):
    def test_initial_load_produces_500_nurses(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = generate(
                root=pathlib.Path(tmp),
                seed=20260821,
                load_date=date(2026, 8, 21),
                nurse_count=500,
                facility_count=40,
                shift_count=3000,
            )
        nurse_file_entry = next(
            e for e in manifest["files"]
            if "entity=nurses" in e["object_key"] and e["object_key"].endswith(".csv")
        )
        self.assertEqual(nurse_file_entry["rows"], 500)


class IncrementalLoad550NursesTest(unittest.TestCase):
    def test_incremental_load_produces_550_nurses(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = generate(
                root=pathlib.Path(tmp),
                seed=20260822550,
                load_date=date(2026, 8, 22),
                nurse_count=550,
                facility_count=40,
                shift_count=3000,
            )
        nurse_file_entry = next(
            e for e in manifest["files"]
            if "entity=nurses" in e["object_key"] and e["object_key"].endswith(".csv")
        )
        self.assertEqual(nurse_file_entry["rows"], 550)

    def test_incremental_nurses_have_distinct_ids(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            generate(
                root=root,
                seed=20260822550,
                load_date=date(2026, 8, 22),
                nurse_count=550,
                facility_count=40,
                shift_count=3000,
            )
            nurse_path = next(root.glob("source=operational/entity=nurses/**/*.csv"))
            with nurse_path.open(newline="", encoding="utf-8") as fh:
                nurse_ids = [row["nurse_id"] for row in csv.DictReader(fh)]
        self.assertEqual(len(nurse_ids), 550)
        self.assertEqual(len(nurse_ids), len(set(nurse_ids)))


class ProductionBatchAndKeyTest(unittest.TestCase):
    """Verifies the actual production functions in src.generate_healthcare_data."""

    def test_sanitize_batch_id_uniqueness(self) -> None:
        run_a = "carematch_initial_20260821T120000Z"
        run_b = "carematch_initial_20260821T130000Z"
        batch_a = sanitize_batch_id(run_a)
        batch_b = sanitize_batch_id(run_b)
        self.assertNotEqual(batch_a, batch_b)
        self.assertEqual(batch_a, "carematch_initial_20260821T120000Z")

    def test_sanitize_batch_id_strips_unsafe_characters(self) -> None:
        dirty_run_id = "run!@#$123/456:789"
        sanitized = sanitize_batch_id(dirty_run_id)
        self.assertEqual(sanitized, "run_123_456_789")
        self.assertRegex(sanitized, r"^[A-Za-z0-9_-]+$")

    def test_build_s3_raw_key_structure(self) -> None:
        rel_key = "source=operational/entity=nurses/load_date=2026-08-21/nurses.csv"
        batch_id = "carematch_batch_001"
        s3_key = build_s3_raw_key(rel_key, batch_id)
        expected = "raw/source=operational/entity=nurses/load_date=2026-08-21/batch_id=carematch_batch_001/nurses.csv"
        self.assertEqual(s3_key, expected)


class SnowflakeIdempotentLoadTest(unittest.TestCase):
    def test_load_sql_has_no_force_true(self) -> None:
        sql = (ROOT / "snowflake/sql/02_s3_stage_and_raw_load.sql").read_text(encoding="utf-8")
        match = re.search(r"FORCE\s*=\s*TRUE", sql, re.IGNORECASE)
        self.assertIsNone(
            match,
            f"COPY INTO must not specify FORCE = TRUE. Found: '{match.group(0) if match else ''}'",
        )

    def test_force_regex_detects_various_spacings(self) -> None:
        cases = [
            "FORCE=TRUE",
            "force = true",
            "FORCE  =  TRUE",
            "Force\t=\tTrue",
            "force\n=\ntrue",
        ]
        pattern = re.compile(r"FORCE\s*=\s*TRUE", re.IGNORECASE)
        for case in cases:
            self.assertIsNotNone(pattern.search(case), f"Regex must match '{case}'")

    def test_load_sql_uses_copy_into(self) -> None:
        sql = (ROOT / "snowflake/sql/02_s3_stage_and_raw_load.sql").read_text(encoding="utf-8").upper()
        self.assertIn("COPY INTO", sql)


class DbtDeduplicationContractTest(unittest.TestCase):
    def _stg_nurses(self) -> str:
        return (ROOT / "dbt/models/staging/stg_nurses.sql").read_text(encoding="utf-8").lower()

    def test_qualify_row_number_present(self) -> None:
        sql = self._stg_nurses()
        self.assertIn("qualify", sql)
        self.assertIn("row_number()", sql)

    def test_partitioned_by_nurse_id(self) -> None:
        self.assertIn("partition by nurse_id", self._stg_nurses())

    def test_orders_by_record_updated_at_desc(self) -> None:
        self.assertIn("order by record_updated_at desc", self._stg_nurses())

    def test_canonical_sources_yml_declares_nurses_table(self) -> None:
        sources_file = ROOT / "dbt/models/sources.yml"
        self.assertTrue(sources_file.exists(), "dbt/models/sources.yml must exist")
        content = sources_file.read_text(encoding="utf-8")
        self.assertIn("name: nurses", content)
        self.assertIn("name: raw", content)


class DbtSourceUniquenessAndParseTest(unittest.TestCase):
    def _extract_source_tables(self, yaml_content: str) -> List[tuple[str, str]]:
        # Regex extraction to avoid pyyaml requirement if not installed
        source_blocks = re.findall(r"-\s*name:\s*([A-Za-z0-9_]+)[\s\S]*?tables:([\s\S]*?)(?=(?:-\s*name:|\Z))", yaml_content)
        results = []
        for src_name, tables_block in source_blocks:
            tables = re.findall(r"-\s*name:\s*([A-Za-z0-9_]+)", tables_block)
            for tbl in tables:
                results.append((src_name.lower(), tbl.lower()))
        return results

    def test_no_duplicate_sources_across_project(self) -> None:
        models_dir = ROOT / "dbt/models"
        all_sources: List[tuple[str, str, str]] = []
        for yml_path in models_dir.rglob("*.yml"):
            tables = self._extract_source_tables(yml_path.read_text(encoding="utf-8"))
            for src, tbl in tables:
                all_sources.append((src, tbl, str(yml_path.relative_to(ROOT))))

        seen: Dict[tuple[str, str], str] = {}
        duplicates = []
        for src, tbl, path in all_sources:
            key = (src, tbl)
            if key in seen:
                duplicates.append(f"{src}.{tbl} in both '{seen[key]}' and '{path}'")
            seen[key] = path

        self.assertEqual(
            duplicates,
            [],
            f"Duplicate dbt sources detected across project: {duplicates}",
        )

    def test_dbt_parse_validates_project_without_credentials(self) -> None:
        temp_profiles = """
carematch:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: dummy_account
      user: dummy_user
      password: dummy_password
      role: dummy_role
      database: CAREMATCH
      warehouse: dummy_wh
      schema: ANALYTICS
      threads: 1
"""
        with tempfile.TemporaryDirectory() as tmpdir:
            p = pathlib.Path(tmpdir) / "profiles.yml"
            p.write_text(temp_profiles, encoding="utf-8")
            res = subprocess.run(
                ["dbt", "--no-version-check", "parse", "--project-dir", str(ROOT / "dbt"), "--profiles-dir", tmpdir],
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                res.returncode,
                0,
                f"dbt parse failed with returncode {res.returncode}.\nSTDOUT: {res.stdout}\nSTDERR: {res.stderr}",
            )


class FivetranSyncBehavioralTest(unittest.TestCase):
    def test_missing_environment_variables(self) -> None:
        with self.assertRaises(ValueError) as ctx:
            sync_fivetran(api_key=None, api_secret=None, connector_id=None)
        self.assertIn("FIVETRAN_APIKEY", str(ctx.exception))
        self.assertIn("FIVETRAN_APISECRET", str(ctx.exception))
        self.assertIn("FIVETRAN_CONNECTOR_ID", str(ctx.exception))

    def test_successful_completion(self) -> None:
        call_count = 0

        def mock_request(url: str, data: Optional[bytes], headers: Dict[str, str]) -> Dict[str, Any]:
            nonlocal call_count
            call_count += 1
            if "/force" in url:
                return {"code": "Success"}
            if call_count == 1:
                # Baseline check
                return {"data": {"status": {"succeeded_at": "2026-08-30T10:00:00Z", "failed_at": None, "sync_state": "scheduled"}}}
            else:
                # Poll check: succeeded_at advanced
                return {"data": {"status": {"succeeded_at": "2026-08-30T10:05:00Z", "failed_at": None, "sync_state": "scheduled"}}}

        simulated_time = 0.0

        def mock_time() -> float:
            return simulated_time

        def mock_sleep(seconds: float) -> None:
            nonlocal simulated_time
            simulated_time += seconds

        res = sync_fivetran(
            api_key="k", api_secret="s", connector_id="conn_1",
            timeout_seconds=60, poll_interval_seconds=5,
            time_fn=mock_time, sleep_fn=mock_sleep, request_fn=mock_request,
        )
        self.assertEqual(res["status"], "success")
        self.assertEqual(res["succeeded_at"], "2026-08-30T10:05:00Z")

    def test_remote_failure(self) -> None:
        call_count = 0

        def mock_request(url: str, data: Optional[bytes], headers: Dict[str, str]) -> Dict[str, Any]:
            nonlocal call_count
            call_count += 1
            if "/force" in url:
                return {"code": "Success"}
            if call_count == 1:
                return {"data": {"status": {"succeeded_at": "2026-08-30T10:00:00Z", "failed_at": None, "sync_state": "scheduled"}}}
            else:
                return {"data": {"status": {"succeeded_at": "2026-08-30T10:00:00Z", "failed_at": "2026-08-30T10:02:00Z", "sync_state": "failed"}}}

        simulated_time = 0.0

        def mock_time() -> float:
            return simulated_time

        def mock_sleep(seconds: float) -> None:
            nonlocal simulated_time
            simulated_time += seconds

        with self.assertRaises(RuntimeError) as ctx:
            sync_fivetran(
                api_key="k", api_secret="s", connector_id="conn_1",
                timeout_seconds=60, poll_interval_seconds=5,
                time_fn=mock_time, sleep_fn=mock_sleep, request_fn=mock_request,
            )
        self.assertIn("Fivetran sync failed at 2026-08-30T10:02:00Z", str(ctx.exception))

    def test_timeout(self) -> None:
        def mock_request(url: str, data: Optional[bytes], headers: Dict[str, str]) -> Dict[str, Any]:
            return {"data": {"status": {"succeeded_at": "2026-08-30T10:00:00Z", "failed_at": None, "sync_state": "syncing"}}}

        simulated_time = 0.0

        def mock_time() -> float:
            return simulated_time

        def mock_sleep(seconds: float) -> None:
            nonlocal simulated_time
            simulated_time += seconds

        with self.assertRaises(TimeoutError):
            sync_fivetran(
                api_key="k", api_secret="s", connector_id="conn_1",
                timeout_seconds=30, poll_interval_seconds=10,
                time_fn=mock_time, sleep_fn=mock_sleep, request_fn=mock_request,
            )

    def test_transient_polling_error(self) -> None:
        call_count = 0

        def mock_request(url: str, data: Optional[bytes], headers: Dict[str, str]) -> Dict[str, Any]:
            nonlocal call_count
            call_count += 1
            if "/force" in url:
                return {"code": "Success"}
            if call_count == 1:
                return {"data": {"status": {"succeeded_at": "2026-08-30T10:00:00Z", "failed_at": None}}}
            elif call_count == 3:  # First poll after trigger
                raise urllib.error.URLError("Network glitch")
            else:  # Second poll after trigger
                return {"data": {"status": {"succeeded_at": "2026-08-30T10:05:00Z", "failed_at": None}}}

        simulated_time = 0.0

        def mock_time() -> float:
            return simulated_time

        def mock_sleep(seconds: float) -> None:
            nonlocal simulated_time
            simulated_time += seconds

        res = sync_fivetran(
            api_key="k", api_secret="s", connector_id="conn_1",
            timeout_seconds=60, poll_interval_seconds=5,
            time_fn=mock_time, sleep_fn=mock_sleep, request_fn=mock_request,
        )
        self.assertEqual(res["status"], "success")

    def test_paused_state_raises_immediately(self) -> None:
        call_count = 0

        def mock_request(url: str, data: Optional[bytes], headers: Dict[str, str]) -> Dict[str, Any]:
            nonlocal call_count
            call_count += 1
            if "/force" in url:
                return {"code": "Success"}
            if call_count == 1:
                return {"data": {"status": {"succeeded_at": "2026-08-30T10:00:00Z", "failed_at": None, "sync_state": "scheduled"}}}
            else:
                return {"data": {"status": {"succeeded_at": "2026-08-30T10:00:00Z", "failed_at": None, "sync_state": "paused"}}}

        with self.assertRaises(RuntimeError) as ctx:
            sync_fivetran(
                api_key="k", api_secret="s", connector_id="conn_1",
                timeout_seconds=60, poll_interval_seconds=5,
                time_fn=lambda: 0.0, sleep_fn=lambda _: None, request_fn=mock_request,
            )
        self.assertIn("non-runnable state 'paused'", str(ctx.exception))


class HightouchSyncBehavioralTest(unittest.TestCase):
    def test_missing_environment_variables(self) -> None:
        with self.assertRaises(ValueError) as ctx:
            sync_hightouch(api_key=None, sync_id=None)
        self.assertIn("HIGHTOUCH_API_KEY", str(ctx.exception))
        self.assertIn("HIGHTOUCH_SYNC_ID", str(ctx.exception))

    def test_successful_completion(self) -> None:
        def mock_request(url: str, data: Optional[bytes], headers: Dict[str, str]) -> Dict[str, Any]:
            if "/trigger" in url:
                return {"id": 999, "status": "pending"}
            if "/sync_requests" in url:
                return {"data": [{"id": 999, "status": "success"}, {"id": 888, "status": "failed"}]}
            return {}

        simulated_time = 0.0

        def mock_time() -> float:
            return simulated_time

        def mock_sleep(seconds: float) -> None:
            nonlocal simulated_time
            simulated_time += seconds

        res = sync_hightouch(
            api_key="k", sync_id="s1",
            timeout_seconds=60, poll_interval_seconds=5,
            time_fn=mock_time, sleep_fn=mock_sleep, request_fn=mock_request,
        )
        self.assertEqual(res["status"], "success")
        self.assertEqual(res["request_id"], 999)

    def test_remote_failure(self) -> None:
        def mock_request(url: str, data: Optional[bytes], headers: Dict[str, str]) -> Dict[str, Any]:
            if "/trigger" in url:
                return {"id": 999, "status": "pending"}
            return {"data": [{"id": 999, "status": "failed"}]}

        with self.assertRaises(RuntimeError) as ctx:
            sync_hightouch(
                api_key="k", sync_id="s1",
                timeout_seconds=60, poll_interval_seconds=5,
                time_fn=lambda: 0.0, sleep_fn=lambda _: None, request_fn=mock_request,
            )
        self.assertIn("failed remotely", str(ctx.exception))

    def test_triggered_request_not_found(self) -> None:
        def mock_request(url: str, data: Optional[bytes], headers: Dict[str, str]) -> Dict[str, Any]:
            if "/trigger" in url:
                return {"id": 999}
            # Return list that does NOT contain 999
            return {"data": [{"id": 111, "status": "success"}, {"id": 222, "status": "success"}]}

        with self.assertRaises(RuntimeError) as ctx:
            sync_hightouch(
                api_key="k", sync_id="s1",
                timeout_seconds=60, poll_interval_seconds=5,
                time_fn=lambda: 0.0, sleep_fn=lambda _: None, request_fn=mock_request,
            )
        self.assertIn("not found in sync_requests response", str(ctx.exception))

    def test_cancelled_or_interrupted(self) -> None:
        for term_status in ["cancelled", "interrupted"]:
            def mock_request(url: str, data: Optional[bytes], headers: Dict[str, str]) -> Dict[str, Any]:
                if "/trigger" in url:
                    return {"id": 999}
                return {"data": [{"id": 999, "status": term_status}]}

            with self.assertRaises(RuntimeError) as ctx:
                sync_hightouch(
                    api_key="k", sync_id="s1",
                    timeout_seconds=60, poll_interval_seconds=5,
                    time_fn=lambda: 0.0, sleep_fn=lambda _: None, request_fn=mock_request,
                )
            self.assertIn(f"was {term_status}", str(ctx.exception))

    def test_timeout(self) -> None:
        def mock_request(url: str, data: Optional[bytes], headers: Dict[str, str]) -> Dict[str, Any]:
            if "/trigger" in url:
                return {"id": 999}
            return {"data": [{"id": 999, "status": "processing"}]}

        simulated_time = 0.0

        def mock_time() -> float:
            return simulated_time

        def mock_sleep(seconds: float) -> None:
            nonlocal simulated_time
            simulated_time += seconds

        with self.assertRaises(TimeoutError):
            sync_hightouch(
                api_key="k", sync_id="s1",
                timeout_seconds=30, poll_interval_seconds=10,
                time_fn=mock_time, sleep_fn=mock_sleep, request_fn=mock_request,
            )

    def test_transient_polling_error(self) -> None:
        call_count = 0

        def mock_request(url: str, data: Optional[bytes], headers: Dict[str, str]) -> Dict[str, Any]:
            nonlocal call_count
            call_count += 1
            if "/trigger" in url:
                return {"id": 999}
            if call_count == 2:
                raise urllib.error.HTTPError(url, 502, "Bad Gateway", {}, None)
            return {"data": [{"id": 999, "status": "success"}]}

        simulated_time = 0.0

        def mock_time() -> float:
            return simulated_time

        def mock_sleep(seconds: float) -> None:
            nonlocal simulated_time
            simulated_time += seconds

        res = sync_hightouch(
            api_key="k", sync_id="s1",
            timeout_seconds=60, poll_interval_seconds=5,
            time_fn=mock_time, sleep_fn=mock_sleep, request_fn=mock_request,
        )
        self.assertEqual(res["status"], "success")


class SnowflakeRunnerTokenTest(unittest.TestCase):
    def test_run_snowflake_sql_raises_on_unresolved_token(self) -> None:
        script_source = (ROOT / "scripts/run_snowflake_sql.py").read_text(encoding="utf-8")
        self.assertIn("__CAREMATCH_", script_source)
        self.assertIn("raise RuntimeError", script_source)


if __name__ == "__main__":
    unittest.main()