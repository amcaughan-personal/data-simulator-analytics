-- Per day and merchant category: how many transactions, how many were declined, and how
-- much money moved. Only complete days: the latest day is still filling up.
with transactions as (
    select *
    from {{ ref('silver_transactions') }}
    where event_at < (select date_trunc('day', max(event_at)) from {{ ref('silver_transactions') }})
)

select
    date(event_at) as day,
    merchant_category,
    count(*) as transactions,
    count_if(is_approved) as approved,
    count_if(not is_approved) as declined,
    round(cast(count_if(not is_approved) as double) / count(*), 4) as decline_rate,
    round(sum(if(is_approved, amount, 0)), 2) as approved_amount,
    round(avg(amount), 2) as average_amount
from transactions
group by 1, 2
