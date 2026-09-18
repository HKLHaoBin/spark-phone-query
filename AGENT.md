# AGENT.md：Spark 手机号码归属地项目说明书

本文档面向继续维护本项目的 Agent。开始工作前，先阅读本文件、[`SKILL.md`](SKILL.md)、[`README.md`](README.md) 和 [`memory-graph.md`](memory-graph.md)，再以当前工作树和命令输出为准，不依赖旧对话中的猜测。

## 1. 项目目标

本项目是一个可重复运行的 Spark standalone 伪分布式实验台，必须持续保留以下能力：

1. 在 Linux 主机上启动一个 Spark Master 和两个 Worker。
2. 运行 Spark Pi，并保存可审计的结果。
3. 生成默认 1,000,000 条手机号码归属地记录，用 Spark 统计 `广东 / 广州` 数量。
4. 提供按省、市、运营商、区号和邮编查询的 API/UI。
5. 保留配置截图、计算结果、验证报告和可迁移的运行记录。

## 2. 当前状态和关键事实

- 当前功能分支：`cursor/spark-phone-query-5bd1`。
- 当前 `origin` 已验证为 `https://github.com/HKLHaoBin/spark-phone-query.git`，功能分支已推送到 GitHub；后续仍须用 `git ls-remote origin` 验证远程状态。
- 当前环境已验证：Python 3.12、Java 21、PySpark 4.2.0、FastAPI 0.141.1、Uvicorn 0.53.0。
- 默认数据量：1,000,000 条；CSV 在 `data/generated/`，被 `.gitignore` 忽略。
- 固定首条记录：`115036,1477799,广东,广州,中国移动,020,510000`。
- 默认统计结果：`广东 AND 广州 = 400,000`。
- 已验证 Pi：`3.14020000`。
- 默认 Web 地址：`http://127.0.0.1:43123`。
- 集群端口：Master RPC `7077`、Master UI `18080`、Worker UI `18081/18082`。

## 3. 架构和入口

```text
config/spark/spark-env.sh
  └── scripts/cluster.sh
        ├── spark-class org.apache.spark.deploy.master.Master
        └── spark-class org.apache.spark.deploy.worker.Worker × 2

scripts/generate_data.py
  └── data/generated/phone_attribution.csv

scripts/run_pipeline.sh
  └── src/spark_jobs/guangzhou_count.py

scripts/run_pi.sh
  └── src/spark_jobs/pi.py

src/app/main.py
  ├── GET /api/health
  ├── GET /api/statistics/guangzhou
  └── GET /api/records?location=...&field=...&offset=...&limit=...

src/web/
  └── 浏览器查询页面
```

修改集群启动方式时，必须继续支持 pip 安装的 PySpark 发行包。该发行包可能没有 `sbin/start-master.sh`，当前实现通过 `spark-class` 直接启动 Master/Worker，并用 `runtime/pids/` 管理进程。

## 4. 标准操作流程

```bash
cd /workspace
./scripts/install.sh
./scripts/cluster.sh start
./scripts/cluster.sh status
./scripts/run_pipeline.sh
./scripts/run_pi.sh
./scripts/capture_evidence.sh
SPARK_MASTER_URL=spark://127.0.0.1:7077 \
PHONE_DATA_PATH=data/generated/phone_attribution.csv \
.venv/bin/uvicorn src.app.main:app --host 0.0.0.0 --port 43123
```

验证接口：

```bash
curl http://127.0.0.1:43123/api/health
curl http://127.0.0.1:43123/api/statistics/guangzhou
curl -G http://127.0.0.1:43123/api/records \
  --data-urlencode "location=广州" \
  --data-urlencode "field=city" \
  --data-urlencode "limit=100"
```

停止资源：

```bash
./scripts/cluster.sh stop
```

## 5. 修改和验收规则

每个逻辑变更都要追加一个正常提交，不能把互不相关的改动合并到同一个提交。测试前先提交当前实现，避免测试结果对应不到提交。

最小验收集：

```bash
.venv/bin/pytest -q
bash -n scripts/*.sh
.venv/bin/python -m compileall -q src scripts
./scripts/cluster.sh status
curl --fail http://127.0.0.1:43123/api/health
git diff --check
git status --short --branch
```

对用户声称“已上传 GitHub”前，必须实际确认：

```bash
git remote -v
git ls-remote <github-remote-url> HEAD
```

远程 URL 不包含 `github.com` 时，只能说已推送到当前配置的远程，不能说已上传 GitHub。若用户提供 GitHub URL，新增独立 remote 或更新明确的 GitHub remote，然后只推送当前功能分支；不要把功能提交到 `main`。

## 6. Git 历史规则

- 保持当前分支和历史线性，正常 `git add`、`git commit`、`git push`。
- 不使用 `git reset --hard`、`git checkout --`、`git rebase`、`git commit --amend` 或强制推送。
- 不离开当前分支，除非用户明确要求。
- 不修改或强制推送 `origin/main`。
- 不创建或合并 Pull Request，除非用户明确要求。
- 推送使用 `git push -u origin <branch>`；网络失败时按 4s、8s、16s、32s 退避重试。

## 7. 证据和记忆图谱

重要证据位于：

- `artifacts/spark-env-config.png`
- `artifacts/pi-result.png`
- `artifacts/phone-query-ui.png`
- `artifacts/guangzhou-count.json`
- `artifacts/pi-result.json`
- `artifacts/verification.md`

每次改变架构、字段、端口、数据规则、验证结果或迁移方式时，同步更新：

- 项目图谱：`memory-graph.md`
- Linux 全局图谱：`/home/ubuntu/.cursor/memory-graphs/GRAPH.md`
- 项目全局条目：`/home/ubuntu/.cursor/memory-graphs/projects/spark-phone-query.md`

Windows 路径 `C:/Users/We3q/.cursor/memory-graphs/` 在当前 Linux 主机不可用；不要伪造该路径的更新。
