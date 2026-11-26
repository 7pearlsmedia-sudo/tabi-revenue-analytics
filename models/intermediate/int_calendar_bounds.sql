{#- Data coverage boundaries, used to keep only complete periods in trend
    metrics (the source starts on a Tuesday and stops on 2011-12-09). -#}

with bounds as (

    select
        min(invoice_date) as first_date,
        max(invoice_date) as last_date
    from {{ ref('int_merchandise_lines') }}

)

select
    first_date,
    last_date,
    {{ add_days('last_date', 1) }}                                    as snapshot_date,
    -- first Monday on/after first_date
    case when {{ week_start('first_date') }} = first_date then first_date
         else {{ add_days(week_start('first_date'), 7) }} end          as first_complete_week,
    -- last Monday whose week (Mon..Sun) ends on/before last_date
    case when {{ add_days(week_start('last_date'), 6) }} <= last_date then {{ week_start('last_date') }}
         else {{ add_days(week_start('last_date'), -7) }} end          as last_complete_week,
    {{ month_start('first_date') }}                                    as first_month,
    -- the last month is complete only if data reaches its final day
    case when {{ month_start(add_days('last_date', 1)) }} > {{ month_start('last_date') }}
         then {{ month_start('last_date') }}
         else {{ month_start(add_days(month_start('last_date'), -1)) }} end
                                                                       as last_complete_month
from bounds
