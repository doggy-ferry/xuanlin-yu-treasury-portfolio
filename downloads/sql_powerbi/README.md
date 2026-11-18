# Treasury SQL and Power BI analytics: published files

These are the reading copies of the project behind the page `sql-powerbi.html`: a SQL data layer and a Power BI report on top of two Excel finance automations (a cash-flow forecast and an FX payment pre-control).

> **All data is synthetic.** No employer data, files, field names or proprietary business rules are included. This is a portfolio project, not a production system, and it makes no claim about any treasury management system.
>
> AI tools were used to accelerate implementation and documentation. Business requirements, control design, testing and final validation remained under the project owner's responsibility.

## What is here

| Folder | Content |
|---|---|
| `sql/sqlserver/` | the six T-SQL scripts: tables, load, transform, four business views, 47 data-quality tests, demo queries |
| `docs/` | `architecture.md` (layers, grain, design decisions), `business_logic.md` (cash-flow and payment-control rules) |
| `powerbi/` | model specification, relationship map, Power Query, the 15 DAX measures with their logic, the report build guide, the reference KPI values |
| `tests/` | `test_results.md`: test names, expected and actual values, SQL Server and SQLite, fault injection |

## What is not here

The generated data files, the helper scripts that read the two source workbooks, the field mapping to those workbooks, and the Power BI report file itself are kept out of this public folder. The SQL scripts therefore show the logic; running them needs the full project. References in these reading copies to helper scripts, SQLite copies, generated model-check outputs or full-project tests belong to the full private build and are intentionally not included in this public download.

## Results

- SQL Server 2022 Express and SQLite: 47 of 47 data-quality tests pass on each, with identical results.
- The payment-control rules agree with an independent Python implementation for all 150 payments and with the original Excel check for all 34 payments that come from the workbook (one documented difference).
- 12 of 12 deliberately injected faults are caught.
- Power BI: a star-schema model with 15 DAX measures, checked on Power BI Desktop's own engine (28 of 28 checks), and a three-page report: Treasury Overview, Cash Flow Analysis, Payment Control.

## Limits

Synthetic data; the rules copy an Excel rule list (not a fraud model); one static planning rate per currency; no full cash-flow statement; T-SQL run on SQL Server 2022 Express only.
