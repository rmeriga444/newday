{{
    config(
        materialized         = 'incremental',
        unique_key           = 'product_category_sk',
        incremental_strategy = 'merge',
        cluster_by           = ['category_name'],
        tags                 = ['silver', 'products']
    )
}}

with source as (

    select * from {{ ref('product_category') }}
    {{ get_incremental_timestamp('_loaded_at', '_processed_at') }}

),

casted as (

    select
        {{ generate_surrogate_key(['product_id', 'category_id']) }}     as product_category_sk,
        {{ generate_surrogate_key(['product_id']) }}                     as product_sk,

        trim(product_id)                                                 as product_id,
        trim(category_id)                                                as category_id,
        trim(category_name)                                              as category_name,
        trim(subcategory)                                                as subcategory,
        trim(brand)                                                      as brand,
        trim(supplier_id)                                                as supplier_id,

        try_cast(cost_price as numeric(18, 2))                           as cost_price,
        try_cast(retail_price as numeric(18, 2))                         as retail_price,
        try_cast(margin_percent as numeric(8, 2))                        as margin_percent,

        round(
            try_cast(retail_price as numeric(18, 2))
            - try_cast(cost_price as numeric(18, 2))
        , 2)                                                             as gross_margin_amount,

        try_cast(stock_level as integer)                                 as stock_level,
        try_cast(reorder_point as integer)                               as reorder_point,
        try_cast(stock_level as integer)
            <= try_cast(reorder_point as integer)                        as is_below_reorder_point,

        case
            when lower(trim(discontinued)) = 'true' then true
            else false
        end                                                              as is_discontinued,

        try_cast(launch_date as date)                                    as launch_date,
        try_cast(last_updated as date)                                   as last_updated,
        current_timestamp()                                              as _processed_at

    from source
    where product_id is not null

)

select * from casted
