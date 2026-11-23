{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='transaction_id',
        partitioned_by=['day(event_at)'],
        on_schema_change='fail',
    )
}}

-- One row per transaction. Each run merges in the days since the last one, plus one day back
-- in case the last run missed some of that day's hours.
--
-- The start day is looked up first and written into the query as a constant: Athena only
-- skips raw partitions for constants, and with a subquery it would list every one.

{% if is_incremental() and execute %}
    {% set start_day = run_query(
        "select date_format(max(event_at) - interval '1' day, '%Y-%m-%d') from " ~ this
    ).columns[0].values()[0] %}
    {% set window_start = (
        modules.datetime.datetime.utcnow().date()
        - modules.datetime.timedelta(days=var('raw_window_days') - 1)
    ).isoformat() %}
    {% if start_day is none %}
        {{ exceptions.raise_compiler_error(
            this ~ " is empty. Rebuild it: dbt build --full-refresh --vars '{backfill: true}'"
        ) }}
    {% elif start_day < window_start and not var('backfill') %}
        {{ exceptions.raise_compiler_error(
            this ~ " was last loaded up to " ~ start_day ~ ", before the raw tables' "
            ~ var('raw_window_days') ~ "-day window, so a normal run would skip days. Catch up from "
            ~ "the history tables: dbt build --select silver_transactions+ --vars '{backfill: true}'"
        ) }}
    {% endif %}
{% endif %}

with new_rows as (
    select *
    from {{ ref('bronze_transactions') }}
    {% if is_incremental() %}
    where dt >= '{{ start_day if execute else "1970-01-01" }}'
    {% endif %}
),

-- A merge needs one row per key. The ELT's fixed keys mean duplicates shouldn't reach raw,
-- but if they ever do, keep one.
deduplicated as (
    select *, row_number() over (partition by transaction_id order by event_at) as copy_number
    from new_rows
)

select
    transaction_id,
    cast(event_at as timestamp(6)) as event_at, -- Iceberg's timestamp precision
    merchant_id,
    merchant_category,
    card_type,
    channel,
    status,
    status = 'approved' as is_approved,
    round(amount, 2) as amount, -- in cents, as charged
    -- The API labels injected anomalies; analysis treats the label as ground truth.
    coalesce(anomaly = 'card_testing', false) as is_card_testing
from deduplicated
where copy_number = 1
