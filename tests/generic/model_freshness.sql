{% test model_freshness(
    model,
    column_name,
    warn_after_hours=24,
    error_after_hours=48
) %}

with freshness_check as (

    select
        max({{ column_name }})                                  as latest_record_ts,
        convert_timezone('UTC', current_timestamp())            as current_ts_utc,
        datediff(
            'hour',
            max({{ column_name }}),
            convert_timezone('UTC', current_timestamp())
        )                                                       as hours_since_latest

    from {{ model }}

)

select
    latest_record_ts,
    current_ts_utc,
    hours_since_latest,
    {{ error_after_hours }}                                     as error_threshold_hours,
    {{ warn_after_hours }}                                      as warn_threshold_hours,
    case
        when hours_since_latest > {{ error_after_hours }}
            then 'ERROR — data is ' || hours_since_latest || ' hours old'
        when hours_since_latest > {{ warn_after_hours }}
            then 'WARN — data is '  || hours_since_latest || ' hours old'
        else 'OK'
    end                                                         as freshness_status

from freshness_check
where hours_since_latest > {{ error_after_hours }}

{% endtest %}
