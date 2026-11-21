{{ config(materialized='table') }}

-- The merchants as of the latest snapshot: one row per merchant.
select
    merchant_id,
    merchant_category,
    city,
    risk_tier,
    monthly_fee,
    snapshot_date as as_of
from {{ ref('bronze_merchants') }}
where snapshot_date = (select max(snapshot_date) from {{ ref('bronze_merchants') }})
