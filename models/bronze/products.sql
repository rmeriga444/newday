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
    current_timestamp()                     as _loaded_at,
    '{{ this.schema }}.{{ this.name }}'     as _source_relation

from {{ source('raw', 'product') }}
