{#- One row per RFM segment with size and value. -#}

with c as (
    select * from {{ ref('mart_customer_rfm') }}
)

select
    rfm_segment,
    count(*)                                                       as customers,
    count(*) * 1.0 / sum(count(*)) over ()                         as share_of_customers,
    sum(monetary_gbp)                                              as net_revenue_gbp,
    sum(monetary_gbp) / nullif(sum(sum(monetary_gbp)) over (), 0)  as share_of_net_revenue,
    avg(recency_days)                                              as avg_recency_days,
    avg(frequency)                                                 as avg_frequency,
    avg(monetary_gbp)                                              as avg_monetary_gbp,
    {{ median_agg("monetary_gbp") }}                                 as median_monetary_gbp,
    avg(loyalty_score)                                             as avg_loyalty_score
from c
group by rfm_segment
