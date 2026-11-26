{#- Use the layer name directly as schema (staging / intermediate / marts)
    instead of dbt's default "<target_schema>_<layer>". On BigQuery these
    become datasets prefixed with the target dataset to avoid collisions. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.type == 'bigquery' -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
