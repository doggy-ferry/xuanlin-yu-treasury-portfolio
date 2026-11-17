# Report build guide (about one hour)

**Status:** the data model and the 15 measures are verified on Power BI Desktop's engine, and the three pages below were built by the project owner by following this guide (saved file read back: 3 pages, every field as listed). Building the pages needs the Desktop interface, which cannot be driven from this project, so the steps marked **YOU** are manual. Tips that came out of the build: the new Card visual holds all six KPI measures in one visual; month axes must be sorted ascending by `year_month` (the default sort is by value); click blank canvas before adding each visual or the field is added to the selected one; clear any slicer selection before comparing with `expected_kpis.csv`.

Colours: navy `#1F3A5F`, teal `#2A9D8F`, grey `#8D99A5` for normal data; red `#C0392B` = High risk; amber `#E9B44C` = Review required; green `#3A9D5D` = Passed defined checks. No 3-D charts, no decoration, at most six main visuals per page (slicers are filters, not visuals).

## Step 1 - model (5 minutes)

1. **YOU**: SQL Server running with scripts `sql/sqlserver/01`-`04` done (`scripts/run_sqlserver.ps1` does it).
2. **YOU**: open Power BI Desktop and create a **blank report** (keep it the only open report).
3. Run, in a terminal:
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File sql_powerbi_portfolio\powerbi\build_model_in_open_report.ps1
   ```
   It creates the parameters, 9 tables, 11 relationships and 15 measures in the open report and refreshes them. If Power BI shows a credentials window during the refresh, choose **Windows -> Use my current credentials -> Connect** (and accept the encryption prompt).
4. Run `powershell -NoProfile -ExecutionPolicy Bypass -File sql_powerbi_portfolio\powerbi\verify_model_in_open_report.ps1`. Expect `Failures: 0 of 28`.
5. **YOU**: File -> Save as `Treasury_SQL_Analytics.pbix` (do this now; the model lives only in memory until you do).
6. **YOU**: Model view -> select `dim_date` -> Table tools -> **Mark as date table** -> `full_date`. Hide key columns (`*_key`, `transaction_id`).
7. **YOU** (optional): View -> Themes -> Browse for themes -> `treasury_portfolio_theme.json` (colour palette only).

If you prefer to build by hand, `power_query_m.md`, `relationship_map.md` and `dax_measures.md` contain everything.

## Page 1 - Treasury Overview

Slicers (filters): `dim_entity[entity_code]`, `dim_currency[currency_code]`, `dim_date[year_month]`.

| Visual | Type | Fields |
|---|---|---|
| KPI strip | Multi-row card | `Closing Cash Position`, `Total Actual`, `Total Forecast`, `Forecast Variance`, `Payment Count`, `Exception Count` |
| Actual vs Forecast trend | Line chart | Axis `dim_date[year_month]`; values `Total Actual`, `Total Forecast` |
| Cash position by entity | Clustered bar | Axis `dim_entity[entity_code]`; value `Closing Cash Position` |
| Payment exceptions by category | Clustered bar | Axis `dim_exception_type[exception_category]`; value `Exception Count` |

Check with no slicer (from `expected_kpis.csv`): Closing Cash Position 745,000,000; Total Actual 249,956,347; Total Forecast 270,480,000; Forecast Variance -20,523,653; Payment Count 150; Exception Count 41. The month axis stops at 2026-10 for cash flow; the payment measures show November.

## Page 2 - Cash Flow Analysis

Slicers: Entity, Currency, `fact_cashflow[scenario]` (Actual / Forecast), `dim_date[year_month]`. Use Date drill-down on the month axis (year -> quarter -> month -> day via `dim_date`).

| Visual | Type | Fields |
|---|---|---|
| Monthly Actual vs Forecast | Clustered column | Axis `dim_date[year_month]`; values `Total Actual`, `Total Forecast` |
| Forecast variance by category | Waterfall | Category `dim_cashflow_category[category_name]`; value `Forecast Variance` |
| Cash flow by category | Bar | Axis `dim_cashflow_category[category_name]`; value `Total Actual` |
| Cash position by entity over time | Line chart | Axis `dim_date[year_month]`; legend `dim_entity[entity_code]`; value `Closing Cash Position` |
| Currency breakdown | Bar | Axis `dim_currency[currency_code]`; value `Total Actual` (JPY) |
| Transaction details | Table | `fact_cashflow[transaction_date]`, `dim_entity[entity_code]`, `dim_currency[currency_code]`, `dim_cashflow_category[category_name]`, `fact_cashflow[scenario]`, `fact_cashflow[amount_original]`, `fact_cashflow[amount_base]`, `fact_cashflow[memo]` |

The transaction table shows `amount_original` next to the currency code and is never totalled across currencies (turn off totals on that column). The Currency slicer does not change "Cash position by entity" (that table is JPY only).

Sorted by absolute variance, the planted events appear at the top (ENT1 September trade payments, ENT3 March USD receipts, ENT4 GBP receipts in July / August, ENT2 June repair).

## Page 3 - Payment Control

Slicers: Entity, Currency, `dim_vendor[vendor_name]`, `fact_payment_control[risk_level]`.

| Visual | Type | Fields |
|---|---|---|
| Payment amount by currency | Bar | Axis `dim_currency[currency_code]`; value `Total Payment Amount Base` |
| Exception count by category | Bar | Axis `dim_exception_type[exception_category]`; value `Exception Count` |
| Exception count by risk level | Bar | Axis `fact_payment_control[risk_level]`; value `Payment Count` |
| Check-result summary | Matrix | Rows `dim_exception_type[exception_name]`; values `Payment Count` |
| Payment detail | Table | `payment_id`, `payment_date`, `entity_code`, `vendor_name`, `vendor_site_key`, `currency_code`, `request_amount`, `scheduled_amount`, `payment_amount`, `exception_category`, `risk_level`, `review_status` (all from `fact_payment_control`) |

- **Colour the risk level** (Format -> Cell elements -> Background colour -> Rules, field `risk_level`): High -> red, Medium -> amber, Passed -> green. Show `review_status` beside it: Hold for confirmation / Review required / Passed defined checks.
- The check-result matrix counts each payment under its **primary** (most serious) failed rule, so it adds up to 41 exceptions. A payment can fail several rules (44 failures in total, in `fact_payment_exception`); the SQL layer holds the full list if the report ever needs it.
- Three payments have no vendor: they appear under a blank vendor. Do not filter them out.
- Expected with no slicer: Payment Count 150, High Risk Count 22, Passed Payment Count 109, Unmatched Vendor Count 3, Total Payment Amount Base 317,121,190.

## Finish

- **YOU**: compare every card with `expected_kpis.csv`; File -> Save.
- **YOU** (optional): save as a Power BI Project (`.pbip`, File -> Save as, after enabling it under Options -> Preview features) to keep the model as readable text files.
- Take screenshots only from your own report.
