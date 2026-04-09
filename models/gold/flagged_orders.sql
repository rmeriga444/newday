{{
    config(
        materialized = 'table',
        cluster_by   = ['order_date'],
        tags         = ['gold', 'operations', 'q5']
    )
}}

with enriched as (

    select * from {{ ref('sales_enriched') }}

),

evaluated as (

    select
        order_sk,
        customer_sk,
        product_sk,
        order_id,
        customer_id,
        product_id,
        customer_name,
        customer_email,
        product_name,
        category_name,
        subcategory,
        order_date,
        to_char(order_month, 'YYYY-MM')         as month_label,
        payment_method,
        order_quantity,
        order_amount,
        net_order_amount,
        discount_applied,
        round(discount_applied * 100, 1)        as discount_pct,
        discount_amount,
        discount_was_null,
        shipping_cost,
        round({{ safe_divide('shipping_cost * 100.0', 'order_amount') }}, 1) as shipping_pct_of_order,
        shipping_was_null,
        is_high_discount,
        is_high_shipping,
        is_high_discount or is_high_shipping    as is_flagged,
        (is_high_discount::integer + is_high_shipping::integer) as flag_count,
        array_to_string(
            array_construct_compact(
                case when is_high_discount
                     then 'HIGH_DISCOUNT (' || discount_pct::varchar || '%)' end,
                case when is_high_shipping
                     then 'HIGH_SHIPPING (' || shipping_pct_of_order::varchar || '% of order)' end
            ),
            ' | '
        )                                       as flag_reasons,
        created_at,
        current_timestamp()                     as _refreshed_at

    from enriched

)

select * from evaluated
where is_flagged
order by flag_count desc, discount_pct desc, order_date
