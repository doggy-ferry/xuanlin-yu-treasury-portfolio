# Power BI model specification

A star schema over the SQL database `TreasurySqlPortfolio`. The business logic lives in SQL (views, rules, tests); Power BI loads the result and adds only measures.

**Status:** built in Power BI Desktop's model engine by `build_model_in_open_report.ps1` and checked by `verify_model_in_open_report.ps1`: 10 tables loaded with the same row counts as SQL, 11 relationships, 15 measures, 28 of 28 checks pass (`model_check_results.csv`). This was done on a throw-away report that was closed without saving. The same script was later run on the report the owner then built the three pages in (28 of 28 again). No `.pbip` exists.

## Tables (storage mode: Import)

| Power BI table | Source object | Grain (one row per ...) | Rows | Role |
|---|---|---|---:|---|
| `dim_date` | `dbo.dim_date` | calendar day, 2025-11-01 to 2026-12-31 | 426 | date table, marked on `full_date` |
| `dim_entity` | `dbo.dim_entity` | legal entity | 4 | dimension |
| `dim_currency` | `dbo.dim_currency` | currency | 5 | dimension |
| `dim_cashflow_category` | `dbo.dim_cashflow_category` | cash-flow category | 7 | dimension |
| `dim_vendor` | `dbo.dim_vendor` | vendor site key | 50 | dimension |
| `dim_exception_type` | `dbo.dim_exception_type` | exception rule | 20 | dimension |
| `fact_cashflow` | `dbo.fact_cashflow` | one Actual or Forecast cash-flow line | 1,323 | fact |
| `fact_cash_position` | `dbo.vw_cash_position_daily` | entity x day (Actual, JPY) | 1,456 | fact |
| `fact_payment_control` | `dbo.vw_fx_payment_control` | payment instruction, with its control result | 150 | fact |
| `_Measures` | (empty table) | - | 0 | holds the 15 measures |

Two Power BI tables are loaded from views: `fact_cash_position` (running balance computed in SQL with a window function) and `fact_payment_control` (payment amounts and control flags joined in SQL). Loading them as one row per payment keeps the star simple: there is **no join between fact tables**.

Not loaded on purpose: `vw_cash_forecast_variance` (variance is a DAX measure over `fact_cashflow`, so it can be sliced any way; the SQL view is the tested reference for the same numbers), `vw_payment_exception_summary` (a Power BI visual does the same grouping), `fact_payment_exception` (a bridge table; see "Check-result summary" in the build guide).

## Columns

All columns of each source object are loaded; types come from the database (`INFORMATION_SCHEMA`): whole numbers -> Whole number, `decimal` -> Decimal, `date` -> Date, text -> Text. Recommended after the build:

- Hide the key columns (`*_key`, `transaction_id`) and the helper columns; keep names that a business user would pick.
- Set **Summarize by = None** on every column (the build script does this); numbers are summed only through measures.
- Sort `dim_date[month_name]` by `dim_date[month_num]` if the month name is shown instead of `year_month`.
- `fact_cashflow[amount_original]` must only be shown next to `dim_currency[currency_code]`; never add it across currencies.

## Parameters

`ServerName` (default `.\SQLEXPRESS`) and `DatabaseName` (default `TreasurySqlPortfolio`), plus the function query `fnSql`. No password anywhere: Power BI asks for Windows credentials on first connection.

## Measures

15 measures, listed with logic and filter context in `dax_measures.md`. Source of truth: `measures.dax`.

## Refresh

Home -> Refresh. The data is a one-off synthetic load, so nothing changes unless `sql/sqlserver/02`-`04` are re-run.

## Known limits

- The cash position is in JPY only (`fact_cash_position` has no currency or category column), so the Currency and Category slicers do not change it; the Entity and Date slicers do.
- Payments are dated November 2026 and cash flows end on 2026-10-31, so a date slicer that covers both shows each fact only where it has data.
- Synthetic data: the model demonstrates structure and controls, not real treasury behaviour.
