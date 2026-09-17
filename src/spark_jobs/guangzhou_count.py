#!/usr/bin/env python3
"""Count Guangzhou records in a CSV dataset with Spark SQL."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from pyspark.sql import SparkSession
from pyspark.sql.functions import col


REQUIRED_COLUMNS = {
    "record_id",
    "phone_number",
    "province",
    "city",
    "operator",
    "area_code",
    "postal_code",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input", type=Path, default=Path("data/generated/phone_attribution.csv")
    )
    parser.add_argument(
        "--output", type=Path, default=Path("artifacts/guangzhou-count.json")
    )
    parser.add_argument("--province", default="广东")
    parser.add_argument("--city", default="广州")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not args.input.exists():
        raise SystemExit(f"输入文件不存在：{args.input}")

    spark = (
        SparkSession.builder.appName("PhoneAttribution-GuangzhouCount")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")
    try:
        frame = (
            spark.read.option("header", "true")
            .option("inferSchema", "false")
            .option("encoding", "UTF-8")
            .csv(str(args.input))
        )
        missing = REQUIRED_COLUMNS.difference(frame.columns)
        if missing:
            raise SystemExit(f"输入文件缺少字段：{sorted(missing)}")

        frame = frame.cache()
        records_scanned = frame.count()
        matching = frame.filter(
            (col("province") == args.province) & (col("city") == args.city)
        )
        matching_count = matching.count()
        result = {
            "province": args.province,
            "city": args.city,
            "count": matching_count,
            "records_scanned": records_scanned,
            "input": str(args.input),
            "master": spark.sparkContext.master,
            "completed_at_utc": datetime.now(timezone.utc).isoformat(),
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"GUANGZHOU_COUNT={matching_count}")
        print(f"RECORDS_SCANNED={records_scanned}")
        print(f"RESULT_FILE={args.output}")
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
