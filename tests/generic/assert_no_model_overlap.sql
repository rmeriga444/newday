{% test assert_no_model_overlap(
    model,
    column_name,
    ref_model,
    ref_column=none
) %}

{%- set rc = ref_column if ref_column is not none else column_name -%}

with this_keys as (

    select distinct {{ column_name }} as key_value
    from {{ model }}
    where {{ column_name }} is not null

),

ref_keys as (

    select distinct {{ rc }} as key_value
    from {{ ref_model }}
    where {{ rc }} is not null

),

overlap as (

    select
        t.key_value,
        'Key value ' || t.key_value::varchar
            || ' in {{ model }} column {{ column_name }}'
            || ' also exists in {{ ref_model }}'
            || ' — models expected to be mutually exclusive'   as failure_reason

    from this_keys t
    inner join ref_keys r using (key_value)

)

select * from overlap

{% endtest %}
