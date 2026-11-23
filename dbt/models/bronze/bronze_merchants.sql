-- Every daily merchants snapshot, with proper types. One row per merchant per snapshot.
select
    merchant_id,
    merchant_category,
    city,
    risk_tier,
    monthly_fee,
    date(snapshot_date) as snapshot_date
from {{ raw_source('merchants') }}
