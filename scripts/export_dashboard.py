"""Export the dbt marts to small JSON files for the static dashboard.

Run after `dbt build`. Reads warehouse.duckdb (read-only) and writes
dashboard/data/*.json. Only pre-aggregated data leaves the warehouse:
no invoice lines and no customer ids are exported.
"""

from __future__ import annotations

import json
import math
import os
import sys
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = Path(os.environ.get("DUCKDB_PATH", ROOT / "warehouse.duckdb"))
OUT_DIR = ROOT / "dashboard" / "data"


def _clean(value):
    if isinstance(value, (date, datetime)):
        return value.isoformat()[:10]
    if isinstance(value, Decimal):
        value = float(value)
    if isinstance(value, float):
        if math.isnan(value) or math.isinf(value):
            return None
        return round(value, 6)
    return value


def rows(con: duckdb.DuckDBPyConnection, sql: str) -> list[dict]:
    rel = con.sql(sql)
    cols = rel.columns
    return [{c: _clean(v) for c, v in zip(cols, r)} for r in rel.fetchall()]


QUERIES: dict[str, str] = {
    "monthly_kpis": "select * from marts.mart_monthly_kpis order by month",
    "weekly_forecast": """
        select split, week_start, horizon_weeks, actual_net_revenue_gbp,
               naive_last_week, moving_avg_4w, seasonal_naive, seasonal_naive_growth
        from marts.mart_forecast_weekly order by week_start, split
    """,
    "forecast_accuracy": "select * from marts.mart_forecast_accuracy order by accuracy_rank",
    "countries": """
        select country_name, region, gross_sales_gbp, returns_gbp, net_revenue_gbp,
               return_rate, share_of_net_revenue, orders, customers, avg_order_value_gbp,
               net_revenue_fy1_gbp, net_revenue_fy2_gbp, yoy_growth
        from marts.mart_country_performance order by net_revenue_gbp desc
    """,
    "products_top": """
        select stock_code, description, gross_sales_gbp, returns_gbp, net_revenue_gbp,
               return_rate, units_sold, orders, customers, countries, revenue_rank, abc_class
        from marts.mart_product_performance where revenue_rank <= 25 order by revenue_rank
    """,
    "products_high_returns": """
        select stock_code, description, gross_sales_gbp, returns_gbp, net_revenue_gbp, return_rate
        from marts.mart_product_performance
        where gross_sales_gbp >= 20000
        order by return_rate desc limit 10
    """,
    "products_abc": """
        select abc_class, count(*) as products, sum(net_revenue_gbp) as net_revenue_gbp
        from marts.mart_product_performance group by abc_class order by abc_class
    """,
    "products_pareto": """
        select revenue_rank, cumulative_revenue_share
        from marts.mart_product_performance
        where revenue_rank % 10 = 1 or revenue_rank = (select max(revenue_rank) from marts.mart_product_performance)
        order by revenue_rank
    """,
    "rfm_segments": "select * from marts.mart_rfm_segments order by net_revenue_gbp desc",
    "rfm_grid": """
        select r_score, fm_score, count(*) as customers, sum(monetary_gbp) as net_revenue_gbp,
               any_value(rfm_segment) as rfm_segment
        from marts.mart_customer_rfm group by r_score, fm_score order by r_score, fm_score
    """,
    "loyalty_distribution": """
        select cast(floor(loyalty_score / 10) * 10 as integer) as bucket, count(*) as customers
        from marts.mart_customer_rfm group by bucket order by bucket
    """,
    "cohort_retention": """
        select cohort_month, months_since_first_order, cohort_size, active_customers,
               retention_rate, is_left_censored_cohort
        from marts.mart_cohort_retention order by cohort_month, months_since_first_order
    """,
    "data_quality": "select * from marts.mart_data_quality order by step",
}


def main() -> int:
    if not DB_PATH.exists():
        print(f"[export] {DB_PATH} not found - run `dbt build` first", file=sys.stderr)
        return 1
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB_PATH), read_only=True)

    for name, sql in QUERIES.items():
        data = rows(con, sql)
        (OUT_DIR / f"{name}.json").write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
        print(f"[export] {name}.json  ({len(data)} rows)")

    bounds = rows(con, "select * from intermediate.int_calendar_bounds")[0]
    totals = rows(
        con,
        """
        select sum(gross_sales_gbp) as gross_sales_gbp, sum(returns_gbp) as returns_gbp,
               sum(net_amount_gbp) as net_revenue_gbp,
               count(distinct case when line_type = 'sale' then invoice_id end) as orders,
               count(distinct customer_id) as customers,
               count(distinct stock_code) as products,
               count(distinct country) as countries
        from intermediate.int_merchandise_lines
        """,
    )[0]
    meta = {
        "dataset": "UCI Online Retail II (Chen, 2012), CC BY 4.0, doi:10.24432/C5CG6D",
        "currency": "GBP",
        "coverage": bounds,
        "totals": totals,
        "forecast": {
            "holdout_weeks": con.sql("select count(*) from marts.mart_forecast_weekly where split = 'holdout'").fetchall()[0][0],
            "horizon_weeks": con.sql("select count(*) from marts.mart_forecast_weekly where split = 'future'").fetchall()[0][0],
        },
    }
    (OUT_DIR / "meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print("[export] meta.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
