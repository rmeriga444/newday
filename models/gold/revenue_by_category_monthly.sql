{{
    config(
        materialized = 'table',
        cluster_by   = ['order_year', 'category_name'],
        tags         = ['gold', 'revenue', 'q1']
    )
}}

with base as (

    select * from {{ ref('sales_enriched') }}

),

monthly as (

    select
        date_trunc('month', order_date)         as order_month,
        category_name,
        round(sum(order_amount), 2)             as total_revenue,
        count(distinct order_sk)                as total_orders,
        sum(order_quantity)                     as total_units_sold,
        round(avg(order_amount), 2)             as avg_order_value

    from base
    group by 1, 2

)

select
    order_month,
    category_name,
    total_revenue,
    total_orders,
    total_units_sold,
    avg_order_value,
    convert_timezone('UTC', current_timestamp()) as load_ts

from monthly
order by order_month, total_revenue desc
