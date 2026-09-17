const countEl = document.querySelector("#guangzhou-count");
const recordsEl = document.querySelector("#records-loaded");
const masterEl = document.querySelector("#master-label");
const statusEl = document.querySelector("#cluster-status");
const statusTextEl = statusEl.querySelector("span:last-child");
const form = document.querySelector("#query-form");
const locationInput = document.querySelector("#location-input");
const fieldInput = document.querySelector("#field-input");
const body = document.querySelector("#results-body");
const resultTitle = document.querySelector("#results-title");
const resultCount = document.querySelector("#result-count");
const tableFooter = document.querySelector("#table-footer");
const formError = document.querySelector("#form-error");

const numberFormat = new Intl.NumberFormat("zh-CN");

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function setStatus(ready, message) {
  statusEl.classList.toggle("ready", ready);
  statusEl.classList.toggle("error", !ready);
  statusTextEl.textContent = message;
}

function showError(message) {
  formError.textContent = message;
  formError.classList.add("visible");
}

function clearError() {
  formError.textContent = "";
  formError.classList.remove("visible");
}

function renderRows(records) {
  if (!records.length) {
    body.innerHTML = `
      <tr class="empty-row">
        <td colspan="7">没有找到归属字段完全匹配的记录。</td>
      </tr>`;
    return;
  }

  body.innerHTML = records
    .map(
      (record) => `
        <tr>
          <td class="mono">${escapeHtml(record.record_id ?? "—")}</td>
          <td class="mono">${escapeHtml(record.phone_number ?? "—")}</td>
          <td>${escapeHtml(record.province ?? "—")}</td>
          <td>${escapeHtml(record.city ?? "—")}</td>
          <td>${escapeHtml(record.operator ?? "—")}</td>
          <td class="mono">${escapeHtml(record.area_code ?? "—")}</td>
          <td class="mono">${escapeHtml(record.postal_code ?? "—")}</td>
        </tr>`
    )
    .join("");
}

async function loadOverview() {
  const healthResponse = await fetch("/api/health");
  const health = await healthResponse.json();
  recordsEl.textContent = health.ready
    ? numberFormat.format(health.records_loaded)
    : "—";
  masterEl.textContent = health.ready
    ? `Master：${health.master}`
    : health.error || "数据源未就绪";
  setStatus(health.ready, health.ready ? "Spark 集群已连接" : "Spark 数据源不可用");

  if (!health.ready) {
    countEl.textContent = "—";
    showError(health.error || "Spark 数据源未就绪，请先生成数据并启动集群。");
    return false;
  }

  const statisticsResponse = await fetch("/api/statistics/guangzhou");
  if (!statisticsResponse.ok) {
    throw new Error("广州统计暂时不可用");
  }
  const statistics = await statisticsResponse.json();
  countEl.textContent = numberFormat.format(statistics.count);
  return true;
}

async function search(event) {
  event.preventDefault();
  clearError();
  const location = locationInput.value.trim();
  if (!location) {
    showError("请输入归属地。");
    locationInput.focus();
    return;
  }

  resultTitle.textContent = `“${location}”的匹配记录`;
  resultCount.textContent = "查询中…";
  tableFooter.textContent = "";
  body.innerHTML = `
    <tr class="empty-row">
      <td colspan="7">Spark 正在执行查询…</td>
    </tr>`;

  const params = new URLSearchParams({ location, limit: "100" });
  if (fieldInput.value) params.set("field", fieldInput.value);

  try {
    const response = await fetch(`/api/records?${params.toString()}`);
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.detail || "查询失败");
    renderRows(payload.records);
    resultCount.textContent = `共 ${numberFormat.format(payload.total)} 条`;
    tableFooter.textContent = payload.has_more
      ? `当前展示前 ${payload.returned} 条，可通过 API 的 offset/limit 参数继续读取全部结果。`
      : `已展示全部 ${payload.returned} 条结果。`;
  } catch (error) {
    resultCount.textContent = "查询失败";
    renderRows([]);
    showError(error.message);
  }
}

form.addEventListener("submit", search);

loadOverview()
  .then((ready) => {
    if (ready) form.requestSubmit();
  })
  .catch((error) => {
    setStatus(false, "服务连接失败");
    showError(error.message);
  });
