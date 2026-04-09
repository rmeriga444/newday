{% test assert_referential_integrity_count(
    model,
    column_name,
    ref_model,
    ref_join_column,
    max_multiplier=1.0
) %}

with source_count as (

    select count(*) as total_rows
    from {{ model }}

),

joined_count as (

    select count(*) as joined_rows
    from {{ model }} s
    inner join {{ ref_model }} r
        on s.{{ column_name }} = r.{{ ref_join_column }}

),

check_result as (

    select
        s.total_rows,
        j.joined_rows,
        round(
            case
                when s.total_rows = 0 then 0
                else j.joined_rows * 1.0 / s.total_rows
            end
        , 4)                                    as row_multiplier,
        {{ max_multiplier }}                    as max_allowed_multiplier

    from source_count s
    cross join joined_count j

)

select
    total_rows,
    joined_rows,
    row_multiplier,
    max_allowed_multiplier,
    'Fan-out detected: join produced ' || joined_rows
        || ' rows from ' || total_rows || ' source rows'
        || ' (multiplier: ' || row_multiplier || ')'
        || ' — expected max: {{ max_multiplier }}'  as failure_reason

from check_result
where row_multiplier > {{ max_multiplier }}

{% endtest %}
