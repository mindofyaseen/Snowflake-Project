from __future__ import annotations

import argparse
import io
import os
import re
from pathlib import Path

import snowflake.connector
from snowflake.connector.util_text import split_statements


def connection() -> snowflake.connector.SnowflakeConnection:
    options: dict[str, object] = {
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "user": os.environ["SNOWFLAKE_USER"],
        "warehouse": os.environ.get("SNOWFLAKE_WAREHOUSE", "CAREMATCH_INGEST_WH"),
        "role": os.environ.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN"),
    }
    private_key_file = os.environ.get("SNOWFLAKE_PRIVATE_KEY_FILE")
    password = os.environ.get("SNOWFLAKE_PASSWORD")
    if private_key_file:
        options["private_key_file"] = private_key_file
    elif password:
        options["password"] = password
    else:
        raise RuntimeError("Set SNOWFLAKE_PRIVATE_KEY_FILE or SNOWFLAKE_PASSWORD")
    return snowflake.connector.connect(**options)


def main() -> int:
    parser = argparse.ArgumentParser(description="Execute CareMatch Snowflake SQL safely in order")
    parser.add_argument("files", nargs="+", type=Path)
    parser.add_argument("--bucket", required=True, help="S3 bucket substituted into stage SQL")
    parser.add_argument("--snowflake-role-arn", default="", help="AWS role ARN used by the storage integration")
    parser.add_argument("--database", default="CAREMATCH", help="Target Snowflake database")
    parser.add_argument("--warehouse", default="CAREMATCH_INGEST_WH", help="Target Snowflake warehouse")
    parser.add_argument("--dry-run", action="store_true", help="Validate SQL syntax and tokens without connecting to Snowflake")
    args = parser.parse_args()

    for path in args.files:
        if not path.is_file():
            raise FileNotFoundError(f"SQL file not found: {path}")
        raw_sql = path.read_text(encoding="utf-8")
        sql = raw_sql.replace("__CAREMATCH_S3_BUCKET__", args.bucket)
        sql = sql.replace("__CAREMATCH_SNOWFLAKE_ROLE_ARN__", args.snowflake_role_arn)
        if "__CAREMATCH_" in sql:
            raise RuntimeError(f"Unresolved deployment token in {path}")
        # Verify no accidental FORCE = TRUE in standard load files
        if "02_s3_stage_and_raw_load" in path.name:
            if re.search(r"FORCE\s*=\s*TRUE", sql, re.IGNORECASE):
                raise ValueError(f"Prohibited FORCE=TRUE detected in {path}")

        statements = [stmt.strip() for stmt, _ in split_statements(io.StringIO(sql)) if stmt.strip()]
        if args.dry_run:
            print(f"[Dry-run] Validated {path}: {len(statements)} statements (no unresolved tokens).")

    if args.dry_run:
        print("[Dry-run] PASS - all SQL files validated successfully without remote connection.")
        return 0

    with connection() as conn:
        cursor = conn.cursor()
        try:
            for path in args.files:
                sql = path.read_text(encoding="utf-8").replace(
                    "__CAREMATCH_S3_BUCKET__", args.bucket
                )
                sql = sql.replace("__CAREMATCH_SNOWFLAKE_ROLE_ARN__", args.snowflake_role_arn)
                print(f"Executing {path}")
                for statement, _ in split_statements(io.StringIO(sql)):
                    if statement.strip():
                        cursor.execute(statement)
                        if cursor.description and cursor.rowcount != 0:
                            print(f"  statement {cursor.sfqid}: rows={cursor.rowcount}")
            conn.commit()
        finally:
            cursor.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
