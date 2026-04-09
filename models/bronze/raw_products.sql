{{
    config(
        materialized = 'view',
        tags         = ['bronze', 'products']
    )
}}

select
    product_id,
    product_name,
    product_category_id,
    current_timestamp()                     as load_ts

from {{ source('raw', 'product') }}
