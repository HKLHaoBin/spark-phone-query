#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
if [ -z "${CHROME_BIN:-}" ]; then
  for candidate in /opt/google/chrome/google-chrome /usr/bin/google-chrome-stable; do
    if [ -x "$candidate" ]; then
      CHROME_BIN="$candidate"
      break
    fi
  done
fi
CHROME_BIN="${CHROME_BIN:-$(command -v chromium || command -v google-chrome || true)}"
if [ -z "$CHROME_BIN" ]; then
  echo "找不到 Google Chrome/Chromium，无法截取 PNG 证据。" >&2
  exit 1
fi
if [ ! -f "$ROOT_DIR/artifacts/pi-result.json" ]; then
  echo "缺少 Pi 结果，请先执行 ./scripts/run_pi.sh。" >&2
  exit 1
fi
if [ ! -f "$ROOT_DIR/artifacts/guangzhou-count.json" ]; then
  echo "缺少广州统计结果，请先执行 ./scripts/run_pipeline.sh。" >&2
  exit 1
fi

EVIDENCE_DIR="$ROOT_DIR/artifacts/evidence"
mkdir -p "$EVIDENCE_DIR" "$ROOT_DIR/runtime/chrome-profile"

"$PYTHON_BIN" - "$ROOT_DIR" <<'PY'
from html import escape
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
evidence = root / "artifacts" / "evidence"

config = (root / "config" / "spark" / "spark-env.sh").read_text(encoding="utf-8")
pi = json.loads((root / "artifacts" / "pi-result.json").read_text(encoding="utf-8"))
count = json.loads((root / "artifacts" / "guangzhou-count.json").read_text(encoding="utf-8"))

base = """
body { margin: 0; padding: 48px; background: #0d1117; color: #f1f5f9;
  font-family: Inter, Arial, sans-serif; }
.card { width: 1420px; margin: auto; border: 1px solid #2b3b4e;
  border-radius: 24px; padding: 36px; background: #151c26; box-sizing: border-box; }
.eyebrow { color: #62d9c8; font-weight: 800; letter-spacing: .18em; font-size: 14px; }
h1 { margin: 12px 0 24px; font-size: 36px; }
pre { margin: 0; padding: 24px; border-radius: 14px; background: #0a0f15;
  color: #d7e4ee; font: 20px/1.55 "Liberation Mono", monospace; white-space: pre-wrap; }
.facts { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin-bottom: 24px; }
.fact { padding: 20px; border-radius: 14px; background: #1b2532; }
.label { color: #91a2b6; font-size: 15px; }
.value { margin-top: 9px; color: #62d9c8; font: 700 28px "Liberation Mono", monospace; }
"""

config_html = f"""<!doctype html><html><head><meta charset="utf-8"><style>{base}</style>
<title>spark-env.sh 配置证据</title></head><body><section class="card">
<div class="eyebrow">SPARK CONFIGURATION EVIDENCE</div>
<h1>spark-env.sh · 伪分布式集群配置</h1>
<pre>{escape(config)}</pre>
</section></body></html>"""

pi_html = f"""<!doctype html><html><head><meta charset="utf-8"><style>{base}</style>
<title>Spark Pi 结果证据</title></head><body><section class="card">
<div class="eyebrow">SPARK PI COMPUTATION EVIDENCE</div>
<h1>Pi 计算结果 · Spark Standalone</h1>
<div class="facts">
  <div class="fact"><div class="label">估算值 Pi</div><div class="value">{pi["pi"]:.8f}</div></div>
  <div class="fact"><div class="label">采样点总数</div><div class="value">{pi["total_points"]:,}</div></div>
  <div class="fact"><div class="label">广州匹配数量</div><div class="value">{count["count"]:,}</div></div>
</div>
<pre>{escape(json.dumps({"pi_result": pi, "guangzhou_count": count}, ensure_ascii=False, indent=2))}</pre>
</section></body></html>"""

(evidence / "spark-env.html").write_text(config_html, encoding="utf-8")
(evidence / "pi-result.html").write_text(pi_html, encoding="utf-8")
PY

"$CHROME_BIN" \
  --headless=new \
  --no-sandbox \
  --disable-gpu \
  --hide-scrollbars \
  --window-size=1600,1100 \
  --user-data-dir="$ROOT_DIR/runtime/chrome-profile" \
  --screenshot="$ROOT_DIR/artifacts/spark-env-config.png" \
  "file://$EVIDENCE_DIR/spark-env.html" >/dev/null

"$CHROME_BIN" \
  --headless=new \
  --no-sandbox \
  --disable-gpu \
  --hide-scrollbars \
  --window-size=1600,1100 \
  --user-data-dir="$ROOT_DIR/runtime/chrome-profile" \
  --screenshot="$ROOT_DIR/artifacts/pi-result.png" \
  "file://$EVIDENCE_DIR/pi-result.html" >/dev/null

{
  echo "# 运行证据"
  echo
  echo "## Spark 集群状态"
  "$ROOT_DIR/scripts/cluster.sh" status
  echo
  echo "## 广州统计"
  cat "$ROOT_DIR/artifacts/guangzhou-count.json"
  echo
  echo "## Pi 计算"
  cat "$ROOT_DIR/artifacts/pi-result.json"
  echo
  echo "截图："
  echo "- \`artifacts/spark-env-config.png\`"
  echo "- \`artifacts/pi-result.png\`"
} > "$ROOT_DIR/artifacts/verification.md"

echo "已保存：artifacts/spark-env-config.png"
echo "已保存：artifacts/pi-result.png"
echo "已保存：artifacts/verification.md"
