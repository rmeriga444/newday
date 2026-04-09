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
    current_timestamp()                     as _loaded_at,
    '{{ this.schema }}.{{ this.name }}'     as _source_relation

from {{ source('raw', 'customer') }}
