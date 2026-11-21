-- The shape of an average day per merchant category: transactions in each hour of the day
-- (UTC), averaged over the days seen, and the average amount spent in that hour.
with hours as (
    select
        date_trunc('hour', event_at) as hour_start,
        merchant_category,
        count(*) as transactions,
        sum(amount) as total_amount
    from {{ ref('silver_transactions') }}
    group by 1, 2
)

select
    hour(hour_start) as hour_of_day,
    merchant_category,
    round(avg(transactions), 1) as average_transactions,
    round(sum(total_amount) / sum(transactions), 2) as average_amount
from hours
group by 1, 2
