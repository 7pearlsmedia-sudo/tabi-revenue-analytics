{#- Net merchandise revenue per complete Monday-Sunday week, with a gap-free
    calendar (weeks with no trading, e.g. Christmas closure, are 0). -#}

with bounds as (
    select * from {{ ref('int_calendar_bounds') }}
),

digits as (
    {% for d in range(10) %}select {{ d }} as d{% if not loop.last %} union all {% endif %}{% endfor %}
),

numbers as (
    select a.d + 10 * b.d + 100 * c.d as n
    from digits as a cross join digits as b cross join digits as c
),

spine as (
    select {{ add_days('b.first_complete_week', '7 * n.n') }} as week_start
    from numbers as n
    cross join bounds as b
    where {{ add_days('b.first_complete_week', '7 * n.n') }} <= b.last_complete_week
),

weekly as (
    select
        invoice_week                         as week_start,
        sum(gross_sales_gbp)                 as gross_sales_gbp,
        sum(returns_gbp)                     as returns_gbp,
        sum(net_amount_gbp)                  as net_revenue_gbp,
        count(distinct case when line_type = 'sale' then invoice_id end) as orders
    from {{ ref('int_merchandise_lines') }}
    group by invoice_week
)

select
    s.week_start,
    coalesce(w.gross_sales_gbp, 0)   as gross_sales_gbp,
    coalesce(w.returns_gbp, 0)       as returns_gbp,
    coalesce(w.net_revenue_gbp, 0)   as net_revenue_gbp,
    coalesce(w.orders, 0)            as orders
from spine as s
left join weekly as w on s.week_start = w.week_start
