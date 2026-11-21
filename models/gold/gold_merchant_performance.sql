-- Each merchant over the last 30 complete days: volume, money approved and decline rate,
-- alongside where it is and its risk tier. Merchants with no transactions still appear.
with period as (
    select
        date_trunc('day', max(event_at)) - interval '30' day as starts_at,
        date_trunc('day', max(event_at)) as ends_at
    from {{ ref('silver_transactions') }}
),

transactions as (
    select t.*
    from {{ ref('silver_transactions') }} as t
    cross join period
    where t.event_at >= period.starts_at and t.event_at < period.ends_at
)

select
    m.merchant_id,
    m.merchant_category,
    m.city,
    m.risk_tier,
    count(t.transaction_id) as transactions,
    round(coalesce(sum(if(t.is_approved, t.amount, 0)), 0), 2) as approved_amount,
    round(cast(count_if(not t.is_approved) as double) / nullif(count(t.transaction_id), 0), 4) as decline_rate
from {{ ref('silver_merchants') }} as m
left join transactions as t on t.merchant_id = m.merchant_id
group by 1, 2, 3, 4
