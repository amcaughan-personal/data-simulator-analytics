# data-simulator-analytics

Turns the raw payments data that
[data-simulator-elt](https://github.com/amcaughan-personal/data-simulator-elt) lands in S3 into
tested models and a dashboard: dbt on Athena, in three layers.

**Dashboard:** https://amcaughan-personal.github.io/data-simulator-analytics/ (rebuilt daily).

```
EventBridge Scheduler (daily) ─► dbt runner (container Lambda) ─► Athena
     ELT raw tables (Glue) ─► bronze ─► silver ─► gold ─► dashboard
```

Why it's built this way: [design decisions](docs/design-decisions.md).

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

## Dashboard

[`dashboard/`](dashboard) is one static page: `build.py` turns the gold tables (exported as CSV
by `scripts/export-gold.sh`) into `data.json`, and `index.html` draws the charts with
[Vega-Lite](https://vega.github.io/vega-lite/), loaded from a CDN at pinned versions with
integrity hashes. [The dashboard workflow](.github/workflows/dashboard.yml) rebuilds it every day
at 08:00 UTC, after the dbt run, and publishes it to GitHub Pages. Its AWS role can only query
production's gold tables.

To build it locally from your machine:

```bash
scripts/export-gold.sh data-simulator-analytics data_simulator_analytics_gold build/gold
uv run python dashboard/build.py build/gold build/site
python3 -m http.server -d build/site   # http://localhost:8000
```

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
| `runner` | the dbt runner: a container Lambda (one run at a time) that runs `dbt source freshness` and `dbt build` daily at 07:30 UTC, allowed to read the ELT's raw zone and write this environment's layers; in prod, an alarm that emails when a run fails |
| `github-deploy` | the role GitHub Actions deploys as (only that GitHub environment's jobs can assume it), and the values the deploy workflow reads |
| `shared/registry` | one ECR repository for the runner's image, used by both environments (immutable tags, the last two images kept) |
| `prod/dashboard-access` | the role the dashboard workflow signs in as: only the repo's `dashboard` GitHub environment can assume it, and it can only query the gold tables |

Cost: about $0.30 a month. Athena bills $5/TB scanned with a 10 MB minimum per query, so a
daily build (~40 queries) in each environment costs about $0.15 a month; the image costs
about $0.05 a month to store; prod's alarm is $0.10. The Lambda stays within the free tier.

## Deploys

Infrastructure is applied by hand from a reviewed plan, dev before prod. The runner's image
ships through [the deploy workflow](.github/workflows/deploy.yml) on every merge that changes
the models or the runner: build the image once, point dev at it and run dbt once, then the same
for prod. Rolling back is re-running an earlier deploy.

## Operations

**The alarm** (`data-simulator-analytics-runner-errors`, prod only) emails when the daily run
fails: stale sources, a failing test, or a model error. The Lambda's logs (dbt's own output)
name the failing nodes. dbt skips the models downstream of a failing test, so they keep their
previous data until it's fixed; everything else is rebuilt as usual.

**Running dbt by hand** in an environment, e.g. rebuilding every table after the raw data
was replayed:

```bash
aws lambda invoke --function-name data-simulator-analytics-dev-runner \
  --payload '{"args": ["build", "--full-refresh"]}' --cli-binary-format raw-in-base64-out \
  --cli-read-timeout 900 /dev/stdout
```

or from your machine with `scripts/dbt.sh dev build --full-refresh`.

**Creating the runner from scratch** needs an image before the function can exist: apply
`shared/registry`, push a first image tagged `initial`, then apply each environment's `runner`
and `github-deploy`.

```bash
repo=$(aws ecr describe-repositories --repository-names data-simulator-analytics-runner \
  --query 'repositories[0].repositoryUri' --output text)
scripts/build-image.sh "$repo:initial"
aws ecr get-login-password | docker login --username AWS --password-stdin "${repo%%/*}"
docker push "$repo:initial"
```

## Development environment

For infrastructure work, open the repo in its dev container (VS Code: *Reopen in Container*): the
org's base image (from [dev-environment](https://github.com/amcaughan-personal/dev-environment))
plus the Terraform, Terragrunt and uv versions from `.tool-versions`.

## Repository layout

```
dbt/               the dbt project: models/ (sources.yml, bronze/, silver/, gold/, each with its
                   tests), data-tests/ (tests that span a model), profiles.yml
runner/            the Lambda that runs dbt, and its image (Dockerfile)
dashboard/         the dashboard page and its build script
tests/             Python tests (the project parses; the runner's behaviour)
scripts/           run dbt locally; build, deploy and smoke-test the runner
infra/terragrunt/  Terraform/Terragrunt for AWS
docs/              design decisions
```

## License

MIT
