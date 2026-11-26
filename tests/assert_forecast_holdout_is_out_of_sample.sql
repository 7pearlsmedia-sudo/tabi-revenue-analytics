-- The holdout must contain exactly the configured number of weeks, every one
-- strictly after the last training week, and every holdout week must have an
-- actual value and a forecast from each method.
with train_end as (
    select max(week_start) as last_train_week
    from {{ ref('mart_forecast_weekly') }}
    where split = 'train'
),
holdout as (
    select * from {{ ref('mart_forecast_weekly') }} where split = 'holdout'
)
select 'wrong holdout size' as problem
from holdout
having count(*) <> {{ var('forecast_holdout_weeks') }}
union all
select 'holdout overlaps training'
from holdout cross join train_end
where holdout.week_start <= train_end.last_train_week
union all
select 'missing actual or forecast'
from holdout
where actual_net_revenue_gbp is null
   or naive_last_week is null
   or moving_avg_4w is null
   or seasonal_naive is null
   or seasonal_naive_growth is null
