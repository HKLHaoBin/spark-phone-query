#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-python3}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "找不到 $PYTHON_BIN，请先安装 Python 3.11+。" >&2
  exit 1
fi

if [ ! -x "$ROOT_DIR/.venv/bin/python" ] || ! "$ROOT_DIR/.venv/bin/python" -m pip --version >/dev/null 2>&1; then
  rm -rf "$ROOT_DIR/.venv"
  if ! "$PYTHON_BIN" -m venv "$ROOT_DIR/.venv"; then
    echo "系统未提供 ensurepip，改用最新 virtualenv 创建隔离环境。" >&2
    rm -rf "$ROOT_DIR/.venv"
    "$PYTHON_BIN" -m pip install --user --break-system-packages --upgrade virtualenv
    "$PYTHON_BIN" -m virtualenv "$ROOT_DIR/.venv"
  fi
fi

"$ROOT_DIR/.venv/bin/python" -m pip install --upgrade pip
"$ROOT_DIR/.venv/bin/python" -m pip install --editable '.[dev]'

echo "依赖安装完成：$ROOT_DIR/.venv"
