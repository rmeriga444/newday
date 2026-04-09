{% test test_sum_threshold_by_product(
    model,
    column_name,
    group_col,
    min_value=none,
    max_value=none,
    max_pct_deviation=none,
    lookback_periods=30,
    date_col=none,
    date_part='month',
    allow_zero=true
) %}

with grouped as (

    select
        {{ group_col }}                                         as group_value,

        {% if date_col is not none %}
        date_trunc('{{ date_part }}', {{ date_col }}::date)     as period,
        {% endif %}

        sum({{ column_name }})                                  as total_sum,
        count(*)                                                as row_count

    from {{ model }}

    group by
        {{ group_col }}
        {% if date_col is not none %}, date_trunc('{{ date_part }}', {{ date_col }}::date) {% endif %}

),

{% if max_pct_deviation is not none and date_col is not none %}

ranked as (

    select
        *,
        row_number() over (
            partition by group_value
            order by period desc
        )                                                       as period_rank

    from grouped

),

historical_avg as (

    select
        group_value,
        avg(total_sum)                                          as avg_sum,
        stddev(total_sum)                                       as stddev_sum,
        count(*)                                                as period_count

    from ranked
    where period_rank between 2 and {{ lookback_periods }} + 1
    group by group_value

),

latest as (

    select * from ranked where period_rank = 1

),

deviation_check as (

    select
        l.group_value,
        l.period                                                as tested_period,
        l.total_sum                                             as current_sum,
        round(h.avg_sum, 2)                                     as historical_avg_sum,
        round(
            abs({{ safe_divide('(l.total_sum - h.avg_sum) * 100.0', 'nullif(h.avg_sum, 0)') }})
        , 2)                                                    as pct_deviation,
        {{ max_pct_deviation }}                                 as max_allowed_pct_deviation

    from latest         l
    left join historical_avg h using (group_value)

),

{% endif %}

violations as (

    select
        group_value,

        {% if max_pct_deviation is not none and date_col is not none %}
        current_sum                                             as total_sum,
        historical_avg_sum,
        pct_deviation,
        max_allowed_pct_deviation,
        {% else %}
        total_sum,
        {% endif %}

        case
            {% if not allow_zero %}
            when total_sum = 0
                then 'FAIL — zero sum for group: ' || group_value::varchar
            {% endif %}
            {% if min_value is not none %}
            when total_sum < {{ min_value }}
                then 'FAIL — sum ' || total_sum::varchar
                    || ' is below min threshold {{ min_value }}'
            {% endif %}
            {% if max_value is not none %}
            when total_sum > {{ max_value }}
                then 'FAIL — sum ' || total_sum::varchar
                    || ' exceeds max threshold {{ max_value }}'
            {% endif %}
            {% if max_pct_deviation is not none and date_col is not none %}
            when pct_deviation > {{ max_pct_deviation }}
                then 'FAIL — ' || pct_deviation::varchar
                    || '% deviation exceeds threshold {{ max_pct_deviation }}%'
            {% endif %}
            else 'OK'
        end                                                     as violation_reason

    from

    {% if max_pct_deviation is not none and date_col is not none %}
        deviation_check
    {% else %}
        grouped
    {% endif %}

)

select *
from violations
where violation_reason like 'FAIL%'
order by group_value

{% endtest %}
