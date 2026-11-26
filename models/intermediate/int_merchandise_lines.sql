{#- Product sales and cancellations only: the basis for every revenue metric.
    Excludes postage, fees, accounting adjustments, manual entries, vouchers,
    tests, zero-price lines and stock write-offs (see staging line_type). -#}

with lines as (

    select * from {{ ref('stg_online_retail__invoice_lines') }}
    where is_merchandise
      and line_type in ('sale', 'cancellation')
      and unit_price_gbp > 0

),

regions as (

    select * from {{ ref('country_regions') }}

)

select
    l.invoice_line_id,
    l.invoice_id,
    l.line_type,
    l.stock_code,
    l.description,
    l.quantity,
    l.unit_price_gbp,
    l.line_amount_gbp                                                  as net_amount_gbp,
    case when l.line_type = 'sale' then l.line_amount_gbp else 0 end   as gross_sales_gbp,
    case when l.line_type = 'cancellation' then -l.line_amount_gbp else 0 end
                                                                       as returns_gbp,
    case when l.line_type = 'sale' then l.quantity else 0 end          as units_sold,
    case when l.line_type = 'cancellation' then -l.quantity else 0 end as units_returned,
    l.invoiced_at,
    l.invoice_date,
    {{ month_start('l.invoice_date') }}                                as invoice_month,
    {{ week_start('l.invoice_date') }}                                 as invoice_week,
    l.customer_id,
    l.customer_id is not null                                          as is_identified_customer,
    l.country,
    coalesce(r.country_name, l.country)                                as country_name,
    coalesce(r.region, 'Unspecified')                                  as region
from lines as l
left join regions as r
    on l.country = r.country
