import json
import sys
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "dashboard"))
from build import build  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures" / "gold"


def test_builds_the_page_and_typed_data(tmp_path):
    build(FIXTURES, tmp_path, datetime(2026, 11, 21, 8, 0, tzinfo=UTC))

    data = json.loads((tmp_path / "data.json").read_text())
    assert data["built_at"] == "2026-11-21 08:00 UTC"
    assert data["tables"]["gold_card_testing"] == [
        {
            "day": "2026-11-02",
            "flagged": 0,
            "card_testing": 0,
            "caught": 0,
            "precision": None,
            "recall": None,
        },
        {"day": "2026-11-01", "flagged": 2, "card_testing": 4, "caught": 2, "precision": 1.0, "recall": 0.5},
    ]
    assert (tmp_path / "index.html").exists()
