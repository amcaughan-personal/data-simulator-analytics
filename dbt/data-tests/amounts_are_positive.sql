-- Every transaction moves money: an amount of zero or less means the source is wrong.
select transaction_id, merchant_category, amount
from {{ ref('silver_transactions') }}
where amount <= 0
