#!/usr/bin/env bash

# Spark pseudo-distributed cluster configuration.
# The launcher exports SPARK_HOME, SPARK_CONF_DIR, PID and log directories.
export SPARK_MASTER_HOST=127.0.0.1
export SPARK_MASTER_PORT=7077
export SPARK_MASTER_WEBUI_PORT=18080

# Two worker processes are started by scripts/cluster.sh.
export SPARK_WORKER_CORES=2
export SPARK_WORKER_MEMORY=1g
export SPARK_WORKER_WEBUI_PORT=18081

# Keep Spark's local shuffle and scratch files inside this project.
export SPARK_LOCAL_DIRS="${SPARK_LOCAL_DIRS:-${PWD}/runtime/spark-local}"

# Keep the standalone master recoverable across a process restart.
export SPARK_MASTER_OPTS="${SPARK_MASTER_OPTS:--Dspark.deploy.recoveryMode=FILESYSTEM -Dspark.deploy.recoveryDirectory=${PWD}/runtime/master-recovery}"
