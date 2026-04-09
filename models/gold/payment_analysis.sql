{{
    config(
        materialized = 'table',
        tags         = ['gold', 'payments', 'q4']
    )
}}

with sales as (

    select * from {{ ref('sales_enriched') }}

),

totals as (

    select
        sum(order_amount)           as grand_revenue,
        count(distinct order_sk)    as grand_orders

    from sales

),

by_method as (

    select
        payment_method,
        round(sum(order_amount), 2)             as total_revenue,
        round(avg(order_amount), 2)             as avg_order_value,
        count(distinct order_sk)                as total_orders

    from sales
    group by payment_method

)

select
    bm.payment_method,
    bm.total_revenue,
    bm.avg_order_value,
    bm.total_orders,
    round({{ safe_divide('bm.total_revenue * 100.0', 't.grand_revenue') }}, 2) as pct_of_total_revenue,
    round({{ safe_divide('bm.total_orders  * 100.0', 't.grand_orders')  }}, 2) as pct_of_total_orders,
    convert_timezone('UTC', current_timestamp()) as load_ts

from by_method bm
cross join totals t
order by total_revenue desc
