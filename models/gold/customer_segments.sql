{{
    config(
        materialized = 'table',
        cluster_by   = ['customer_tier'],
        tags         = ['gold', 'customers', 'q3']
    )
}}

with orders as (

    select * from {{ ref('sales_enriched') }}

),

customers as (

    select * from {{ ref('customers') }}

),

order_totals as (

    select
        customer_id,
        count(distinct order_sk)        as total_orders,
        round(sum(order_amount), 2)     as total_purchase_amount

    from orders
    group by customer_id

),

segmented as (

    select
        c.customer_name,
        c.customer_id,
        coalesce(o.total_orders, 0)             as total_orders,
        coalesce(o.total_purchase_amount, 0)    as total_purchase_amount,
        case
            when coalesce(o.total_purchase_amount, 0) >= 1000 then 'High Value'
            when coalesce(o.total_purchase_amount, 0) >= 500  then 'Medium Value'
            else 'Low Value'
        end                                     as customer_tier

    from customers c
    left join order_totals o using (customer_id)

)

select
    customer_name,
    customer_id,
    customer_tier,
    total_orders,
    total_purchase_amount,
    convert_timezone('UTC', current_timestamp()) as load_ts

from segmented
order by customer_tier, total_purchase_amount desc
