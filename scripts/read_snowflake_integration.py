from __future__ import annotations

import json
import os

import snowflake.connector


def main() -> int:
    options: dict[str, str] = {
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "user": os.environ["SNOWFLAKE_USER"],
        "warehouse": os.environ.get("SNOWFLAKE_WAREHOUSE", "CAREMATCH_INGEST_WH"),
        "role": os.environ.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN"),
    }
    if os.environ.get("SNOWFLAKE_PRIVATE_KEY_FILE"):
        options["private_key_file"] = os.environ["SNOWFLAKE_PRIVATE_KEY_FILE"]
    else:
        options["password"] = os.environ["SNOWFLAKE_PASSWORD"]

    with snowflake.connector.connect(**options) as conn:
        cursor = conn.cursor()
        cursor.execute("DESC INTEGRATION CAREMATCH_S3_INT")
        values = {row[0]: row[2] for row in cursor.fetchall()}
    print(json.dumps({
        "iam_user_arn": values["STORAGE_AWS_IAM_USER_ARN"],
        "external_id": values["STORAGE_AWS_EXTERNAL_ID"],
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

