# SKILL.md：项目执行问题、解决方案与必备技能

本文档记录运行本项目时已经遇到的环境差异和解决办法。后续 Agent 应先查阅这里，再重复排障。这里的“技能”是本项目实际需要掌握的技术，不是泛化的教程。

## 1. 必须掌握的技能

### Spark standalone / PySpark

- 能配置 Master、Worker、RPC/UI 端口、Worker cores/memory 和本地目录。
- 能用 `spark-class org.apache.spark.deploy.master.Master` 和 `spark-class org.apache.spark.deploy.worker.Worker` 启动进程。
- 能用 `spark-submit --master spark://127.0.0.1:7077 --deploy-mode client` 提交 Python 作业。
- 能区分 Driver、Executor、Worker 和 Master；统计必须由 Spark DataFrame/RDD action 产生。
- 能读取 UTF-8 CSV、缓存 DataFrame、执行精确条件过滤和 count。

### Python Web 服务

- 能使用 FastAPI lifespan 创建和停止 SparkSession。
- 能让 `/api/health` 暴露真实数据源状态，不在 Spark 未就绪时伪造统计结果。
- 能处理分页参数、空结果、非法字段和大结果集，避免默认把几十万条记录全部收集到浏览器。
- 修改静态页面后，使用真实 API 验证页面状态，不只检查 HTML 是否能打开。

### Linux 运行和调试

- 能使用 `bash -n`、`ps`、`ss`、`curl`、日志文件和 `tmux` 管理长时间运行的 Spark 进程。
- 能定位 Java、Python、Spark submit、Executor 和 Worker 之间的进程关系。
- 能在无 `python3-venv` 软件包的机器上创建可用的 Python 虚拟环境。
- 能使用原生 Chrome headless 截取本地页面和配置证据。

### Git 迁移和线性历史

- 能在功能分支上追加提交并推送，不能用 rebase/amend/force push 改写历史。
- 推送前确认远程 URL 和权限；`origin.cursor.com` 不是 GitHub，不能混淆两者。
- 能通过 `git ls-remote` 证明目标远程真实存在且可访问。
- 能在换环境时用分支名、提交 SHA、README、AGENT 和本文件恢复工作上下文。

## 2. 已遇到的问题和解决方法

### 问题 A：`python3 -m venv` 报 `ensurepip is not available`

现象：

```text
The virtual environment was not created successfully because ensurepip is not available.
```

原因：主机没有安装 `python3.12-venv`，而且当前 apt 源没有该候选包。

解决：`scripts/install.sh` 先尝试标准 `venv`；失败后使用最新 `virtualenv` 创建 `.venv`，再安装项目依赖。以后不要手工删除这个回退逻辑。

### 问题 B：PySpark pip 包没有 `sbin/start-master.sh`

现象：

```text
env: .../pyspark/sbin/start-master.sh: No such file or directory
```

原因：PyPI 的 PySpark 发行包包含 Spark class/jars，但不一定包含传统 standalone shell wrapper。

解决：`scripts/cluster.sh` 直接调用：

```bash
$SPARK_HOME/bin/spark-class org.apache.spark.deploy.master.Master ...
$SPARK_HOME/bin/spark-class org.apache.spark.deploy.worker.Worker ...
```

脚本自行管理 PID 文件、日志、Worker work directory 和停止流程。不要把 `/opt/spark` 或手工下载的 Spark 目录写死。

### 问题 C：Spark Master `/json` 返回 301

现象：`curl http://127.0.0.1:18080/json` 获得重定向，后续 JSON 解析失败。

解决：Spark 4.2 使用带尾斜杠的地址 `http://127.0.0.1:18080/json/`。所有集群状态检查脚本必须使用该地址，或者明确使用 `curl -L`。

### 问题 D：shell 内嵌 Python 的引号错误

现象：`cluster.sh status` 出现 `SyntaxError` 或 `NameError`，但 Spark 本身正常。

原因：shell 外层单引号包住 Python 程序时，Python f-string 内又使用单引号，导致 shell 提前结束字符串。

解决：内嵌脚本使用 `.format()` 和双引号，或改成独立 Python 文件。修改 shell 内嵌代码后必须执行 `bash -n scripts/*.sh` 和实际 `./scripts/cluster.sh status`。

### 问题 E：Chrome wrapper 截图进程不退出

现象：`/usr/local/bin/google-chrome` 成功写入第一张图片，但截图脚本卡住，第二张图片没有生成。

原因：主机上的 wrapper 注入了桌面 Chrome 的远程调试参数和固定 profile。

解决：`scripts/capture_evidence.sh` 优先选择原生 `/opt/google/chrome/google-chrome`，使用独立的 `runtime/chrome-profile`。截图后应确认 PNG 非空。

### 问题 F：跨 Spark 版本没有 `DataFrame.offset`

现象：部分 Spark 版本不支持 `matching.offset(offset)`。

解决：当前查询实现使用 `matching.limit(offset + limit).collect()[offset:]`，保持兼容性并限制默认收集量。对大结果使用分页；只有用户明确传 `limit=0` 时才收集完整匹配集。

### 问题 G：主机名解析到 loopback 的警告

现象：

```text
Your hostname ... resolves to a loopback address
```

解决：当前单机伪分布式仍能使用容器网卡 `172.30.0.2` 注册 Worker，属于已验证的非致命警告。若迁移到多机环境，应在 `spark-env.sh` 明确设置可达的 `SPARK_LOCAL_IP`，并把 Master 地址改成其他节点可访问的地址。

## 3. 数据和接口不变量

- CSV 列顺序和名称必须保持：`record_id`、`phone_number`、`province`、`city`、`operator`、`area_code`、`postal_code`。
- 第 1 条记录必须保持题目给定的七个值。
- 默认生成规则使 1,000,000 行中的广州数量为 400,000；改变规则时必须同步测试、README、AGENT、记忆图谱和证据。
- 统计条件是 `province == 广东 AND city == 广州`，查询条件默认在五个归属字段中做精确匹配。
- API 默认分页返回 100 条；`limit=0` 表示完整匹配集，生产环境不要对大城市结果无条件使用它。
- 项目没有认证和授权，默认只绑定本机/内网用于实验，不能直接暴露到公网。

## 4. 换环境恢复清单

```bash
git clone <remote-url> <directory>
cd <directory>
git fetch --all --prune
git switch cursor/spark-phone-query-5bd1
git log --oneline --decorate --graph -12
./scripts/install.sh
./scripts/cluster.sh start
./scripts/cluster.sh status
ROWS=10000 ./scripts/run_pipeline.sh
PI_POINTS_PER_PARTITION=50000 ./scripts/run_pi.sh
.venv/bin/pytest -q
```

确认小规模运行成功后，再运行默认 1,000,000 行和完整截图。不要把 `.venv/`、`data/generated/` 或 `runtime/` 提交到 Git。

## 5. 交接验收清单

- [ ] `git status --short --branch` 无未提交代码。
- [ ] `git remote -v` 与用户要求的托管平台一致。
- [ ] `git log --graph` 显示历史线性追加，没有未经说明的 merge/rebase。
- [ ] `./scripts/cluster.sh status` 显示 2 个存活 Worker。
- [ ] `artifacts/guangzhou-count.json`、`artifacts/pi-result.json` 与截图内容一致。
- [ ] API 健康、统计、匹配、空结果和错误输入均有验证。
- [ ] 项目 `memory-graph.md` 和全局项目条目已同步。
