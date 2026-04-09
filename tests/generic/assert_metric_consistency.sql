{% test assert_metric_consistency(
    model,
    column_name,
    expression,
    tolerance=0.01,
    group_col=none
) %}

with validation as (

    select
        {% if group_col is not none %}
        {{ group_col }}                                         as group_value,
        {% endif %}
        {{ column_name }}                                       as actual_value,
        round({{ expression }}, 10)                            as expected_value,
        abs(
            {{ column_name }} - round({{ expression }}, 10)
        )                                                       as absolute_diff,
        {{ tolerance }}                                         as allowed_tolerance

    from {{ model }}
    where {{ column_name }} is not null

),

failures as (

    select
        *,
        'Column {{ column_name }} value ' || actual_value
            || ' does not match expression {{ expression }}'
            || ' (expected: ' || expected_value
            || ', diff: ' || absolute_diff
            || ', tolerance: ' || allowed_tolerance || ')'     as failure_reason

    from validation
    where absolute_diff > {{ tolerance }}

)

select * from failures
order by absolute_diff desc

{% endtest %}
