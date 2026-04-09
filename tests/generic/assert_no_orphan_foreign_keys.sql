{% test assert_no_orphan_foreign_keys(
    model,
    column_name,
    ref_model,
    ref_column,
    allow_null=true
) %}

with parent_keys as (

    select distinct {{ ref_column }} as pk_value
    from {{ ref_model }}

),

child_keys as (

    select
        {{ column_name }}           as fk_value,
        count(*)                    as row_count

    from {{ model }}

    {% if allow_null %}
    where {{ column_name }} is not null
    {% endif %}

    group by 1

),

orphans as (

    select
        c.fk_value                  as orphaned_fk,
        c.row_count                 as affected_rows,
        'FK value ' || c.fk_value
            || ' in column {{ column_name }}'
            || ' has no match in {{ ref_model }}'
                                    as failure_reason

    from child_keys c
    left join parent_keys p
        on c.fk_value = p.pk_value
    where p.pk_value is null

)

select * from orphans
order by affected_rows desc

{% endtest %}
