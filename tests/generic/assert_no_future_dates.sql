{% test assert_no_future_dates(model, column_name, grace_days=0) %}

select {{ column_name }}
from {{ model }}
where {{ column_name }}::date > dateadd('day', {{ grace_days }}, current_date())

{% endtest %}
