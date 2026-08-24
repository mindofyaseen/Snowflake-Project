select
  campaign_date,
  channel,
  city,
  sum(impressions) as impressions,
  sum(clicks) as clicks,
  sum(applicants) as applicants,
  sum(qualified_applicants) as qualified_applicants,
  sum(spend_usd) as spend_usd,
  sum(clicks) / nullif(sum(impressions), 0) as click_through_rate,
  sum(qualified_applicants) / nullif(sum(applicants), 0) as qualification_rate,
  sum(spend_usd) / nullif(sum(applicants), 0) as cost_per_applicant,
  sum(spend_usd) / nullif(sum(qualified_applicants), 0) as cost_per_qualified_applicant
from {{ source('raw', 'campaign_performance') }}
group by 1, 2, 3
