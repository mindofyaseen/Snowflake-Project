# Synthetic source data dictionary

All records are synthetic and generated for this project. No source contains real patients, nurses, employees, facilities, accounts, or contact details.

| Source | Entity | Grain | Purpose |
|---|---|---|---|
| operational | nurses | One row per synthetic nurse | Profile, specialty, license, activity, and consent |
| operational | facilities | One row per synthetic facility | Location, type, and quality tier |
| operational | shifts | One row per staffing shift | Demand, schedule, rate, urgency, and outcome |
| operational | applications | One row per nurse-shift application | Application funnel and channel |
| operational | assignments | One row per staffed shift | Assigned nurse, rate, and outcome |
| operational | health_screenings | One row per nurse | Synthetic safety and license eligibility |
| external | market_conditions | City-specialty daily snapshot | Supply, demand, market rate, and demand index |
| data_science | nurse_scores | One row per nurse and score date | Completion, churn, value, and eligibility scores |
| appcast | campaign_performance | Campaign-channel snapshot | Impressions, clicks, applicants, qualified applicants, and spend |
| app_stream | events | One row per application event | Product engagement events in JSON Lines format |
| spreadsheets | manual_overrides | One row per approved override | Temporary suppression and review controls |
| surveymonkey | survey_responses | One row per synthetic response | Satisfaction, relevance, experience, and recommendation |
| marketo | leads | One row per synthetic lead | Marketing status, source, consent, and campaign recency |
| pendo | product_events | One row per product event | Pendo-shaped application activity in JSON Lines format |

## Key relationships

- `nurse_id` joins nurses, applications, assignments, screenings, scores, events, surveys, Marketo leads, Pendo events, and overrides.
- `facility_id` joins facilities and shifts.
- `shift_id` joins shifts, applications, and assignments.
- City and specialty join operational shifts to external market conditions.

## Storage convention

```text
source=<source>/entity=<entity>/load_date=YYYY-MM-DD/<entity>.<csv|jsonl>
```

Each generator run replaces its local output directory. S3 retains versions at the bucket level.
