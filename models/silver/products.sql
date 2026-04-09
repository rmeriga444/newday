{{
    config(
        materialized         = 'incremental',
        unique_key           = 'product_sk',
        incremental_strategy = 'merge',
        tags                 = ['silver', 'products']
    )
}}

with source as (

    select * from {{ ref('raw_products') }}
    {{ get_incremental_timestamp('load_ts', '_processed_at') }}

),

casted as (

    select
        {{ generate_surrogate_key(['product_id']) }}        as product_sk,
        trim(product_id)                                    as product_id,
        trim(product_category_id)                           as product_category_id,
        trim(product_name)                                  as product_name,
        current_timestamp()                                 as _processed_at

    from source
    where product_id is not null

)

select * from casted
