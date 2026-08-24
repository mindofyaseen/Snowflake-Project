select a.*
from {{ ref('stg_applications') }} a
left join {{ ref('stg_shifts') }} s using (shift_id)
left join {{ ref('stg_nurses') }} n using (nurse_id)
where s.shift_id is null or n.nurse_id is null
