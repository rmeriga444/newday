{% macro get_incremental_timestamp(source_ts_col, watermark_col=none) %}

  {%- set wm_col = watermark_col if watermark_col is not none else source_ts_col -%}

  {% if is_incremental() %}

    where {{ source_ts_col }} > (
        select coalesce(max(t.{{ wm_col }}), '1900-01-01'::timestamp_ntz)
        from {{ this }} t
    )

  {% endif %}

{% endmacro %}
