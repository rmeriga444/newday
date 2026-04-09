{{
    config(
        materialized = 'table',
        cluster_by   = ['customer_tier'],
        tags         = ['gold', 'customers', 'q3']
    )
}}

with orders as (

    select * from {{ ref('sales_enriched') }}
    where not is_zero_quantity

),

customers as (

    select * from {{ ref('customers') }}

),

customer_metrics as (

    select
        customer_sk,
        customer_id,
        count(distinct order_sk)                as total_orders,
        round(sum(order_amount), 2)             as total_gross_spend,
        round(sum(net_order_amount), 2)         as total_net_spend,
        round(sum(discount_amount), 2)          as total_discounts_received,
        round(avg(order_amount), 2)             as avg_order_value,
        round(min(order_amount), 2)             as min_order_value,
        round(max(order_amount), 2)             as max_order_value,
        min(order_date)                         as first_order_date,
        max(order_date)                         as last_order_date,
        datediff('day', min(order_date), max(order_date)) as tenure_days,
        mode(payment_method)                    as preferred_payment_method,
        count_if(is_zero_quantity)              as zero_qty_orders,
        count_if(is_flagged_for_review)         as flagged_orders

    from orders
    group by 1, 2

),

segmented as (

    select
        c.customer_sk,
        c.customer_id,
        c.customer_name,
        c.customer_email,
        c.status                                as customer_status,
        c.is_active,
        c.valid_from,
        c.valid_to,

        coalesce(m.total_orders, 0)             as total_orders,
        coalesce(m.total_gross_spend, 0)        as total_gross_spend,
        coalesce(m.total_net_spend, 0)          as total_net_spend,
        coalesce(m.total_discounts_received, 0) as total_discounts_received,
        coalesce(m.avg_order_value, 0)          as avg_order_value,
        m.min_order_value,
        m.max_order_value,
        m.first_order_date,
        m.last_order_date,
        coalesce(m.tenure_days, 0)              as tenure_days,
        m.preferred_payment_method,
        coalesce(m.zero_qty_orders, 0)          as zero_qty_orders,
        coalesce(m.flagged_orders, 0)           as flagged_orders,

        case
            when coalesce(m.total_gross_spend, 0) >= {{ var('tier_high_value') }}   then 'High Value'
            when coalesce(m.total_gross_spend, 0) >= {{ var('tier_medium_value') }} then 'Medium Value'
            else 'Low Value'
        end                                     as customer_tier,

        case
            when coalesce(m.total_gross_spend, 0) >= {{ var('tier_high_value') }}   then 1
            when coalesce(m.total_gross_spend, 0) >= {{ var('tier_medium_value') }} then 2
            else 3
        end                                     as tier_sort_order,

        current_timestamp()                     as _refreshed_at

    from customers c
    left join customer_metrics m
        on c.customer_sk = m.customer_sk
        and c.customer_id = m.customer_id

)

select
    *,
    rank() over (
        partition by customer_tier
        order by total_gross_spend desc
    )                                           as rank_within_tier,

    rank() over (
        order by total_gross_spend desc
    )                                           as global_spend_rank

from segmented
order by tier_sort_order, total_gross_spend desc
