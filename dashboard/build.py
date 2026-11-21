"""Build the dashboard site: the page, plus the gold tables in one JSON file that it reads.

    python dashboard/build.py <csv-dir> <site-dir>

<csv-dir> holds one CSV per gold table, as scripts/export-gold.sh writes them. CSV has no
types, so values that look like numbers become numbers again and empty values become null.
"""

import csv
import json
import shutil
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

PAGE = Path(__file__).with_name("index.html")


def parse(value: str) -> Any:
    if value == "":
        return None
    for number in (int, float):
        try:
            return number(value)
        except ValueError:
            pass
    return value


def read_table(path: Path) -> list[dict[str, Any]]:
    with path.open(newline="") as file:
        return [{key: parse(value) for key, value in row.items()} for row in csv.DictReader(file)]


def build(csv_dir: Path, site_dir: Path, now: datetime) -> None:
    tables = {path.stem: read_table(path) for path in sorted(csv_dir.glob("*.csv"))}
    if not tables:
        raise SystemExit(f"no CSV files in {csv_dir}")

    site_dir.mkdir(parents=True, exist_ok=True)
    data = {"built_at": now.strftime("%Y-%m-%d %H:%M UTC"), "tables": tables}
    (site_dir / "data.json").write_text(json.dumps(data, separators=(",", ":")))
    shutil.copy(PAGE, site_dir / "index.html")


if __name__ == "__main__":
    build(Path(sys.argv[1]), Path(sys.argv[2]), datetime.now(UTC))
