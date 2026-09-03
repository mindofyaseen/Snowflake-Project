from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from typing import Any, Callable, Dict, Optional


def sync_fivetran(
    api_key: Optional[str] = None,
    api_secret: Optional[str] = None,
    connector_id: Optional[str] = None,
    timeout_seconds: int = 1800,
    poll_interval_seconds: int = 30,
    time_fn: Callable[[], float] = time.time,
    sleep_fn: Callable[[float], None] = time.sleep,
    request_fn: Optional[Callable[[str, Optional[bytes], Dict[str, str]], Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """Trigger and poll a Fivetran connector sync until completion or timeout.

    Validates that succeeded_at or failed_at timestamps advance past the pre-trigger
    baseline, rather than relying on a static sync_state string.
    """
    api_key = api_key or os.environ.get("FIVETRAN_APIKEY")
    api_secret = api_secret or os.environ.get("FIVETRAN_APISECRET")
    connector_id = connector_id or os.environ.get("FIVETRAN_CONNECTOR_ID")

    missing = []
    if not api_key:
        missing.append("FIVETRAN_APIKEY")
    if not api_secret:
        missing.append("FIVETRAN_APISECRET")
    if not connector_id:
        missing.append("FIVETRAN_CONNECTOR_ID")
    if missing:
        raise ValueError(f"Missing Fivetran environment variables: {', '.join(missing)}")

    pair = f"{api_key}:{api_secret}"
    token = base64.b64encode(pair.encode("utf-8")).decode("ascii")
    headers = {
        "Authorization": f"Basic {token}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    base_uri = f"https://api.fivetran.com/v1/connectors/{connector_id}"

    def default_http(url: str, data: Optional[bytes], req_headers: Dict[str, str]) -> Dict[str, Any]:
        req = urllib.request.Request(url, data=data, headers=req_headers)
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body.strip() else {}

    http_call = request_fn or default_http

    # 1. Capture baseline timestamps before triggering
    try:
        baseline_res = http_call(base_uri, None, headers)
    except Exception as e:
        raise RuntimeError(f"Failed to read Fivetran connector status before trigger: {e}") from e

    status_data = baseline_res.get("data", {}).get("status", {})
    baseline_succeeded = status_data.get("succeeded_at")
    baseline_failed = status_data.get("failed_at")

    # 2. Trigger the sync
    try:
        http_call(f"{base_uri}/force", b"{}", headers)
    except Exception as e:
        raise RuntimeError(f"Fivetran force-sync trigger failed: {e}") from e

    start_time = time_fn()
    deadline = start_time + timeout_seconds

    # 3. Poll until completion or timeout
    while time_fn() < deadline:
        sleep_fn(poll_interval_seconds)
        try:
            poll_res = http_call(base_uri, None, headers)
            cur_status = poll_res.get("data", {}).get("status", {})
        except Exception as e:
            # Transient polling error - log warning to stderr and continue until deadline
            print(f"[Fivetran] Warning: status poll error (will retry): {e}", file=sys.stderr)
            continue

        sync_state = cur_status.get("sync_state")
        succeeded_at = cur_status.get("succeeded_at")
        failed_at = cur_status.get("failed_at")

        if sync_state in ("paused", "rescheduled"):
            raise RuntimeError(
                f"Fivetran connector in non-runnable state '{sync_state}'. Unpause connector and retry."
            )

        if succeeded_at and succeeded_at != baseline_succeeded:
            return {"status": "success", "succeeded_at": succeeded_at, "sync_state": sync_state}

        if failed_at and failed_at != baseline_failed:
            raise RuntimeError(f"Fivetran sync failed at {failed_at} (state: {sync_state})")

    raise TimeoutError(f"Fivetran sync did not complete within {timeout_seconds} seconds")


def sync_hightouch(
    api_key: Optional[str] = None,
    sync_id: Optional[str] = None,
    timeout_seconds: int = 1800,
    poll_interval_seconds: int = 30,
    time_fn: Callable[[], float] = time.time,
    sleep_fn: Callable[[float], None] = time.sleep,
    request_fn: Optional[Callable[[str, Optional[bytes], Dict[str, str]], Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """Trigger and poll a Hightouch sync until completion or timeout.

    Follows only the exact triggered sync request ID and never falls back to
    unrelated requests.
    """
    api_key = api_key or os.environ.get("HIGHTOUCH_API_KEY")
    sync_id = sync_id or os.environ.get("HIGHTOUCH_SYNC_ID")

    missing = []
    if not api_key:
        missing.append("HIGHTOUCH_API_KEY")
    if not sync_id:
        missing.append("HIGHTOUCH_SYNC_ID")
    if missing:
        raise ValueError(f"Missing Hightouch environment variables: {', '.join(missing)}")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }
    sync_uri = f"https://api.hightouch.com/api/v1/syncs/{sync_id}"

    def default_http(url: str, data: Optional[bytes], req_headers: Dict[str, str]) -> Dict[str, Any]:
        req = urllib.request.Request(url, data=data, headers=req_headers)
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body.strip() else {}

    http_call = request_fn or default_http

    # 1. Trigger the sync
    try:
        trigger_res = http_call(f"{sync_uri}/trigger", b"{}", headers)
    except Exception as e:
        raise RuntimeError(f"Hightouch trigger API call failed: {e}") from e

    sync_request_id = trigger_res.get("id")
    if not sync_request_id:
        raise RuntimeError(
            f"Hightouch trigger response did not contain a valid request ID: {trigger_res}"
        )

    start_time = time_fn()
    deadline = start_time + timeout_seconds

    # 2. Poll sync_requests requiring exact match on triggered ID
    while time_fn() < deadline:
        sleep_fn(poll_interval_seconds)
        try:
            reqs_res = http_call(f"{sync_uri}/sync_requests", None, headers)
        except Exception as e:
            print(f"[Hightouch] Warning: status poll error (will retry): {e}", file=sys.stderr)
            continue

        data_items = reqs_res.get("data", [])
        matched = next(
            (item for item in data_items if str(item.get("id")) == str(sync_request_id)),
            None,
        )
        if not matched:
            raise RuntimeError(
                f"Triggered sync request ID '{sync_request_id}' not found in sync_requests response"
            )

        status = matched.get("status")
        if status == "success":
            return {"status": "success", "request_id": sync_request_id}
        elif status == "failed":
            raise RuntimeError(f"Hightouch sync request {sync_request_id} failed remotely")
        elif status == "cancelled":
            raise RuntimeError(f"Hightouch sync request {sync_request_id} was cancelled")
        elif status == "interrupted":
            raise RuntimeError(f"Hightouch sync request {sync_request_id} was interrupted")
        # Otherwise (pending, processing, queued, running): continue polling

    raise TimeoutError(f"Hightouch sync request {sync_request_id} did not complete within {timeout_seconds}s")


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Trigger and poll SaaS syncs safely")
    subparsers = parser.add_subparsers(dest="command", required=True)

    fivetran_p = subparsers.add_parser("fivetran", help="Trigger and poll Fivetran connector sync")
    fivetran_p.add_argument("--timeout", type=int, default=1800, help="Timeout in seconds")
    fivetran_p.add_argument("--interval", type=int, default=30, help="Polling interval in seconds")

    hightouch_p = subparsers.add_parser("hightouch", help="Trigger and poll Hightouch sync")
    hightouch_p.add_argument("--timeout", type=int, default=1800, help="Timeout in seconds")
    hightouch_p.add_argument("--interval", type=int, default=30, help="Polling interval in seconds")

    args = parser.parse_args(argv)
    try:
        if args.command == "fivetran":
            res = sync_fivetran(timeout_seconds=args.timeout, poll_interval_seconds=args.interval)
            print(f"[Fivetran] PASS - {res}")
        elif args.command == "hightouch":
            res = sync_hightouch(timeout_seconds=args.timeout, poll_interval_seconds=args.interval)
            print(f"[Hightouch] PASS - {res}")
        return 0
    except TimeoutError as e:
        print(f"[{args.command.title()}] TIMEOUT - {e}", file=sys.stderr)
        return 2
    except ValueError as e:
        print(f"[{args.command.title()}] CONFIG ERROR - {e}", file=sys.stderr)
        return 3
    except RuntimeError as e:
        print(f"[{args.command.title()}] FAIL - {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"[{args.command.title()}] UNEXPECTED ERROR - {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())