{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='transaction_id',
        partitioned_by=['day(event_at)'],
        on_schema_change='fail',
    )
}}

-- One row per transaction. Each run merges in the days since the last one (from the raw
-- partitions, so only those files are read), plus one day back in case the last run
-- missed some of that day's hours.

with new_rows as (
    select *
    from {{ ref('bronze_transactions') }}
    {% if is_incremental() %}
    where dt >= (select date_format(max(event_at) - interval '1' day, '%Y-%m-%d') from {{ this }})
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
