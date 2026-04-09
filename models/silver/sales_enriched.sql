{{
    config(
        materialized = 'view',
        tags         = ['silver', 'sales', 'enriched']
    )
}}

with sales as (

    select * from {{ ref('sales_fact') }}

),

products as (

    select
        product_sk,
        product_id,
        product_name
    from {{ ref('products') }}

),

categories as (

    select
        product_sk,
        category_id,
        category_name,
        subcategory,
        brand,
        supplier_id,
        cost_price,
        retail_price,
        gross_margin_amount,
        margin_percent,
        is_discontinued,
        is_below_reorder_point
    from {{ ref('product_category') }}

),

customers as (

    select
        customer_sk,
        customer_id,
        customer_name,
        customer_email,
        status          as customer_status,
        is_active       as customer_is_active
    from {{ ref('customers') }}

),

enriched as (

    select
        s.order_sk,
        s.customer_sk,
        s.product_sk,

        s.order_id,
        s.customer_id,
        s.product_id,

        c.customer_name,
        c.customer_email,
        c.customer_status,
        c.customer_is_active,

        coalesce(p.product_name,    'Unknown Product')  as product_name,
        coalesce(cat.category_id,   'UNKNOWN')          as category_id,
        coalesce(cat.category_name, 'Unknown')          as category_name,
        coalesce(cat.subcategory,   'Unknown')          as subcategory,
        cat.brand,
        cat.cost_price,
        cat.retail_price,
        cat.gross_margin_amount,
        cat.margin_percent,
        cat.is_discontinued,
        cat.is_below_reorder_point,

        s.order_date,
        s.order_month,
        s.order_quarter,
        s.order_year,
        s.order_month_num,
        s.order_quarter_num,
        s.order_day_of_week,
        s.order_day_of_year,
        s.created_at,

        s.order_amount,
        s.order_quantity,
        s.discount_applied,
        s.shipping_cost,
        s.net_order_amount,
        s.discount_amount,
        s.unit_price,
        s.discount_was_null,
        s.shipping_was_null,

        s.payment_method,

        s.is_zero_quantity,
        s.is_high_discount,
        s.is_high_shipping,
        s.is_high_discount or s.is_high_shipping    as is_flagged_for_review,

        s._processed_at

    from sales s
    left join products   p   on s.product_sk  = p.product_sk
    left join categories cat on s.product_sk  = cat.product_sk
    left join customers  c   on s.customer_sk = c.customer_sk

)

select * from enriched
