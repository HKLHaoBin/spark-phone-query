#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
if [ ! -x "$PYTHON_BIN" ]; then
  echo "未找到虚拟环境，请先执行 ./scripts/install.sh。" >&2
  exit 1
fi

SPARK_HOME="${SPARK_HOME:-$("$PYTHON_BIN" -c 'from pathlib import Path; import pyspark; print(Path(pyspark.__file__).resolve().parent)')}"
export SPARK_HOME
export SPARK_CONF_DIR="$ROOT_DIR/config/spark"
export PYSPARK_PYTHON="$PYTHON_BIN"
export PYSPARK_DRIVER_PYTHON="$PYTHON_BIN"
export SPARK_MASTER_URL="${SPARK_MASTER_URL:-spark://127.0.0.1:7077}"

if ! curl --silent --fail "http://127.0.0.1:18080/json/" >/dev/null 2>&1; then
  echo "Spark master 未运行，请先执行 ./scripts/cluster.sh start。" >&2
  exit 1
fi

"$SPARK_HOME/bin/spark-submit" \
  --master "$SPARK_MASTER_URL" \
  --deploy-mode client \
  --conf "spark.pyspark.python=$PYSPARK_PYTHON" \
  --conf "spark.pyspark.driver.python=$PYSPARK_DRIVER_PYTHON" \
  "$ROOT_DIR/src/spark_jobs/pi.py" \
  --partitions "${PI_PARTITIONS:-4}" \
  --points-per-partition "${PI_POINTS_PER_PARTITION:-250000}" \
  --output "$ROOT_DIR/artifacts/pi-result.json"
