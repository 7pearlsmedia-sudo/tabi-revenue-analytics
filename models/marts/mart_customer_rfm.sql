{#-
  RFM segmentation for identified customers, as of the day after the data ends.

  - Recency   = days since the customer's last order
  - Frequency = number of distinct orders (sales invoices)
  - Monetary  = net merchandise revenue (sales minus cancellations), GBP
  Scores are quintiles (1 = worst, 5 = best). Segment names follow the widely
  used R x FM grid. loyalty_score (0-100) is the mean percentile rank of
  R, F and M - a transparent composite, not a predictive model.
-#}

with bounds as (
    select snapshot_date from {{ ref('int_calendar_bounds') }}
),

orders as (
    select
        customer_id,
        count(*)                as frequency,
        min(invoice_date)       as first_order_date,
        max(invoice_date)       as last_order_date
    from {{ ref('int_invoices') }}
    where customer_id is not null
    group by customer_id
),

money as (
    select
        customer_id,
        sum(net_amount_gbp)     as monetary_gbp,
        sum(gross_sales_gbp)    as gross_sales_gbp,
        sum(returns_gbp)        as returns_gbp
    from {{ ref('int_merchandise_lines') }}
    where customer_id is not null
    group by customer_id
),

home_country as (
    select customer_id, country_name, region
    from (
        select
            customer_id, country_name, region,
            row_number() over (partition by customer_id order by count(*) desc, country_name) as rn
        from {{ ref('int_invoices') }}
        where customer_id is not null
        group by customer_id, country_name, region
    ) as c
    where rn = 1
),

base as (
    select
        o.customer_id,
        h.country_name,
        h.region,
        o.first_order_date,
        o.last_order_date,
        {{ days_between('o.last_order_date', 'b.snapshot_date') }}   as recency_days,
        o.frequency,
        m.monetary_gbp,
        m.gross_sales_gbp,
        m.returns_gbp
    from orders as o
    inner join money as m on o.customer_id = m.customer_id
    left join home_country as h on o.customer_id = h.customer_id
    cross join bounds as b
),

scored as (
    select
        *,
        ntile(5) over (order by recency_days desc, customer_id)      as r_score,
        ntile(5) over (order by frequency asc, customer_id)          as f_score,
        ntile(5) over (order by monetary_gbp asc, customer_id)       as m_score,
        percent_rank() over (order by recency_days desc)             as r_pct,
        percent_rank() over (order by frequency asc)                 as f_pct,
        percent_rank() over (order by monetary_gbp asc)              as m_pct
    from base
),

with_fm as (
    select
        *,
        cast(round((f_score + m_score) / 2.0 + 0.001) as integer) as fm_score
    from scored
)

select
    customer_id,
    country_name,
    region,
    first_order_date,
    last_order_date,
    recency_days,
    frequency,
    monetary_gbp,
    gross_sales_gbp,
    returns_gbp,
    r_score,
    f_score,
    m_score,
    fm_score,
    cast(round(100 * (r_pct + f_pct + m_pct) / 3) as integer)        as loyalty_score,
    case
        when r_score >= 4 and fm_score >= 4 then 'Champions'
        when r_score >= 3 and fm_score >= 4 then 'Loyal customers'
        when r_score >= 4 and fm_score = 3  then 'Potential loyalists'
        when r_score = 5  and fm_score <= 2 then 'New customers'
        when r_score = 4  and fm_score <= 2 then 'Promising'
        when r_score = 3  and fm_score = 3  then 'Need attention'
        when r_score = 3  and fm_score <= 2 then 'About to sleep'
        when r_score <= 2 and fm_score = 5  then 'Cannot lose them'
        when r_score <= 2 and fm_score >= 3 then 'At risk'
        when r_score = 2  and fm_score <= 2 then 'Hibernating'
        else 'Lost'
    end                                                               as rfm_segment
from with_fm
