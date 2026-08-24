select *
from {{ ref('audience_at_risk_nurses') }}
where not notification_opt_in
   or has_active_override
   or email is null
