{{
    config(
        materialized = 'view',
        tags         = ['bronze', 'sales']
    )
}}

select
    order_id,
    product_id,
    customer_id,
    order_date,
    order_amount,
    order_quantity,
    payment_method,
    discount_applied,
    shipping_cost,
    created_at,
    convert_timezone('UTC', current_timestamp())                     as load_ts

from {{ source('raw', 'sales_fact') }}
