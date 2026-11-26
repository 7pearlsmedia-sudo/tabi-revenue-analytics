{#- Audit trail of the cleaning: how many raw lines end up where, and why.
    Published in the dashboard so every number can be traced back. -#}

with raw_lines as (
    select count(*) as n from {{ source('online_retail', 'invoice_lines') }}
),

staged as (
    select * from {{ ref('stg_online_retail__invoice_lines') }}
),

overlap as (
    select count(*) as n
    from {{ source('online_retail', 'invoice_lines') }}
    where _source_sheet = 'Year 2009-2010'
      and cast(InvoiceDate as timestamp) >= cast('2010-12-01' as timestamp)
)

select 10 as step, 'Raw invoice lines in the source workbook' as label,
       (select n from raw_lines) as line_count, cast(null as {{ dbt.type_float() }}) as amount_gbp
union all
select 20, 'Removed: worksheet overlap (2010-12-01..09 appears in both sheets)',
       (select n from overlap), null
union all
select 30, 'Removed: exact duplicate lines',
       (select n from raw_lines) - (select n from overlap) - (select count(*) from staged), null
union all
select 40, 'Clean lines after de-duplication', (select count(*) from staged), sum(line_amount_gbp)
from staged
union all
select 50, 'Excluded: non-product lines (postage, fees, adjustments, vouchers...)',
       count(*), sum(line_amount_gbp)
from staged where not is_merchandise
union all
select 60, 'Excluded: zero-price lines and stock write-offs',
       count(*), sum(line_amount_gbp)
from staged where is_merchandise and (line_type in ('stock_adjustment', 'bad_debt_adjustment') or unit_price_gbp <= 0)
union all
select 70, 'Kept: product sales lines', count(*), sum(gross_sales_gbp)
from {{ ref('int_merchandise_lines') }} where line_type = 'sale'
union all
select 80, 'Kept: product cancellation lines (returns)', count(*), -sum(returns_gbp)
from {{ ref('int_merchandise_lines') }} where line_type = 'cancellation'
union all
select 90, 'Kept lines without a customer id (guest / unidentified)', count(*), sum(net_amount_gbp)
from {{ ref('int_merchandise_lines') }} where not is_identified_customer
