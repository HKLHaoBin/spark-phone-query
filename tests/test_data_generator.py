from __future__ import annotations

import csv

from scripts.generate_data import FIELDNAMES, generate, record_for


def test_required_example_record_is_present():
    assert record_for(0) == {
        "record_id": "115036",
        "phone_number": "1477799",
        "province": "广东",
        "city": "广州",
        "operator": "中国移动",
        "area_code": "020",
        "postal_code": "510000",
    }


def test_generator_writes_requested_number_of_rows(tmp_path):
    output = tmp_path / "phone_attribution.csv"
    assert generate(output, 12) == 12

    with output.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))

    assert len(rows) == 12
    assert list(rows[0]) == FIELDNAMES
    assert sum(row["city"] == "广州" for row in rows) > 0


def test_generator_rejects_non_positive_size(tmp_path):
    try:
        generate(tmp_path / "invalid.csv", 0)
    except ValueError as exc:
        assert "大于 0" in str(exc)
    else:
        raise AssertionError("expected ValueError")
