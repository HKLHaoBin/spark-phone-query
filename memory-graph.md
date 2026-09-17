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
- 截图和报告：`scripts/capture_evidence.sh` 生成 `artifacts/spark-env-config.png`、`artifacts/pi-result.png`、`artifacts/verification.md`。
- 项目测试：`pytest` 覆盖生成器的字段、行数和非法输入。

## 最近验证状态

初始图谱建立于项目脚手架阶段。运行真实 Spark 集群、数据统计、Pi、查询接口和截图后，应将结果（时间、数量、Pi 值、worker 数量）补充到本节。
