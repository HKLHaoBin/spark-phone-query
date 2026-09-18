# 项目记忆图谱：Spark 手机号码归属地实验台

## 目的

- 在 Linux 主机上提供一个可重复运行的 Spark standalone 伪分布式集群演示。
- 用 Spark 处理确定性生成的海量手机号码归属地数据，输出广东广州数量。
- 通过 HTTP 页面和 API 按归属地字段查询匹配记录。
- 保存配置、Pi 计算和统计结果的可审计证据。

## 架构

```text
scripts/cluster.sh
  ├── Spark standalone master :7077 / UI :18080
  └── worker-1 :7078 / UI :18081, worker-2 :7079 / UI :18082

scripts/generate_data.py
  └── data/generated/phone_attribution.csv (默认 1,000,000 行，未纳入 Git)

scripts/run_pipeline.sh ──> src/spark_jobs/guangzhou_count.py ──> artifacts/guangzhou-count.json
scripts/run_pi.sh ────────> src/spark_jobs/pi.py ───────────────> artifacts/pi-result.json

src/app/main.py ──> Spark DataFrame 缓存 ──> /api/statistics/guangzhou
                                      └──> /api/records?location=...
src/web/ ──> 浏览器查询界面

AGENT.md ──> 后续 Agent 的约束、验收和线性 Git 流程
SKILL.md ──> 本项目的环境排障记录和迁移技能
```

## 关键实体和不变量

- 记录字段：`record_id`、`phone_number`、`province`、`city`、`operator`、`area_code`、`postal_code`。
- 第一条记录固定为 `115036,1477799,广东,广州,中国移动,020,510000`。
- 默认生成规则使约 40% 的记录是 `广东/广州`，1,000,000 条时预期统计结果为 400,000。
- Spark 统计只计 `province=广东 AND city=广州`，不会用 UI 文本或客户端结果冒充计算。
- 查询默认跨省、市、运营商、区号、邮编做精确匹配；`field` 参数可限定字段，`limit=0` 请求完整匹配集，常规页面使用分页。
- 缺少数据或 Spark 启动失败时，健康接口返回 `ready=false` 和错误信息。

## 证据与运行入口

- 配置：`config/spark/spark-env.sh`。
- 集群：`scripts/cluster.sh {start|stop|restart|status}`。
- 统计：`scripts/run_pipeline.sh`。
- Pi：`scripts/run_pi.sh`。
- 截图和报告：`scripts/capture_evidence.sh` 生成 `artifacts/spark-env-config.png`、`artifacts/pi-result.png`、`artifacts/verification.md`；`artifacts/phone-query-ui.png` 是查询页面证据。
- 项目测试：`pytest` 覆盖生成器的字段、行数和非法输入。

## 最近验证状态

2026-09-17 UTC 已在真实 Spark standalone 集群上验证：

- Master `ALIVE`，两个 Worker 均 `ALIVE`，每个 Worker 为 2 cores / 1024 MiB。
- 扫描 1,000,000 条 CSV 记录，`广东 AND 广州` 数量为 `400,000`。
- Spark Pi 使用 4 partitions、1,000,000 个采样点，结果为 `3.14020000`。
- `/api/health` 就绪；`/api/statistics/guangzhou`、`/api/records?location=广州&field=city`、空结果和非法字段 `400` 均已验证。
- 证据 PNG：`artifacts/spark-env-config.png`、`artifacts/pi-result.png`、`artifacts/phone-query-ui.png`；原始记录：`artifacts/verification.md`。
- 交接文档：`README.md`（用户）、`AGENT.md`（Agent）、`SKILL.md`（项目技能和问题记录）。
- 当前远程地址已核实为 Cursor Origin endpoint，不是 GitHub；若要完成 GitHub 上传，必须先提供/配置真实 GitHub remote，再通过 `git ls-remote` 验证。
