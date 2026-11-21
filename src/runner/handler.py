"""Lambda entry point. EventBridge Scheduler invokes it once a day with `{}`, which runs:

1. `dbt source freshness`: is the ELT's raw data recent?
2. `dbt build`: every model, then its tests, layer by layer.

Both run even if the first fails, so the models stay as fresh as the raw data allows; the
run then fails, which is what the alarm watches. An event with `args` runs those dbt
arguments instead, e.g. `{"args": ["build", "--full-refresh"]}` to rebuild every table.

dbt reads the environment's workgroup, bucket and schema prefix from environment variables
(see profiles.yml) and writes its working files under /tmp (the only writable path).
"""

import logging
import os
from typing import Any

from dbt.cli.main import dbtRunner

log = logging.getLogger(__name__)
log.setLevel(logging.INFO)

SCHEDULED_COMMANDS = [["source", "freshness"], ["build"]]


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    commands = [event["args"]] if event.get("args") else SCHEDULED_COMMANDS
    project_dir = os.environ["DBT_PROJECT_DIR"]

    results = {}
    for args in commands:
        command = " ".join(args)
        result = dbtRunner().invoke([*args, "--project-dir", project_dir, "--profiles-dir", project_dir])
        results[command] = "succeeded" if result.success else "failed"
        log.info("dbt %s %s", command, results[command])

    failed = [command for command, outcome in results.items() if outcome == "failed"]
    if failed:
        raise RuntimeError(f"dbt failed: {', '.join(failed)}. The log above says which nodes and why.")
    return results
