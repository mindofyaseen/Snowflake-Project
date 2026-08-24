select
  assignment_id,
  shift_id,
  nurse_id,
  assigned_hourly_rate,
  lower(assignment_outcome) as assignment_outcome,
  lower(cancelled_by) as cancelled_by
from {{ source('raw', 'assignments') }}
