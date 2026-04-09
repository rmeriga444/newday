{{
    config(
        materialized = 'table',
        cluster_by   = ['order_month', 'category_name'],
        tags         = ['gold', 'revenue', 'q2']
    )
}}

with base as (

    select * from {{ ref('sales_enriched') }}

),

payment_totals as (

    select
        date_trunc('month', order_date)                             as order_month,
        category_name,
        payment_method,
        count(distinct order_sk)                                    as orders_by_method,
        round(sum(order_amount), 2)                                 as revenue_by_method,
        count(distinct case when order_quantity = 0
                            then order_sk end)                      as zero_quantity_orders

    from base
    group by 1, 2, 3

),

category_totals as (

    select
        order_month,
        category_name,
        sum(orders_by_method)                                       as total_orders,
        sum(revenue_by_method)                                      as total_revenue

    from payment_totals
    group by 1, 2

)

select
    pt.order_month,
    pt.category_name,
    pt.payment_method,
    pt.orders_by_method,
    pt.revenue_by_method,
    pt.zero_quantity_orders,
    round({{ safe_divide('pt.orders_by_method * 100.0',  'ct.total_orders')  }}, 2) as pct_orders_by_payment,
    round({{ safe_divide('pt.revenue_by_method * 100.0', 'ct.total_revenue') }}, 2) as pct_revenue_by_payment,
    convert_timezone('UTC', current_timestamp())                    as load_ts

from payment_totals  pt
inner join category_totals ct
    on  pt.order_month   = ct.order_month
    and pt.category_name = ct.category_name

order by pt.order_month, pt.category_name, pct_revenue_by_payment desc
