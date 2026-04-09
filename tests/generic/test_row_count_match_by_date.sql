{% test test_row_count_match_by_date(
    model,
    column_name,
    compare_model,
    compare_col,
    date_part='day',
    threshold_pct=0
) %}

with source_counts as (

    select
        date_trunc('{{ date_part }}', {{ column_name }}::date)  as period,
        count(*)                                                as source_rows

    from {{ model }}
    group by 1

),

compare_counts as (

    select
        date_trunc('{{ date_part }}', {{ compare_col }}::date)  as period,
        count(*)                                                as compare_rows

    from {{ compare_model }}
    group by 1

),

joined as (

    select
        coalesce(s.period, c.period)                            as period,
        coalesce(s.source_rows,  0)                             as source_rows,
        coalesce(c.compare_rows, 0)                             as compare_rows,
        coalesce(s.source_rows,  0)
            - coalesce(c.compare_rows, 0)                       as row_diff,
        abs(
            {{ safe_divide(
                '(coalesce(s.source_rows, 0) - coalesce(c.compare_rows, 0)) * 100.0',
                'nullif(coalesce(c.compare_rows, 0), 0)'
            ) }}
        )                                                       as pct_diff

    from source_counts  s
    full outer join compare_counts c using (period)

)

select
    period,
    source_rows,
    compare_rows,
    row_diff,
    round(pct_diff, 2)                                          as pct_diff,
    {{ threshold_pct }}                                         as allowed_threshold_pct

from joined
where pct_diff > {{ threshold_pct }}
   or source_rows = 0
   or compare_rows = 0
order by period

{% endtest %}
