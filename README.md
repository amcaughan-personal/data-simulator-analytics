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

## Status

The AWS side of the warehouse (bucket, Glue databases, Athena workgroup) is in
`infra/terragrunt`. The dbt models, the scheduled dbt run and the dashboard come next.

## AWS

Terragrunt stacks per environment (`dev`, `prod`), with `env.hcl` holding the only differences.
`dev` is a full copy that changes go through before `prod`, and a place to experiment. Both read
the ELT's production raw tables.

| Stack | What it holds |
|---|---|
| `warehouse` | an S3 bucket for the models' tables and Athena's query results (kept a week), a Glue database per layer, and an Athena workgroup that caps how much one query may scan (1 GiB) |

## Development environment

Open the repo in its dev container (VS Code: *Reopen in Container*): the org's base image (from
[dev-environment](https://github.com/amcaughan-personal/dev-environment)) plus the Terraform,
Terragrunt and uv versions from `.tool-versions`.

## License

MIT
