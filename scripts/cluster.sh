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
if [ -z "$SPARK_HOME" ] || [ ! -x "$SPARK_HOME/bin/spark-class" ]; then
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

start_daemon() {
  local name="$1"
  local log_file="$2"
  shift 2
  local pid_file="$ROOT_DIR/runtime/pids/$name.pid"

  if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    echo "$name 已在运行（PID $(cat "$pid_file")）。"
    return 0
  fi
  rm -f "$pid_file"
  mkdir -p "$(dirname "$log_file")"

  (
    exec "$@"
  ) >>"$log_file" 2>&1 &
  echo $! >"$pid_file"
  echo "已启动 $name（PID $(cat "$pid_file")）。"
}

stop_daemon() {
  local name="$1"
  local pid_file="$ROOT_DIR/runtime/pids/$name.pid"
  if [ ! -f "$pid_file" ]; then
    return 0
  fi

  local pid
  pid="$(cat "$pid_file")"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pid_file"
  echo "已停止 $name。"
}

start_cluster() {
  mkdir -p "$ROOT_DIR/runtime/logs/master" "$ROOT_DIR/runtime/logs/worker-1" "$ROOT_DIR/runtime/logs/worker-2"

  start_daemon master "$ROOT_DIR/runtime/logs/master/master.log" \
    env \
      SPARK_PID_DIR="$ROOT_DIR/runtime/pids/master" \
      SPARK_LOG_DIR="$ROOT_DIR/runtime/logs/master" \
      SPARK_LOCAL_DIRS="$ROOT_DIR/runtime/spark-local/master" \
      "$SPARK_HOME/bin/spark-class" \
      org.apache.spark.deploy.master.Master \
      --host 127.0.0.1 --port 7077 --webui-port 18080
  start_daemon worker-1 "$ROOT_DIR/runtime/logs/worker-1/worker.log" \
    env \
      SPARK_PID_DIR="$ROOT_DIR/runtime/pids/worker-1" \
      SPARK_LOG_DIR="$ROOT_DIR/runtime/logs/worker-1" \
      SPARK_WORKER_DIR="$ROOT_DIR/runtime/workers/worker-1" \
      SPARK_LOCAL_DIRS="$ROOT_DIR/runtime/spark-local/worker-1" \
      "$SPARK_HOME/bin/spark-class" \
      org.apache.spark.deploy.worker.Worker \
      "$SPARK_MASTER_URL" --cores 2 --memory 1g --port 7078 --webui-port 18081 \
      --work-dir "$ROOT_DIR/runtime/workers/worker-1"
  start_daemon worker-2 "$ROOT_DIR/runtime/logs/worker-2/worker.log" \
    env \
      SPARK_PID_DIR="$ROOT_DIR/runtime/pids/worker-2" \
      SPARK_LOG_DIR="$ROOT_DIR/runtime/logs/worker-2" \
      SPARK_WORKER_DIR="$ROOT_DIR/runtime/workers/worker-2" \
      SPARK_LOCAL_DIRS="$ROOT_DIR/runtime/spark-local/worker-2" \
      "$SPARK_HOME/bin/spark-class" \
      org.apache.spark.deploy.worker.Worker \
      "$SPARK_MASTER_URL" --cores 2 --memory 1g --port 7079 --webui-port 18082 \
      --work-dir "$ROOT_DIR/runtime/workers/worker-2"

  for _ in $(seq 1 30); do
    if payload="$(curl --silent --fail "http://127.0.0.1:18080/json/" 2>/dev/null)"; then
      worker_count="$("$PYTHON_BIN" -c '
import json
import sys
payload = json.loads(sys.stdin.read())
print(sum(
    1 for worker in payload.get("workers", [])
    if worker.get("alive", worker.get("state") == "ALIVE")
))
' <<<"$payload")"
      if [ "$worker_count" -ge 2 ]; then
        echo "Spark master 已启动：$SPARK_MASTER_URL"
        status_cluster
        return 0
      fi
    fi
    sleep 1
  done

  echo "Spark master 或 worker 启动超时，请查看 runtime/logs。" >&2
  exit 1
}

stop_cluster() {
  stop_daemon worker-2
  stop_daemon worker-1
  stop_daemon master
  echo "Spark 伪分布式集群已停止。"
}

status_cluster() {
  local payload
  if ! payload="$(curl --silent --fail "http://127.0.0.1:18080/json/")"; then
    echo "Spark master 未运行。"
    return 1
  fi

  "$PYTHON_BIN" -c '
import json
import sys

payload = json.loads(sys.stdin.read())
workers = payload.get("workers", [])
def is_alive(worker):
    return worker.get("alive", worker.get("state") == "ALIVE")
alive = [worker for worker in workers if is_alive(worker)]
print(f"master={payload.get(\"status\", \"UNKNOWN\")} url={payload.get(\"url\", \"unknown\")}")
for worker in workers:
    state = "ALIVE" if is_alive(worker) else "DEAD"
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
