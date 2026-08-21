# Local data

`data/generated/` is created by the deterministic generator and intentionally ignored by Git.

Generate the full local dataset:

```powershell
python -m src.generate_healthcare_data --output data/generated
```

The folder structure matches the S3 object-key layout. `manifest.json` records every file, row count, byte count, and SHA-256 checksum.
