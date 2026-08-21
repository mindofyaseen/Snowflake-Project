from __future__ import annotations

import argparse
import csv
import hashlib
import json
import random
import shutil
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable


GENERATOR_VERSION = "1.0.0"
DEFAULT_SEED = 20260821
DEFAULT_LOAD_DATE = date(2026, 8, 21)
CITIES = ["Boston", "Cambridge", "Quincy", "Brockton", "Worcester"]
SPECIALTIES = ["CNA", "LPN", "RN"]
FIRST_NAMES = ["Avery", "Jordan", "Taylor", "Morgan", "Riley", "Casey", "Jamie", "Cameron"]
LAST_NAMES = ["Khan", "Patel", "Rivera", "Lee", "Brown", "Davis", "Wilson", "Martin"]


def object_path(root: Path, source: str, entity: str, load_date: date, suffix: str = "csv") -> Path:
    return root / f"source={source}" / f"entity={entity}" / f"load_date={load_date.isoformat()}" / f"{entity}.{suffix}"


def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        raise ValueError(f"Cannot write empty dataset: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_jsonl(path: Path, rows: Iterable[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        for row in rows:
            stream.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def generate_nurses(rng: random.Random, count: int, load_date: date) -> list[dict]:
    nurses = []
    for index in range(1, count + 1):
        hired = load_date - timedelta(days=rng.randint(30, 2200))
        completed = rng.randint(0, 180)
        cancelled = rng.randint(0, min(20, completed + 3))
        nurses.append({
            "nurse_id": f"N{index:06d}",
            "full_name": f"{rng.choice(FIRST_NAMES)} {rng.choice(LAST_NAMES)}",
            "email": f"nurse{index:06d}@carematch.example",
            "city": rng.choice(CITIES),
            "specialty": rng.choices(SPECIALTIES, weights=[45, 35, 20])[0],
            "experience_years": rng.randint(1, 25),
            "hire_date": hired.isoformat(),
            "license_expiry_date": (load_date + timedelta(days=rng.randint(-20, 500))).isoformat(),
            "completed_shifts_lifetime": completed,
            "cancelled_shifts_lifetime": cancelled,
            "days_since_active": rng.randint(0, 120),
            "notification_opt_in": str(rng.random() >= 0.12).lower(),
            "record_updated_at": datetime.combine(load_date, datetime.min.time(), tzinfo=timezone.utc).isoformat(),
        })
    return nurses


def generate_facilities(rng: random.Random, count: int, load_date: date) -> list[dict]:
    rows = []
    for index in range(1, count + 1):
        rows.append({
            "facility_id": f"F{index:05d}",
            "facility_name": f"Community Care Center {index:03d}",
            "city": CITIES[(index - 1) % len(CITIES)],
            "facility_type": rng.choice(["Skilled Nursing", "Assisted Living", "Rehabilitation"]),
            "quality_tier": rng.choices(["A", "B", "C"], weights=[40, 45, 15])[0],
            "active": "true",
            "record_updated_at": datetime.combine(load_date, datetime.min.time(), tzinfo=timezone.utc).isoformat(),
        })
    return rows


def generate_shifts(rng: random.Random, facilities: list[dict], count: int, load_date: date) -> list[dict]:
    rows = []
    start = load_date - timedelta(days=120)
    for index in range(1, count + 1):
        facility = rng.choice(facilities)
        shift_date = start + timedelta(days=rng.randint(0, 180))
        status = "open" if shift_date >= load_date else rng.choices(
            ["completed", "cancelled", "unfilled"], weights=[78, 12, 10]
        )[0]
        rows.append({
            "shift_id": f"S{index:07d}",
            "facility_id": facility["facility_id"],
            "city": facility["city"],
            "shift_date": shift_date.isoformat(),
            "start_hour": rng.choice([7, 7, 15, 15, 23]),
            "hours": rng.choice([8, 8, 8, 12]),
            "specialty_required": rng.choices(SPECIALTIES, weights=[48, 34, 18])[0],
            "base_hourly_rate": rng.choice([25, 28, 32, 36, 42, 48]),
            "urgency": rng.randint(1, 5),
            "status": status,
            "posted_at": datetime.combine(shift_date - timedelta(days=rng.randint(1, 21)), datetime.min.time(), tzinfo=timezone.utc).isoformat(),
        })
    return rows


def generate_applications(
    rng: random.Random, nurses: list[dict], shifts: list[dict]
) -> tuple[list[dict], list[dict]]:
    by_specialty = defaultdict(list)
    for nurse in nurses:
        by_specialty[nurse["specialty"]].append(nurse)

    applications = []
    assignments = []
    application_index = 1
    assignment_index = 1
    for shift in shifts:
        candidates = by_specialty[shift["specialty_required"]]
        sampled = rng.sample(candidates, k=min(rng.randint(1, 6), len(candidates)))
        shift_apps = []
        for nurse in sampled:
            status = rng.choices(["submitted", "withdrawn", "rejected", "accepted"], weights=[25, 8, 32, 35])[0]
            row = {
                "application_id": f"A{application_index:08d}",
                "shift_id": shift["shift_id"],
                "nurse_id": nurse["nurse_id"],
                "application_status": status,
                "applied_at": shift["posted_at"],
                "source_channel": rng.choice(["mobile_app", "web", "email", "sms"]),
            }
            applications.append(row)
            shift_apps.append(row)
            application_index += 1

        accepted = [row for row in shift_apps if row["application_status"] == "accepted"]
        if accepted and shift["status"] != "unfilled":
            winner = rng.choice(accepted)
            outcome = shift["status"] if shift["status"] in {"completed", "cancelled"} else "scheduled"
            assignments.append({
                "assignment_id": f"AS{assignment_index:07d}",
                "shift_id": shift["shift_id"],
                "nurse_id": winner["nurse_id"],
                "assigned_hourly_rate": round(float(shift["base_hourly_rate"]) * (1 + 0.05 * (int(shift["urgency"]) - 1)), 2),
                "assignment_outcome": outcome,
                "cancelled_by": rng.choice(["nurse", "facility", "none"]) if outcome == "cancelled" else "none",
            })
            assignment_index += 1
    return applications, assignments


def generate_health_screenings(rng: random.Random, nurses: list[dict], load_date: date) -> list[dict]:
    rows = []
    for index, nurse in enumerate(nurses, start=1):
        symptom = rng.random() < 0.045
        license_valid = date.fromisoformat(nurse["license_expiry_date"]) >= load_date
        rows.append({
            "screening_id": f"H{index:06d}",
            "nurse_id": nurse["nurse_id"],
            "screened_on": (load_date - timedelta(days=rng.randint(0, 6))).isoformat(),
            "symptom_flag": str(symptom).lower(),
            "license_valid": str(license_valid).lower(),
            "cleared_to_work": str((not symptom) and license_valid).lower(),
        })
    return rows


def generate_market_conditions(rng: random.Random, shifts: list[dict], load_date: date) -> list[dict]:
    demand = Counter((row["city"], row["specialty_required"]) for row in shifts if row["status"] == "open")
    rows = []
    for city in CITIES:
        for specialty in SPECIALTIES:
            open_demand = demand[(city, specialty)]
            rows.append({
                "market_date": load_date.isoformat(),
                "city": city,
                "specialty": specialty,
                "open_shift_demand": open_demand,
                "estimated_available_supply": max(1, open_demand + rng.randint(-8, 15)),
                "market_hourly_rate": rng.choice([27, 30, 34, 38, 44]),
                "external_demand_index": round(rng.uniform(0.65, 1.45), 3),
            })
    return rows


def generate_scores(nurses: list[dict], screenings: list[dict], load_date: date) -> list[dict]:
    clearance = {row["nurse_id"]: row["cleared_to_work"] for row in screenings}
    rows = []
    for nurse in nurses:
        completed = int(nurse["completed_shifts_lifetime"])
        cancelled = int(nurse["cancelled_shifts_lifetime"])
        total = completed + cancelled
        reliability = completed / total if total else 0.55
        inactivity = int(nurse["days_since_active"])
        churn_risk = min(0.98, 0.12 + inactivity / 150 + cancelled / max(1, total) * 0.35)
        rows.append({
            "nurse_id": nurse["nurse_id"],
            "score_date": load_date.isoformat(),
            "shift_completion_probability": round(reliability, 4),
            "churn_probability": round(churn_risk, 4),
            "estimated_12m_value": round(completed * 46.5 * max(0.2, 1 - churn_risk), 2),
            "eligible_for_recommendations": clearance[nurse["nurse_id"]],
            "model_version": "synthetic-baseline-1.0",
        })
    return rows


def generate_campaigns(rng: random.Random, nurses: list[dict], load_date: date) -> list[dict]:
    rows = []
    channels = ["search", "social", "referral", "job_board"]
    for index, channel in enumerate(channels, start=1):
        impressions = rng.randint(20_000, 80_000)
        clicks = int(impressions * rng.uniform(0.025, 0.085))
        applicants = int(clicks * rng.uniform(0.08, 0.22))
        rows.append({
            "campaign_id": f"C{index:04d}",
            "campaign_date": load_date.isoformat(),
            "channel": channel,
            "city": rng.choice(CITIES),
            "impressions": impressions,
            "clicks": clicks,
            "applicants": applicants,
            "qualified_applicants": int(applicants * rng.uniform(0.45, 0.75)),
            "spend_usd": round(rng.uniform(2500, 9000), 2),
        })
    return rows


def generate_app_events(rng: random.Random, nurses: list[dict], load_date: date) -> list[dict]:
    rows = []
    event_index = 1
    for nurse in nurses:
        for _ in range(rng.randint(2, 10)):
            event_time = datetime.combine(load_date - timedelta(days=rng.randint(0, 30)), datetime.min.time(), tzinfo=timezone.utc) + timedelta(seconds=rng.randint(0, 86399))
            rows.append({
                "event_id": f"EV{event_index:09d}",
                "nurse_id": nurse["nurse_id"],
                "event_name": rng.choice(["app_open", "shift_search", "shift_view", "application_start", "notification_open"]),
                "event_timestamp": event_time.isoformat(),
                "platform": rng.choice(["ios", "android", "web"]),
                "session_id": f"SESSION{rng.randint(1, 99999999):08d}",
            })
            event_index += 1
    return rows


def generate_overrides(rng: random.Random, nurses: list[dict], load_date: date) -> list[dict]:
    sampled = rng.sample(nurses, k=max(1, len(nurses) // 50))
    return [{
        "override_id": f"O{index:05d}",
        "nurse_id": nurse["nurse_id"],
        "override_type": rng.choice(["temporary_suppression", "manual_review", "contact_pause"]),
        "reason_code": rng.choice(["support_case", "consent_review", "credential_review"]),
        "effective_date": load_date.isoformat(),
        "expires_on": (load_date + timedelta(days=rng.randint(7, 45))).isoformat(),
        "approved_by": "operations@carematch.example",
    } for index, nurse in enumerate(sampled, start=1)]


def generate_surveys(rng: random.Random, nurses: list[dict], load_date: date) -> list[dict]:
    sampled = rng.sample(nurses, k=max(1, len(nurses) // 3))
    return [{
        "response_id": f"SR{index:06d}",
        "nurse_id": nurse["nurse_id"],
        "response_date": (load_date - timedelta(days=rng.randint(0, 60))).isoformat(),
        "onboarding_satisfaction": rng.randint(1, 5),
        "shift_relevance": rng.randint(1, 5),
        "facility_experience": rng.randint(1, 5),
        "recommendation_score": rng.randint(0, 10),
    } for index, nurse in enumerate(sampled, start=1)]


def generate_marketo(rng: random.Random, nurses: list[dict], load_date: date) -> list[dict]:
    return [{
        "lead_id": f"ML{index:06d}",
        "nurse_id": nurse["nurse_id"],
        "lead_status": rng.choice(["new", "nurturing", "qualified", "inactive"]),
        "acquisition_channel": rng.choice(["search", "social", "referral", "job_board"]),
        "email_opt_in": nurse["notification_opt_in"],
        "last_campaign_date": (load_date - timedelta(days=rng.randint(0, 120))).isoformat(),
    } for index, nurse in enumerate(nurses, start=1)]


def generate_pendo(events: list[dict]) -> list[dict]:
    return [{
        "event_id": row["event_id"],
        "visitor_id": row["nurse_id"],
        "event_type": row["event_name"],
        "event_timestamp": row["event_timestamp"],
        "app_id": "carematch-demo-app",
        "platform": row["platform"],
    } for row in events]


def build_manifest(root: Path, seed: int, load_date: date, row_counts: dict[str, int]) -> dict:
    files = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.name == "manifest.json":
            continue
        relative = path.relative_to(root).as_posix()
        files.append({
            "object_key": relative,
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
            "rows": row_counts.get(relative),
        })
    return {
        "generator": "carematch-synthetic-healthcare",
        "generator_version": GENERATOR_VERSION,
        "seed": seed,
        "load_date": load_date.isoformat(),
        "generated_at": datetime.combine(load_date, datetime.min.time(), tzinfo=timezone.utc).isoformat(),
        "classification": "SYNTHETIC_NO_REAL_PERSONAL_DATA",
        "license": "Project-generated synthetic data for demonstration use",
        "files": files,
    }


def generate(root: Path, seed: int, load_date: date, nurse_count: int, facility_count: int, shift_count: int) -> dict:
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)
    rng = random.Random(seed)

    nurses = generate_nurses(rng, nurse_count, load_date)
    facilities = generate_facilities(rng, facility_count, load_date)
    shifts = generate_shifts(rng, facilities, shift_count, load_date)
    applications, assignments = generate_applications(rng, nurses, shifts)
    screenings = generate_health_screenings(rng, nurses, load_date)
    market = generate_market_conditions(rng, shifts, load_date)
    scores = generate_scores(nurses, screenings, load_date)
    campaigns = generate_campaigns(rng, nurses, load_date)
    events = generate_app_events(rng, nurses, load_date)
    overrides = generate_overrides(rng, nurses, load_date)
    surveys = generate_surveys(rng, nurses, load_date)
    marketo = generate_marketo(rng, nurses, load_date)
    pendo = generate_pendo(events)

    datasets = [
        ("operational", "nurses", nurses, "csv"),
        ("operational", "facilities", facilities, "csv"),
        ("operational", "shifts", shifts, "csv"),
        ("operational", "applications", applications, "csv"),
        ("operational", "assignments", assignments, "csv"),
        ("operational", "health_screenings", screenings, "csv"),
        ("external", "market_conditions", market, "csv"),
        ("data_science", "nurse_scores", scores, "csv"),
        ("appcast", "campaign_performance", campaigns, "csv"),
        ("app_stream", "events", events, "jsonl"),
        ("spreadsheets", "manual_overrides", overrides, "csv"),
        ("surveymonkey", "survey_responses", surveys, "csv"),
        ("marketo", "leads", marketo, "csv"),
        ("pendo", "product_events", pendo, "jsonl"),
    ]

    row_counts = {}
    for source, entity, rows, file_type in datasets:
        path = object_path(root, source, entity, load_date, file_type)
        if file_type == "jsonl":
            write_jsonl(path, rows)
        else:
            write_csv(path, rows)
        row_counts[path.relative_to(root).as_posix()] = len(rows)

    manifest = build_manifest(root, seed, load_date, row_counts)
    (root / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate deterministic CareMatch healthcare staffing data.")
    parser.add_argument("--output", type=Path, default=Path("data/generated"))
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--load-date", type=date.fromisoformat, default=DEFAULT_LOAD_DATE)
    parser.add_argument("--nurses", type=int, default=500)
    parser.add_argument("--facilities", type=int, default=40)
    parser.add_argument("--shifts", type=int, default=3000)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest = generate(args.output.resolve(), args.seed, args.load_date, args.nurses, args.facilities, args.shifts)
    print(json.dumps({
        "output": str(args.output.resolve()),
        "files": len(manifest["files"]),
        "rows": sum(item["rows"] for item in manifest["files"] if item["rows"] is not None),
        "seed": manifest["seed"],
    }, indent=2))


if __name__ == "__main__":
    main()
