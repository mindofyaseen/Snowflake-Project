from __future__ import annotations

import argparse
import os
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
    args = parser.parse_args()

    with connection() as conn:
        cursor = conn.cursor()
        try:
            for path in args.files:
                sql = path.read_text(encoding="utf-8").replace(
                    "__CAREMATCH_S3_BUCKET__", args.bucket
                )
                sql = sql.replace("__CAREMATCH_SNOWFLAKE_ROLE_ARN__", args.snowflake_role_arn)
                if "__CAREMATCH_" in sql:
                    raise RuntimeError(f"Unresolved deployment token in {path}")
                print(f"Executing {path}")
                for statement, _ in split_statements(iter(sql.splitlines(keepends=True))):
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
