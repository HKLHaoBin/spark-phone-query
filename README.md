# Spark 手机号码归属地实验台

这是一个可重复运行的 Spark 伪分布式集群示例。它在当前 Linux 主机上启动一个 standalone master 和两个 worker，使用 Spark 完成 Pi 计算、生成的海量归属地 CSV 统计，并提供一个可查询的浏览器界面。

## 已实现能力

- `config/spark/spark-env.sh`：master、两个 worker、端口、内存和本地目录配置。
- `scripts/cluster.sh`：启动、停止、重启和检查伪分布式集群。
- `scripts/run_pi.sh`：通过 `spark-submit` 运行 Spark Pi。
- `scripts/generate_data.py`：默认生成 1,000,000 条确定性的归属地记录。
- `scripts/run_pipeline.sh`：生成数据后交给 Spark，统计 `广东 / 广州` 的数量并输出 JSON。
- FastAPI + 静态页面：输入省、市、运营商、区号或邮编，查询所有匹配记录；接口支持 `offset` / `limit` 分页，`limit=0` 可请求完整匹配集。
- `scripts/capture_evidence.sh`：将真实的 `spark-env.sh` 配置和 Pi/广州统计结果渲染成 PNG 证据图。

生成器的第一条记录严格包含题目给出的七个值：

| record_id | phone_number | province | city | operator | area_code | postal_code |
| --- | --- | --- | --- | --- | --- | --- |
| 115036 | 1477799 | 广东 | 广州 | 中国移动 | 020 | 510000 |

## 环境要求

- Linux
- Python 3.11+
- Java 17+（当前环境使用 Java 21）
- Google Chrome 或 Chromium（仅用于生成截图证据）

## 快速运行

```bash
./scripts/install.sh

# 启动一个 master 和两个 worker
./scripts/cluster.sh start
./scripts/cluster.sh status

# 生成 100 万条数据，并通过 Spark 统计广州数量
./scripts/run_pipeline.sh

# 运行 Spark Pi
./scripts/run_pi.sh

# 生成两张 PNG 和一份可审计的运行报告
./scripts/capture_evidence.sh
```

默认数据会写入 `data/generated/phone_attribution.csv`，该海量数据被 `.gitignore` 忽略；结果与截图保存在 `artifacts/`。要快速验证流程，可以降低行数：

```bash
ROWS=10000 ./scripts/run_pipeline.sh
PI_POINTS_PER_PARTITION=50000 ./scripts/run_pi.sh
```

## 启动查询服务

先完成上面的数据生成，然后让 API 驱动连接到 standalone master：

```bash
SPARK_MASTER_URL=spark://127.0.0.1:7077 \
PHONE_DATA_PATH=data/generated/phone_attribution.csv \
  .venv/bin/uvicorn src.app.main:app --host 0.0.0.0 --port 43123
```

打开 <http://127.0.0.1:43123/>。页面会显示广州数量，并提供归属地查询表格。API 示例：

```bash
# 统计广州数量
curl http://127.0.0.1:43123/api/statistics/guangzhou

# 查询所有 city=广州 的结果页；total 是完整匹配数量
curl 'http://127.0.0.1:43123/api/records?location=广州&field=city&limit=100'

# 请求完整匹配集（数据量很大时建议使用分页）
curl 'http://127.0.0.1:43123/api/records?location=广州&limit=0'
```

查询服务在启动时将 CSV 缓存为 Spark DataFrame；如果数据文件或 Spark master 不可用，`/api/health` 会报告明确错误，页面会展示错误状态，而不是返回伪造结果。

## 测试与停止

```bash
.venv/bin/pytest
./scripts/cluster.sh status
./scripts/cluster.sh stop
```

证据文件：

- `artifacts/spark-env-config.png`：实际 `spark-env.sh` 配置截图。
- `artifacts/pi-result.png`：实际 Spark Pi 和广州统计结果截图。
- `artifacts/verification.md`：集群状态、统计 JSON、Pi JSON 的原始运行记录。
