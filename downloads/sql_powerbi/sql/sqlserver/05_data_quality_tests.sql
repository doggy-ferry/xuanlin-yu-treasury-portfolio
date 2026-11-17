/* =====================================================================
   05_data_quality_tests.sql  (SQL Server)
   One result set. Every row is a test with the expected value, the actual value and PASS / FAIL.

   INTEGRITY  must always hold (expected 0, or an equality).
   DETECTION  expected = the number of defects / events that were planted on purpose in the synthetic data
              (see scripts/generate_synthetic_data.py). They prove the rules catch what they claim to catch.

   Run after 03 and 04, and again after any change to the data or the views.
   ===================================================================== */
USE TreasurySqlPortfolio;
GO

-- @@PORTABLE_BEGIN
SELECT t.test_id, t.test_group, t.test_name, '05_data_quality_tests.sql' AS sql_file, t.expected_value, t.actual_value,
       CASE WHEN ABS(t.actual_value - t.expected_value) < 0.01 THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
    /* ---------- keys, duplicates, required fields ---------- */
    SELECT 'T01' AS test_id, 'INTEGRITY' AS test_group, 'Duplicate primary key in fact_cashflow' AS test_name, 0 AS expected_value,
           (SELECT COUNT(*) FROM (SELECT transaction_id FROM dbo.fact_cashflow GROUP BY transaction_id HAVING COUNT(*) > 1) q) AS actual_value
    UNION ALL SELECT 'T02', 'INTEGRITY', 'Duplicate business key (transaction_ref) in fact_cashflow', 0,
           (SELECT COUNT(*) FROM (SELECT transaction_ref FROM dbo.fact_cashflow GROUP BY transaction_ref HAVING COUNT(*) > 1) q)
    UNION ALL SELECT 'T03', 'INTEGRITY', 'Duplicate primary key in fact_fx_payment', 0,
           (SELECT COUNT(*) FROM (SELECT payment_id FROM dbo.fact_fx_payment GROUP BY payment_id HAVING COUNT(*) > 1) q)
    UNION ALL SELECT 'T04', 'INTEGRITY', 'Required fields empty in fact_cashflow', 0,
           (SELECT COUNT(*) FROM dbo.fact_cashflow WHERE transaction_date IS NULL OR entity_key IS NULL OR currency_key IS NULL OR category_key IS NULL
                  OR scenario IS NULL OR amount_original IS NULL OR fx_rate IS NULL OR amount_base IS NULL)
    UNION ALL SELECT 'T05', 'INTEGRITY', 'Required fields empty in fact_fx_payment', 0,
           (SELECT COUNT(*) FROM dbo.fact_fx_payment WHERE payment_date IS NULL OR entity_key IS NULL OR currency_key IS NULL OR payment_amount IS NULL)
    /* ---------- dates, currencies, orphan keys ---------- */
    UNION ALL SELECT 'T06', 'INTEGRITY', 'Invalid date: cash-flow date not in the calendar', 0,
           (SELECT COUNT(*) FROM dbo.fact_cashflow f LEFT JOIN dbo.dim_date d ON d.full_date = f.transaction_date WHERE d.date_key IS NULL)
    UNION ALL SELECT 'T07', 'INTEGRITY', 'Invalid date: payment date not in the calendar', 0,
           (SELECT COUNT(*) FROM dbo.fact_fx_payment f LEFT JOIN dbo.dim_date d ON d.full_date = f.payment_date WHERE d.date_key IS NULL)
    UNION ALL SELECT 'T08', 'INTEGRITY', 'Invalid currency in fact_cashflow (not in dim_currency)', 0,
           (SELECT COUNT(*) FROM dbo.fact_cashflow f LEFT JOIN dbo.dim_currency c ON c.currency_key = f.currency_key WHERE c.currency_key IS NULL)
    UNION ALL SELECT 'T09', 'INTEGRITY', 'Invalid currency in fact_fx_payment (not in dim_currency)', 0,
           (SELECT COUNT(*) FROM dbo.fact_fx_payment f LEFT JOIN dbo.dim_currency c ON c.currency_key = f.currency_key WHERE c.currency_key IS NULL)
    UNION ALL SELECT 'T10', 'INTEGRITY', 'Orphan entity or category key in fact_cashflow', 0,
           (SELECT COUNT(*) FROM dbo.fact_cashflow f LEFT JOIN dbo.dim_entity e ON e.entity_key = f.entity_key
                   LEFT JOIN dbo.dim_cashflow_category k ON k.category_key = f.category_key WHERE e.entity_key IS NULL OR k.category_key IS NULL)
    UNION ALL SELECT 'T11', 'INTEGRITY', 'Orphan vendor key (key set but vendor missing) in fact_fx_payment', 0,
           (SELECT COUNT(*) FROM dbo.fact_fx_payment f LEFT JOIN dbo.dim_vendor v ON v.vendor_key = f.vendor_key WHERE f.vendor_key IS NOT NULL AND v.vendor_key IS NULL)
    UNION ALL SELECT 'T12', 'INTEGRITY', 'Payments without a control row, or control rows without a payment', 0,
           (SELECT COUNT(*) FROM dbo.fact_fx_payment p LEFT JOIN dbo.fact_payment_control c ON c.payment_id = p.payment_id WHERE c.payment_id IS NULL)
         + (SELECT COUNT(*) FROM dbo.fact_payment_control c LEFT JOIN dbo.fact_fx_payment p ON p.payment_id = c.payment_id WHERE p.payment_id IS NULL)
    UNION ALL SELECT 'T13', 'INTEGRITY', 'Duplicate payments (same vendor key, currency, amount and date)', 0,
           (SELECT COUNT(*) FROM (SELECT vendor_site_key, currency_key, payment_amount, payment_date FROM dbo.fact_fx_payment
                                  WHERE vendor_site_key IS NOT NULL GROUP BY vendor_site_key, currency_key, payment_amount, payment_date HAVING COUNT(*) > 1) q)
    /* ---------- amounts, conversion, scenario, sign ---------- */
    UNION ALL SELECT 'T14', 'INTEGRITY', 'Abnormal cash-flow amount (zero, or over 500 million JPY)', 0,
           (SELECT COUNT(*) FROM dbo.fact_cashflow WHERE amount_base = 0 OR ABS(amount_base) > 500000000)
    UNION ALL SELECT 'T15', 'INTEGRITY', 'Abnormal payment amount (zero or negative, or over 20 million JPY)', 0,
           (SELECT COUNT(*) FROM dbo.fact_fx_payment WHERE payment_amount <= 0 OR payment_amount_base > 20000000)
    UNION ALL SELECT 'T16', 'INTEGRITY', 'Currency conversion: |amount_original x fx_rate - amount_base| above 1 JPY', 0,
           (SELECT COUNT(*) FROM dbo.fact_cashflow WHERE ABS(amount_original * fx_rate - amount_base) > 1)
    UNION ALL SELECT 'T17', 'INTEGRITY', 'Scenario other than Actual / Forecast', 0,
           (SELECT COUNT(*) FROM dbo.fact_cashflow WHERE scenario NOT IN ('Actual', 'Forecast'))
    UNION ALL SELECT 'T18', 'INTEGRITY', 'Sign contradicts category (inflow must be +, outflow must be -)', 0,
           (SELECT COUNT(*) FROM dbo.fact_cashflow f JOIN dbo.dim_cashflow_category k ON k.category_key = f.category_key
            WHERE (k.expected_sign = 1 AND f.amount_base < 0) OR (k.expected_sign = -1 AND f.amount_base > 0))
    /* ---------- payment control consistency ---------- */
    UNION ALL SELECT 'T19', 'INTEGRITY', 'Risk level contradicts exception code (Passed with exceptions, or exceptions marked Passed)', 0,
           (SELECT COUNT(*) FROM dbo.fact_payment_control
            WHERE (risk_level = 'Passed' AND (exception_count > 0 OR exception_code IS NOT NULL)) OR (risk_level <> 'Passed' AND exception_code IS NULL))
    UNION ALL SELECT 'T20', 'INTEGRITY', 'Risk level differs from the risk of the primary exception code', 0,
           (SELECT COUNT(*) FROM dbo.fact_payment_control c JOIN dbo.dim_exception_type t ON t.exception_code = c.exception_code WHERE c.risk_level <> t.risk_level)
    UNION ALL SELECT 'T21', 'INTEGRITY', 'Primary exception is not the most serious failed rule', 0,
           (SELECT COUNT(*) FROM dbo.fact_payment_control c
            JOIN dbo.dim_exception_type tp ON tp.exception_code = c.exception_code
            WHERE EXISTS (SELECT 1 FROM dbo.fact_payment_exception x JOIN dbo.dim_exception_type tx ON tx.exception_code = x.exception_code
                          WHERE x.payment_id = c.payment_id AND tx.priority_rank < tp.priority_rank))
    UNION ALL SELECT 'T22', 'INTEGRITY', 'SWIFT flag disagrees with exceptions (flag 0 must equal FX01 or FX04)', 0,
           (SELECT COUNT(*) FROM dbo.fact_payment_control c
            WHERE CASE WHEN c.swift_match_flag = 0 THEN 1 ELSE 0 END
               <> CASE WHEN EXISTS (SELECT 1 FROM dbo.fact_payment_exception x WHERE x.payment_id = c.payment_id AND x.exception_code IN ('FX01', 'FX04')) THEN 1 ELSE 0 END)
    UNION ALL SELECT 'T23', 'INTEGRITY', 'IBAN flag disagrees with exceptions (flag 0 must equal FX11 or FX19)', 0,
           (SELECT COUNT(*) FROM dbo.fact_payment_control c
            WHERE CASE WHEN c.iban_match_flag = 0 THEN 1 ELSE 0 END
               <> CASE WHEN EXISTS (SELECT 1 FROM dbo.fact_payment_exception x WHERE x.payment_id = c.payment_id AND x.exception_code IN ('FX11', 'FX19')) THEN 1 ELSE 0 END)
    UNION ALL SELECT 'T24', 'INTEGRITY', 'ERP account flag disagrees with exceptions (flag 0 must equal FX13)', 0,
           (SELECT COUNT(*) FROM dbo.fact_payment_control c
            WHERE CASE WHEN c.account_match_flag = 0 THEN 1 ELSE 0 END
               <> CASE WHEN EXISTS (SELECT 1 FROM dbo.fact_payment_exception x WHERE x.payment_id = c.payment_id AND x.exception_code = 'FX13') THEN 1 ELSE 0 END)
    /* ---------- import reconciliation ---------- */
    UNION ALL SELECT 'T25', 'INTEGRITY', 'Row count, cash flow: staging rows - loaded rows - rejected rows', 0,
           (SELECT COUNT(*) FROM dbo.stg_cashflow) - (SELECT COUNT(*) FROM dbo.fact_cashflow)
         - (SELECT COUNT(*) FROM dbo.rejected_record WHERE source_table = 'stg_cashflow')
    UNION ALL SELECT 'T26', 'INTEGRITY', 'Row count, payments: staging rows - loaded rows - rejected rows', 0,
           (SELECT COUNT(*) FROM dbo.stg_fx_payment) - (SELECT COUNT(*) FROM dbo.fact_fx_payment)
         - (SELECT COUNT(*) FROM dbo.rejected_record WHERE source_table = 'stg_fx_payment')
    /* ---------- cash position ---------- */
    UNION ALL SELECT 'T27', 'INTEGRITY', 'Closing cash on the last day = 745,000,000 JPY (cash summary sheet balance on 2026-10-31)', 745000000,
           (SELECT SUM(closing_balance_base) FROM dbo.vw_cash_position_daily WHERE full_date = (SELECT MAX(full_date) FROM dbo.vw_cash_position_daily))
    UNION ALL SELECT 'T28', 'INTEGRITY', 'Daily continuity: opening balance of a day differs from the previous closing', 0,
           (SELECT COUNT(*) FROM (SELECT opening_balance_base, LAG(closing_balance_base) OVER (PARTITION BY entity_key ORDER BY full_date) AS prev_closing
                                  FROM dbo.vw_cash_position_daily) q
            WHERE q.prev_closing IS NOT NULL AND ABS(q.opening_balance_base - q.prev_closing) > 0.01)
    UNION ALL SELECT 'T29', 'INTEGRITY', 'Days with a negative closing balance', 0,
           (SELECT COUNT(*) FROM dbo.vw_cash_position_daily WHERE closing_balance_base < 0)
    UNION ALL SELECT 'T30', 'INTEGRITY', 'Pooling sweeps that do not net to zero on a date', 0,
           (SELECT COUNT(*) FROM (SELECT f.transaction_date FROM dbo.fact_cashflow f JOIN dbo.dim_cashflow_category k ON k.category_key = f.category_key
                                  WHERE f.scenario = 'Actual' AND k.category_code = 'FIN_POOLING'
                                  GROUP BY f.transaction_date HAVING ABS(SUM(f.amount_base)) > 0.5) q)
    UNION ALL SELECT 'T31', 'INTEGRITY', 'Variance view total - (Actual total - Forecast total)', 0,
           (SELECT SUM(variance_base) FROM dbo.vw_cash_forecast_variance)
         - ((SELECT SUM(amount_base) FROM dbo.fact_cashflow WHERE scenario = 'Actual') - (SELECT SUM(amount_base) FROM dbo.fact_cashflow WHERE scenario = 'Forecast'))
    UNION ALL SELECT 'T32', 'INTEGRITY', 'Position view net flow total - Actual total', 0,
           (SELECT SUM(net_cash_flow_base) FROM dbo.vw_cash_position_daily) - (SELECT SUM(amount_base) FROM dbo.fact_cashflow WHERE scenario = 'Actual')
    UNION ALL SELECT 'T33', 'INTEGRITY', 'Month x entity without both Actual and Forecast lines', 0,
           (SELECT COUNT(*) FROM (SELECT year_month, entity_code FROM dbo.vw_cash_forecast_variance GROUP BY year_month, entity_code
                                  HAVING SUM(forecast_lines) = 0 OR SUM(actual_lines) = 0) q)
    UNION ALL SELECT 'T34', 'INTEGRITY', 'Payment control view row count - payment fact row count (LEFT JOIN must not drop payments)', 0,
           (SELECT COUNT(*) FROM dbo.vw_fx_payment_control) - (SELECT COUNT(*) FROM dbo.fact_fx_payment)
    UNION ALL SELECT 'T35', 'INTEGRITY', 'Vendor bank history: account still duplicated after de-duplication', 0,
           (SELECT COUNT(*) FROM (SELECT acct_norm FROM dbo.wrk_history_clean GROUP BY acct_norm HAVING COUNT(*) > 1) q)
    UNION ALL SELECT 'T36', 'INTEGRITY', 'exception_count in the control table differs from the rows in fact_payment_exception', 0,
           (SELECT COUNT(*) FROM dbo.fact_payment_control c
            WHERE c.exception_count <> (SELECT COUNT(*) FROM dbo.fact_payment_exception x WHERE x.payment_id = c.payment_id))
    /* ---------- detection: the planted defects and events ---------- */
    UNION ALL SELECT 'D01', 'DETECTION', 'Planted: duplicate cash-flow reference rejected', 2,
           (SELECT COUNT(*) FROM dbo.rejected_record WHERE reject_reason = 'DUPLICATE_REF')
    UNION ALL SELECT 'D02', 'DETECTION', 'Planted: unknown currency rejected', 1,
           (SELECT COUNT(*) FROM dbo.rejected_record WHERE reject_reason = 'UNKNOWN_CURRENCY')
    UNION ALL SELECT 'D03', 'DETECTION', 'Planted: missing amount rejected', 1,
           (SELECT COUNT(*) FROM dbo.rejected_record WHERE reject_reason = 'NULL_AMOUNT')
    UNION ALL SELECT 'D04', 'DETECTION', 'Planted: impossible date rejected', 1,
           (SELECT COUNT(*) FROM dbo.rejected_record WHERE reject_reason = 'INVALID_DATE')
    UNION ALL SELECT 'D05', 'DETECTION', 'Planted: unknown entity rejected', 1,
           (SELECT COUNT(*) FROM dbo.rejected_record WHERE reject_reason = 'UNKNOWN_ENTITY')
    UNION ALL SELECT 'D06', 'DETECTION', 'Payments that could not be tied to a vendor stay in the fact (2 without key + 1 unknown key)', 3,
           (SELECT COUNT(*) FROM dbo.fact_fx_payment WHERE vendor_key IS NULL)
    UNION ALL SELECT 'D07', 'DETECTION', 'Planted: unknown vendor site key raises FX25', 1,
           (SELECT COUNT(*) FROM dbo.fact_payment_exception WHERE exception_code = 'FX25')
    UNION ALL SELECT 'D08', 'DETECTION', 'Planted event: ENT3 March USD trade receipts short-paid -> Large variance', 1,
           (SELECT COUNT(*) FROM dbo.vw_cash_forecast_variance WHERE entity_code = 'ENT3' AND year_month = '2026-03' AND currency_code = 'USD'
                  AND category_code = 'RCPT_TRADE' AND variance_status = 'Large variance')
    UNION ALL SELECT 'D09', 'DETECTION', 'Planted event: ENT1 September trade payments delayed -> Not realised (JPY, USD, EUR)', 3,
           (SELECT COUNT(*) FROM dbo.vw_cash_forecast_variance WHERE entity_code = 'ENT1' AND year_month = '2026-09' AND category_code = 'PAY_TRADE'
                  AND variance_status = 'Not realised')
    UNION ALL SELECT 'D10', 'DETECTION', 'Planted event: ENT4 July GBP receipts never arrived -> Not realised', 1,
           (SELECT COUNT(*) FROM dbo.vw_cash_forecast_variance WHERE entity_code = 'ENT4' AND year_month = '2026-07' AND currency_code = 'GBP'
                  AND category_code = 'RCPT_TRADE' AND variance_status = 'Not realised')
    UNION ALL SELECT 'D11', 'DETECTION', 'Planted event: ENT2 June unplanned repair -> Large variance on expenses', 1,
           (SELECT COUNT(*) FROM dbo.vw_cash_forecast_variance WHERE entity_code = 'ENT2' AND year_month = '2026-06' AND category_code = 'PAY_EXPENSE'
                  AND variance_status = 'Large variance')
) t
ORDER BY t.test_id;
-- @@PORTABLE_END
