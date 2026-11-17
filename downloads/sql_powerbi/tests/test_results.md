# Test results

Generated 2026-11-16 02:10 by `scripts/write_test_report.py` from the files the two runners wrote in `tests/`.

What these tests are: SQL data-quality tests (`sql/*/05_data_quality_tests.sql`, expected 0 for INTEGRITY, expected = planted count for DETECTION) plus a few Python checks that compare the SQL output with an independent re-implementation of the rules and with the original Excel check sheet. The data is synthetic; passing means the logic does what it is specified to do, not that it is right for any real data.

## Summary

| Engine | SQL tests | Extra checks |
|---|---|---|
| SQL Server 2022 Express | 47 / 47 pass | 6 / 6 pass |
| SQLite | 47 / 47 pass | 6 / 6 pass |

## A. SQL Server 2022 Express (primary target, run on the development machine)

```
﻿Server: .\SQLEXPRESS
Version: Microsoft SQL Server 2022 (RTM) - 16.0.1000.6 (X64) Oct 8 2022 05:58:25 Copyright (C) 2022 Microsoft Corporation Express Edition (64-bit) on Windows 10 Home 10.0 <X64> (Build 26200: ) (Hypervisor) 
Run at: 2026-11-16T02:10:04
OK    01_create_tables.sql (4 batches, 0 result sets)
```

**Data-quality tests (05_data_quality_tests.sql): 47 of 47 pass.  Extra Python checks on this engine's output: 6 of 6 pass.**

| Test | Name | SQL file | Expected | Actual | Result |
|---|---|---|---:|---:|---|
| D01 | Planted: duplicate cash-flow reference rejected | 05_data_quality_tests.sql | 2 | 2 | **Pass** |
| D02 | Planted: unknown currency rejected | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D03 | Planted: missing amount rejected | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D04 | Planted: impossible date rejected | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D05 | Planted: unknown entity rejected | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D06 | Payments that could not be tied to a vendor stay in the fact (2 without key + 1 unknown key) | 05_data_quality_tests.sql | 3 | 3 | **Pass** |
| D07 | Planted: unknown vendor site key raises FX25 | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D08 | Planted event: ENT3 March USD trade receipts short-paid -> Large variance | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D09 | Planted event: ENT1 September trade payments delayed -> Not realised (JPY, USD, EUR) | 05_data_quality_tests.sql | 3 | 3 | **Pass** |
| D10 | Planted event: ENT4 July GBP receipts never arrived -> Not realised | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D11 | Planted event: ENT2 June unplanned repair -> Large variance on expenses | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| T01 | Duplicate primary key in fact_cashflow | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T02 | Duplicate business key (transaction_ref) in fact_cashflow | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T03 | Duplicate primary key in fact_fx_payment | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T04 | Required fields empty in fact_cashflow | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T05 | Required fields empty in fact_fx_payment | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T06 | Invalid date: cash-flow date not in the calendar | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T07 | Invalid date: payment date not in the calendar | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T08 | Invalid currency in fact_cashflow (not in dim_currency) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T09 | Invalid currency in fact_fx_payment (not in dim_currency) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T10 | Orphan entity or category key in fact_cashflow | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T11 | Orphan vendor key (key set but vendor missing) in fact_fx_payment | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T12 | Payments without a control row, or control rows without a payment | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T13 | Duplicate payments (same vendor key, currency, amount and date) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T14 | Abnormal cash-flow amount (zero, or over 500 million JPY) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T15 | Abnormal payment amount (zero or negative, or over 20 million JPY) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T16 | Currency conversion: |amount_original x fx_rate - amount_base| above 1 JPY | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T17 | Scenario other than Actual / Forecast | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T18 | Sign contradicts category (inflow must be +, outflow must be -) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T19 | Risk level contradicts exception code (Passed with exceptions, or exceptions marked Passed) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T20 | Risk level differs from the risk of the primary exception code | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T21 | Primary exception is not the most serious failed rule | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T22 | SWIFT flag disagrees with exceptions (flag 0 must equal FX01 or FX04) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T23 | IBAN flag disagrees with exceptions (flag 0 must equal FX11 or FX19) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T24 | ERP account flag disagrees with exceptions (flag 0 must equal FX13) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T25 | Row count, cash flow: staging rows - loaded rows - rejected rows | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T26 | Row count, payments: staging rows - loaded rows - rejected rows | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T27 | Closing cash on the last day = 745,000,000 JPY (cash summary sheet balance on 2026-10-31) | 05_data_quality_tests.sql | 745,000,000 | 745,000,000 | **Pass** |
| T28 | Daily continuity: opening balance of a day differs from the previous closing | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T29 | Days with a negative closing balance | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T30 | Pooling sweeps that do not net to zero on a date | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T31 | Variance view total - (Actual total - Forecast total) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T32 | Position view net flow total - Actual total | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T33 | Month x entity without both Actual and Forecast lines | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T34 | Payment control view row count - payment fact row count (LEFT JOIN must not drop payments) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T35 | Vendor bank history: account still duplicated after de-duplication | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T36 | exception_count in the control table differs from the rows in fact_payment_exception | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| X1 | SQL exception codes equal the independent Python rule engine, all 150 payments (mismatching payments) | scripts/write_test_report.py | 0 | 0 | **Pass** |
| X2 | SQL exception codes equal the original Excel check sheet result for the 34 workbook payments (S23 has one documented extra, FX13) | scripts/write_test_report.py | 0 | 0 | **Pass** |
| X3fac | Row count of fact_cashflow equals the generator's expected count | scripts/write_test_report.py | 1,323 | 1,323 | **Pass** |
| X3rej | Row count of rejected_record equals the generator's expected count | scripts/write_test_report.py | 6 | 6 | **Pass** |
| X3fac | Row count of fact_fx_payment equals the generator's expected count | scripts/write_test_report.py | 150 | 150 | **Pass** |
| X3dim | Row count of dim_vendor equals the generator's expected count | scripts/write_test_report.py | 50 | 50 | **Pass** |

## B. SQLite (portable copy, standard-library Python)

```
SQLite 3.42.0 | Python 3.12.0 | run at 2026-11-16T02:10:03
OK    01_create_tables.sql
OK    02_load_data (Python loader, 16 tables)
OK    03_transform.sql (0 result sets)
```

**Data-quality tests (05_data_quality_tests.sql): 47 of 47 pass.  Extra Python checks on this engine's output: 6 of 6 pass.**

| Test | Name | SQL file | Expected | Actual | Result |
|---|---|---|---:|---:|---|
| D01 | Planted: duplicate cash-flow reference rejected | 05_data_quality_tests.sql | 2 | 2 | **Pass** |
| D02 | Planted: unknown currency rejected | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D03 | Planted: missing amount rejected | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D04 | Planted: impossible date rejected | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D05 | Planted: unknown entity rejected | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D06 | Payments that could not be tied to a vendor stay in the fact (2 without key + 1 unknown key) | 05_data_quality_tests.sql | 3 | 3 | **Pass** |
| D07 | Planted: unknown vendor site key raises FX25 | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D08 | Planted event: ENT3 March USD trade receipts short-paid -> Large variance | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D09 | Planted event: ENT1 September trade payments delayed -> Not realised (JPY, USD, EUR) | 05_data_quality_tests.sql | 3 | 3 | **Pass** |
| D10 | Planted event: ENT4 July GBP receipts never arrived -> Not realised | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| D11 | Planted event: ENT2 June unplanned repair -> Large variance on expenses | 05_data_quality_tests.sql | 1 | 1 | **Pass** |
| T01 | Duplicate primary key in fact_cashflow | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T02 | Duplicate business key (transaction_ref) in fact_cashflow | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T03 | Duplicate primary key in fact_fx_payment | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T04 | Required fields empty in fact_cashflow | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T05 | Required fields empty in fact_fx_payment | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T06 | Invalid date: cash-flow date not in the calendar | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T07 | Invalid date: payment date not in the calendar | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T08 | Invalid currency in fact_cashflow (not in dim_currency) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T09 | Invalid currency in fact_fx_payment (not in dim_currency) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T10 | Orphan entity or category key in fact_cashflow | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T11 | Orphan vendor key (key set but vendor missing) in fact_fx_payment | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T12 | Payments without a control row, or control rows without a payment | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T13 | Duplicate payments (same vendor key, currency, amount and date) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T14 | Abnormal cash-flow amount (zero, or over 500 million JPY) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T15 | Abnormal payment amount (zero or negative, or over 20 million JPY) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T16 | Currency conversion: |amount_original x fx_rate - amount_base| above 1 JPY | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T17 | Scenario other than Actual / Forecast | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T18 | Sign contradicts category (inflow must be +, outflow must be -) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T19 | Risk level contradicts exception code (Passed with exceptions, or exceptions marked Passed) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T20 | Risk level differs from the risk of the primary exception code | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T21 | Primary exception is not the most serious failed rule | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T22 | SWIFT flag disagrees with exceptions (flag 0 must equal FX01 or FX04) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T23 | IBAN flag disagrees with exceptions (flag 0 must equal FX11 or FX19) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T24 | ERP account flag disagrees with exceptions (flag 0 must equal FX13) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T25 | Row count, cash flow: staging rows - loaded rows - rejected rows | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T26 | Row count, payments: staging rows - loaded rows - rejected rows | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T27 | Closing cash on the last day = 745,000,000 JPY (cash summary sheet balance on 2026-10-31) | 05_data_quality_tests.sql | 745,000,000 | 745,000,000 | **Pass** |
| T28 | Daily continuity: opening balance of a day differs from the previous closing | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T29 | Days with a negative closing balance | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T30 | Pooling sweeps that do not net to zero on a date | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T31 | Variance view total - (Actual total - Forecast total) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T32 | Position view net flow total - Actual total | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T33 | Month x entity without both Actual and Forecast lines | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T34 | Payment control view row count - payment fact row count (LEFT JOIN must not drop payments) | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T35 | Vendor bank history: account still duplicated after de-duplication | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| T36 | exception_count in the control table differs from the rows in fact_payment_exception | 05_data_quality_tests.sql | 0 | 0 | **Pass** |
| X1 | SQL exception codes equal the independent Python rule engine, all 150 payments (mismatching payments) | scripts/write_test_report.py | 0 | 0 | **Pass** |
| X2 | SQL exception codes equal the original Excel check sheet result for the 34 workbook payments (S23 has one documented extra, FX13) | scripts/write_test_report.py | 0 | 0 | **Pass** |
| X3fac | Row count of fact_cashflow equals the generator's expected count | scripts/write_test_report.py | 1,323 | 1,323 | **Pass** |
| X3rej | Row count of rejected_record equals the generator's expected count | scripts/write_test_report.py | 6 | 6 | **Pass** |
| X3fac | Row count of fact_fx_payment equals the generator's expected count | scripts/write_test_report.py | 150 | 150 | **Pass** |
| X3dim | Row count of dim_vendor equals the generator's expected count | scripts/write_test_report.py | 50 | 50 | **Pass** |

## C. Cross-checks

| Check | Result |
|---|---|
| SQL Server and SQLite give identical `export_fact_payment_exception.csv` (44 rows) | **Pass** |
| SQL Server and SQLite give identical `export_fact_payment_control.csv` (150 rows) | **Pass** |
| `Treasury_Cash_Flow_and_Forecast_Portfolio.xlsm` is byte-identical to its backup (the existing workbooks were not changed) | **Pass** |
| `FX_Payment_Pre_Control_Portfolio.xlsx` is byte-identical to its backup (the existing workbooks were not changed) | **Pass** |

## D. Fault injection (SQLite copy)

A test that cannot fail proves nothing. Each row breaks the data on purpose and shows which tests turned red.

| Fault injected | Expected to fail | Tests that failed | Result |
|---|---|---|---|
| Flip the sign of one Actual inflow | T18 | T18 T27 | **caught** |
| Change one fx_rate without changing amount_base | T16 | T16 | **caught** |
| Drop one payment control row | T12 | T12 T34 | **caught** |
| Duplicate a payment (same vendor key, currency, amount, date) | T13 T12 | T12 T13 T26 T34 | **caught** |
| Mark a payment with exceptions as Passed | T19 T20 | T19 T20 | **caught** |
| Turn off a SWIFT flag that has no exception | T22 | T22 | **caught** |
| Delete an exception row but keep the control row's count and code | T36 | T36 | **caught** |
| Move one Actual cash-flow line to a date outside the calendar (FK off) | T06 | T06 T31 | **caught** |
| Remove the opening balance of one entity | T27 | T27 T32 | **caught** |
| Add an unbalanced pooling sweep | T30 T27 T25 | T25 T27 T30 | **caught** |
| Delete an Actual row that was loaded (row count and closing cash no longer reconcile) | T25 T27 | T25 T27 | **caught** |
| Leave a vendor key pointing nowhere (FK off) | T11 | T11 | **caught** |

The first run of this table exposed one real gap: deleting a row of `fact_payment_exception` while keeping the control row's count and primary code was not detected. Test T36 was added for it. Two other first-run misses were wrong expectations in the fault list, not weak tests, and were corrected.
