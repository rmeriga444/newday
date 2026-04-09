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

payment_slices as (

    select
        order_year,
        order_month,
        to_char(order_month, 'YYYY-MM')         as month_label,
        category_name,
        payment_method,
        count(distinct order_sk)                as total_orders,
        sum(order_quantity)                     as total_units,
        round(sum(order_amount), 2)             as gross_revenue,
        round(sum(net_order_amount), 2)         as net_revenue,
        round(sum(discount_amount), 2)          as total_discounts,
        count_if(is_zero_quantity)              as zero_qty_orders,
        round(
            sum(case when is_zero_quantity then order_amount else 0 end)
        , 2)                                    as zero_qty_gross_revenue,
        count_if(discount_was_null)             as orders_missing_discount,
        count_if(shipping_was_null)             as orders_missing_shipping

    from base
    group by 1, 2, 3, 4, 5

),

category_month_totals as (

    select
        order_month,
        category_name,
        sum(total_orders)                       as cat_total_orders,
        sum(gross_revenue)                      as cat_gross_revenue

    from payment_slices
    group by 1, 2

),

final as (

    select
        ps.order_year,
        ps.order_month,
        ps.month_label,
        ps.category_name,
        ps.payment_method,
        ps.total_orders,
        ps.total_units,
        ps.gross_revenue,
        ps.net_revenue,
        ps.total_discounts,
        ps.zero_qty_orders,
        ps.zero_qty_gross_revenue,
        ps.total_orders - ps.zero_qty_orders    as non_zero_qty_orders,
        ps.orders_missing_discount,
        ps.orders_missing_shipping,
        cm.cat_total_orders,
        cm.cat_gross_revenue,
        round({{ safe_divide('ps.total_orders * 100.0',  'cm.cat_total_orders')  }}, 2) as pct_orders_by_payment,
        round({{ safe_divide('ps.gross_revenue * 100.0', 'cm.cat_gross_revenue') }}, 2) as pct_revenue_by_payment,
        round({{ safe_divide('ps.gross_revenue',         'ps.total_orders')      }}, 2) as avg_order_value,
        convert_timezone('UTC', current_timestamp())                     as load_ts

    from payment_slices ps
    inner join category_month_totals cm
        on ps.order_month   = cm.order_month
        and ps.category_name = cm.category_name

)

select * from final
order by order_month, category_name, pct_revenue_by_payment desc
