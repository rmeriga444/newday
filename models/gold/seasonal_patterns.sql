{{
    config(
        materialized = 'table',
        cluster_by   = ['category_name', 'order_year'],
        tags         = ['gold', 'analytics', 'q6']
    )
}}

with base as (

    select * from {{ ref('sales_enriched') }}
    where not is_zero_quantity

),

monthly as (

    select
        order_year,
        order_month,
        order_month_num,
        order_quarter,
        order_quarter_num,
        to_char(order_month, 'YYYY-MM')         as month_label,
        to_char(order_month, 'Mon')             as month_short_name,
        category_name,
        subcategory,
        count(distinct order_sk)                as total_orders,
        count(distinct customer_sk)             as unique_customers,
        sum(order_quantity)                     as total_units,
        round(sum(order_amount), 2)             as gross_revenue,
        round(sum(net_order_amount), 2)         as net_revenue,
        round(sum(discount_amount), 2)          as total_discounts,
        round(avg(order_amount), 2)             as avg_order_value,
        round(avg(net_order_amount), 2)         as avg_net_order_value

    from base
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9

),

quarterly as (

    select
        order_year,
        order_quarter,
        order_quarter_num,
        category_name,
        round(sum(gross_revenue), 2)            as quarterly_gross_revenue,
        sum(total_orders)                       as quarterly_orders

    from monthly
    group by 1, 2, 3, 4

),

category_cv as (

    select
        category_name,
        round(avg(gross_revenue), 2)            as cat_avg_monthly_revenue,
        round(stddev(gross_revenue), 2)         as cat_stddev_monthly_revenue,
        count(*)                                as months_with_data,
        round({{ safe_divide('stddev(gross_revenue) * 100.0', 'avg(gross_revenue)') }}, 2) as coefficient_of_variation,
        case
            when {{ safe_divide('stddev(gross_revenue) * 100.0', 'avg(gross_revenue)') }} < 15 then 'Stable'
            when {{ safe_divide('stddev(gross_revenue) * 100.0', 'avg(gross_revenue)') }} < 30 then 'Moderate'
            else 'High Volatility'
        end                                     as volatility_label

    from monthly
    group by 1

),

month_ranks as (

    select
        category_name,
        month_label,
        rank() over (partition by category_name order by gross_revenue desc)    as best_month_rank,
        rank() over (partition by category_name order by gross_revenue asc)     as worst_month_rank

    from monthly

),

assembled as (

    select
        m.order_year,
        m.order_month,
        m.order_month_num,
        m.order_quarter,
        m.order_quarter_num,
        m.month_label,
        m.month_short_name,
        m.category_name,
        m.subcategory,
        m.total_orders,
        m.unique_customers,
        m.total_units,
        m.gross_revenue,
        m.net_revenue,
        m.total_discounts,
        m.avg_order_value,
        m.avg_net_order_value,

        q.quarterly_gross_revenue,
        q.quarterly_orders,

        lag(q.quarterly_gross_revenue) over (
            partition by m.category_name order by m.order_quarter
        )                                       as prev_quarterly_gross_revenue,

        round(
            {{ safe_divide(
                '(q.quarterly_gross_revenue - lag(q.quarterly_gross_revenue) over (partition by m.category_name order by m.order_quarter)) * 100.0',
                'nullif(lag(q.quarterly_gross_revenue) over (partition by m.category_name order by m.order_quarter), 0)'
            ) }}
        , 2)                                    as qoq_growth_pct,

        lag(m.gross_revenue) over (
            partition by m.category_name order by m.order_month
        )                                       as prev_month_gross_revenue,

        round(
            {{ safe_divide(
                '(m.gross_revenue - lag(m.gross_revenue) over (partition by m.category_name order by m.order_month)) * 100.0',
                'nullif(lag(m.gross_revenue) over (partition by m.category_name order by m.order_month), 0)'
            ) }}
        , 2)                                    as mom_growth_pct,

        mr.best_month_rank,
        mr.worst_month_rank,
        mr.best_month_rank  = 1                 as is_best_month,
        mr.worst_month_rank = 1                 as is_worst_month,

        cv.cat_avg_monthly_revenue,
        cv.cat_stddev_monthly_revenue,
        cv.months_with_data,
        cv.coefficient_of_variation,
        cv.volatility_label,

        convert_timezone('UTC', current_timestamp())                     as load_ts

    from monthly        m
    inner join quarterly    q   on m.category_name     = q.category_name
                                and m.order_year        = q.order_year
                                and m.order_quarter_num = q.order_quarter_num
    inner join category_cv  cv  on m.category_name     = cv.category_name
    inner join month_ranks  mr  on m.category_name     = mr.category_name
                                and m.month_label       = mr.month_label

)

select * from assembled
order by category_name, order_month
