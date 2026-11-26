{#- Holdout error of each forecast method. Lower WAPE is better.
    WAPE = sum(|forecast - actual|) / sum(actual)
    bias = sum(forecast - actual) / sum(actual)   (positive = over-forecast) -#}

{%- set methods = ['naive_last_week', 'moving_avg_4w', 'seasonal_naive', 'seasonal_naive_growth'] %}

with holdout as (
    select * from {{ ref('mart_forecast_weekly') }}
    where split = 'holdout'
),

long_format as (
    {%- for m in methods %}
    select '{{ m }}' as method, week_start, actual_net_revenue_gbp as actual, {{ m }} as forecast
    from holdout
    {% if not loop.last %}union all{% endif %}
    {%- endfor %}
),

scored as (
    select
        method,
        count(*)                                               as holdout_weeks,
        min(week_start)                                        as holdout_start,
        max(week_start)                                        as holdout_end,
        avg(abs(forecast - actual))                            as mae_gbp,
        sum(abs(forecast - actual)) / nullif(sum(actual), 0)   as wape,
        sum(forecast - actual) / nullif(sum(actual), 0)        as bias,
        sum(actual)                                            as actual_total_gbp,
        sum(forecast)                                          as forecast_total_gbp
    from long_format
    group by method
)

select
    *,
    row_number() over (order by wape, method) as accuracy_rank
from scored
