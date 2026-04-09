{% macro get_start_date(default_date='2023-01-01') %}
  '{{ var("start_date", default_date) }}'::date
{% endmacro %}

{% macro get_end_date(default_date='2024-12-31') %}
  '{{ var("end_date", default_date) }}'::date
{% endmacro %}

{% macro assert_date_range_valid(start_date, end_date) %}
  {% if start_date > end_date %}
    {{ exceptions.raise_compiler_error(
        "Date range invalid: start_date (" ~ start_date ~ ") must be on or before end_date (" ~ end_date ~ ")."
    ) }}
  {% endif %}
{% endmacro %}
