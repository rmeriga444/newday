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
    {{ get_incremental_timestamp('load_ts', 'load_ts') }}

),

casted as (

    select
        {{ generate_surrogate_key(['product_id']) }}        as product_sk,
        trim(product_id)                                    as product_id,
        trim(product_category_id)                           as product_category_id,
        trim(product_name)                                  as product_name,
        convert_timezone('UTC', current_timestamp())                                 as load_ts

    from source
    where product_id is not null

)

select * from casted
