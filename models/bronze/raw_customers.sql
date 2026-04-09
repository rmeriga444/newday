{{
    config(
        materialized = 'view',
        tags         = ['bronze', 'customers']
    )
}}

select
    customer_id,
    customer_name,
    customer_email,
    start_date,
    end_date,
    status,
    current_timestamp()                     as load_ts

from {{ source('raw', 'customer') }}
