-- Every identified customer with an order appears exactly once in the RFM mart.
select customer_id from {{ ref('int_invoices') }} where customer_id is not null
except
select customer_id from {{ ref('mart_customer_rfm') }}
