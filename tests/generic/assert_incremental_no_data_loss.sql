{% test assert_incremental_no_data_loss(
    model,
    column_name,
    source_model,
    source_col,
    date_part='day',
    tolerance_pct=0
) %}

with target_counts as (

    select
        date_trunc('{{ date_part }}', {{ column_name }}::date)  as period,
        count(*)                                                as target_rows

    from {{ model }}
    group by 1

),

source_counts as (

    select
        date_trunc('{{ date_part }}', {{ source_col }}::date)   as period,
        count(*)                                                as source_rows

    from {{ source_model }}
    group by 1

),

comparison as (

    select
        coalesce(t.period, s.period)                            as period,
        coalesce(s.source_rows, 0)                              as source_rows,
        coalesce(t.target_rows, 0)                              as target_rows,
        coalesce(s.source_rows, 0)
            - coalesce(t.target_rows, 0)                        as rows_lost,
        round(
            case
                when coalesce(s.source_rows, 0) = 0 then 0
                else (coalesce(s.source_rows, 0)
                    - coalesce(t.target_rows, 0)) * 100.0
                    / coalesce(s.source_rows, 0)
            end
        , 2)                                                    as pct_lost

    from source_counts s
    full outer join target_counts t using (period)

)

select
    period,
    source_rows,
    target_rows,
    rows_lost,
    pct_lost,
    {{ tolerance_pct }}                                         as tolerance_pct,
    'Data loss detected for period ' || period::varchar
        || ': source had ' || source_rows || ' rows'
        || ' but target has ' || target_rows
        || ' (' || pct_lost || '% lost)'                       as failure_reason

from comparison
where rows_lost > 0
  and pct_lost > {{ tolerance_pct }}
order by period

{% endtest %}
