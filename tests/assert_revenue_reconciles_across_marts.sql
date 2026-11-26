-- Net revenue must be identical whether summed by line, country or product.
-- Returns rows (= failure) if any total differs by more than 1 penny.
with totals as (
    select 'lines' as source, sum(net_amount_gbp) as net from {{ ref('int_merchandise_lines') }}
    union all
    select 'countries', sum(net_revenue_gbp) from {{ ref('mart_country_performance') }}
    union all
    select 'products', sum(net_revenue_gbp) from {{ ref('mart_product_performance') }}
)
select t.*
from totals as t
cross join (select net from totals where source = 'lines') as base
where abs(t.net - base.net) > 0.01
