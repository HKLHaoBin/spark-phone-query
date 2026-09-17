# 运行证据

## Spark 集群状态
master=ALIVE url=spark://127.0.0.1:7077
worker=worker-20260917034553-172.30.0.2-7078 state=ALIVE cores=2 memory=1024
worker=worker-20260917034553-172.30.0.2-7079 state=ALIVE cores=2 memory=1024
workers_alive=2

## 广州统计
{
  "province": "广东",
  "city": "广州",
  "count": 400000,
  "records_scanned": 1000000,
  "input": "/workspace/data/generated/phone_attribution.csv",
  "master": "spark://127.0.0.1:7077",
  "completed_at_utc": "2026-09-17T03:47:06.478802+00:00"
}

## Pi 计算
{
  "application": "PhoneAttribution-Pi",
  "partitions": 4,
  "points_per_partition": 250000,
  "total_points": 1000000,
  "inside_points": 785050,
  "pi": 3.1402,
  "seed": 20260917,
  "master": "spark://127.0.0.1:7077",
  "completed_at_utc": "2026-09-17T03:47:20.659829+00:00"
}

截图：
- `artifacts/spark-env-config.png`
- `artifacts/pi-result.png`
