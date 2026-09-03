# ADR-0001: Airflow on EC2 with Docker Compose Instead of AWS MWAA

## Status
Accepted

## Context
CareMatch requires an orchestration engine to schedule and trigger synthetic healthcare data generation and S3 landing.
Managed Workflows for Apache Airflow (MWAA) incurs a continuous baseline cost (~$0.49/hour, ~$350/month) even when idle,
and requires 15-20 minutes to spin up or modify worker configurations.

## Decision
Deploy Apache Airflow 2.8 via Docker Compose on a single `t3.large` AWS EC2 instance managed exclusively via AWS Systems Manager (SSM).

## Benefits
- Drastically lower cost ($0.0832/hour vs $0.49/hour), with zero compute cost when the EC2 instance is stopped.
- Fast startup and iteration cycles (<60 seconds container restarts).
- Fully reproducible via Terraform and Docker Compose without complex AWS VPC endpoint requirements.
- Zero open inbound internet ports (100% private subnet with SSM Session Manager).

## Drawbacks
- Single-node deployment lacks high-availability multi-node clustering.
- Requires operator management of host operating system and Docker updates.

## Risks
- If host volume fills up, Docker containers could pause. Mitigated by automated log rotation and ephemeral data directories.

## Alternatives Considered
- AWS MWAA: Rejected due to high static cost and slow deployment cycles for a demonstration and agile development environment.
- Airflow on AWS ECS Fargate: Viable, but more complex networking and task definitions for simple batch scheduled jobs.
