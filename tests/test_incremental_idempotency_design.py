import unittest
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent

class IncrementalAndIdempotencyDesignTest(unittest.TestCase):
    def test_initial_and_incremental_modes_differ(self) -> None:
        dag_source = (ROOT / "airflow" / "dags" / "synthetic_sources_to_s3.py").read_text(encoding="utf-8")
        self.assertIn("500 if load_mode == \"initial\" else 550", dag_source)

    def test_current_utc_date_is_default(self) -> None:
        dag_source = (ROOT / "airflow" / "dags" / "synthetic_sources_to_s3.py").read_text(encoding="utf-8")
        self.assertIn("datetime.now(timezone.utc).date()", dag_source)
        ps_source = (ROOT / "scripts" / "invoke_case_study_pipeline.ps1").read_text(encoding="utf-8")
        self.assertIn("(Get-Date).ToUniversalTime().Date", ps_source)

    def test_each_run_receives_unique_batch_id(self) -> None:
        dag_source = (ROOT / "airflow" / "dags" / "synthetic_sources_to_s3.py").read_text(encoding="utf-8")
        self.assertIn("batch_id = sanitize_batch_id(raw_run_id)", dag_source)
        ps_source = (ROOT / "scripts" / "invoke_case_study_pipeline.ps1").read_text(encoding="utf-8")
        self.assertIn("carematch_${LoadMode}_$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))", ps_source)

    def test_same_s3_file_not_loaded_twice_no_force_true(self) -> None:
        sql_load = (ROOT / "snowflake" / "sql" / "02_s3_stage_and_raw_load.sql").read_text(encoding="utf-8")
        self.assertIn("COPY INTO NURSES", sql_load)
        # Verify absence of FORCE = TRUE
        self.assertIsNone(
            re.search(r"FORCE\s*=\s*TRUE", sql_load, re.IGNORECASE),
            "FORCE = TRUE must not be present in production load SQL to ensure idempotency"
        )

    def test_dbt_deduplication_selects_latest_record(self) -> None:
        stg_nurses = (ROOT / "dbt" / "models" / "staging" / "stg_nurses.sql").read_text(encoding="utf-8")
        self.assertIn("qualify row_number() over", stg_nurses.lower())
        self.assertIn("partition by nurse_id", stg_nurses.lower())
        self.assertIn("order by record_updated_at desc", stg_nurses.lower())

    def test_raw_history_remains_available(self) -> None:
        sql_load = (ROOT / "snowflake" / "sql" / "02_s3_stage_and_raw_load.sql").read_text(encoding="utf-8")
        self.assertNotIn("TRUNCATE TABLE", sql_load.upper())
        self.assertNotIn("DELETE FROM", sql_load.upper())

    def test_existing_batch_reuse_avoids_rerunning_airflow(self) -> None:
        ps_source = (ROOT / "scripts" / "invoke_case_study_pipeline.ps1").read_text(encoding="utf-8")
        self.assertIn("if ($ExistingBatchId -or $SkipAirflow)", ps_source)
        self.assertIn("Skipping Airflow trigger: using existing S3 batch", ps_source)

if __name__ == "__main__":
    unittest.main()
