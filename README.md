# data-simulator-analytics

> **Paused (November 2026).** The AWS resources are torn down to save cost, so the models
> don't run and the dashboard shows its last data (24 November 2026); the code,
> infrastructure and CI are all here. [Resuming](#resuming) brings it back.

Turns the raw payments data that
[data-simulator-elt](https://github.com/amcaughan-personal/data-simulator-elt) lands in S3 into
tested models and a dashboard: dbt on Athena, in three layers.

**Dashboard:** https://amcaughan-personal.github.io/data-simulator-analytics/ (rebuilt daily;
while paused, it shows the last build).

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
| `shared/registry` | one ECR repository for the runner's image, used by both environments (immutable tags, the last two images kept) |

The roles GitHub Actions signs in as live in personal-infra (`github-ci-roles/data-simulator-analytics/`): each environment's deploy role (only that GitHub environment's jobs can assume it; dev's can push the runner image, prod's can only read it) and the dashboard's role (only the `dashboard` environment; it can only query the gold tables). Every IAM role created here carries personal-infra's permissions boundary for this repo.

Cost: about $0.30 a month. Athena bills $5/TB scanned with a 10 MB minimum per query, so a
daily build (~40 queries) in each environment costs about $0.15 a month; the image costs
about $0.05 a month to store; prod's alarm is $0.10. The Lambda stays within the free tier.

## Deploys

Infrastructure changes get a plan comment on their pull request, and
[terragrunt-apply](.github/workflows/terragrunt-apply.yml) applies them after merging: the shared
registry, dev, then prod once approved (the run's summary shows prod's plan before that). It can
create and change this repo's resources but not delete them, so a change that would destroy or
replace anything stops there and is applied by hand. The runner's image
ships through [the deploy workflow](.github/workflows/deploy.yml) on every merge that changes
the models or the runner: build the image once, point dev at it and run dbt once, then the same
for prod. Rolling back is re-running an earlier deploy.

A [daily drift check](.github/workflows/drift.yml) plans `main` read-only and fails if AWS
doesn't match it: a change made outside Terraform, or one merged but not applied yet.

## Operations

**The alarm** (`data-simulator-analytics-runner-errors`, prod only) emails when the daily run
fails: stale sources, a failing test, or a model error. The Lambda's logs (dbt's own output)
name the failing nodes. dbt skips the models downstream of a failing test, so they keep their
previous data until it's fixed; everything else is rebuilt as usual.

**Running dbt by hand** in an environment: pass dbt arguments to the Lambda, e.g. one model and
everything downstream of it:

```bash
aws lambda invoke --function-name data-simulator-analytics-dev-runner \
  --payload '{"args": ["build", "--select", "silver_transactions+"]}' \
  --cli-binary-format raw-in-base64-out --cli-read-timeout 900 /dev/stdout
```

or from your machine: `scripts/dbt.sh dev build --select silver_transactions+`.

**Backfills.** The ELT's raw tables (`transactions`, `merchants`) reach back only 14 days, so a
query on them lists a bounded number of S3 prefixes however old the data gets. Its
`<table>_history` tables reach back to the first day; `--vars '{backfill: true}'` makes the
bronze models read those instead:

- **Catch up after a long gap.** If silver is older than the 14-day window, the daily build
  fails rather than skip days, and says so. Catch up from the history tables:
  `scripts/dbt.sh prod build --select silver_transactions+ --vars '{backfill: true}'`.
- **Rebuild everything**, e.g. after changing how silver is computed:
  `scripts/dbt.sh prod build --full-refresh --vars '{backfill: true}'`. Without `backfill`, a
  full refresh would rebuild only the last 14 days.

In a Lambda payload: `{"args": ["build", "--full-refresh", "--vars", "{backfill: true}"]}`.
A backfill lists every raw prefix since the first day once per query, a few cents at most.
If the raw files themselves are gone, the ELT re-pulls them from the API first (see its README).

**Creating the runner from scratch** needs an image before the function can exist: apply
`shared/registry`, push a first image tagged `initial`, then apply each environment's `runner`
(by hand: creating the function needs to read the image, which CI's apply role can't).

```bash
repo=$(aws ecr describe-repositories --repository-names data-simulator-analytics-runner \
  --query 'repositories[0].repositoryUri' --output text)
scripts/build-image.sh "$repo:initial"
aws ecr get-login-password | docker login --username AWS --password-stdin "${repo%%/*}"
docker push "$repo:initial"
```

## Resuming

Resume data-simulator-elt first, so there's raw data to read. Then:

1. Revert the pause PR, which turns the automatic triggers back on (deploy, apply, drift,
   dashboard).
2. Apply `shared/registry` (by hand, or [terragrunt-apply](.github/workflows/terragrunt-apply.yml)
   started by hand, which also creates the warehouses), push a first image and create each
   environment's `runner` by hand, as in *Creating the runner from scratch* above.
3. Rebuild every table from all of the raw data, not just the last 14 days:
   `scripts/dbt.sh prod build --full-refresh --vars '{backfill: true}'` (and the same for
   `dev`). Then run the [dashboard workflow](.github/workflows/dashboard.yml) by hand.

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
