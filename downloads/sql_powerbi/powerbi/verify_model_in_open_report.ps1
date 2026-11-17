<#
  Reads the model of the open Power BI Desktop report and checks it against powerbi\expected_kpis.csv (no slicers selected).
  Also checks: row counts of every table, that slicing by Entity and by Currency adds up to the total, and the built-in
  reconciliation Net Cash Flow = Total Actual. Output: powerbi\model_check_results.csv
  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File verify_model_in_open_report.ps1 [-Port <local port>]
#>
param([int]$Port = 0, [string]$Out = (Join-Path $PSScriptRoot 'model_check_results.csv'))
$ErrorActionPreference = 'Stop'
[void][Reflection.Assembly]::LoadFrom('C:\Program Files (x86)\Microsoft.NET\ADOMD.NET\160\Microsoft.AnalysisServices.AdomdClient.dll')
if ($Port -eq 0) {
    $p = (Get-Process msmdsrv | Sort-Object StartTime -Descending | Select-Object -First 1).Id
    $Port = (Get-NetTCPConnection -State Listen -OwningProcess $p | Where-Object LocalAddress -eq '127.0.0.1' | Select-Object -First 1).LocalPort
}
$cn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection "Data Source=localhost:$Port"; $cn.Open()
function Dax($q) { $c = $cn.CreateCommand(); $c.CommandText = $q; $r = $c.ExecuteReader(); $rows = @(); while ($r.Read()) { $o = [ordered]@{}; for ($i = 0; $i -lt $r.FieldCount; $i++) { $o[$r.GetName($i).Trim('[', ']')] = $r.GetValue($i) }; $rows += [pscustomobject]$o }; $r.Close(); $rows }
$res = New-Object System.Collections.ArrayList
function Add($name, $got, $exp, $tol) { [void]$res.Add([pscustomobject]@{ check = $name; power_bi = $got; expected = $exp; result = $(if ($null -ne $got -and [math]::Abs([double]$got - [double]$exp) -le $tol) { 'Pass' } else { 'Fail' }) }) }

# row counts must equal the database
$sql = New-Object System.Data.SqlClient.SqlConnection 'Server=.\SQLEXPRESS;Database=TreasurySqlPortfolio;Integrated Security=True;TrustServerCertificate=True'; $sql.Open()
foreach ($t in @(('dim_date','dim_date'),('dim_entity','dim_entity'),('dim_currency','dim_currency'),('dim_vendor','dim_vendor'),('dim_cashflow_category','dim_cashflow_category'),('dim_exception_type','dim_exception_type'),('fact_cashflow','fact_cashflow'),('fact_cash_position','vw_cash_position_daily'),('fact_payment_control','vw_fx_payment_control'))) {
    $c = $sql.CreateCommand(); $c.CommandText = "SELECT COUNT(*) FROM dbo.$($t[1])"; $exp = [double]$c.ExecuteScalar()
    Add "rows in $($t[0])" ((Dax "EVALUATE ROW(""n"", COUNTROWS('$($t[0])'))").n) $exp 0
}
$sql.Close()
# every KPI
foreach ($k in (Import-Csv (Join-Path $PSScriptRoot 'expected_kpis.csv'))) {
    $v = (Dax "EVALUATE ROW(""v"", [$($k.measure)])").v
    Add "measure: $($k.measure)" $v ([double]$k.expected_value) $(if ($k.unit -eq 'ratio') { 0.00005 } else { 0.01 })
}
# built-in reconciliation and slicing
$d = Dax 'EVALUATE ROW("a", [Total Actual], "n", [Net Cash Flow])'
Add 'Net Cash Flow (position table) = Total Actual (transaction table)' ([double]$d.n - [double]$d.a) 0 0.01
$byEnt = (Dax 'EVALUATE SUMMARIZECOLUMNS(dim_entity[entity_code], "v", [Total Actual])' | Measure-Object -Property v -Sum).Sum
Add 'Total Actual by entity adds up to the total' ($byEnt - [double]$d.a) 0 0.01
$byCur = (Dax 'EVALUATE SUMMARIZECOLUMNS(dim_currency[currency_code], "v", [Total Actual])' | Measure-Object -Property v -Sum).Sum
Add 'Total Actual by currency adds up to the total' ($byCur - [double]$d.a) 0 0.01
$pc = (Dax 'EVALUATE SUMMARIZECOLUMNS(dim_exception_type[exception_category], "v", [Exception Count])' | Measure-Object -Property v -Sum).Sum
Add 'Exception Count by category adds up (payments without exception have no category)' ($pc) 41 0
$res | Export-Csv $Out -NoTypeInformation -Encoding UTF8
$res | Format-Table -AutoSize
"Failures: " + @($res | Where-Object { $_.result -eq 'Fail' }).Count + " of " + $res.Count
$cn.Close()
