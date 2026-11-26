{#- Small cross-database helpers so the same models run on DuckDB and BigQuery. -#}

{# Monday-based week start for a date/timestamp expression. #}
{% macro week_start(expr) -%}
    {{ return(adapter.dispatch('week_start')(expr)) }}
{%- endmacro %}

{% macro default__week_start(expr) -%}
    cast(date_trunc('week', {{ expr }}) as date)
{%- endmacro %}

{% macro bigquery__week_start(expr) -%}
    date_trunc(cast({{ expr }} as date), isoweek)
{%- endmacro %}

{# First day of the month as a DATE. #}
{% macro month_start(expr) -%}
    {{ return(adapter.dispatch('month_start')(expr)) }}
{%- endmacro %}

{% macro default__month_start(expr) -%}
    cast(date_trunc('month', {{ expr }}) as date)
{%- endmacro %}

{% macro bigquery__month_start(expr) -%}
    date_trunc(cast({{ expr }} as date), month)
{%- endmacro %}

{# Whole months between two month-start dates. #}
{% macro months_between(start_expr, end_expr) -%}
    {{ return(adapter.dispatch('months_between')(start_expr, end_expr)) }}
{%- endmacro %}

{% macro default__months_between(start_expr, end_expr) -%}
    cast(date_diff('month', {{ start_expr }}, {{ end_expr }}) as integer)
{%- endmacro %}

{% macro bigquery__months_between(start_expr, end_expr) -%}
    date_diff({{ end_expr }}, {{ start_expr }}, month)
{%- endmacro %}

{# Whole days between two dates. #}
{% macro days_between(start_expr, end_expr) -%}
    {{ return(adapter.dispatch('days_between')(start_expr, end_expr)) }}
{%- endmacro %}

{% macro default__days_between(start_expr, end_expr) -%}
    cast(date_diff('day', cast({{ start_expr }} as date), cast({{ end_expr }} as date)) as integer)
{%- endmacro %}

{% macro bigquery__days_between(start_expr, end_expr) -%}
    date_diff(cast({{ end_expr }} as date), cast({{ start_expr }} as date), day)
{%- endmacro %}

{# Add N days to a date. #}
{% macro add_days(expr, n) -%}
    {{ return(adapter.dispatch('add_days')(expr, n)) }}
{%- endmacro %}

{% macro default__add_days(expr, n) -%}
    cast({{ expr }} + to_days(cast({{ n }} as integer)) as date)
{%- endmacro %}

{% macro bigquery__add_days(expr, n) -%}
    date_add({{ expr }}, interval cast({{ n }} as int64) day)
{%- endmacro %}

{# Median as an aggregate. #}
{% macro median_agg(expr) -%}
    {{ return(adapter.dispatch('median_agg')(expr)) }}
{%- endmacro %}

{% macro default__median_agg(expr) -%}
    median({{ expr }})
{%- endmacro %}

{% macro bigquery__median_agg(expr) -%}
    approx_quantiles({{ expr }}, 2)[offset(1)]
{%- endmacro %}
