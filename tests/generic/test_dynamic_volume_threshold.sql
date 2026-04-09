{% test test_dynamic_volume_threshold(
    model,
    column_name,
    date_part='day',
    lookback_periods=30,
    std_dev_multiplier=2,
    min_periods=7
) %}

with daily_counts as (

    select
        date_trunc('{{ date_part }}', {{ column_name }}::date)  as period,
        count(*)                                                as row_count

    from {{ model }}
    group by 1

),

ordered as (

    select
        period,
        row_count,
        row_number() over (order by period desc)                as recency_rank,
        count(*) over ()                                        as total_periods

    from daily_counts

),

baseline as (

    select
        avg(row_count)                                          as avg_rows,
        stddev(row_count)                                       as stddev_rows,
        count(*)                                                as baseline_periods

    from ordered

    where recency_rank between 2 and {{ lookback_periods }} + 1

),

latest_period as (

    select
        period,
        row_count

    from ordered
    where recency_rank = 1

),

anomaly_check as (

    select
        l.period                                                as tested_period,
        l.row_count                                             as current_rows,
        round(b.avg_rows,    2)                                 as historical_avg,
        round(b.stddev_rows, 2)                                 as historical_stddev,
        b.baseline_periods,
        round(b.avg_rows - ({{ std_dev_multiplier }} * b.stddev_rows), 0)
                                                                as lower_bound,
        round(b.avg_rows + ({{ std_dev_multiplier }} * b.stddev_rows), 0)
                                                                as upper_bound,
        {{ std_dev_multiplier }}                                as std_dev_threshold,
        {{ min_periods }}                                       as min_periods_required,

        case
            when b.baseline_periods < {{ min_periods }}
                then 'SKIP — insufficient history ('
                    || b.baseline_periods || ' periods)'
            when l.row_count < (b.avg_rows - {{ std_dev_multiplier }} * b.stddev_rows)
                then 'FAIL — volume DROP detected ('
                    || l.row_count || ' rows vs avg '
                    || round(b.avg_rows, 0) || ')'
            when l.row_count > (b.avg_rows + {{ std_dev_multiplier }} * b.stddev_rows)
                then 'FAIL — volume SPIKE detected ('
                    || l.row_count || ' rows vs avg '
                    || round(b.avg_rows, 0) || ')'
            else 'OK'
        end                                                     as anomaly_status

    from latest_period  l
    cross join baseline b

)

select *
from anomaly_check
where anomaly_status like 'FAIL%'

{% endtest %}
