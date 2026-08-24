select
  nurse_id,
  full_name,
  lower(email) as email,
  city,
  specialty,
  experience_years,
  hire_date,
  license_expiry_date,
  completed_shifts_lifetime,
  cancelled_shifts_lifetime,
  days_since_active,
  notification_opt_in,
  record_updated_at,
  cancelled_shifts_lifetime / nullif(completed_shifts_lifetime + cancelled_shifts_lifetime, 0) as lifetime_cancel_rate
from {{ source('raw', 'nurses') }}
