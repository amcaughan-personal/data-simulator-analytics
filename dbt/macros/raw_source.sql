{#
    The raw table a model reads. The ELT's routine tables (transactions, merchants) cover only
    its last 14 days, so a query on them never lists more than that many days of S3 prefixes.
    With --vars '{backfill: true}' models read the <table>_history tables instead, which reach
    back to the first day: for catching up after a long gap, or rebuilding everything with
    --full-refresh. See the README's "Backfills".
#}
{% macro raw_source(table) %}
    {{ return(source('raw', table ~ ('_history' if var('backfill') else ''))) }}
{% endmacro %}
