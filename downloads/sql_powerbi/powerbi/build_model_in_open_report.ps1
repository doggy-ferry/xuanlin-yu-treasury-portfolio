<#
  Builds the Power BI semantic model inside a Power BI Desktop report that is ALREADY OPEN and empty.
  It talks to the report's local model engine (the way Power BI external tools do), so Power BI itself checks every table,
  relationship and DAX measure as it is created. Nothing is installed and no credential is stored in any file.

  Needs: Power BI Desktop with a blank report open; the SQL Server database from sql\sqlserver\01-04 already built;
         Microsoft.AnalysisServices.Tabular.dll (installed with SQL Server; default path below is SQL Server 2022).
  Columns and types are read from the database (INFORMATION_SCHEMA), so they cannot drift from the SQL.
  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File build_model_in_open_report.ps1 [-Port <local port>] [-Reset]
         -Reset removes every table, relationship and query from the open report first (use only on a throw-away report).
#>
param(
    [int]$Port = 0,
    [string]$Server = '.\SQLEXPRESS',
    [string]$Database = 'TreasurySqlPortfolio',
    [string]$TomDir = 'C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\SQL2022\x64',
    [switch]$Reset
)
$ErrorActionPreference = 'Stop'
foreach ($n in 'Microsoft.AnalysisServices.Core','Microsoft.AnalysisServices','Microsoft.AnalysisServices.Tabular.Json','Microsoft.AnalysisServices.Tabular') { [void][Reflection.Assembly]::LoadFrom("$TomDir\$n.dll") }
$NS = 'Microsoft.AnalysisServices.Tabular'
if ($Port -eq 0) {
    $p = (Get-Process msmdsrv | Sort-Object StartTime -Descending | Select-Object -First 1).Id
    $Port = (Get-NetTCPConnection -State Listen -OwningProcess $p | Where-Object LocalAddress -eq '127.0.0.1' | Select-Object -First 1).LocalPort
}
$srv = New-Object "$NS.Server"; $srv.Connect("Data Source=localhost:$Port")
$model = $srv.Databases[0].Model
if ($Reset) {
    $model.Relationships.Clear(); $model.Tables.Clear(); $model.Expressions.Clear(); $model.SaveChanges() | Out-Null
}
if ($model.Tables.Count -gt 0) { throw "The open report already has $($model.Tables.Count) tables. Use a blank report (or -Reset on a throw-away one)." }

# ---- what to load: Power BI table name = source object in the database
$tables = [ordered]@{
    'dim_date' = 'dim_date'; 'dim_entity' = 'dim_entity'; 'dim_currency' = 'dim_currency'; 'dim_vendor' = 'dim_vendor'
    'dim_cashflow_category' = 'dim_cashflow_category'; 'dim_exception_type' = 'dim_exception_type'
    'fact_cashflow' = 'fact_cashflow'; 'fact_cash_position' = 'vw_cash_position_daily'; 'fact_payment_control' = 'vw_fx_payment_control'
}
$sql = New-Object System.Data.SqlClient.SqlConnection "Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True"
$sql.Open()
function Columns($obj) {
    $c = $sql.CreateCommand(); $c.CommandText = "SELECT COLUMN_NAME, DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = '$obj' ORDER BY ORDINAL_POSITION"
    $r = $c.ExecuteReader(); $o = @(); while ($r.Read()) { $o += , @($r['COLUMN_NAME'], $r['DATA_TYPE']) }; $r.Close(); $o
}
function AddExpr($n, $text) { $e = New-Object "$NS.NamedExpression"; $e.Name = $n; $e.Kind = [Microsoft.AnalysisServices.Tabular.ExpressionKind]::M; $e.Expression = $text; $model.Expressions.Add($e) }
AddExpr 'ServerName'   ('"' + $Server.Replace('"', '""') + '" meta [IsParameterQuery = true, Type = "Text", IsParameterQueryRequired = true]')
AddExpr 'DatabaseName' ('"' + $Database.Replace('"', '""') + '" meta [IsParameterQuery = true, Type = "Text", IsParameterQueryRequired = true]')
AddExpr 'fnSql' "(objectName as text) as table =>`nlet`n    Source = Sql.Database(ServerName, DatabaseName, [CommandTimeout = #duration(0, 0, 2, 0)]),`n    Result = Source{[Schema = `"dbo`", Item = objectName]}[Data]`nin`n    Result"

$dtMap = @{ int = 'Int64'; smallint = 'Int64'; tinyint = 'Int64'; bigint = 'Int64'; decimal = 'Decimal'; numeric = 'Decimal'; date = 'DateTime'; datetime = 'DateTime'; datetime2 = 'DateTime'; varchar = 'String'; char = 'String'; nvarchar = 'String' }
foreach ($tn in $tables.Keys) {
    $t = New-Object "$NS.Table"; $t.Name = $tn
    foreach ($cd in (Columns $tables[$tn])) {
        $col = New-Object "$NS.DataColumn"; $col.Name = $cd[0]; $col.SourceColumn = $cd[0]
        $col.DataType = [Microsoft.AnalysisServices.Tabular.DataType]::($dtMap[$cd[1]])
        $col.SummarizeBy = [Microsoft.AnalysisServices.Tabular.AggregateFunction]::None
        if ($cd[1] -eq 'date') { $col.FormatString = 'yyyy-mm-dd' }
        if ($cd[1] -eq 'decimal') { $col.FormatString = '#,0.00' }
        $t.Columns.Add($col)
    }
    $part = New-Object "$NS.Partition"; $part.Name = $tn
    $src = New-Object "$NS.MPartitionSource"; $src.Expression = "let`n    Source = fnSql(`"$($tables[$tn])`")`nin`n    Source"; $part.Source = $src
    $part.Mode = [Microsoft.AnalysisServices.Tabular.ModeType]::Import
    $t.Partitions.Add($part)
    $model.Tables.Add($t)
}
$sql.Close()
$d = $model.Tables['dim_date']; $d.DataCategory = 'Time'; $d.Columns['full_date'].IsKey = $true

# a table that only holds the measures
$mt = New-Object "$NS.Table"; $mt.Name = '_Measures'
$mc = New-Object "$NS.DataColumn"; $mc.Name = 'Hide'; $mc.DataType = [Microsoft.AnalysisServices.Tabular.DataType]::String; $mc.SourceColumn = 'Hide'; $mc.IsHidden = $true; $mt.Columns.Add($mc)
$mp = New-Object "$NS.Partition"; $mp.Name = '_Measures'; $ms0 = New-Object "$NS.MPartitionSource"; $ms0.Expression = '#table(type table [Hide = text], {})'; $mp.Source = $ms0; $mt.Partitions.Add($mp)
$model.Tables.Add($mt)

# ---- relationships: many -> one, single direction, every dimension reaches each fact on exactly one path
$rel = @(
  'fact_cashflow|entity_key|dim_entity|entity_key', 'fact_cashflow|currency_key|dim_currency|currency_key', 'fact_cashflow|category_key|dim_cashflow_category|category_key',
  'fact_cashflow|transaction_date|dim_date|full_date',
  'fact_cash_position|entity_key|dim_entity|entity_key', 'fact_cash_position|full_date|dim_date|full_date',
  'fact_payment_control|entity_key|dim_entity|entity_key', 'fact_payment_control|currency_key|dim_currency|currency_key', 'fact_payment_control|vendor_key|dim_vendor|vendor_key',
  'fact_payment_control|payment_date|dim_date|full_date', 'fact_payment_control|exception_code|dim_exception_type|exception_code')
foreach ($r in $rel) {
    $a = $r.Split('|')
    $x = New-Object "$NS.SingleColumnRelationship"
    $x.FromColumn = $model.Tables[$a[0]].Columns[$a[1]]; $x.ToColumn = $model.Tables[$a[2]].Columns[$a[3]]
    $x.FromCardinality = [Microsoft.AnalysisServices.Tabular.RelationshipEndCardinality]::Many
    $x.ToCardinality = [Microsoft.AnalysisServices.Tabular.RelationshipEndCardinality]::One
    $x.CrossFilteringBehavior = [Microsoft.AnalysisServices.Tabular.CrossFilteringBehavior]::OneDirection
    $model.Relationships.Add($x)
}

# ---- measures from measures.dax (a measure starts at column 0 as "Name ="; lines starting with VAR belong to the body above)
$cur = $null; $body = New-Object System.Collections.ArrayList; $fmt = ''; $list = @()
foreach ($line in (Get-Content (Join-Path $PSScriptRoot 'measures.dax') -Encoding UTF8)) {
    if ($line -match '^// format:\s*(?<f>.+)$') { $fmt = $Matches.f.Trim(); continue }
    if ($line -match '^(?!VAR\s|//)(?<n>[A-Za-z][^=]*?)\s=\s*$') {
        if ($cur) { $list += , @($cur, ($body -join "`n").Trim(), $curFmt) }
        $cur = $Matches.n.Trim(); $curFmt = $fmt; $body = New-Object System.Collections.ArrayList; continue
    }
    if (-not $cur -or $line.StartsWith('//')) { continue }
    [void]$body.Add($line)
}
if ($cur) { $list += , @($cur, ($body -join "`n").Trim(), $curFmt) }
foreach ($e in $list) {
    $m = New-Object "$NS.Measure"; $m.Name = $e[0]; $m.Expression = $e[1]; $m.FormatString = $e[2]
    $mt.Measures.Add($m)
}
"Defined: $($model.Tables.Count) tables, $($model.Relationships.Count) relationships, $($mt.Measures.Count) measures. Saving to the open report..."
$model.SaveChanges() | Out-Null
"Saved. Requesting a full refresh from SQL Server..."
$model.RequestRefresh([Microsoft.AnalysisServices.Tabular.RefreshType]::Full)
$model.SaveChanges() | Out-Null
"Refresh finished."
$srv.Disconnect()
