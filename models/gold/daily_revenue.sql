{{
    config(
        materialized = 'table',
        cluster_by   = ['order_date'],
        tags         = ['gold', 'revenue', 'q7']
    )
}}

{{ assert_date_range_valid(var('start_date'), var('end_date')) }}

with base as (

    select * from {{ ref('sales_enriched') }}
    where order_date::date >= {{ get_start_date() }}
      and order_date::date <= {{ get_end_date() }}

),

daily as (

    select
        order_date,
        round(sum(order_amount), 2)             as total_revenue,
        count(distinct order_sk)                as total_orders,
        round(avg(order_amount), 2)             as avg_order_value

    from base
    group by order_date

)

select
    order_date,
    total_revenue,
    total_orders,
    avg_order_value,
    convert_timezone('UTC', current_timestamp()) as load_ts

from daily
order by order_date
