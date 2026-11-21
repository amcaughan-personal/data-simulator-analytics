-- How well a simple rule catches card testing (fraudsters checking stolen cards with tiny
-- charges), scored daily against the API's labels:
-- - the rule flags any charge of $1.00 or less;
-- - precision: the share of flagged charges that really were card testing;
-- - recall: the share of card-testing charges the rule flagged.
-- Only complete days.
with transactions as (
    select
        date(event_at) as day,
        amount <= 1.00 as is_flagged,
        is_card_testing
    from {{ ref('silver_transactions') }}
    where event_at < (select date_trunc('day', max(event_at)) from {{ ref('silver_transactions') }})
)

select
    day,
    count_if(is_flagged) as flagged,
    count_if(is_card_testing) as card_testing,
    count_if(is_flagged and is_card_testing) as caught,
    round(cast(count_if(is_flagged and is_card_testing) as double) / nullif(count_if(is_flagged), 0), 3)
        as precision,
    round(cast(count_if(is_flagged and is_card_testing) as double) / nullif(count_if(is_card_testing), 0), 3)
        as recall
from transactions
group by 1
