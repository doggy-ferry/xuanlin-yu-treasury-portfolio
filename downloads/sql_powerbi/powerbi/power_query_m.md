# Power Query (M)

Create these in Power BI Desktop (Home -> Transform data). `build_model_in_open_report.ps1` creates exactly the same queries automatically; use this page if you build by hand.

No credentials are written anywhere. The first refresh asks for Windows credentials ("Use my current credentials") for the server.

## Parameters (Manage Parameters -> New, type Text, required)

```m
// ServerName
".\SQLEXPRESS" meta [IsParameterQuery = true, Type = "Text", IsParameterQueryRequired = true]
// DatabaseName
"TreasurySqlPortfolio" meta [IsParameterQuery = true, Type = "Text", IsParameterQueryRequired = true]
```

For LocalDB use `(localdb)\MSSQLLocalDB`.

## Function query `fnSql`

```m
(objectName as text) as table =>
let
    Source = Sql.Database(ServerName, DatabaseName, [CommandTimeout = #duration(0, 0, 2, 0)]),
    Result = Source{[Schema = "dbo", Item = objectName]}[Data]
in
    Result
```

Navigating to the object (instead of sending SQL text) lets Power Query fold work back to SQL Server.

## One query per table (query name = table name)

| Query name | M | Source object |
|---|---|---|
| `dim_date` | `let Source = fnSql("dim_date") in Source` | table |
| `dim_entity` | `let Source = fnSql("dim_entity") in Source` | table |
| `dim_currency` | `let Source = fnSql("dim_currency") in Source` | table |
| `dim_cashflow_category` | `let Source = fnSql("dim_cashflow_category") in Source` | table |
| `dim_vendor` | `let Source = fnSql("dim_vendor") in Source` | table |
| `dim_exception_type` | `let Source = fnSql("dim_exception_type") in Source` | table |
| `fact_cashflow` | `let Source = fnSql("fact_cashflow") in Source` | table |
| `fact_cash_position` | `let Source = fnSql("vw_cash_position_daily") in Source` | view |
| `fact_payment_control` | `let Source = fnSql("vw_fx_payment_control") in Source` | view |

Types come through from SQL Server (date, decimal, whole number, text), so no `Table.TransformColumnTypes` step is needed.

## Why `fnSql` takes its server from parameters and not from a worksheet

Reading a server name from an Excel table and connecting to SQL Server in the same query makes Power Query ask for a privacy level for each source ("Information is needed in order to combine data"). Parameters avoid that; the Excel workbook's refresh macro in the earlier project handled it by writing the names into the query text. Here parameters are enough because everything is inside Power BI.
