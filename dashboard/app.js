/* global Plot, d3 */
// Tabi Labs · Revenue Analytics dashboard.
// Reads pre-aggregated JSON exported from the dbt marts (scripts/export_dashboard.py).
// Every sentence with a number is computed from that data at render time.

const C = {
  ink: "#15171f",
  muted: "#555b68",
  faint: "#8a8f99",
  line: "#e4e2dc",
  surface2: "#f3f2ee",
  brand: "#26235f",
  accent: "#5b47c9",
  accentSoft: "#eeebfa",
  s1: "#5b47c9",
  s2: "#eb6834",
};

const gbp = (v) => (v == null ? "–" : (v < 0 ? "−£" : "£") + d3.format(",.0f")(Math.abs(v)));
const gbpShort = (v) => {
  if (v == null) return "–";
  const a = Math.abs(v);
  if (a >= 1e6) return "£" + d3.format(".2~f")(v / 1e6) + "M";
  if (a >= 1e3) return "£" + d3.format(".0f")(v / 1e3) + "k";
  return "£" + d3.format(".0f")(v);
};
const pct = (v, digits = 1) => (v == null ? "–" : d3.format(`.${digits}%`)(v));
const signedPct = (v) => (v == null ? "–" : (v > 0 ? "+" : "") + d3.format(".1%")(v));
const int = (v) => (v == null ? "–" : d3.format(",")(v));
const monthFmt = d3.utcFormat("%b %Y");
const dayFmt = d3.utcFormat("%d %b %Y");
const parse = (s) => new Date(s + "T00:00:00Z");

const METHOD_LABELS = {
  seasonal_naive_growth: "Seasonal naive × YoY growth",
  seasonal_naive: "Seasonal naive (same week last year)",
  naive_last_week: "Naive (last week, flat)",
  moving_avg_4w: "4-week moving average",
};

async function load(name) {
  const res = await fetch(`data/${name}.json`);
  if (!res.ok) throw new Error(`Failed to load ${name}.json`);
  return res.json();
}

function el(id) { return document.getElementById(id); }

function mount(id, node) {
  const host = el(id);
  host.replaceChildren(node);
}

function width(id) {
  return Math.max(300, Math.floor(el(id).getBoundingClientRect().width));
}

const baseStyle = { fontFamily: "Inter, system-ui, sans-serif", fontSize: "12px", color: C.muted, overflow: "visible" };

function table(id, columns, rows, rowClass) {
  const t = el(id);
  const head = `<thead><tr>${columns.map((c) => `<th class="${c.num ? "num" : ""}">${c.label}</th>`).join("")}</tr></thead>`;
  const body = rows
    .map((r) => `<tr class="${rowClass ? rowClass(r) : ""}">${columns
      .map((c) => `<td class="${c.num ? "num" : ""} ${c.wrap ? "wrap-cell" : ""}">${c.fmt ? c.fmt(r[c.key], r) : escapeHtml(r[c.key])}</td>`)
      .join("")}</tr>`)
    .join("");
  t.innerHTML = head + `<tbody>${body}</tbody>`;
}

function escapeHtml(v) {
  return String(v ?? "").replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
}

function titleCase(s) {
  return s.toLowerCase().replace(/\b([a-z])/g, (m) => m.toUpperCase());
}

/* ---------------------------------------------------------------- KPIs */
function renderKpis(meta, monthly) {
  const t = meta.totals;
  const fy = (start, end) => monthly.filter((m) => m.month >= start && m.month <= end).reduce((s, m) => s + m.net_revenue_gbp, 0);
  const fy1 = fy("2009-12-01", "2010-11-01");
  const fy2 = fy("2010-12-01", "2011-11-01");
  const tiles = [
    { label: "Net revenue", value: gbpShort(t.net_revenue_gbp), note: `${dayFmt(parse(meta.coverage.first_date))} – ${dayFmt(parse(meta.coverage.last_date))}` },
    { label: "Year-over-year", value: signedPct(fy2 / fy1 - 1), note: "Dec–Nov FY2 vs FY1" },
    { label: "Orders", value: int(t.orders), note: `avg ${gbp(t.gross_sales_gbp / t.orders)} per order` },
    { label: "Identified customers", value: int(t.customers), note: `${t.countries} countries` },
    { label: "Cancelled value", value: pct(t.returns_gbp / t.gross_sales_gbp), note: `${gbpShort(t.returns_gbp)} of gross sales` },
  ];
  el("kpis").innerHTML = tiles
    .map((k) => `<div class="kpi"><div class="label">${k.label}</div><div class="value">${k.value}</div><div class="note">${k.note}</div></div>`)
    .join("");
}

/* ------------------------------------------------------- monthly trend */
function renderMonthly(monthly) {
  const data = monthly.map((d) => ({ ...d, date: parse(d.month) }));
  const chart = Plot.plot({
    width: width("chart-monthly"),
    height: 280,
    marginLeft: 56,
    style: baseStyle,
    x: { type: "utc", label: null, ticks: "3 months", tickFormat: d3.utcFormat("%b %y") },
    y: { label: null, grid: true, tickFormat: gbpShort, nice: true },
    marks: [
      Plot.rectY(data, {
        x: "date", y: "net_revenue_gbp", interval: "month", insetLeft: 1.5, insetRight: 1.5,
        fill: C.accent, rx: 2,
      }),
      Plot.ruleY([0], { stroke: C.line }),
      Plot.tip(data, Plot.pointerX({
        x: (d) => new Date(d.date.getTime() + 15 * 864e5), y: "net_revenue_gbp",
        title: (d) => [
          monthFmt(d.date),
          `Net revenue  ${gbp(d.net_revenue_gbp)}`,
          `Orders  ${int(d.orders)}`,
          `Avg order  ${gbp(d.avg_order_value_gbp)}`,
          `Active customers  ${int(d.active_customers)} (${int(d.new_customers)} new)`,
          `Cancelled  ${pct(d.return_rate)}`,
        ].join("\n"),
      })),
    ],
  });
  mount("chart-monthly", chart);

  const fy2 = monthly.filter((m) => m.month >= "2010-12-01");
  const total = d3.sum(fy2, (m) => m.net_revenue_gbp);
  const q4 = d3.sum(fy2.filter((m) => m.month >= "2011-09-01"), (m) => m.net_revenue_gbp);
  const peak = d3.greatest(fy2, (m) => m.net_revenue_gbp);
  const low = d3.least(fy2, (m) => m.net_revenue_gbp);
  el("takeaway-monthly").textContent =
    `Strongly seasonal: in Dec 2010–Nov 2011, September to November alone brought ${pct(q4 / total, 0)} of the year's net revenue. ` +
    `The peak month (${monthFmt(parse(peak.month))}, ${gbpShort(peak.net_revenue_gbp)}) was ${d3.format(".1f")(peak.net_revenue_gbp / low.net_revenue_gbp)}× the weakest (${monthFmt(parse(low.month))}).`;
}

/* ------------------------------------------------------------ forecast */
function renderForecast(weekly, accuracy, meta) {
  document.querySelectorAll('[data-meta="holdout"]').forEach((n) => (n.textContent = meta.forecast.holdout_weeks));
  document.querySelectorAll('[data-meta="horizon"]').forEach((n) => (n.textContent = meta.forecast.horizon_weeks));

  const select = el("method-select");
  select.innerHTML = accuracy
    .map((a) => `<option value="${a.method}">${METHOD_LABELS[a.method]}${a.accuracy_rank === 1 ? " (lowest error)" : ""}</option>`)
    .join("");

  const rows = weekly.map((d) => ({ ...d, date: parse(d.week_start) }));
  const holdout = rows.filter((d) => d.split === "holdout");
  const future = rows.filter((d) => d.split === "future");
  const actual = rows.filter((d) => d.split !== "future");
  const hStart = holdout[0].date;
  const hEnd = new Date(holdout[holdout.length - 1].date.getTime() + 7 * 864e5);
  const fStart = future[0].date;
  const fEnd = new Date(future[future.length - 1].date.getTime() + 7 * 864e5);

  function draw() {
    const m = select.value;
    const fc = [...holdout, ...future].map((d) => ({ date: d.date, value: d[m], split: d.split, actual: d.actual_net_revenue_gbp }));
    const pointerRows = [...actual.filter((d) => d.split === "train"), ...holdout, ...future].map((d) => ({
      date: d.date, actual: d.actual_net_revenue_gbp, forecast: d.split === "train" ? null : d[m], split: d.split,
    }));
    const chart = Plot.plot({
      width: width("chart-forecast"),
      height: 320,
      marginLeft: 56,
      style: baseStyle,
      x: { type: "utc", label: null, tickFormat: d3.utcFormat("%b %y") },
      y: { label: null, grid: true, tickFormat: gbpShort, nice: true },
      marks: [
        Plot.rectX([{ x1: hStart, x2: hEnd }], { x1: "x1", x2: "x2", fill: C.surface2 }),
        Plot.rectX([{ x1: fStart, x2: fEnd }], { x1: "x1", x2: "x2", fill: C.accentSoft, fillOpacity: 0.6 }),
        Plot.text([{ x: hStart, t: "Holdout" }, { x: fStart, t: "Forecast" }], {
          x: "x", text: "t", frameAnchor: "top", textAnchor: "start", dx: 4, dy: 4, fill: C.muted, fontSize: 11,
        }),
        Plot.ruleY([0], { stroke: C.line }),
        Plot.line(actual, { x: "date", y: "actual_net_revenue_gbp", stroke: C.ink, strokeWidth: 1.5 }),
        Plot.line(fc, { x: "date", y: "value", stroke: C.accent, strokeWidth: 2, strokeDasharray: "5,3" }),
        Plot.ruleX(pointerRows, Plot.pointerX({ x: "date", stroke: C.faint, strokeWidth: 1 })),
        Plot.tip(pointerRows, Plot.pointerX({
          x: "date", y: (d) => d.actual ?? d.forecast,
          title: (d) => [
            `Week of ${dayFmt(d.date)}`,
            d.actual != null ? `Actual  ${gbp(d.actual)}` : null,
            d.forecast != null ? `Forecast  ${gbp(d.forecast)}` : null,
            d.split === "holdout" && d.forecast != null ? `Error  ${signedPct(d.forecast / d.actual - 1)}` : null,
          ].filter(Boolean).join("\n"),
        })),
      ],
    });
    mount("chart-forecast", chart);
  }
  select.addEventListener("change", draw);
  draw();
  window.addEventListener("resize", debounce(draw, 200));

  el("legend-forecast").innerHTML = `
    <span class="key"><span class="line" style="border-color:${C.ink}"></span>Actual net revenue</span>
    <span class="key"><span class="line dashed" style="border-color:${C.accent}"></span>Forecast (selected method)</span>
    <span class="key"><span class="band"></span>Holdout: forecast made without seeing these weeks</span>`;

  table("table-accuracy", [
    { key: "method", label: "Method", fmt: (v, r) => `${METHOD_LABELS[v]} ${r.accuracy_rank === 1 ? '<span class="pill best">lowest error</span>' : ""}` },
    { key: "wape", label: "WAPE", num: true, fmt: (v) => pct(v) },
    { key: "mae_gbp", label: "MAE / week", num: true, fmt: gbp },
    { key: "bias", label: "Bias", num: true, fmt: signedPct },
    { key: "forecast_total_gbp", label: "Forecast total", num: true, fmt: gbp },
    { key: "actual_total_gbp", label: "Actual total", num: true, fmt: gbp },
  ], accuracy, (r) => (r.accuracy_rank === 1 ? "best" : ""));

  const best = accuracy[0];
  const naive = accuracy.find((a) => a.method === "naive_last_week");
  const sn = accuracy.find((a) => a.method === "seasonal_naive");
  el("takeaway-forecast").textContent =
    `Seasonality is the signal. Using the same week of the previous year cuts the holdout error from ${pct(naive.wape)} (naive) to ${pct(sn.wape)} WAPE; ` +
    `adjusting it for recent year-over-year growth gives ${pct(best.wape)}, a marginal gain that also turns a ${signedPct(sn.bias)} bias into ${signedPct(best.bias)}. ` +
    `These are deliberately simple baselines: any more complex model would have to beat ${pct(best.wape)} to justify itself.`;
}

/* ------------------------------------------------------------------ RFM */
function renderRfm(segments, grid) {
  const order = segments.map((s) => s.rfm_segment);
  const long = segments.flatMap((s) => [
    { segment: s.rfm_segment, metric: "Customers", value: s.share_of_customers, s },
    { segment: s.rfm_segment, metric: "Net revenue", value: s.share_of_net_revenue, s },
  ]);
  const chart = Plot.plot({
    width: width("chart-rfm"),
    height: 40 + order.length * 34,
    marginLeft: 130,
    marginRight: 44,
    style: baseStyle,
    x: { label: null, tickFormat: (v) => pct(v, 0), grid: true, domain: [0, Math.max(0.8, d3.max(long, (d) => d.value))] },
    y: { label: null, axis: null, domain: ["Customers", "Net revenue"] },
    fy: { label: null, domain: order, padding: 0.18 },
    color: { domain: ["Customers", "Net revenue"], range: [C.s2, C.s1] },
    marks: [
      Plot.barX(long, { x: "value", y: "metric", fy: "segment", fill: "metric", rx: 2, insetTop: 1, insetBottom: 1 }),
      Plot.text(long, { x: "value", y: "metric", fy: "segment", text: (d) => pct(d.value, 0), textAnchor: "start", dx: 4, fill: C.muted, fontSize: 11 }),
      Plot.axisFy({ anchor: "left", label: null, tickSize: 0, fill: C.ink, fontSize: 12 }),
      Plot.tip(long, Plot.pointerY({
        x: "value", y: "metric", fy: "segment",
        title: (d) => [
          d.segment,
          `${int(d.s.customers)} customers (${pct(d.s.share_of_customers)})`,
          `${gbp(d.s.net_revenue_gbp)} net revenue (${pct(d.s.share_of_net_revenue)})`,
          `Avg last order  ${d3.format(".0f")(d.s.avg_recency_days)} days ago`,
          `Avg orders  ${d3.format(".1f")(d.s.avg_frequency)}`,
        ].join("\n"),
      })),
    ],
  });
  mount("chart-rfm", chart);
  el("legend-rfm").innerHTML = `
    <span class="key"><span class="swatch" style="background:${C.s2}"></span>Share of customers</span>
    <span class="key"><span class="swatch" style="background:${C.s1}"></span>Share of net revenue</span>`;

  const maxC = d3.max(grid, (d) => d.customers);
  const gridChart = Plot.plot({
    width: Math.min(width("chart-rfm-grid"), 460),
    height: 340,
    marginLeft: 70,
    marginBottom: 44,
    style: baseStyle,
    x: { label: "Frequency / Monetary score →", domain: [1, 2, 3, 4, 5], labelAnchor: "center", labelOffset: 36 },
    y: { label: "Recency score ↑", domain: [1, 2, 3, 4, 5], reverse: true, labelAnchor: "center" },
    color: { type: "linear", domain: [0, maxC], range: [C.accentSoft, C.brand] },
    marks: [
      Plot.cell(grid, { x: "fm_score", y: "r_score", fill: "customers", inset: 1, rx: 3 }),
      Plot.text(grid, { x: "fm_score", y: "r_score", text: (d) => int(d.customers), fill: (d) => (d.customers > maxC * 0.5 ? "#fff" : C.ink), fontSize: 12 }),
      Plot.tip(grid, Plot.pointer({
        x: "fm_score", y: "r_score",
        title: (d) => [`R ${d.r_score} · FM ${d.fm_score}`, d.rfm_segment, `${int(d.customers)} customers`, `${gbp(d.net_revenue_gbp)} net revenue`].join("\n"),
      })),
    ],
  });
  mount("chart-rfm-grid", gridChart);

  const champ = segments.find((s) => s.rfm_segment === "Champions");
  const atRisk = segments.filter((s) => s.rfm_segment === "At risk" || s.rfm_segment === "Cannot lose them");
  el("takeaway-rfm").textContent =
    `Champions are ${pct(champ.share_of_customers, 0)} of identified customers but ${pct(champ.share_of_net_revenue, 0)} of their net revenue. ` +
    `${int(d3.sum(atRisk, (s) => s.customers))} customers in "At risk" and "Cannot lose them" bought often in the past but not for about a year; ` +
    `they account for ${gbpShort(d3.sum(atRisk, (s) => s.net_revenue_gbp))} of historical revenue: the obvious first list for a win-back campaign.`;
}

/* --------------------------------------------------------------- cohort */
function renderCohort(cohort) {
  const data = cohort
    .filter((d) => !d.is_left_censored_cohort && d.months_since_first_order > 0)
    .map((d) => ({ ...d, label: monthFmt(parse(d.cohort_month)) }));
  const cohorts = [...new Set(data.map((d) => d.label))];
  const maxM = d3.max(data, (d) => d.months_since_first_order);
  const w = Math.max(width("chart-cohort"), 760);
  const chart = Plot.plot({
    width: w,
    height: 40 + cohorts.length * 22,
    marginLeft: 80,
    marginTop: 34,
    style: baseStyle,
    x: { label: "Months since first order", domain: d3.range(1, maxM + 1), axis: "top", labelAnchor: "left", tickSize: 0 },
    y: { label: null, domain: cohorts, tickSize: 0 },
    color: { type: "linear", domain: [0, d3.max(data, (d) => d.retention_rate)], range: [C.accentSoft, C.brand] },
    marks: [
      Plot.cell(data, { x: "months_since_first_order", y: "label", fill: "retention_rate", inset: 0.75, rx: 2 }),
      Plot.text(data, {
        x: "months_since_first_order", y: "label", text: (d) => d3.format(".0f")(d.retention_rate * 100),
        fill: (d) => (d.retention_rate > 0.2 ? "#fff" : C.ink), fontSize: 9,
      }),
      Plot.tip(data, Plot.pointer({
        x: "months_since_first_order", y: "label",
        title: (d) => [`${d.label} cohort (${int(d.cohort_size)} customers)`, `Month ${d.months_since_first_order}: ${int(d.active_customers)} ordered`, `Retention ${pct(d.retention_rate)}`].join("\n"),
      })),
    ],
  });
  mount("chart-cohort", chart);

  const weighted = (m) => {
    const rows = data.filter((d) => d.months_since_first_order === m);
    return { rate: d3.sum(rows, (d) => d.active_customers) / d3.sum(rows, (d) => d.cohort_size), n: rows.length };
  };
  const m1 = weighted(1), m3 = weighted(3), m12 = weighted(12);
  const censored = cohort.filter((d) => d.is_left_censored_cohort && d.months_since_first_order === 12)[0];
  el("takeaway-cohort").textContent =
    `About ${pct(m1.rate, 0)} of new customers order again the following month (weighted across ${m1.n} cohorts), ${pct(m3.rate, 0)} in month 3 and ${pct(m12.rate, 0)} in month 12. ` +
    `Retention is flat rather than decaying after the first month: whoever comes back keeps coming back, so the leverage is in the first repeat order. ` +
    (censored ? `(Excluded Dec 2009 cohort: ${pct(censored.retention_rate, 0)} at month 12, inflated by pre-existing customers.)` : "");
}

/* -------------------------------------------------------------- markets */
function renderMarkets(countries) {
  const select = el("region-select");
  const regions = ["Outside the UK", "All markets", ...[...new Set(countries.map((c) => c.region))].sort()];
  select.innerHTML = regions.map((r) => `<option>${r}</option>`).join("");

  function draw() {
    const r = select.value;
    const rows = countries.filter((c) =>
      r === "All markets" ? true : r === "Outside the UK" ? c.region !== "United Kingdom" : c.region === r);
    const top = rows.slice(0, 12);
    const chart = Plot.plot({
      width: width("chart-countries"),
      height: 40 + top.length * 26,
      marginLeft: 150,
      marginRight: 60,
      style: baseStyle,
      x: { label: null, grid: true, tickFormat: gbpShort, nice: true },
      y: { label: null, domain: top.map((d) => d.country_name), tickSize: 0 },
      marks: [
        Plot.barX(top, { x: "net_revenue_gbp", y: "country_name", fill: C.accent, rx: 2, insetTop: 3, insetBottom: 3 }),
        Plot.text(top, { x: "net_revenue_gbp", y: "country_name", text: (d) => gbpShort(d.net_revenue_gbp), textAnchor: "start", dx: 4, fill: C.muted, fontSize: 11 }),
        Plot.ruleX([0], { stroke: C.line }),
        Plot.tip(top, Plot.pointerY({
          x: "net_revenue_gbp", y: "country_name",
          title: (d) => [d.country_name, `Net revenue  ${gbp(d.net_revenue_gbp)} (${pct(d.share_of_net_revenue)} of total)`, `Customers  ${int(d.customers)}`, `Orders  ${int(d.orders)}`, `YoY  ${signedPct(d.yoy_growth)}`, `Cancelled  ${pct(d.return_rate)}`].join("\n"),
        })),
      ],
    });
    mount("chart-countries", chart);
    table("table-countries", [
      { key: "country_name", label: "Country" },
      { key: "region", label: "Region" },
      { key: "net_revenue_gbp", label: "Net revenue", num: true, fmt: gbp },
      { key: "share_of_net_revenue", label: "Share", num: true, fmt: (v) => pct(v) },
      { key: "customers", label: "Customers", num: true, fmt: int },
      { key: "avg_order_value_gbp", label: "Avg order", num: true, fmt: gbp },
      { key: "return_rate", label: "Cancelled", num: true, fmt: (v) => pct(v) },
      { key: "yoy_growth", label: "YoY (FY2/FY1)", num: true, fmt: signedPct },
    ], rows.slice(0, 15));
  }
  select.addEventListener("change", draw);
  draw();
  window.addEventListener("resize", debounce(draw, 200));

  const uk = countries.find((c) => c.region === "United Kingdom");
  const eu = d3.sum(countries.filter((c) => c.region === "European Union"), (c) => c.net_revenue_gbp);
  const total = d3.sum(countries, (c) => c.net_revenue_gbp);
  const nonUk = countries.filter((c) => c.region !== "United Kingdom");
  const lead = nonUk[0];
  const fewCustomers = nonUk.filter((c) => c.customers <= 5 && c.share_of_net_revenue >= 0.01);
  el("takeaway-markets").textContent =
    `The UK is ${pct(uk.share_of_net_revenue, 0)} of net revenue and was flat year over year (${signedPct(uk.yoy_growth)}); EU markets add ${pct(eu / total, 0)}. ` +
    `Export revenue is concentrated: the largest non-UK market, ${lead.country_name} (${gbpShort(lead.net_revenue_gbp)}), comes from just ${int(lead.customers)} identified customers` +
    (fewCustomers.length > 1 ? `, so losing one account would move the export line materially.` : `.`);
}

/* ------------------------------------------------------------- products */
function renderProducts(top, pareto, abc, highReturns) {
  const n = d3.max(pareto, (d) => d.revenue_rank);
  const chart = Plot.plot({
    width: width("chart-pareto"),
    height: 300,
    marginLeft: 44,
    marginBottom: 44,
    style: baseStyle,
    x: { label: "Products, ranked by net revenue →", labelAnchor: "center", labelOffset: 36, domain: [0, n], tickFormat: int },
    y: { label: null, domain: [0, 1.05], tickFormat: (v) => pct(v, 0), grid: true },
    marks: [
      Plot.ruleY([0.8], { stroke: C.faint, strokeDasharray: "3,3" }),
      Plot.line(pareto, { x: "revenue_rank", y: "cumulative_revenue_share", stroke: C.accent, strokeWidth: 2 }),
      Plot.tip(pareto, Plot.pointerX({ x: "revenue_rank", y: "cumulative_revenue_share", title: (d) => `Top ${int(d.revenue_rank)} products\n${pct(d.cumulative_revenue_share)} of net revenue` })),
    ],
  });
  mount("chart-pareto", chart);

  const t15 = top.slice(0, 15).map((d) => ({ ...d, label: truncate(titleCase(d.description), 30) }));
  const bars = Plot.plot({
    width: width("chart-top-products"),
    height: 40 + t15.length * 22,
    marginLeft: 200,
    marginRight: 50,
    style: baseStyle,
    x: { label: null, grid: true, tickFormat: gbpShort, nice: true },
    y: { label: null, domain: t15.map((d) => d.label), tickSize: 0 },
    marks: [
      Plot.barX(t15, { x: "net_revenue_gbp", y: "label", fill: C.accent, rx: 2, insetTop: 2, insetBottom: 2 }),
      Plot.text(t15, { x: "net_revenue_gbp", y: "label", text: (d) => gbpShort(d.net_revenue_gbp), textAnchor: "start", dx: 4, fill: C.muted, fontSize: 11 }),
      Plot.tip(t15, Plot.pointerY({
        x: "net_revenue_gbp", y: "label",
        title: (d) => [titleCase(d.description), `Stock code ${d.stock_code}`, `Net revenue  ${gbp(d.net_revenue_gbp)}`, `Units sold  ${int(d.units_sold)}`, `Customers  ${int(d.customers)}`, `Cancelled  ${pct(d.return_rate)}`].join("\n"),
      })),
    ],
  });
  mount("chart-top-products", bars);

  table("table-returns", [
    { key: "description", label: "Product", wrap: true, fmt: (v) => escapeHtml(titleCase(v)) },
    { key: "stock_code", label: "Code" },
    { key: "gross_sales_gbp", label: "Gross sales", num: true, fmt: gbp },
    { key: "returns_gbp", label: "Cancelled", num: true, fmt: gbp },
    { key: "return_rate", label: "Rate", num: true, fmt: (v) => pct(v) },
  ], highReturns);

  const a = abc.find((d) => d.abc_class === "A");
  const totalProducts = d3.sum(abc, (d) => d.products);
  const big = highReturns.filter((d) => d.return_rate > 0.9);
  el("takeaway-products").textContent =
    `${int(a.products)} of ${int(totalProducts)} products (${pct(a.products / totalProducts, 0)}) generate 80% of net revenue. ` +
    (big.length
      ? `The highest cancellation rates are not product-quality signals: ${big.map((d) => titleCase(d.description)).join(" and ")} each owe their rate to a single bulk order that was cancelled, which is why gross sales and return rates should always be read alongside net revenue.`
      : "");
}

/* --------------------------------------------------------- data quality */
function renderQuality(rows) {
  table("table-quality", [
    { key: "label", label: "Step", wrap: true },
    { key: "line_count", label: "Lines", num: true, fmt: int },
    { key: "amount_gbp", label: "Value", num: true, fmt: (v) => (v == null ? "" : gbp(v)) },
  ], rows);
}

function truncate(s, n) { return s.length > n ? s.slice(0, n - 1) + "…" : s; }
function debounce(fn, ms) { let t; return () => { clearTimeout(t); t = setTimeout(fn, ms); }; }

async function main() {
  const names = ["meta", "monthly_kpis", "weekly_forecast", "forecast_accuracy", "rfm_segments", "rfm_grid",
    "cohort_retention", "countries", "products_top", "products_pareto", "products_abc", "products_high_returns", "data_quality"];
  const d = Object.fromEntries(await Promise.all(names.map(async (n) => [n, await load(n)])));
  renderKpis(d.meta, d.monthly_kpis);
  const redrawStatic = () => {
    renderMonthly(d.monthly_kpis);
    renderRfm(d.rfm_segments, d.rfm_grid);
    renderCohort(d.cohort_retention);
    renderProducts(d.products_top, d.products_pareto, d.products_abc, d.products_high_returns);
  };
  redrawStatic();
  renderForecast(d.weekly_forecast, d.forecast_accuracy, d.meta);
  renderMarkets(d.countries);
  renderQuality(d.data_quality);
  window.addEventListener("resize", debounce(redrawStatic, 200));
}

main().catch((err) => {
  console.error(err);
  document.querySelector("main").insertAdjacentHTML("afterbegin", `<p class="loading">Could not load the data files. Serve this folder over HTTP (see README).</p>`);
});
