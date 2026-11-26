{#-
  Weekly net revenue forecast with an honest backtest.

  The last `forecast_holdout_weeks` complete weeks are hidden from every
  method; forecasts for them are made from the training data only (a single
  forecast origin, horizons 1..N). The same methods are then re-fitted on all
  data and projected `forecast_horizon_weeks` into the future.

  Methods (deliberately simple, explainable baselines):
    naive_last_week        last observed week, held flat
    moving_avg_4w          mean of the last 4 observed weeks, held flat
    seasonal_naive         same week one year earlier (t - 52 weeks)
    seasonal_naive_growth  seasonal_naive x trailing year-over-year growth,
                           growth = sum(last G weeks) / sum(same weeks a year earlier)
-#}

{%- set holdout = var('forecast_holdout_weeks') -%}
{%- set horizon = var('forecast_horizon_weeks') -%}
{%- set growth_window = var('forecast_growth_window_weeks') %}

with weekly as (
    select week_start, net_revenue_gbp from {{ ref('mart_weekly_revenue') }}
),

bounds as (
    select max(week_start) as last_week from weekly
),

origins as (
    -- backtest origin: last training week; future origin: last observed week
    select 'holdout' as split, {{ add_days('last_week', -7 * holdout) }} as origin_week from bounds
    union all
    select 'future' as split, last_week as origin_week from bounds
),

targets as (
    {%- for h in range(1, [holdout, horizon] | max + 1) %}
    select o.split, o.origin_week, {{ h }} as horizon_weeks,
           {{ add_days('o.origin_week', 7 * h) }} as week_start
    from origins as o
    where ({{ h }} <= {{ holdout }} and o.split = 'holdout')
       or ({{ h }} <= {{ horizon }} and o.split = 'future')
    {% if not loop.last %}union all{% endif %}
    {%- endfor %}
),

origin_stats as (
    select
        o.split,
        max(case when w.week_start = o.origin_week then w.net_revenue_gbp end) as last_week_value,
        avg(case when w.week_start > {{ add_days('o.origin_week', -28) }}
                  and w.week_start <= o.origin_week then w.net_revenue_gbp end) as avg_last_4w,
        sum(case when w.week_start > {{ add_days('o.origin_week', -7 * growth_window) }}
                  and w.week_start <= o.origin_week then w.net_revenue_gbp end) as recent_sum,
        sum(case when w.week_start > {{ add_days('o.origin_week', -7 * growth_window - 364) }}
                  and w.week_start <= {{ add_days('o.origin_week', -364) }}
                 then w.net_revenue_gbp end) as year_ago_sum
    from origins as o
    cross join weekly as w
    group by o.split
),

forecasts as (
    select
        t.split,
        t.origin_week,
        t.horizon_weeks,
        t.week_start,
        actual.net_revenue_gbp                                           as actual_net_revenue_gbp,
        s.last_week_value                                                as naive_last_week,
        s.avg_last_4w                                                    as moving_avg_4w,
        ly.net_revenue_gbp                                               as seasonal_naive,
        ly.net_revenue_gbp * (s.recent_sum / nullif(s.year_ago_sum, 0)) as seasonal_naive_growth,
        s.recent_sum / nullif(s.year_ago_sum, 0)                         as growth_factor
    from targets as t
    inner join origin_stats as s on t.split = s.split
    -- holdout actuals exist; future weeks have none
    left join weekly as actual on actual.week_start = t.week_start
    left join weekly as ly     on ly.week_start = {{ add_days('t.week_start', -364) }}
),

training as (
    select
        'train'                              as split,
        cast(null as date)                   as origin_week,
        cast(null as integer)                as horizon_weeks,
        w.week_start,
        w.net_revenue_gbp                    as actual_net_revenue_gbp,
        cast(null as {{ dbt.type_float() }}) as naive_last_week,
        cast(null as {{ dbt.type_float() }}) as moving_avg_4w,
        cast(null as {{ dbt.type_float() }}) as seasonal_naive,
        cast(null as {{ dbt.type_float() }}) as seasonal_naive_growth,
        cast(null as {{ dbt.type_float() }}) as growth_factor
    from weekly as w
    cross join bounds as b
    where w.week_start <= {{ add_days('b.last_week', -7 * holdout) }}
)

select * from training
union all
select * from forecasts
