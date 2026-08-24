select
  nurse_id,
  full_name,
  email,
  city,
  specialty,
  days_since_active,
  churn_probability,
  estimated_12m_value,
  notification_opt_in,
  has_active_override,
  override_type
from {{ ref('dim_nurses') }}
where is_at_risk
  and notification_opt_in
  and not has_active_override
  and coalesce(cleared_to_work, false)
