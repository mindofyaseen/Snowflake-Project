select
  application_id,
  shift_id,
  nurse_id,
  lower(application_status) as application_status,
  applied_at,
  lower(source_channel) as source_channel
from {{ source('raw', 'applications') }}
