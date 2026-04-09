{% test assert_column_values_not_blank(model, column_name, additional_values=[]) %}

{%- set sentinel_values = [
    "''",
    "' '",
    "'NULL'",
    "'null'",
    "'N/A'",
    "'na'",
    "'none'",
    "'None'",
    "'unknown'",
    "'UNKNOWN'",
    "'undefined'",
    "'-'"
] -%}

{%- for val in additional_values -%}
    {%- do sentinel_values.append("'" ~ val ~ "'") -%}
{%- endfor -%}

select
    {{ column_name }}               as blank_value,
    count(*)                        as affected_rows,
    'Blank or sentinel value found in column {{ column_name }}: ['
        || coalesce({{ column_name }}, 'NULL') || ']'
                                    as failure_reason

from {{ model }}
where {{ column_name }} is null
   or trim({{ column_name }}) = ''
   or {{ column_name }} in (
       {{ sentinel_values | join(', ') }}
   )

group by 1, 3
having count(*) > 0

{% endtest %}
