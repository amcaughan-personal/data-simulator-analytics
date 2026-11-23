# Design decisions

Why the analytics side is built the way it is, and what each choice gives up.

- [dbt on Athena](#dbt-on-athena)
- [Bronze, silver, gold](#bronze-silver-gold)
- [One incremental model](#one-incremental-model)
- [Both environments read production's raw data](#both-environments-read-productions-raw-data)
- [dbt runs in a container Lambda](#dbt-runs-in-a-container-lambda)
- [Tests run with every build; CI only parses](#tests-run-with-every-build-ci-only-parses)
- [One image, one registry](#one-image-one-registry)
- [A static dashboard, rebuilt daily](#a-static-dashboard-rebuilt-daily)

## dbt on Athena

**Decision:** the models are dbt SQL, run by Athena over S3, with Glue as the catalog.

**Why:** the raw data is already in S3 with Glue tables (data-simulator-elt), so Athena reads
it where it is. Everything is pay-per-query and costs nothing while idle, and the catalog makes
every layer queryable by hand too. A warehouse such as Redshift or Snowflake would cost more
per month than this whole project does in a year.

**Trade-off:** Athena has a 10 MB minimum per query and a few seconds of latency each, so a
build of ~40 queries takes a couple of minutes. For a daily job that's fine.

## Bronze, silver, gold

**Decision:** three layers, each in its own Glue database:
- **bronze:** views that only fix types and names;
- **silver:** clean, deduplicated tables, one row per business entity;
- **gold:** metrics shaped for the dashboard.

**Why:** each layer has one job, so a question about the data has an obvious place to look,
and gold models never touch raw quirks (ISO strings, partition columns). Bronze being views
costs nothing to keep in step with raw.

## One incremental model

**Decision:** `silver_transactions` is incremental: each run merges the raw days since the
last run (plus one day back) into an Iceberg table, on `transaction_id`. Everything else is
rebuilt in full.

**Why:** transactions are the only table that grows without limit; merging only new
partitions keeps a run's cost flat as history grows. The rest is small enough that rebuilding
is simpler and can't drift. The day of overlap makes a missed run harmless: the next one
picks up its hours.

The start day is looked up before the merge and written into the query as a constant. Athena
skips raw partitions only for constants; with the start as a subquery, every run listed every
raw prefix since the first day, and that was most of the account's S3 bill.

**Trade-off:** a change to how silver is computed needs a full rebuild to apply to history, and
since the ELT's routine raw tables reach back only 14 days, that rebuild reads its history
tables: `--full-refresh --vars '{backfill: true}'`. The same switch catches up after a gap
longer than 14 days; a normal run fails rather than skip those days.

## Both environments read production's raw data

**Decision:** dev and prod models both read the ELT's production raw tables; they differ only
in where they write.

**Why:** that's the usual dbt arrangement: changes are developed and checked on real data. The
ELT's own dev environment stays its sandbox.

## dbt runs in a container Lambda

**Decision:** an EventBridge schedule invokes a Lambda, built from a container image holding
dbt and the project, once a day.

**Why:** everything lives in AWS and goes away with `terragrunt destroy`; there's no server,
and nothing costs money between runs. A build takes about two minutes, well inside Lambda's
15. An image (rather than a zip) is needed because dbt and its dependencies are too large for
a zip package.

**Trade-off:** if the project ever needed more than 15 minutes, it would move to ECS or Step
Functions. A single daily step doesn't need an orchestrator yet.

## Tests run with every build; CI only parses

**Decision:** data tests, unit tests and source freshness run inside every `dbt build`, in
dev first on each deploy, then prod. Pull requests only parse the project.

**Why:** dbt's tests need the warehouse. Running them on pull requests would mean CI writing
to AWS from unmerged code, with its own role and schemas. Instead, the deploy builds and tests
in dev before prod is touched, which catches the same problems one step later.

**Trade-off:** a SQL error is found after merging, in dev, rather than on the pull request.

## One image, one registry

**Decision:** each deploy builds one image and pushes it once to a registry both environments
share; dev, then prod, are pointed at its digest.

**Why:** prod runs exactly what dev tested, with nothing rebuilt or copied. Only dev's deploy
role can push; prod's can only read the image.

## A static dashboard, rebuilt daily

**Decision:** the dashboard is one HTML page on GitHub Pages with the gold tables baked in as
JSON, rebuilt by a GitHub Actions workflow every day after the dbt run. Charts are Vega-Lite
specs; the only code is a short Python build script and a little JavaScript to fill the page.

**Why:** the data changes once a day, so a static page shows the same thing a live BI tool would,
with nothing to host, secure or pay for. Viewers never touch AWS: the workflow's role can only
query production's gold tables. Vega-Lite charts are declarative JSON, readable without knowing
a charting library. A BI-as-code framework was considered, but the one that fitted best
(Evidence's open-source framework) has been deprecated in favour of a hosted product.

**Trade-off:** no interactive filtering beyond tooltips, and the page is as fresh as its last
build (it shows the date). If the scheduled workflow stopped (GitHub disables schedules after
60 days without repository activity), the page would keep showing its last data.
