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
    current_timestamp()                     as _loaded_at,
    '{{ this.schema }}.{{ this.name }}'     as _source_relation

from {{ source('raw', 'sales_fact') }}
