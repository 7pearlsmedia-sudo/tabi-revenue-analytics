{#- Revenue and returns by country, split into two comparable 12-month
    periods: Dec 2009 - Nov 2010 ("FY1") and Dec 2010 - Nov 2011 ("FY2"). -#}

with lines as (
    select
        *,
        case
            when invoice_month between cast('2009-12-01' as date) and cast('2010-11-01' as date) then 'fy1'
            when invoice_month between cast('2010-12-01' as date) and cast('2011-11-01' as date) then 'fy2'
        end as period
    from {{ ref('int_merchandise_lines') }}
),

agg as (
    select
        country,
        max(country_name)                                                    as country_name,
        max(region)                                                          as region,
        sum(gross_sales_gbp)                                                 as gross_sales_gbp,
        sum(returns_gbp)                                                     as returns_gbp,
        sum(net_amount_gbp)                                                  as net_revenue_gbp,
        count(distinct case when line_type = 'sale' then invoice_id end)     as orders,
        count(distinct customer_id)                                          as customers,
        sum(case when period = 'fy1' then net_amount_gbp else 0 end)         as net_revenue_fy1_gbp,
        sum(case when period = 'fy2' then net_amount_gbp else 0 end)         as net_revenue_fy2_gbp
    from lines
    group by country
)

select
    country,
    country_name,
    region,
    gross_sales_gbp,
    returns_gbp,
    net_revenue_gbp,
    returns_gbp / nullif(gross_sales_gbp, 0)                                 as return_rate,
    net_revenue_gbp / nullif(sum(net_revenue_gbp) over (), 0)                as share_of_net_revenue,
    orders,
    customers,
    gross_sales_gbp / nullif(orders, 0)                                      as avg_order_value_gbp,
    net_revenue_fy1_gbp,
    net_revenue_fy2_gbp,
    case when net_revenue_fy1_gbp > 0
         then net_revenue_fy2_gbp / net_revenue_fy1_gbp - 1 end              as yoy_growth
from agg
