with latest_score as (
  select *
  from {{ source('raw', 'nurse_scores') }}
  qualify row_number() over (partition by nurse_id order by score_date desc) = 1
),
latest_screening as (
  select *
  from {{ source('raw', 'health_screenings') }}
  qualify row_number() over (partition by nurse_id order by screened_on desc) = 1
),
active_override as (
  select *
  from {{ source('raw', 'manual_overrides') }}
  where current_date between effective_date and expires_on
  qualify row_number() over (partition by nurse_id order by effective_date desc) = 1
)
select
  n.*,
  s.shift_completion_probability,
  s.churn_probability,
  s.estimated_12m_value,
  s.eligible_for_recommendations,
  h.cleared_to_work,
  h.license_valid,
  o.override_type,
  o.reason_code as override_reason,
  iff(o.nurse_id is not null, true, false) as has_active_override,
  iff(n.days_since_active >= 30 or s.churn_probability >= 0.65, true, false) as is_at_risk
from {{ ref('stg_nurses') }} n
left join latest_score s using (nurse_id)
left join latest_screening h using (nurse_id)
left join active_override o using (nurse_id)
