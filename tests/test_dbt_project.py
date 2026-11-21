"""dbt checks that need no warehouse: the project parses (models, refs, tests and YAML are
consistent). The models' SQL and data tests run against Athena on every dbt build."""

from pathlib import Path

from dbt.cli.main import dbtRunner

PROJECT_DIR = Path(__file__).parent.parent / "dbt"


def test_project_parses(monkeypatch, tmp_path):
    for name in ("DBT_SCHEMA_PREFIX", "DBT_ATHENA_WORKGROUP", "DBT_WAREHOUSE_BUCKET"):
        monkeypatch.setenv(name, "unused")

    result = dbtRunner().invoke(
        [
            "parse",
            "--project-dir",
            str(PROJECT_DIR),
            "--profiles-dir",
            str(PROJECT_DIR),
            "--target-path",
            str(tmp_path / "target"),
            "--log-path",
            str(tmp_path / "logs"),
        ]
    )

    assert result.success, result.exception
    models = {node.name for node in result.result.nodes.values() if node.resource_type == "model"}
    assert {"silver_transactions", "gold_card_testing"} <= models
