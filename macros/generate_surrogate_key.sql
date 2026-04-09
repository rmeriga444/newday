{% macro generate_surrogate_key(field_list) %}

  {%- if field_list is string -%}
    {%- set field_list = [field_list] -%}
  {%- endif -%}

  md5(
    concat_ws(
      '{{ var("sk_delimiter", "||") }}'
      {%- for field in field_list -%}
        , coalesce(cast({{ field }} as varchar), 'NULL')
      {%- endfor %}
    )
  )

{% endmacro %}
