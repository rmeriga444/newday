{% test assert_no_null_surrogate_keys(model, column_name) %}

select
    {{ column_name }}               as null_surrogate_key,
    count(*)                        as affected_rows,
    min(load_ts)              as earliest_affected_load,
    max(load_ts)              as latest_affected_load,
    'NULL surrogate key detected in column: {{ column_name }}'
                                    as failure_reason

from {{ model }}
where {{ column_name }} is null
group by 1, 5
having count(*) > 0

{% endtest %}
