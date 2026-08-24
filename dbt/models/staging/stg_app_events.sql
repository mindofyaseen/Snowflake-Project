select
  payload:event_id::varchar as event_id,
  payload:event_name::varchar as event_name,
  payload:event_timestamp::timestamp_tz as event_timestamp,
  payload:nurse_id::varchar as nurse_id,
  payload:platform::varchar as platform,
  payload:session_id::varchar as session_id
from {{ source('raw', 'app_events') }}
