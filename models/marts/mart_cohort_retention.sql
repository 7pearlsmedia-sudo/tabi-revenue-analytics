{#-
  Monthly acquisition cohorts of identified customers.
  cohort_month = month of the customer's first order in the data.
  A customer is "retained" in month N if they placed at least one order then.
  Only complete months are used. Note: the first cohort (Dec 2009) is
  left-censored - it also contains customers who had bought before the
  data begins, so its retention is structurally higher.
-#}

with bounds as (
    select * from {{ ref('int_calendar_bounds') }}
),

orders as (
    select i.customer_id, i.invoice_month, i.order_value_gbp
    from {{ ref('int_invoices') }} as i
    cross join bounds as b
    where i.customer_id is not null
      and i.invoice_month <= b.last_complete_month
),

cohorts as (
    select customer_id, min(invoice_month) as cohort_month
    from orders
    group by customer_id
),

cohort_sizes as (
    select cohort_month, count(*) as cohort_size
    from cohorts
    group by cohort_month
),

activity as (
    select
        c.cohort_month,
        {{ months_between('c.cohort_month', 'o.invoice_month') }}   as months_since_first_order,
        count(distinct o.customer_id)                                as active_customers,
        sum(o.order_value_gbp)                                       as gross_sales_gbp
    from orders as o
    inner join cohorts as c on o.customer_id = c.customer_id
    group by 1, 2
)

select
    a.cohort_month,
    a.months_since_first_order,
    s.cohort_size,
    a.active_customers,
    a.active_customers * 1.0 / s.cohort_size                         as retention_rate,
    a.gross_sales_gbp,
    a.gross_sales_gbp / s.cohort_size                                as gross_sales_per_cohort_customer_gbp,
    a.cohort_month = (select first_month from bounds)                as is_left_censored_cohort
from activity as a
inner join cohort_sizes as s on a.cohort_month = s.cohort_month
