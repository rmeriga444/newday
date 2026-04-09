{% test assert_grain_is_unique(model, column_name, grain_columns) %}

with grain_counts as (

    select
        {% for col in grain_columns %}
        {{ col }},
        {% endfor %}
        count(*)                                                as occurrence_count

    from {{ model }}
    group by
        {% for col in grain_columns %}
        {{ col }}{% if not loop.last %},{% endif %}
        {% endfor %}

    having count(*) > 1

),

failures as (

    select
        *,
        'Duplicate grain detected: ('
        {% for col in grain_columns %}
            || '{{ col }}=' || coalesce({{ col }}::varchar, 'NULL')
            {% if not loop.last %} || ', ' {% endif %}
        {% endfor %}
        || ') appears ' || occurrence_count || ' times'         as failure_reason

    from grain_counts

)

select * from failures
order by occurrence_count desc

{% endtest %}
