"""
CareMatch Modern Data Stack: Portable Local Validation Runner (Python)
Executes all credential-free checks across Python, dbt, SQL, Terraform, BOM, and security.
"""
from __future__ import annotations

import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

def run_cmd(name: str, cmd: list[str], cwd: pathlib.Path = ROOT) -> tuple[bool, str]:
    print(f"\n>>> Running: {name}...")
    try:
        res = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=True)
        print(f"PASS: {name}")
        return True, "PASS"
    except subprocess.CalledProcessError as e:
        msg = f"Command failed (exit code {e.returncode}):\n{e.stderr or e.stdout}"
        print(f"FAIL: {name} - {msg}", file=sys.stderr)
        return False, msg
    except Exception as ex:
        msg = f"Execution error: {ex}"
        print(f"FAIL: {name} - {msg}", file=sys.stderr)
        return False, msg

def main() -> int:
    results: dict[str, str] = {}
    any_failed = False

    # 1. Python Unit Tests & Contracts
    ok, status = run_cmd("Python Unit Tests & Contracts", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"])
    results["Python Unit Tests & Contracts"] = status
    if not ok: any_failed = True

    # 2. Credential-Free dbt Parse
    with tempfile.TemporaryDirectory() as tmpdir:
        prof = pathlib.Path(tmpdir) / "profiles.yml"
        prof.write_text("""carematch:
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
""", encoding="utf-8")
        ok, status = run_cmd(
            "Credential-Free dbt Parse",
            ["dbt", "--no-version-check", "--no-send-anonymous-usage-stats", "parse", "--project-dir", "dbt", "--profiles-dir", tmpdir]
        )
        results["Credential-Free dbt Parse"] = status
        if not ok: any_failed = True

    # 3. Snowflake SQL Dry-Run Parse
    ok, status = run_cmd(
        "Snowflake SQL Dry-Run Validation",
        [sys.executable, "scripts/run_snowflake_sql.py", "--dry-run", "--bucket", "dummy-bucket",
         "snowflake/sql/02_s3_stage_and_raw_load.sql",
         "snowflake/sql/06_incremental_demo.sql",
         "snowflake/sql/07_pipeline_audit.sql"]
    )
    results["Snowflake SQL Dry-Run Validation"] = status
    if not ok: any_failed = True

    # 4. Terraform Format Check
    ok, status = run_cmd("Terraform Format Check", ["terraform", "fmt", "-check", "-recursive", "infra/terraform"])
    results["Terraform Format Check"] = status
    if not ok: any_failed = True

    # 5. Terraform Validate (Platform)
    ok, status = run_cmd("Terraform Validate (Platform)", ["terraform", "-chdir=infra/terraform/platform", "validate"])
    results["Terraform Validate (Platform)"] = status
    if not ok: any_failed = True

    # 6. UTF-8 BOM Scan
    print("\n>>> Running: UTF-8 BOM Scan...")
    bom_files = [
        str(p.relative_to(ROOT))
        for p in ROOT.rglob("*")
        if p.is_file()
        and not any(x in str(p) for x in [".git", ".venv", "__pycache__", ".terraform", "data"])
        and p.read_bytes().startswith(b"\xef\xbb\xbf")
    ]
    if bom_files:
        print(f"FAIL: UTF-8 BOM Scan - Found BOM in {bom_files}", file=sys.stderr)
        results["UTF-8 BOM Scan"] = f"FAIL: {bom_files}"
        any_failed = True
    else:
        print("PASS: UTF-8 BOM Scan")
        results["UTF-8 BOM Scan"] = "PASS"

    # 7. Secret & State Leak Scan
    print("\n>>> Running: Secret & State Leak Scan...")
    try:
        tracked = subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True).splitlines()
        violations = [
            p for p in tracked
            if (p.endswith(".env") and not p.endswith(".env.example"))
            or any(p.endswith(x) for x in [".p8", ".pem", ".key"])
            or ".tfstate" in p
        ]
        if violations:
            print(f"FAIL: Secret & State Leak Scan - Found {violations}", file=sys.stderr)
            results["Secret & State Leak Scan"] = f"FAIL: {violations}"
            any_failed = True
        else:
            print("PASS: Secret & State Leak Scan")
            results["Secret & State Leak Scan"] = "PASS"
    except Exception as ex:
        results["Secret & State Leak Scan"] = f"FAIL: {ex}"
        any_failed = True

    # 8. Git Whitespace Check
    ok, status = run_cmd("Git Diff Whitespace Check", ["git", "diff", "--check"])
    results["Git Diff Whitespace Check"] = status
    if not ok: any_failed = True

    # Summary
    print("\n" + "=" * 50)
    print(" CareMatch Unified Validation Summary")
    print("=" * 50)
    for k, v in results.items():
        tag = "[PASS]" if v == "PASS" else "[FAIL]"
        print(f"  {tag} {k}")
    print("=" * 50)

    if any_failed:
        print("\nVALIDATION FAILED: One or more checks failed.\n", file=sys.stderr)
        return 1
    print("\nVALIDATION PASSED: All checks succeeded!\n")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
