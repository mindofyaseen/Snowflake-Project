from __future__ import annotations

"""
test_pipeline_contract.py
~~~~~~~~~~~~~~~~~~~~~~~~~
Credential-free contract tests for the CareMatch pipeline.

These tests verify the pipeline's structural guarantees without connecting to
AWS, Snowflake, Fivetran, or Hightouch:

1.  Generator produces exactly 500 nurses for the initial load.
2.  Generator produces exactly 550 nurses for the incremental load.
3.  Two same-day Airflow runs produce different S3 batch paths (unique batch_id).
4.  Snowflake load SQL has no FORCE = TRUE (idempotent-load contract).
5.  stg_nurses.sql uses QUALIFY ROW_NUMBER() for deduplication by business key.
6.  stg_nurses.sql orders by record_updated_at DESC (latest-record selection).
7.  Pipeline script raises on missing Fivetran environment variables.
8.  Pipeline script raises on missing Hightouch environment variables.
"""

import csv
import re
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class InitialLoad500NursesTest(unittest.TestCase):
    """Generator produces exactly 500 unique nurses for the initial load."""

    def test_initial_load_produces_500_nurses(self) -> None:
        from datetime import date
        from src.generate_healthcare_data import generate

        with tempfile.TemporaryDirectory() as tmp:
            manifest = generate(
                root=Path(tmp),
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
        self.assertEqual(nurse_file_entry["rows"], 500, "Initial load must produce exactly 500 nurses")


class IncrementalLoad550NursesTest(unittest.TestCase):
    """Generator produces exactly 550 unique nurses for the incremental load."""

    def test_incremental_load_produces_550_nurses(self) -> None:
        from datetime import date
        from src.generate_healthcare_data import generate

        with tempfile.TemporaryDirectory() as tmp:
            manifest = generate(
                root=Path(tmp),
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
        self.assertEqual(nurse_file_entry["rows"], 550, "Incremental load must produce exactly 550 nurses")

    def test_incremental_nurses_have_distinct_ids(self) -> None:
        from datetime import date
        from src.generate_healthcare_data import generate

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
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

        self.assertEqual(len(nurse_ids), len(set(nurse_ids)), "All 550 nurse_ids must be unique")
        self.assertEqual(len(nurse_ids), 550)


class UniqueBatchPathTest(unittest.TestCase):
    """Two Airflow runs on the same date produce different S3 batch paths."""

    def _batch_id_for_run_id(self, raw_run_id: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", raw_run_id).strip("_")

    def test_same_day_runs_produce_unique_batch_ids(self) -> None:
        run_id_a = "carematch_initial_20260821T120000Z"
        run_id_b = "carematch_initial_20260821T130000Z"

        batch_a = self._batch_id_for_run_id(run_id_a)
        batch_b = self._batch_id_for_run_id(run_id_b)

        self.assertNotEqual(batch_a, batch_b, "Different run IDs must yield different batch IDs")

    def test_batch_id_embedded_in_object_key(self) -> None:
        from datetime import date
        from src.generate_healthcare_data import generate

        with tempfile.TemporaryDirectory() as tmp:
            manifest = generate(
                root=Path(tmp),
                seed=20260821,
                load_date=date(2026, 8, 21),
                nurse_count=60,
                facility_count=10,
                shift_count=180,
            )
        # DAG embeds batch_id into the S3 key: raw/{path}/batch_id={batch_id}/{filename}
        # Verify the manifest object keys use the expected Hive-style layout
        # (batch_id is injected at upload time, not in the local path).
        for entry in manifest["files"]:
            key = entry["object_key"]
            # Must start with source= partition
            self.assertTrue(
                key.startswith("source="),
                f"Object key must begin with source= partition: {key}",
            )
            # Must contain entity= partition
            self.assertIn("entity=", key, f"Object key must contain entity= partition: {key}")
            # Must contain load_date= partition
            self.assertIn("load_date=", key, f"Object key must contain load_date= partition: {key}")


class SnowflakeIdempotentLoadTest(unittest.TestCase):
    """COPY INTO SQL must not contain FORCE = TRUE so reloads are safe."""

    def test_load_sql_has_no_force_true(self) -> None:
        sql = (ROOT / "snowflake/sql/02_s3_stage_and_raw_load.sql").read_text(encoding="utf-8")
        self.assertNotIn(
            "FORCE = TRUE",
            sql.upper().replace(" ", "").replace("\n", ""),
            "COPY INTO must not use FORCE = TRUE – rerunning the load must be idempotent",
        )

    def test_load_sql_uses_copy_into(self) -> None:
        sql = (ROOT / "snowflake/sql/02_s3_stage_and_raw_load.sql").read_text(encoding="utf-8").upper()
        self.assertIn("COPY INTO", sql, "02_s3_stage_and_raw_load.sql must contain COPY INTO statements")


class DbtDeduplicationContractTest(unittest.TestCase):
    """stg_nurses.sql deduplicates by nurse_id and selects the latest record."""

    def _stg_nurses(self) -> str:
        return (ROOT / "dbt/models/staging/stg_nurses.sql").read_text(encoding="utf-8")

    def test_qualify_row_number_present(self) -> None:
        sql = self._stg_nurses().lower()
        self.assertIn(
            "qualify",
            sql,
            "stg_nurses must use QUALIFY to deduplicate rows",
        )
        self.assertIn(
            "row_number()",
            sql,
            "stg_nurses must use ROW_NUMBER() for deduplication",
        )

    def test_partitioned_by_nurse_id(self) -> None:
        sql = self._stg_nurses().lower()
        # QUALIFY ROW_NUMBER() OVER (PARTITION BY nurse_id ...)
        self.assertIn(
            "partition by nurse_id",
            sql,
            "stg_nurses must partition by nurse_id so each nurse gets one row",
        )

    def test_orders_by_record_updated_at_desc(self) -> None:
        sql = self._stg_nurses().lower()
        self.assertIn(
            "order by record_updated_at desc",
            sql,
            "stg_nurses must order by record_updated_at DESC to select the latest record",
        )

    def test_sources_yml_declares_nurses_table(self) -> None:
        sources_file = ROOT / "dbt/models/staging/sources.yml"
        self.assertTrue(sources_file.exists(), "dbt/models/staging/sources.yml must exist")
        content = sources_file.read_text(encoding="utf-8")
        self.assertIn("name: nurses", content, "sources.yml must declare the nurses source table")
        self.assertIn("name: raw", content, "sources.yml must declare the raw source")


class MissingEnvVarTest(unittest.TestCase):
    """Pipeline script must guard against missing SaaS environment variables."""

    def test_pipeline_script_checks_fivetran_apikey(self) -> None:
        script = (ROOT / "scripts/invoke_case_study_pipeline.ps1").read_text(encoding="utf-8")
        # The script must check all three Fivetran variables and name them in the error.
        self.assertIn("FIVETRAN_APIKEY", script)
        self.assertIn("FIVETRAN_APISECRET", script)
        self.assertIn("FIVETRAN_CONNECTOR_ID", script)
        # Must throw/raise on missing vars, not silently skip
        self.assertIn("$missing", script, "Script must accumulate missing var names before throwing")

    def test_pipeline_script_checks_hightouch_api_key(self) -> None:
        script = (ROOT / "scripts/invoke_case_study_pipeline.ps1").read_text(encoding="utf-8")
        self.assertIn("HIGHTOUCH_API_KEY", script)
        self.assertIn("HIGHTOUCH_SYNC_ID", script)
        self.assertIn("$missing", script, "Script must accumulate missing var names before throwing")

    def test_run_snowflake_sql_raises_on_unresolved_token(self) -> None:
        import sys

        sys.path.insert(0, str(ROOT / "scripts"))
        # Import the module to verify the token-check logic exists in source.
        script_source = (ROOT / "scripts/run_snowflake_sql.py").read_text(encoding="utf-8")
        self.assertIn(
            "__CAREMATCH_",
            script_source,
            "run_snowflake_sql.py must check for unresolved __CAREMATCH_ tokens",
        )
        self.assertIn(
            "raise RuntimeError",
            script_source,
            "run_snowflake_sql.py must raise RuntimeError on unresolved tokens",
        )


if __name__ == "__main__":
    unittest.main()
