#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
if [ ! -x "$PYTHON_BIN" ]; then
  echo "未找到虚拟环境，请先执行 ./scripts/install.sh。" >&2
  exit 1
fi

SPARK_HOME="${SPARK_HOME:-$("$PYTHON_BIN" -c 'from pathlib import Path; import pyspark; print(Path(pyspark.__file__).resolve().parent)' 2>/dev/null)}"
if [ -z "$SPARK_HOME" ] || [ ! -d "$SPARK_HOME/sbin" ]; then
  echo "无法定位 PySpark 的 Spark 发行目录，请重新执行安装。" >&2
  exit 1
fi

export SPARK_HOME
export SPARK_CONF_DIR="$ROOT_DIR/config/spark"
export PYSPARK_PYTHON="$PYTHON_BIN"
export PYSPARK_DRIVER_PYTHON="$PYTHON_BIN"
export SPARK_MASTER_URL="${SPARK_MASTER_URL:-spark://127.0.0.1:7077}"
export SPARK_LOG_DIR="$ROOT_DIR/runtime/logs"

mkdir -p "$ROOT_DIR/runtime"/{logs,master,pids,workers/worker-1,workers/worker-2,spark-local,master-recovery}

master_env() {
  env \
    SPARK_PID_DIR="$ROOT_DIR/runtime/pids/master" \
    SPARK_LOG_DIR="$ROOT_DIR/runtime/logs/master" \
    SPARK_LOCAL_DIRS="$ROOT_DIR/runtime/spark-local/master" \
    "$@"
}

worker_env() {
  local name="$1"
  shift
  env \
    SPARK_PID_DIR="$ROOT_DIR/runtime/pids/$name" \
    SPARK_LOG_DIR="$ROOT_DIR/runtime/logs/$name" \
    SPARK_WORKER_DIR="$ROOT_DIR/runtime/workers/$name" \
    SPARK_LOCAL_DIRS="$ROOT_DIR/runtime/spark-local/$name" \
    "$@"
}

start_cluster() {
  mkdir -p "$ROOT_DIR/runtime/logs/master" "$ROOT_DIR/runtime/logs/worker-1" "$ROOT_DIR/runtime/logs/worker-2"

  master_env "$SPARK_HOME/sbin/start-master.sh"
  worker_env worker-1 "$SPARK_HOME/sbin/start-worker.sh" "$SPARK_MASTER_URL" \
    --cores 2 --memory 1g --port 7078 --webui-port 18081
  worker_env worker-2 "$SPARK_HOME/sbin/start-worker.sh" "$SPARK_MASTER_URL" \
    --cores 2 --memory 1g --port 7079 --webui-port 18082

  for _ in $(seq 1 30); do
    if curl --silent --fail "http://127.0.0.1:18080/json" >/dev/null 2>&1; then
      echo "Spark master 已启动：$SPARK_MASTER_URL"
      status_cluster
      return 0
    fi
    sleep 1
  done

  echo "Spark master 启动超时，请查看 runtime/logs。" >&2
  exit 1
}

stop_cluster() {
  worker_env worker-2 "$SPARK_HOME/sbin/stop-worker.sh" || true
  worker_env worker-1 "$SPARK_HOME/sbin/stop-worker.sh" || true
  master_env "$SPARK_HOME/sbin/stop-master.sh" || true
  echo "Spark 伪分布式集群已停止。"
}

status_cluster() {
  local payload
  if ! payload="$(curl --silent --fail "http://127.0.0.1:18080/json")"; then
    echo "Spark master 未运行。"
    return 1
  fi

  "$PYTHON_BIN" -c '
import json
import sys

payload = json.loads(sys.stdin.read())
workers = payload.get("workers", [])
alive = [worker for worker in workers if worker.get("alive")]
print(f"master={payload.get(\"status\", \"UNKNOWN\")} url={payload.get(\"url\", \"unknown\")}")
for worker in workers:
    state = "ALIVE" if worker.get("alive") else "DEAD"
    print(f"worker={worker.get(\"id\", \"unknown\")} state={state} cores={worker.get(\"cores\", 0)} memory={worker.get(\"memory\", 0)}")
print(f"workers_alive={len(alive)}")
if len(alive) < 2:
    raise SystemExit("需要两个存活 worker，当前状态不足。")
' <<<"$payload"
}

case "${1:-}" in
  start)
    start_cluster
    ;;
  stop)
    stop_cluster
    ;;
  restart)
    stop_cluster
    start_cluster
    ;;
  status)
    status_cluster
    ;;
  *)
    echo "用法：$0 {start|stop|restart|status}" >&2
    exit 2
    ;;
esac
