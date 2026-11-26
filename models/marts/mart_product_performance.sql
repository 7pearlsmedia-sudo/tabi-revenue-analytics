{#- Revenue, returns and reach per product (stock code). -#}

with lines as (
    select * from {{ ref('int_merchandise_lines') }}
),

descriptions as (
    -- most frequent non-null description per stock code (ties: alphabetical)
    select stock_code, description
    from (
        select
            stock_code,
            description,
            row_number() over (partition by stock_code order by count(*) desc, description) as rn
        from lines
        where description is not null
        group by stock_code, description
    ) as d
    where rn = 1
),

agg as (
    select
        stock_code,
        sum(gross_sales_gbp)                                                 as gross_sales_gbp,
        sum(returns_gbp)                                                     as returns_gbp,
        sum(net_amount_gbp)                                                  as net_revenue_gbp,
        sum(units_sold)                                                      as units_sold,
        sum(units_returned)                                                  as units_returned,
        count(distinct case when line_type = 'sale' then invoice_id end)     as orders,
        count(distinct case when line_type = 'sale' then customer_id end)    as customers,
        count(distinct case when line_type = 'sale' then country end)        as countries,
        min(case when line_type = 'sale' then invoice_date end)              as first_sold_on,
        max(case when line_type = 'sale' then invoice_date end)              as last_sold_on
    from lines
    group by stock_code
),

ranked as (
    select
        a.*,
        row_number() over (order by a.net_revenue_gbp desc, a.stock_code)    as revenue_rank,
        sum(a.net_revenue_gbp) over (
            order by a.net_revenue_gbp desc, a.stock_code
            rows between unbounded preceding and current row
        ) / nullif(sum(a.net_revenue_gbp) over (), 0)                        as cumulative_revenue_share
    from agg as a
)

select
    r.stock_code,
    coalesce(d.description, '(no description)')                              as description,
    r.gross_sales_gbp,
    r.returns_gbp,
    r.net_revenue_gbp,
    r.returns_gbp / nullif(r.gross_sales_gbp, 0)                             as return_rate,
    r.units_sold,
    r.units_returned,
    r.orders,
    r.customers,
    r.countries,
    r.first_sold_on,
    r.last_sold_on,
    r.revenue_rank,
    r.cumulative_revenue_share,
    case
        when r.cumulative_revenue_share <= 0.80 then 'A'
        when r.cumulative_revenue_share <= 0.95 then 'B'
        else 'C'
    end                                                                      as abc_class
from ranked as r
left join descriptions as d on r.stock_code = d.stock_code
