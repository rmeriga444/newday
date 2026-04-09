{{
    config(
        materialized = 'view',
        tags         = ['bronze', 'products']
    )
}}

select
    product_id,
    category_id,
    category_name,
    subcategory,
    brand,
    supplier_id,
    cost_price,
    retail_price,
    margin_percent,
    stock_level,
    reorder_point,
    discontinued,
    launch_date,
    last_updated,
    convert_timezone('UTC', current_timestamp())                     as load_ts

from {{ source('raw', 'product_category') }}
