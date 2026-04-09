{{
    config(
        materialized = 'table',
        cluster_by   = ['order_date'],
        tags         = ['gold', 'operations', 'q5']
    )
}}

with base as (

    select * from {{ ref('sales_enriched') }}

),

flagged as (

    select
        order_id,
        order_date,
        order_amount,
        order_quantity,
        coalesce(discount_applied, 0)                                   as discount_applied,
        coalesce(shipping_cost, 0)                                      as shipping_cost,
        payment_method,
        customer_name,
        product_name,
        category_name,
        convert_timezone('UTC', current_timestamp())                    as load_ts

    from base
    where coalesce(discount_applied, 0) > 0.30
       or coalesce(shipping_cost, 0) > 0.10 * order_amount

)

select * from flagged
order by order_date
