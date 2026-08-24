select
  shift_id,
  facility_id,
  city,
  shift_date,
  start_hour,
  hours,
  specialty_required,
  base_hourly_rate,
  urgency,
  lower(status) as shift_status,
  posted_at,
  hours * base_hourly_rate as estimated_shift_value
from {{ source('raw', 'shifts') }}
qualify row_number() over (
  partition by shift_id
  order by posted_at desc
) = 1
