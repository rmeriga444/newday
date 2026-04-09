{{
    config(
        materialized         = 'incremental',
        unique_key           = 'order_sk',
        incremental_strategy = 'merge',
        cluster_by           = ['order_date', 'customer_id'],
        tags                 = ['silver', 'sales']
    )
}}

with source as (

    select * from {{ ref('sales_fact') }}
    {{ get_incremental_timestamp('_loaded_at', '_processed_at') }}

),

casted as (

    select
        {{ generate_surrogate_key(['order_id']) }}                                          as order_sk,
        {{ generate_surrogate_key(['customer_id']) }}                                       as customer_sk,
        {{ generate_surrogate_key(['product_id']) }}                                        as product_sk,

        trim(order_id)                                                                      as order_id,
        trim(product_id)                                                                    as product_id,
        trim(customer_id)                                                                   as customer_id,

        try_cast(order_date as date)                                                        as order_date,
        date_trunc('month',   try_cast(order_date as date))                                 as order_month,
        date_trunc('quarter', try_cast(order_date as date))                                 as order_quarter,
        year(try_cast(order_date as date))                                                  as order_year,
        month(try_cast(order_date as date))                                                 as order_month_num,
        quarter(try_cast(order_date as date))                                               as order_quarter_num,
        dayofweek(try_cast(order_date as date))                                             as order_day_of_week,
        dayofyear(try_cast(order_date as date))                                             as order_day_of_year,
        try_cast(created_at as timestamp_ntz)                                               as created_at,

        try_cast(order_amount as numeric(18, 2))                                            as order_amount,
        try_cast(order_quantity as integer)                                                 as order_quantity,
        coalesce(try_cast(discount_applied as numeric(8, 4)), 0)                            as discount_applied,
        coalesce(try_cast(shipping_cost as numeric(18, 2)), 0)                              as shipping_cost,
        try_cast(discount_applied as numeric(8, 4)) is null                                 as discount_was_null,
        try_cast(shipping_cost as numeric(18, 2)) is null                                   as shipping_was_null,

        lower(trim(payment_method))                                                         as payment_method,

        round(
            try_cast(order_amount as numeric(18, 2))
            * (1 - coalesce(try_cast(discount_applied as numeric(8, 4)), 0))
        , 2)                                                                                as net_order_amount,

        round(
            try_cast(order_amount as numeric(18, 2))
            * coalesce(try_cast(discount_applied as numeric(8, 4)), 0)
        , 2)                                                                                as discount_amount,

        {{ safe_divide(
            'try_cast(order_amount as numeric(18,2))',
            'nullif(try_cast(order_quantity as integer), 0)'
        ) }}                                                                                as unit_price,

        coalesce(try_cast(order_quantity as integer), 0) = 0                                as is_zero_quantity,

        coalesce(try_cast(discount_applied as numeric(8, 4)), 0)
            > {{ var('flag_discount_threshold') }}                                          as is_high_discount,

        coalesce(try_cast(shipping_cost as numeric(18, 2)), 0)
            > ({{ var('flag_shipping_pct') }} * try_cast(order_amount as numeric(18, 2)))   as is_high_shipping,

        current_timestamp()                                                                 as _processed_at

    from source
    where order_id is not null

)

select * from casted
