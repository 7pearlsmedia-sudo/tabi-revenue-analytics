{#- Headline monthly KPIs over complete months only. -#}

with bounds as (
    select * from {{ ref('int_calendar_bounds') }}
),

lines as (
    select l.*
    from {{ ref('int_merchandise_lines') }} as l
    cross join bounds as b
    where l.invoice_month between b.first_month and b.last_complete_month
),

invoices as (
    select i.*
    from {{ ref('int_invoices') }} as i
    cross join bounds as b
    where i.invoice_month between b.first_month and b.last_complete_month
),

first_purchase as (
    select customer_id, min(invoice_month) as first_month
    from {{ ref('int_invoices') }}
    where customer_id is not null
    group by customer_id
),

revenue as (
    select
        invoice_month,
        sum(gross_sales_gbp)                                             as gross_sales_gbp,
        sum(returns_gbp)                                                 as returns_gbp,
        sum(net_amount_gbp)                                              as net_revenue_gbp,
        sum(case when is_identified_customer then gross_sales_gbp else 0 end)
                                                                         as identified_gross_sales_gbp
    from lines
    group by invoice_month
),

orders as (
    select
        invoice_month,
        count(*)                                      as orders,
        count(distinct customer_id)                   as active_customers,
        avg(order_value_gbp)                          as avg_order_value_gbp
    from invoices
    group by invoice_month
),

new_customers as (
    select first_month as invoice_month, count(*) as new_customers
    from first_purchase
    group by first_month
)

select
    r.invoice_month                                                     as month,
    r.gross_sales_gbp,
    r.returns_gbp,
    r.net_revenue_gbp,
    r.returns_gbp / nullif(r.gross_sales_gbp, 0)                        as return_rate,
    o.orders,
    o.avg_order_value_gbp,
    o.active_customers,
    coalesce(n.new_customers, 0)                                        as new_customers,
    o.active_customers - coalesce(n.new_customers, 0)                   as returning_customers,
    r.identified_gross_sales_gbp / nullif(r.gross_sales_gbp, 0)         as identified_sales_share
from revenue as r
left join orders as o on r.invoice_month = o.invoice_month
left join new_customers as n on r.invoice_month = n.invoice_month
