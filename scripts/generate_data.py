#!/usr/bin/env python3
"""Generate deterministic synthetic phone-attribution data for Spark."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path
from typing import Dict, Iterable


FIELDNAMES = [
    "record_id",
    "phone_number",
    "province",
    "city",
    "operator",
    "area_code",
    "postal_code",
]

LOCATIONS = [
    ("广东", "广州", "中国移动", "020", "510000"),
    ("广东", "深圳", "中国联通", "0755", "518000"),
    ("广东", "佛山", "中国电信", "0757", "528000"),
    ("浙江", "杭州", "中国移动", "0571", "310000"),
    ("四川", "成都", "中国联通", "028", "610000"),
    ("湖北", "武汉", "中国电信", "027", "430000"),
    ("北京", "北京", "中国移动", "010", "100000"),
    ("上海", "上海", "中国联通", "021", "200000"),
]


def record_for(index: int) -> Dict[str, str]:
    """Return one deterministic record.

    The first record deliberately contains every value supplied in the task:
    115036, 1477799, 广东, 广州, 中国移动, 020, 510000.
    """

    if index == 0:
        return dict(
            zip(
                FIELDNAMES,
                ["115036", "1477799", "广东", "广州", "中国移动", "020", "510000"],
            )
        )

    # Keep Guangzhou frequent enough to make the aggregation meaningful while
    # distributing the remainder across seven other attribution locations.
    if index % 5 in (0, 1):
        location_index = 0
    else:
        location_index = 1 + ((index * 17) % (len(LOCATIONS) - 1))
    province, city, operator, area_code, postal_code = LOCATIONS[location_index]

    return {
        "record_id": str(115036 + index),
        "phone_number": f"1{(4700000000 + index):010d}",
        "province": province,
        "city": city,
        "operator": operator,
        "area_code": area_code,
        "postal_code": postal_code,
    }


def records(count: int) -> Iterable[Dict[str, str]]:
    for index in range(count):
        yield record_for(index)


def generate(output: Path, count: int) -> int:
    if count <= 0:
        raise ValueError("数据量必须大于 0")

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, lineterminator="\n")
        writer.writeheader()
        writer.writerows(records(count))
    return count


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--rows",
        type=int,
        default=1_000_000,
        help="生成行数（默认 1,000,000；包含表头的文件行数会多一行）",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/generated/phone_attribution.csv"),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    count = generate(args.output, args.rows)
    print(f"已生成 {count:,} 条归属地记录：{args.output}")
    print(f"示例首条记录：{record_for(0)}")


if __name__ == "__main__":
    main()
