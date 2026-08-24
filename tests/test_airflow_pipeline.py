from __future__ import annotations

import ast
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DAG_FILE = REPO_ROOT / "airflow" / "dags" / "synthetic_sources_to_s3.py"
COMPOSE_FILE = REPO_ROOT / "airflow" / "docker-compose.ec2.yaml"


class AirflowPipelineTests(unittest.TestCase):
    def test_dag_is_valid_python(self):
        tree = ast.parse(DAG_FILE.read_text(encoding="utf-8"), filename=str(DAG_FILE))
        function_names = {node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)}
        self.assertTrue({"generate_files", "upload_source", "upload_manifest"} <= function_names)

    def test_six_source_families_are_declared(self):
        tree = ast.parse(DAG_FILE.read_text(encoding="utf-8"))
        assignment = next(
            node for node in tree.body
            if isinstance(node, ast.Assign)
            and any(isinstance(target, ast.Name) and target.id == "SOURCE_FAMILIES" for target in node.targets)
        )
        sources = ast.literal_eval(assignment.value)
        self.assertEqual(
            sources,
            ("operational", "external", "data_science", "appcast", "app_stream", "spreadsheets"),
        )

    def test_manual_runs_can_select_an_incremental_load_date(self):
        dag_source = DAG_FILE.read_text(encoding="utf-8")
        self.assertIn('context.get("dag_run").conf', dag_source)
        self.assertIn('date.fromisoformat(configured_load_date)', dag_source)

    def test_compose_binds_ui_to_loopback_only(self):
        compose = COMPOSE_FILE.read_text(encoding="utf-8")
        self.assertIn('"127.0.0.1:8080:8080"', compose)
        self.assertIn("AIRFLOW_CONN_AWS_DEFAULT: aws://", compose)
        self.assertNotIn('"0.0.0.0:8080:8080"', compose)


if __name__ == "__main__":
    unittest.main()
