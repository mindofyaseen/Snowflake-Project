# ADR-0007: Deterministic Synthetic Healthcare Data Generation

## Status
Accepted

## Context
Demonstrating an end-to-end healthcare data platform requires realistic clinical shifts, nurse rosters, and credentialing
data without violating HIPAA regulations or exposing real Protected Health Information (PHI).

## Decision
Generate fully synthetic clinical data using Python's standard library with deterministic seeding, reserved `.example` email
domains, and realistic clinical specialties (ICU, Telemetry, ER).

## Benefits
- Zero HIPAA / PII compliance risks.
- Deterministic reproducibility: Identical seeds produce bit-for-bit identical files and checksums.
- Supports precise validation of initial (500 nurses) and incremental (550 nurses) pipeline runs.

## Drawbacks
- Synthetic data cannot capture 100% of real-world anomaly edge cases.

## Risks
- Accidental assumption that data represents real patient records. Mitigated by explicit `SYNTHETIC_NO_REAL_PERSONAL_DATA` manifest classification.

## Alternatives Considered
- Anonymized Real Data: High legal risk, costly de-identification audits, and potential re-identification vulnerabilities.
