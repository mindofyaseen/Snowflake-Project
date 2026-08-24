select
  market_date,
  city,
  specialty,
  open_shift_demand,
  estimated_available_supply,
  open_shift_demand - estimated_available_supply as supply_gap,
  open_shift_demand / nullif(estimated_available_supply, 0) as demand_supply_ratio,
  market_hourly_rate,
  external_demand_index
from {{ source('raw', 'market_conditions') }}
