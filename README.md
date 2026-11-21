# data-simulator-analytics

Turns the raw payments data that
[data-simulator-elt](https://github.com/amcaughan-personal/data-simulator-elt) lands in S3 into
tested models and a dashboard: dbt on Athena, in three layers.

```
ELT raw tables (Glue) ─► bronze ─► silver ─► gold ─► dashboard
```

| Layer | What it holds |
|---|---|
| bronze | raw rows with proper types and names, one row per source row |
| silver | cleaned, deduplicated and joined: one row per transaction, merchants as a dimension |
| gold | metrics for the dashboard |

## Models

| Model | Layer | What it is |
|---|---|---|
| `bronze_transactions`, `bronze_merchants` | bronze (views) | the raw tables with proper types and names |
| `silver_transactions` | silver | one row per transaction, deduplicated, amounts in cents. **Incremental**: each run merges the days since the last one, reading only those raw partitions |
| `silver_merchants` | silver | the merchants as of the latest daily snapshot |
| `gold_daily_category_metrics` | gold | per complete day and category: volume, declines, decline rate, money approved |
| `gold_hourly_pattern` | gold | an average day's shape per category: transactions and average amount by hour |
| `gold_merchant_performance` | gold | each merchant over the last 30 complete days, with city and risk tier |
| `gold_card_testing` | gold | daily precision and recall of a simple card-testing rule (flag charges of $1.00 or less) against the API's labels |

**Tests** run with every build:
- **Data tests:** unique and not-null keys, accepted values, every transaction's merchant
  exists, amounts are positive.
- **dbt unit tests:** the decline-rate and precision/recall logic, on hand-written rows.
- **Source freshness:** warns after 3 hours without new transactions, fails after 6.

CI also parses the project on every pull request (`tests/`), which catches broken refs, YAML
and Jinja without a warehouse.

## Run it locally

```bash
uv sync
uv run pytest                                   # parse the project
scripts/dbt.sh dev build                        # build and test everything in dev
scripts/dbt.sh dev source freshness
scripts/dbt.sh dev show --select gold_card_testing
```

`scripts/dbt.sh` uses your AWS credentials and points dbt at the environment's workgroup and
bucket. uv uses the Python version in `.python-version`.

## AWS

Terragrunt stacks per environment (`dev`, `prod`), with `env.hcl` holding the only differences.
`dev` is a full copy that changes go through before `prod`, and a place to experiment. Both read
the ELT's production raw tables.

| Stack | What it holds |
|---|---|
| `warehouse` | an S3 bucket for the models' tables and Athena's query results (kept a week), a Glue database per layer, and an Athena workgroup that caps how much one query may scan (1 GiB) |

## Development environment

For infrastructure work, open the repo in its dev container (VS Code: *Reopen in Container*): the
org's base image (from [dev-environment](https://github.com/amcaughan-personal/dev-environment))
plus the Terraform, Terragrunt and uv versions from `.tool-versions`.

## Repository layout

```
models/            dbt models: sources.yml, bronze/, silver/, gold/ (each with its tests)
data-tests/        SQL data tests that span a model
tests/             Python tests (the project parses)
scripts/dbt.sh     run dbt against dev or prod
infra/terragrunt/  Terraform/Terragrunt for AWS
```

## License

MIT
