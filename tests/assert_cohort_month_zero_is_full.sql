-- By definition every customer is active in their first month (retention = 100%).
select *
from {{ ref('mart_cohort_retention') }}
where months_since_first_order = 0
  and abs(retention_rate - 1) > 1e-9
