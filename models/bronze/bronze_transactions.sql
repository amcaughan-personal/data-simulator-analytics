-- Raw transactions with proper types and names. One row per raw row; nothing is dropped.
select
    transaction_id,
    cast(from_iso8601_timestamp("timestamp") as timestamp) as event_at,
    merchant_id,
    merchant_category,
    card_type,
    channel,
    status,
    amount,
    anomaly,
    -- The raw file's partition (the event's UTC date), kept so filters on it prune files.
    dt
from {{ source('raw', 'transactions') }}
