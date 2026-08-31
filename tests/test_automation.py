from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AutomationTests(unittest.TestCase):
    def test_snowflake_stage_uses_runtime_bucket(self):
        sql = (ROOT / "snowflake/sql/02_s3_stage_and_raw_load.sql").read_text(encoding="utf-8")
        self.assertIn("__CAREMATCH_S3_BUCKET__", sql)
        self.assertNotIn("carematch-data-237657481511-dev", sql)

        bootstrap = (ROOT / "snowflake/sql/01_platform_bootstrap.sql").read_text(encoding="utf-8")
        self.assertIn("__CAREMATCH_SNOWFLAKE_ROLE_ARN__", bootstrap)
        self.assertIn("__CAREMATCH_S3_BUCKET__", bootstrap)
        self.assertNotIn("237657481511", bootstrap)
        self.assertNotIn("TO USER YASEEN", bootstrap)

    def test_orchestrator_has_separate_load_modes(self):
        script = (ROOT / "scripts/invoke_case_study_pipeline.ps1").read_text(encoding="utf-8")
        self.assertIn('ValidateSet("infrastructure", "initial", "incremental", "verify")', script)
        self.assertIn("$InitialNurseCount = 500", script)
        self.assertIn("$IncrementalNurseCount = 550", script)
        self.assertIn("Invoke-FivetranSync", script)
        self.assertIn("Invoke-HightouchSync", script)

    def test_secrets_are_read_from_environment(self):
        script = (ROOT / "scripts/invoke_case_study_pipeline.ps1").read_text(encoding="utf-8")
        self.assertIn("$env:FIVETRAN_APIKEY", script)
        self.assertIn("$env:HIGHTOUCH_API_KEY", script)
        self.assertNotIn("Scotland$Wise", script)


if __name__ == "__main__":
    unittest.main()
