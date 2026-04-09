{{
    config(
        materialized         = 'incremental',
        unique_key           = 'customer_sk',
        incremental_strategy = 'merge',
        cluster_by           = ['status'],
        tags                 = ['silver', 'customers']
    )
}}

with source as (

    select * from {{ ref('raw_customers') }}
    {{ get_incremental_timestamp('load_ts', '_processed_at') }}

),

casted as (

    select
        {{ generate_surrogate_key(['customer_id']) }}       as customer_sk,
        trim(customer_id)                                   as customer_id,
        trim(customer_name)                                 as customer_name,
        lower(trim(customer_email))                         as customer_email,
        lower(trim(status))                                 as status,
        lower(trim(status)) = 'active'                      as is_active,
        try_cast(start_date as date)                        as valid_from,
        try_cast(end_date as date)                          as valid_to,
        current_timestamp()                                 as _processed_at

    from source
    where customer_id is not null

)

select * from casted
