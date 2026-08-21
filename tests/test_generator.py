from __future__ import annotations

import csv
import json
import tempfile
import unittest
from pathlib import Path

from src.generate_healthcare_data import DEFAULT_LOAD_DATE, generate, sha256


class GeneratorTests(unittest.TestCase):
    def generate_small(self, root: Path):
        return generate(root, seed=12345, load_date=DEFAULT_LOAD_DATE, nurse_count=60, facility_count=10, shift_count=180)

    def test_reproducible_checksums(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            one = self.generate_small(Path(first))
            two = self.generate_small(Path(second))
        self.assertEqual(
            [(x["object_key"], x["sha256"]) for x in one["files"]],
            [(x["object_key"], x["sha256"]) for x in two["files"]],
        )

    def test_manifest_hashes_and_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = self.generate_small(root)
            self.assertEqual(len(manifest["files"]), 14)
            for entry in manifest["files"]:
                path = root / entry["object_key"]
                self.assertTrue(path.exists())
                self.assertEqual(entry["sha256"], sha256(path))
                self.assertGreater(entry["rows"], 0)

    def test_operational_foreign_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.generate_small(root)
            rows = {}
            for entity in ["nurses", "facilities", "shifts", "applications", "assignments", "health_screenings"]:
                path = next(root.glob(f"source=operational/entity={entity}/load_date=*/{entity}.csv"))
                with path.open(newline="", encoding="utf-8") as stream:
                    rows[entity] = list(csv.DictReader(stream))

            nurse_ids = {row["nurse_id"] for row in rows["nurses"]}
            facility_ids = {row["facility_id"] for row in rows["facilities"]}
            shift_ids = {row["shift_id"] for row in rows["shifts"]}
            self.assertEqual(len(nurse_ids), len(rows["nurses"]))
            self.assertEqual(len(facility_ids), len(rows["facilities"]))
            self.assertEqual(len(shift_ids), len(rows["shifts"]))
            self.assertTrue({row["facility_id"] for row in rows["shifts"]} <= facility_ids)
            self.assertTrue({row["nurse_id"] for row in rows["applications"]} <= nurse_ids)
            self.assertTrue({row["shift_id"] for row in rows["applications"]} <= shift_ids)
            self.assertTrue({row["nurse_id"] for row in rows["assignments"]} <= nurse_ids)
            self.assertTrue({row["shift_id"] for row in rows["assignments"]} <= shift_ids)
            self.assertEqual({row["nurse_id"] for row in rows["health_screenings"]}, nurse_ids)

    def test_synthetic_identity_and_classification(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = self.generate_small(root)
            nurse_file = next(root.glob("source=operational/entity=nurses/load_date=*/nurses.csv"))
            content = nurse_file.read_text(encoding="utf-8")
            self.assertIn("@carematch.example", content)
            self.assertEqual(manifest["classification"], "SYNTHETIC_NO_REAL_PERSONAL_DATA")


if __name__ == "__main__":
    unittest.main()
