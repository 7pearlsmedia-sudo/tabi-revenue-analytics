{#- One row per sales invoice (order). Cancellation invoices are not orders. -#}

select
    invoice_id,
    min(invoiced_at)                 as invoiced_at,
    min(invoice_date)                as invoice_date,
    min(invoice_month)               as invoice_month,
    min(invoice_week)                as invoice_week,
    max(customer_id)                 as customer_id,
    max(country)                     as country,
    max(country_name)                as country_name,
    max(region)                      as region,
    count(*)                         as line_count,
    count(distinct stock_code)       as distinct_products,
    sum(units_sold)                  as units,
    sum(gross_sales_gbp)             as order_value_gbp
from {{ ref('int_merchandise_lines') }}
where line_type = 'sale'
group by invoice_id
