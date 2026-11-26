{#-
  Typed, de-duplicated invoice lines with a business classification.

  Cleaning rules (each one is documented in the README "Data quality" section):
  1. The two worksheets overlap on 2010-12-01 .. 2010-12-09 with identical rows.
     Those dates are taken from the 2010-2011 sheet only.
  2. Exact duplicate lines (all fields equal) are kept once.
  3. Every line gets a line_type and an is_merchandise flag; nothing is
     silently dropped here, so downstream models choose what to include.
-#}

with source as (

    select * from {{ source('online_retail', 'invoice_lines') }}

),

typed as (

    select
        trim(Invoice)                                        as invoice_id,
        trim(StockCode)                                      as stock_code,
        nullif(trim(Description), '')                        as description,
        cast(Quantity as integer)                            as quantity,
        cast(InvoiceDate as timestamp)                       as invoiced_at,
        cast(Price as {{ dbt.type_float() }})                as unit_price_gbp,
        -- Excel stores the id as a number ("13085" / "13085.0"); normalise to text.
        cast(cast(cast({{ adapter.quote("Customer ID") }} as {{ dbt.type_float() }}) as integer) as {{ dbt.type_string() }})
                                                             as customer_id,
        trim(Country)                                        as country,
        _source_sheet                                        as source_sheet
    from source

),

without_sheet_overlap as (

    select *
    from typed
    where not (
        source_sheet = 'Year 2009-2010'
        and invoiced_at >= cast('2010-12-01' as timestamp)
    )

),

deduplicated as (

    select
        *,
        row_number() over (
            partition by invoice_id, stock_code, description, quantity,
                         invoiced_at, unit_price_gbp, customer_id, country
            order by source_sheet
        ) as duplicate_rank
    from without_sheet_overlap

),

non_merch as (

    select stock_code, category from {{ ref('non_merchandise_codes') }}

)

select
    {{ dbt.hash(dbt.concat([
        "d.invoice_id", "'|'", "d.stock_code", "'|'",
        "coalesce(d.description, '')", "'|'", "cast(d.quantity as " ~ dbt.type_string() ~ ")", "'|'",
        "cast(d.invoiced_at as " ~ dbt.type_string() ~ ")", "'|'",
        "cast(d.unit_price_gbp as " ~ dbt.type_string() ~ ")", "'|'",
        "coalesce(d.customer_id, '')", "'|'", "d.country"
    ])) }}                                                   as invoice_line_id,
    d.invoice_id,
    d.stock_code,
    d.description,
    d.quantity,
    d.unit_price_gbp,
    d.quantity * d.unit_price_gbp                            as line_amount_gbp,
    d.invoiced_at,
    cast(d.invoiced_at as date)                              as invoice_date,
    d.customer_id,
    d.country,
    case
        when substr(d.invoice_id, 1, 1) = 'A' then 'bad_debt_adjustment'
        when substr(d.invoice_id, 1, 1) = 'C' then 'cancellation'
        when d.quantity <= 0 or d.unit_price_gbp <= 0 then 'stock_adjustment'
        else 'sale'
    end                                                      as line_type,
    nm.stock_code is null                                    as is_merchandise,
    nm.category                                              as non_merchandise_category,
    d.source_sheet
from deduplicated as d
left join non_merch as nm
    on d.stock_code = nm.stock_code
where d.duplicate_rank = 1
