{% test assert_no_duplicate_surrogate_keys(model, column_name, natural_key) %}

with duplicates as (

    select
        {{ column_name }}                       as surrogate_key,
        {{ natural_key }}                       as natural_key_value,
        count(*)                                as occurrence_count,
        min(_processed_at)                      as first_seen,
        max(_processed_at)                      as last_seen

    from {{ model }}
    group by 1, 2
    having count(*) > 1

)

select
    surrogate_key,
    natural_key_value,
    occurrence_count,
    first_seen,
    last_seen,
    'Duplicate SK: ' || surrogate_key
        || ' appears ' || occurrence_count || ' times'
        || ' for natural key: ' || natural_key_value  as failure_reason

from duplicates

{% endtest %}
