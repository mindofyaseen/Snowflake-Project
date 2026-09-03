import unittest
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parent.parent

EXPECTED_ENTITIES = {
    "nurses",
    "facilities",
    "shifts",
    "applications",
    "assignments",
    "health_screenings",
    "nurse_scores",
    "events",
    "campaign_performance",
    "market_conditions",
    "manual_overrides",
}

VALID_SOURCE_FAMILIES = {
    "operational",
    "data_science",
    "app_stream",
    "appcast",
    "external",
    "spreadsheets",
}

class DataContractsStructureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        contracts_path = ROOT / "contracts" / "data_contracts.yml"
        cls.assertTrue(cls, contracts_path.is_file(), "contracts/data_contracts.yml must exist")
        with open(contracts_path, "r", encoding="utf-8") as f:
            cls.data = yaml.safe_load(f)

    def test_top_level_structure(self) -> None:
        self.assertIn("version", self.data)
        self.assertIn("contracts", self.data)
        self.assertIsInstance(self.data["contracts"], list)
        self.assertEqual(len(self.data["contracts"]), 11)

    def test_all_11_entities_present(self) -> None:
        found_entities = {c["entity"] for c in self.data["contracts"]}
        self.assertEqual(found_entities, EXPECTED_ENTITIES)

    def test_mandatory_fields_present_in_every_contract(self) -> None:
        mandatory_fields = [
            "entity",
            "source_family",
            "file_format",
            "business_purpose",
            "primary_key",
            "deduplication_key",
            "incremental_watermark",
            "foreign_keys",
            "required_columns",
            "column_schema",
            "validation_rules",
        ]
        for c in self.data["contracts"]:
            entity_name = c["entity"]
            for field in mandatory_fields:
                self.assertIn(field, c, f"Entity '{entity_name}' missing field '{field}'")
            
            self.assertIn(c["source_family"], VALID_SOURCE_FAMILIES, f"Invalid source_family for {entity_name}")
            self.assertIn(c["file_format"], {"csv", "jsonl"}, f"Invalid file_format for {entity_name}")
            self.assertGreater(len(c["business_purpose"]), 15, f"Business purpose too short for {entity_name}")
            self.assertIsInstance(c["primary_key"], list)
            self.assertGreater(len(c["primary_key"]), 0)
            self.assertIsInstance(c["deduplication_key"], list)
            self.assertGreater(len(c["deduplication_key"]), 0)
            self.assertIsInstance(c["required_columns"], list)
            self.assertGreater(len(c["required_columns"]), 0)
            self.assertIsInstance(c["validation_rules"], list)
            self.assertGreater(len(c["validation_rules"]), 0)

    def test_column_schema_aligns_with_required_columns(self) -> None:
        for c in self.data["contracts"]:
            entity_name = c["entity"]
            schema_cols = set(c["column_schema"].keys())
            req_cols = set(c["required_columns"])
            self.assertTrue(req_cols.issubset(schema_cols), f"{entity_name}: required columns not in schema")
            for col, spec in c["column_schema"].items():
                self.assertIn("type", spec, f"{entity_name}.{col} missing type")
                self.assertIn("nullable", spec, f"{entity_name}.{col} missing nullable flag")

if __name__ == "__main__":
    unittest.main()
