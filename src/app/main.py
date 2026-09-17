#!/usr/bin/env python3
"""FastAPI UI/API backed by a cached Spark DataFrame."""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from dataclasses import dataclass
from functools import reduce
from operator import or_
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import col, lower, trim


ROOT_DIR = Path(__file__).resolve().parents[2]
WEB_DIR = ROOT_DIR / "src" / "web"
DEFAULT_DATA_PATH = ROOT_DIR / "data" / "generated" / "phone_attribution.csv"
SEARCH_FIELDS = ("province", "city", "operator", "area_code", "postal_code")
LOGGER = logging.getLogger("phone-attribution")


@dataclass
class SparkStore:
    """Own the Spark session and provide safe query operations for the API."""

    data_path: Path
    master: str
    spark: SparkSession | None = None
    frame: DataFrame | None = None
    records_loaded: int = 0
    error: str | None = None

    def start(self) -> None:
        if not self.data_path.exists():
            self.error = f"数据文件不存在：{self.data_path}"
            return

        try:
            self.spark = (
                SparkSession.builder.appName("PhoneAttribution-Web")
                .master(self.master)
                .config("spark.sql.shuffle.partitions", "8")
                .getOrCreate()
            )
            self.spark.sparkContext.setLogLevel("WARN")
            self.frame = (
                self.spark.read.option("header", "true")
                .option("inferSchema", "false")
                .option("encoding", "UTF-8")
                .csv(str(self.data_path))
                .cache()
            )
            self.records_loaded = self.frame.count()
            self.error = None
        except Exception as exc:  # Spark startup errors must be visible to health API.
            LOGGER.exception("Spark 数据源启动失败")
            self.error = str(exc)
            self.stop()

    def stop(self) -> None:
        if self.spark is not None:
            self.spark.stop()
        self.spark = None
        self.frame = None

    @property
    def ready(self) -> bool:
        return self.frame is not None and self.error is None

    def require_frame(self) -> DataFrame:
        if not self.ready:
            raise HTTPException(
                status_code=503,
                detail=self.error or "Spark 数据源尚未就绪",
            )
        assert self.frame is not None
        return self.frame

    def location_condition(self, location: str, field: str | None) -> Any:
        normalized = location.strip().lower()
        fields = (field,) if field else SEARCH_FIELDS
        return reduce(
            or_,
            (lower(trim(col(name))) == normalized for name in fields),
        )

    def query(
        self,
        location: str,
        field: str | None,
        offset: int,
        limit: int,
    ) -> dict[str, Any]:
        frame = self.require_frame()
        matching = frame.filter(self.location_condition(location, field))
        total = matching.count()
        if limit == 0:
            selected_rows = matching.collect()
        else:
            # DataFrame.offset is not available in every supported Spark
            # release. Limit before collecting to keep pagination bounded.
            selected_rows = matching.limit(offset + limit).collect()[offset:]
        rows = [{key: value for key, value in row.asDict().items()} for row in selected_rows]
        return {
            "location": location.strip(),
            "field": field or "all-attribution-fields",
            "total": total,
            "offset": offset,
            "returned": len(rows),
            "has_more": offset + len(rows) < total,
            "records": rows,
        }

    def guangzhou_count(self) -> int:
        frame = self.require_frame()
        return frame.filter(
            (col("province") == "广东") & (col("city") == "广州")
        ).count()


def build_store() -> SparkStore:
    configured_path = Path(
        os.getenv("PHONE_DATA_PATH", str(DEFAULT_DATA_PATH))
    ).expanduser()
    if not configured_path.is_absolute():
        configured_path = ROOT_DIR / configured_path
    return SparkStore(
        data_path=configured_path,
        master=os.getenv("SPARK_MASTER_URL", "local[2]"),
    )


store = build_store()


@asynccontextmanager
async def lifespan(_: FastAPI):
    store.start()
    yield
    store.stop()


app = FastAPI(
    title="Spark 手机号码归属地查询",
    description="使用 Spark 统计广州号码数量，并按归属地字段查询记录。",
    version="0.1.0",
    lifespan=lifespan,
)


@app.get("/api/health")
def health() -> dict[str, Any]:
    return {
        "service": "phone-attribution",
        "ready": store.ready,
        "master": store.master,
        "data_path": str(store.data_path),
        "records_loaded": store.records_loaded,
        "error": store.error,
    }


@app.get("/api/statistics/guangzhou")
def statistics() -> dict[str, Any]:
    return {
        "province": "广东",
        "city": "广州",
        "count": store.guangzhou_count(),
        "records_scanned": store.records_loaded,
        "master": store.master,
    }


@app.get("/api/records")
def records(
    location: str = Query(..., min_length=1, max_length=64),
    field: str | None = Query(None),
    offset: int = Query(0, ge=0, le=10_000_000),
    limit: int = Query(100, ge=0, le=10_000),
) -> dict[str, Any]:
    if field is not None and field not in SEARCH_FIELDS:
        raise HTTPException(
            status_code=400,
            detail=f"field 必须是以下值之一：{', '.join(SEARCH_FIELDS)}",
        )
    return store.query(location, field, offset, limit)


@app.get("/", include_in_schema=False)
def root() -> RedirectResponse:
    return RedirectResponse(url="/index.html")


app.mount("/", StaticFiles(directory=str(WEB_DIR), html=True), name="web")
