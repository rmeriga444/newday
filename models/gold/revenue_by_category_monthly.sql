{{
    config(
        materialized = 'table',
        cluster_by   = ['order_year', 'category_name'],
        tags         = ['gold', 'revenue', 'q1']
    )
}}

with base as (

    select * from {{ ref('sales_enriched') }}
    where not is_zero_quantity

),

monthly_category as (

    select
        order_year,
        order_month,
        order_month_num,
        to_char(order_month, 'YYYY-MM') || ' (' || to_char(order_month, 'Mon') || ')' as month_label,
        category_name,
        subcategory,
        count(distinct order_sk)                as total_orders,
        count(distinct customer_sk)             as unique_customers,
        sum(order_quantity)                     as total_units_sold,
        round(sum(order_amount), 2)             as gross_revenue,
        round(sum(net_order_amount), 2)         as net_revenue,
        round(sum(discount_amount), 2)          as total_discounts,
        round(avg(order_amount), 2)             as avg_order_value,
        round(min(order_amount), 2)             as min_order_value,
        round(max(order_amount), 2)             as max_order_value

    from base
    group by 1, 2, 3, 4, 5, 6

),

with_growth as (

    select
        *,
        rank() over (
            partition by order_month
            order by gross_revenue desc
        )                                       as revenue_rank_in_month,

        lag(gross_revenue) over (
            partition by category_name
            order by order_month
        )                                       as prev_month_gross_revenue,

        round(
            {{ safe_divide(
                '(gross_revenue - lag(gross_revenue) over (partition by category_name order by order_month))',
                'nullif(lag(gross_revenue) over (partition by category_name order by order_month), 0)'
            ) }} * 100
        , 2)                                    as mom_revenue_growth_pct,

        convert_timezone('UTC', current_timestamp())                     as load_ts

    from monthly_category

)

select * from with_growth
order by order_month, revenue_rank_in_month
