{{
    config(
        materialized = 'table',
        tags         = ['gold', 'payments', 'q4']
    )
}}

with sales as (

    select * from {{ ref('sales_enriched') }}
    where not is_zero_quantity

),

grand as (

    select
        count(distinct order_sk)                as grand_orders,
        sum(order_amount)                       as grand_gross_revenue

    from sales

),

payment_agg as (

    select
        payment_method,
        count(distinct order_sk)                as total_orders,
        sum(order_amount)                       as total_gross_revenue,
        sum(net_order_amount)                   as total_net_revenue,
        avg(order_amount)                       as avg_order_value,
        min(order_amount)                       as min_order_value,
        max(order_amount)                       as max_order_value,
        percentile_cont(0.5) within group (
            order by order_amount
        )                                       as median_order_value,
        stddev(order_amount)                    as stddev_order_value

    from sales
    group by 1

),

final as (

    select
        pa.payment_method,
        pa.total_orders,
        pa.total_gross_revenue,
        pa.total_net_revenue,
        round(pa.avg_order_value, 2)            as avg_order_value,
        round(pa.median_order_value, 2)         as median_order_value,
        round(pa.min_order_value, 2)            as min_order_value,
        round(pa.max_order_value, 2)            as max_order_value,
        round(pa.stddev_order_value, 2)         as stddev_order_value,
        round({{ safe_divide('pa.total_orders * 100.0',       'g.grand_orders') }},        2) as pct_of_total_orders,
        round({{ safe_divide('pa.total_gross_revenue * 100.0', 'g.grand_gross_revenue') }}, 2) as pct_of_total_revenue,
        rank() over (order by pa.total_gross_revenue desc)  as revenue_rank,
        rank() over (order by pa.total_orders desc)         as order_volume_rank,
        convert_timezone('UTC', current_timestamp())                     as load_ts

    from payment_agg pa
    cross join grand g

)

select * from final
order by revenue_rank
