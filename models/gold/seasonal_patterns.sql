{{
    config(
        materialized = 'table',
        cluster_by   = ['category_name', 'order_year'],
        tags         = ['gold', 'analytics', 'q6']
    )
}}

with base as (

    select * from {{ ref('sales_enriched') }}

),

monthly as (

    select
        category_name,
        date_trunc('month',   order_date)       as order_month,
        date_trunc('quarter', order_date)       as order_quarter,
        year(order_date)                        as order_year,
        round(sum(order_amount), 2)             as monthly_revenue,
        count(distinct order_sk)                as total_orders

    from base
    group by 1, 2, 3, 4

),

quarterly as (

    select
        category_name,
        order_quarter,
        round(sum(monthly_revenue), 2)          as quarterly_revenue

    from monthly
    group by 1, 2

),

category_stats as (

    select
        category_name,
        round(avg(monthly_revenue), 2)          as avg_monthly_revenue,
        round(stddev(monthly_revenue), 2)       as stddev_monthly_revenue,
        round(
            {{ safe_divide('stddev(monthly_revenue) * 100.0', 'avg(monthly_revenue)') }}
        , 2)                                    as coefficient_of_variation

    from monthly
    group by 1

),

with_ranks as (

    select
        m.category_name,
        m.order_month,
        m.order_quarter,
        m.order_year,
        m.monthly_revenue,
        m.total_orders,
        q.quarterly_revenue,
        lag(q.quarterly_revenue) over (
            partition by m.category_name
            order by m.order_quarter
        )                                       as prev_quarter_revenue,
        round(
            {{ safe_divide(
                '(q.quarterly_revenue - lag(q.quarterly_revenue) over (partition by m.category_name order by m.order_quarter)) * 100.0',
                'nullif(lag(q.quarterly_revenue) over (partition by m.category_name order by m.order_quarter), 0)'
            ) }}
        , 2)                                    as qoq_growth_pct,
        rank() over (
            partition by m.category_name
            order by m.monthly_revenue desc
        )                                       as best_month_rank,
        rank() over (
            partition by m.category_name
            order by m.monthly_revenue asc
        )                                       as worst_month_rank,
        cs.avg_monthly_revenue,
        cs.coefficient_of_variation

    from monthly       m
    inner join quarterly    q  on m.category_name = q.category_name
                               and m.order_quarter = q.order_quarter
    inner join category_stats cs on m.category_name = cs.category_name

)

select
    category_name,
    order_month,
    order_year,
    monthly_revenue,
    total_orders,
    quarterly_revenue,
    qoq_growth_pct,
    best_month_rank  = 1                        as is_best_month,
    worst_month_rank = 1                        as is_worst_month,
    avg_monthly_revenue,
    coefficient_of_variation,
    convert_timezone('UTC', current_timestamp()) as load_ts

from with_ranks
order by category_name, order_month
