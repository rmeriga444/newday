{{
    config(
        materialized = 'table',
        cluster_by   = ['order_date'],
        tags         = ['gold', 'revenue', 'q7']
    )
}}

{{ assert_date_range_valid(var('start_date'), var('end_date')) }}

with base as (

    select * from {{ ref('sales_enriched') }}
    where order_date::date >= {{ get_start_date() }}
      and order_date::date <= {{ get_end_date() }}

),

daily as (

    select
        order_date,
        to_char(order_date, 'YYYY-MM-DD')       as date_label,
        to_char(order_date, 'Day')              as day_name,
        order_day_of_week,
        order_month,
        order_quarter,
        order_year,
        count(distinct order_sk)                as total_orders,
        count(distinct customer_sk)             as unique_customers,
        sum(case when not is_zero_quantity then order_quantity    else 0 end) as total_units_sold,
        round(sum(case when not is_zero_quantity then order_amount     else 0 end), 2) as gross_revenue,
        round(sum(case when not is_zero_quantity then net_order_amount else 0 end), 2) as net_revenue,
        round(sum(case when not is_zero_quantity then discount_amount  else 0 end), 2) as total_discounts,
        round(sum(case when not is_zero_quantity then shipping_cost    else 0 end), 2) as total_shipping_collected,
        round(avg(case when not is_zero_quantity then order_amount end), 2)            as avg_order_value,
        count(distinct case when is_zero_quantity        then order_sk end) as zero_qty_orders,
        count(distinct case when is_flagged_for_review   then order_sk end) as flagged_orders,
        round(
            avg(sum(case when not is_zero_quantity then order_amount else 0 end)) over (
                order by order_date
                rows between 6 preceding and current row
            )
        , 2)                                    as rolling_7d_avg_revenue

    from base
    group by
        order_date,
        to_char(order_date, 'YYYY-MM-DD'),
        to_char(order_date, 'Day'),
        order_day_of_week,
        order_month,
        order_quarter,
        order_year

),

final as (

    select
        *,
        lag(gross_revenue) over (order by order_date)   as prev_day_revenue,
        round(
            {{ safe_divide(
                '(gross_revenue - lag(gross_revenue) over (order by order_date)) * 100.0',
                'nullif(lag(gross_revenue) over (order by order_date), 0)'
            ) }}
        , 2)                                    as dod_revenue_growth_pct,
        {{ get_start_date() }}                  as filter_start_date,
        {{ get_end_date() }}                    as filter_end_date,
        current_timestamp()                     as _refreshed_at

    from daily

)

select * from final
order by order_date
