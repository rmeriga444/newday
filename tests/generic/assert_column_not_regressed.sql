{% test assert_column_not_regressed(
    model,
    column_name,
    max_null_pct=0,
    min_row_threshold=1
) %}

with stats as (

    select
        count(*)                                                as total_rows,
        count({{ column_name }})                               as non_null_rows,
        count(*) - count({{ column_name }})                    as null_rows,
        round(
            (count(*) - count({{ column_name }})) * 100.0
            / nullif(count(*), 0)
        , 2)                                                    as null_pct

    from {{ model }}

)

select
    total_rows,
    non_null_rows,
    null_rows,
    null_pct,
    {{ max_null_pct }}                                          as max_allowed_null_pct,
    'Column {{ column_name }} null rate is '
        || null_pct || '%'
        || ' which exceeds max allowed '
        || {{ max_null_pct }} || '%'
        || ' (' || null_rows || ' of ' || total_rows
        || ' rows are null)'                                    as failure_reason

from stats
where total_rows >= {{ min_row_threshold }}
  and null_pct > {{ max_null_pct }}

{% endtest %}
