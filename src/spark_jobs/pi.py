#!/usr/bin/env python3
"""Estimate Pi with Spark and save a compact result for the evidence page."""

from __future__ import annotations

import argparse
import json
import random
from datetime import datetime, timezone
from pathlib import Path

from pyspark.sql import SparkSession


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--partitions", type=int, default=4)
    parser.add_argument("--points-per-partition", type=int, default=250_000)
    parser.add_argument("--seed", type=int, default=20260917)
    parser.add_argument("--output", type=Path, default=Path("artifacts/pi-result.json"))
    return parser.parse_args()


def count_inside(partition_id: int, _: object, points_per_partition: int, seed: int):
    rng = random.Random(seed + partition_id)
    inside = 0
    for _ in range(points_per_partition):
        x = rng.random() * 2 - 1
        y = rng.random() * 2 - 1
        if x * x + y * y <= 1:
            inside += 1
    yield inside


def main() -> None:
    args = parse_args()
    if args.partitions <= 0 or args.points_per_partition <= 0:
        raise SystemExit("partitions 和 points-per-partition 必须大于 0")

    spark = (
        SparkSession.builder.appName("PhoneAttribution-Pi")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")
    try:
        inside = (
            spark.sparkContext.range(0, args.partitions, numSlices=args.partitions)
            .mapPartitionsWithIndex(
                lambda partition_id, values: count_inside(
                    partition_id, values, args.points_per_partition, args.seed
                )
            )
            .sum()
        )
        total = args.partitions * args.points_per_partition
        pi = 4 * inside / total
        result = {
            "application": "PhoneAttribution-Pi",
            "partitions": args.partitions,
            "points_per_partition": args.points_per_partition,
            "total_points": total,
            "inside_points": int(inside),
            "pi": pi,
            "seed": args.seed,
            "master": spark.sparkContext.master,
            "completed_at_utc": datetime.now(timezone.utc).isoformat(),
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"PI_RESULT={pi:.8f}")
        print(f"POINTS={total} INSIDE={inside} PARTITIONS={args.partitions}")
        print(f"RESULT_FILE={args.output}")
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
