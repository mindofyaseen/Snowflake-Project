from __future__ import annotations

import json
import os
import re
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

from airflow.decorators import dag, task
from airflow.exceptions import AirflowException
from airflow.providers.amazon.aws.hooks.s3 import S3Hook

sys.path.insert(0, "/opt/carematch")
from src.generate_healthcare_data import build_s3_raw_key, generate, sanitize_batch_id  # noqa: E402


SOURCE_FAMILIES = (
    "operational",
    "external",
    "data_science",
    "appcast",
    "app_stream",
    "spreadsheets",
)
GENERATED_ROOT = Path("/opt/carematch/generated")


def _bucket_name() -> str:
    bucket = os.environ.get("CAREMATCH_S3_BUCKET", "").strip()
    if not bucket:
        raise AirflowException("CAREMATCH_S3_BUCKET is not configured")
    return bucket


@dag(
    dag_id="carematch_synthetic_sources_to_s3",
    description="Generate six synthetic healthcare source families and land them in S3.",
    schedule="0 2 * * *",
    start_date=datetime(2026, 1, 1, tzinfo=timezone.utc),
    catchup=False,
    max_active_runs=1,
    default_args={"owner": "data-platform", "retries": 2, "retry_delay": timedelta(minutes=2)},
    tags=["carematch", "synthetic", "s3"],
)
def synthetic_sources_to_s3():
    @task
    def generate_files(**context) -> dict:
        dag_run = context.get("dag_run")
        config = (dag_run.conf or {}) if dag_run else {}
        configured_load_date = config.get("load_date")
        load_mode = str(config.get("load_mode", "incremental")).lower()
        if load_mode not in {"initial", "incremental"}:
            raise AirflowException("load_mode must be initial or incremental")
        run_date: date = (
            date.fromisoformat(configured_load_date)
            if configured_load_date
            else datetime.now(timezone.utc).date()
        )
        default_nurse_count = 500 if load_mode == "initial" else 550
        nurse_count = int(config.get("nurse_count", default_nurse_count))
        if not 1 <= nurse_count <= 5000:
            raise AirflowException("nurse_count must be between 1 and 5000")

        raw_run_id = dag_run.run_id if dag_run else context["run_id"]
        batch_id = sanitize_batch_id(raw_run_id)
        run_root = GENERATED_ROOT / run_date.isoformat() / batch_id
        manifest = generate(
            root=run_root,
            seed=int(run_date.strftime("%Y%m%d")) + nurse_count,
            load_date=run_date,
            nurse_count=nurse_count,
            facility_count=40,
            shift_count=3000,
        )
        return {
            "root": str(run_root),
            "load_date": run_date.isoformat(),
            "batch_id": batch_id,
            "nurse_count": nurse_count,
            "load_mode": load_mode,
            "manifest": manifest,
        }

    @task
    def upload_source(source: str, payload: dict) -> dict:
        if source not in SOURCE_FAMILIES:
            raise AirflowException(f"Unsupported source family: {source}")

        root = Path(payload["root"])
        selected = [
            entry for entry in payload["manifest"]["files"]
            if entry["object_key"].startswith(f"source={source}/")
        ]
        if not selected:
            raise AirflowException(f"No generated files found for source={source}")

        hook = S3Hook(aws_conn_id="aws_default")
        bucket = _bucket_name()
        uploaded = []
        for entry in selected:
            local_file = root / entry["object_key"]
            key = build_s3_raw_key(entry["object_key"], payload["batch_id"])
            hook.load_file(filename=str(local_file), key=key, bucket_name=bucket, replace=True)
            remote_size = hook.get_key(key=key, bucket_name=bucket).content_length
            if remote_size != entry["bytes"]:
                raise AirflowException(
                    f"Size mismatch for s3://{bucket}/{key}: {remote_size} != {entry['bytes']}"
                )
            uploaded.append({"key": key, "bytes": remote_size, "sha256": entry["sha256"]})
        return {"source": source, "files": uploaded}

    @task
    def upload_manifest(payload: dict, source_results: list[dict]) -> str:
        completed = {result["source"] for result in source_results}
        if completed != set(SOURCE_FAMILIES):
            raise AirflowException(f"Expected six completed source families, got {sorted(completed)}")

        bucket = _bucket_name()
        key = (
            f"manifests/load_date={payload['load_date']}"
            f"/batch_id={payload['batch_id']}/manifest.json"
        )
        landed_files = [
            entry for entry in payload["manifest"]["files"]
            if entry["object_key"].split("/", 1)[0].removeprefix("source=") in completed
        ]
        body = json.dumps(
            {
                **payload["manifest"],
                "batch_id": payload["batch_id"],
                "requested_nurse_count": payload["nurse_count"],
                "load_mode": payload["load_mode"],
                "files": landed_files,
                "uploaded_source_families": sorted(completed),
            },
            indent=2,
        )
        S3Hook(aws_conn_id="aws_default").load_string(
            string_data=body,
            key=key,
            bucket_name=bucket,
            replace=True,
        )
        return f"s3://{bucket}/{key}"

    generated = generate_files()
    uploads = [
        upload_source.override(task_id=f"upload_{source}")(source, generated)
        for source in SOURCE_FAMILIES
    ]
    upload_manifest(generated, uploads)


synthetic_sources_to_s3()
