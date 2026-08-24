with application_rollup as (
  select
    shift_id,
    count(*) as application_count,
    count_if(application_status = 'accepted') as accepted_application_count,
    min(applied_at) as first_application_at
  from {{ ref('stg_applications') }}
  group by 1
),
assignment_rollup as (
  select
    shift_id,
    count(*) as assignment_count,
    count_if(assignment_outcome = 'completed') as completed_assignment_count,
    count_if(cancelled_by not in ('none', '')) as cancelled_assignment_count,
    avg(assigned_hourly_rate) as average_assigned_hourly_rate
  from {{ ref('stg_assignments') }}
  group by 1
)
select
  s.*,
  f.facility_name,
  f.facility_type,
  f.quality_tier,
  coalesce(a.application_count, 0) as application_count,
  coalesce(a.accepted_application_count, 0) as accepted_application_count,
  a.first_application_at,
  coalesce(x.assignment_count, 0) as assignment_count,
  coalesce(x.completed_assignment_count, 0) as completed_assignment_count,
  coalesce(x.cancelled_assignment_count, 0) as cancelled_assignment_count,
  x.average_assigned_hourly_rate,
  iff(x.assignment_count > 0, true, false) as was_filled,
  iff(x.completed_assignment_count > 0, true, false) as was_completed
from {{ ref('stg_shifts') }} s
left join {{ source('raw', 'facilities') }} f using (facility_id)
left join application_rollup a using (shift_id)
left join assignment_rollup x using (shift_id)
