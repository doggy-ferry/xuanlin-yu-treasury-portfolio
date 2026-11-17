/* =====================================================================
   03_transform.sql  (SQL Server)
   Staging -> typed work tables -> facts.

   Part A  clears the targets (portable SQL)
   Part B  parses and standardises the raw text into the wrk_* tables (T-SQL specific: TRY_CONVERT, TRIM, LEFT, +)
   Part C  business rules: facts, exceptions, control flags (portable SQL; the SQLite build reuses it unchanged)

   Standardisation done here: TRIM, UPPER, spaces removed from account numbers, empty text -> NULL, text -> DATE / DECIMAL
   (unparseable values become NULL and the row is rejected, never silently changed), account numbers masked.
   Nothing is deleted without a trace: every cash-flow row that is not loaded is written to rejected_record with a reason.
   ===================================================================== */
USE TreasurySqlPortfolio;
GO
SET NOCOUNT ON;

-- @@PRELUDE_BEGIN
DELETE FROM dbo.fact_payment_control;
DELETE FROM dbo.fact_payment_exception;
DELETE FROM dbo.fact_fx_payment;
DELETE FROM dbo.fact_cashflow;
DELETE FROM dbo.rejected_record;
DELETE FROM dbo.wrk_payment_enriched;
DELETE FROM dbo.wrk_payment_clean;
DELETE FROM dbo.wrk_history_clean;
DELETE FROM dbo.wrk_invoice_clean;
DELETE FROM dbo.wrk_ap_clean;
DELETE FROM dbo.wrk_cashflow_clean;
-- @@PRELUDE_END
GO

-- @@DIALECT_BEGIN
/* ---------------- B1. cash-flow staging -> wrk_cashflow_clean ---------------- */
INSERT INTO dbo.wrk_cashflow_clean (row_id, transaction_ref, txn_date, entity_key, currency_key, category_key, scenario,
                                    amount_original, fx_rate, amount_base, source_type, memo, reject_reason)
SELECT x.row_id, x.transaction_ref, x.txn_date, x.entity_key, x.currency_key, x.category_key, x.scenario,
       x.amount_original, x.fx_rate, x.amount_base, x.source_type, x.memo,
       CASE WHEN x.dup_rank > 1                  THEN 'DUPLICATE_REF'      -- same reference seen before: keep the first
            WHEN x.txn_date IS NULL              THEN 'INVALID_DATE'       -- not a date, or outside the calendar
            WHEN x.entity_key IS NULL            THEN 'UNKNOWN_ENTITY'
            WHEN x.currency_key IS NULL          THEN 'UNKNOWN_CURRENCY'
            WHEN x.category_key IS NULL          THEN 'UNKNOWN_CATEGORY'
            WHEN x.scenario IS NULL              THEN 'INVALID_SCENARIO'
            WHEN x.amount_original IS NULL OR x.fx_rate IS NULL OR x.amount_base IS NULL THEN 'NULL_AMOUNT'
       END
FROM (
    SELECT s.row_id,
           NULLIF(TRIM(s.transaction_ref), '') AS transaction_ref,
           d.full_date                         AS txn_date,
           e.entity_key, c.currency_key, k.category_key,
           CASE UPPER(TRIM(s.scenario_raw)) WHEN 'ACTUAL' THEN 'Actual' WHEN 'FORECAST' THEN 'Forecast' END AS scenario,
           TRY_CONVERT(DECIMAL(18,2), NULLIF(TRIM(s.amount_original_raw), '')) AS amount_original,
           TRY_CONVERT(DECIMAL(18,6), NULLIF(TRIM(s.fx_rate_raw), ''))         AS fx_rate,
           TRY_CONVERT(DECIMAL(18,2), NULLIF(TRIM(s.amount_base_raw), ''))     AS amount_base,
           NULLIF(TRIM(s.source_type), '') AS source_type,
           NULLIF(TRIM(s.memo), '')        AS memo,
           ROW_NUMBER() OVER (PARTITION BY NULLIF(TRIM(s.transaction_ref), '') ORDER BY s.row_id) AS dup_rank
    FROM dbo.stg_cashflow s
    LEFT JOIN dbo.dim_date d              ON d.full_date     = TRY_CONVERT(DATE, NULLIF(TRIM(s.transaction_date_raw), ''), 23)
    LEFT JOIN dbo.dim_entity e            ON e.entity_code   = UPPER(TRIM(s.entity_code_raw))
    LEFT JOIN dbo.dim_currency c          ON c.currency_code = UPPER(TRIM(s.currency_code_raw))
    LEFT JOIN dbo.dim_cashflow_category k ON k.category_code = UPPER(TRIM(s.category_code_raw))
) x;

/* ---------------- B2. ERP schedule, invoices ---------------- */
INSERT INTO dbo.wrk_ap_clean (row_id, account, currency_code, due_date, scheduled_amount, bop_code, supplier_code)
SELECT row_id,
       UPPER(REPLACE(TRIM(bank_account_raw), ' ', '')),
       UPPER(TRIM(currency_code_raw)),
       TRY_CONVERT(DATE, NULLIF(TRIM(payment_due_date_raw), ''), 23),
       TRY_CONVERT(DECIMAL(18,2), NULLIF(TRIM(scheduled_amount_raw), '')),
       NULLIF(TRIM(bop_code_raw), ''),
       NULLIF(UPPER(TRIM(supplier_code)), '')
FROM dbo.stg_ap_schedule;

INSERT INTO dbo.wrk_invoice_clean (row_id, invoice_no, currency_code, invoice_amount, bop_code)
SELECT row_id,
       NULLIF(UPPER(TRIM(invoice_no)), ''),
       UPPER(TRIM(currency_code_raw)),
       TRY_CONVERT(DECIMAL(18,2), NULLIF(TRIM(invoice_amount_raw), '')),
       NULLIF(TRIM(bop_code_raw), '')
FROM dbo.stg_invoice;

/* ---------------- B3. payment instructions -> wrk_payment_clean ---------------- */
INSERT INTO dbo.wrk_payment_clean (row_id, payment_id, payment_date, entity_code, vendor_site_key, currency_code, payment_amount,
                                   name_norm, name_display, acct_norm, acct_masked, iban_masked, is_iban, bank_name, bank_country,
                                   swift_full, swift8, swift3, bene_country, city, bop_code, purp_code, invoice_no)
SELECT y.row_id, y.payment_id, y.payment_date, y.entity_code, y.vendor_site_key, y.currency_code, y.payment_amount,
       y.name_norm, y.name_display, y.acct_norm,
       CASE WHEN LEN(y.acct_norm) > 8 THEN LEFT(y.acct_norm, 4) + '****' + RIGHT(y.acct_norm, 4) ELSE '****' END,
       CASE WHEN y.is_iban = 1 AND LEN(y.acct_norm) > 8 THEN LEFT(y.acct_norm, 4) + '****' + RIGHT(y.acct_norm, 4) END,
       y.is_iban, y.bank_name, y.bank_country,
       y.swift_full, NULLIF(SUBSTRING(y.swift_full, 1, 8), ''),
       CASE WHEN y.swift_full IS NULL THEN NULL ELSE COALESCE(NULLIF(SUBSTRING(y.swift_full, 9, 3), ''), 'XXX') END,
       y.bene_country, y.city, y.bop_code, y.purp_code, y.invoice_no
FROM (
    SELECT s.row_id,
           UPPER(TRIM(s.payment_ref))                                AS payment_id,
           TRY_CONVERT(DATE, NULLIF(TRIM(s.payment_date_raw), ''), 23) AS payment_date,
           COALESCE(a.entity_code, UPPER(TRIM(s.entity_code_raw)))   AS entity_code,    -- alias: a legal entity code -> ENT1
           NULLIF(UPPER(TRIM(s.vendor_site_key_raw)), '')            AS vendor_site_key,
           UPPER(TRIM(s.currency_code_raw))                          AS currency_code,
           TRY_CONVERT(DECIMAL(18,2), NULLIF(TRIM(s.payment_amount_raw), '')) AS payment_amount,
           UPPER(TRIM(s.beneficiary_name_raw))                       AS name_norm,
           TRIM(s.beneficiary_name_raw)                              AS name_display,
           UPPER(REPLACE(TRIM(s.beneficiary_account_raw), ' ', ''))  AS acct_norm,
           CASE WHEN SUBSTRING(UPPER(REPLACE(TRIM(s.beneficiary_account_raw), ' ', '')), 1, 1) BETWEEN 'A' AND 'Z'
                 AND SUBSTRING(UPPER(REPLACE(TRIM(s.beneficiary_account_raw), ' ', '')), 2, 1) BETWEEN 'A' AND 'Z' THEN 1 ELSE 0 END AS is_iban,
           NULLIF(TRIM(s.bank_name_raw), '')                         AS bank_name,
           NULLIF(UPPER(TRIM(s.bank_country_raw)), '')               AS bank_country,
           NULLIF(UPPER(TRIM(s.swift_raw)), '')                      AS swift_full,
           NULLIF(UPPER(TRIM(s.beneficiary_country_raw)), '')        AS bene_country,
           NULLIF(TRIM(s.city_raw), '')                              AS city,
           NULLIF(TRIM(s.bop_code_raw), '')                          AS bop_code,
           NULLIF(TRIM(s.purp_code_raw), '')                         AS purp_code,
           NULLIF(UPPER(TRIM(s.invoice_no_raw)), '')                 AS invoice_no
    FROM dbo.stg_fx_payment s
    LEFT JOIN dbo.ref_entity_alias a ON a.alias_code = UPPER(TRIM(s.entity_code_raw))
) y;
GO

/* ---------------- B4. helper view: one row per payment with everything the rules need ---------------- */
DROP VIEW IF EXISTS dbo.vw_payment_rule_base;
GO
CREATE VIEW dbo.vw_payment_rule_base AS
SELECT c.payment_id, c.currency_code, c.payment_amount, c.is_iban, c.acct_norm, c.name_norm, c.bank_name, c.bank_country,
       c.swift8, c.swift3, c.bene_country, c.city, c.vendor_site_key, c.purp_code,
       e.hist_key, e.name_in_history, e.hist_cur_cnt, e.cur_in_hist, e.hist_bop_cnt, e.bop_in_hist, e.iban_expected_len,
       e.sched_amount, e.sched_cnt, e.instr_total, e.bop_in_erp, e.inv_total, e.inv_blank_bop, e.inv_distinct_bop,
       h.name_norm AS h_name, h.bank_name AS h_bank_name, h.bank_country AS h_bank_country, h.swift8 AS h_swift8, h.swift3 AS h_swift3,
       h.bene_country AS h_bene_country, h.city AS h_city,
       f.vendor_key
FROM dbo.fact_fx_payment f
JOIN dbo.wrk_payment_clean c    ON c.payment_id = f.payment_id
JOIN dbo.wrk_payment_enriched e ON e.payment_id = f.payment_id
LEFT JOIN dbo.wrk_history_clean h ON h.history_key = e.hist_key;
GO
-- @@DIALECT_END

-- @@PORTABLE_BEGIN
/* ---------------- C1. cash-flow facts and the reject list ---------------- */
INSERT INTO dbo.rejected_record (reject_id, source_table, source_row_id, source_ref, reject_reason, detail)
SELECT ROW_NUMBER() OVER (ORDER BY w.row_id), 'stg_cashflow', w.row_id, w.transaction_ref, w.reject_reason, w.memo
FROM dbo.wrk_cashflow_clean w
WHERE w.reject_reason IS NOT NULL;

INSERT INTO dbo.fact_cashflow (transaction_id, transaction_ref, transaction_date, entity_key, currency_key, category_key, scenario,
                               amount_original, fx_rate, amount_base, source_type, memo)
SELECT ROW_NUMBER() OVER (ORDER BY w.row_id), w.transaction_ref, w.txn_date, w.entity_key, w.currency_key, w.category_key, w.scenario,
       w.amount_original, w.fx_rate, w.amount_base, w.source_type, w.memo
FROM dbo.wrk_cashflow_clean w
WHERE w.reject_reason IS NULL;

/* ---------------- C2. vendor bank history: de-duplicate by account, keep the first row ---------------- */
INSERT INTO dbo.wrk_history_clean (history_key, name_norm, acct_norm, bank_name, bank_country, swift8, swift3, bene_country, city)
SELECT h.history_key, UPPER(TRIM(h.beneficiary_name)), h.acct_norm, NULLIF(TRIM(h.bank_name), ''), NULLIF(UPPER(TRIM(h.bank_country)), ''),
       NULLIF(SUBSTRING(UPPER(TRIM(h.swift_code)), 1, 8), ''),
       CASE WHEN NULLIF(TRIM(h.swift_code), '') IS NULL THEN NULL ELSE COALESCE(NULLIF(SUBSTRING(UPPER(TRIM(h.swift_code)), 9, 3), ''), 'XXX') END,
       NULLIF(UPPER(TRIM(h.beneficiary_country)), ''), NULLIF(TRIM(h.city), '')
FROM (SELECT r.history_key, r.beneficiary_name, r.bank_name, r.bank_country, r.swift_code, r.beneficiary_country, r.city,
             UPPER(REPLACE(TRIM(r.account_iban), ' ', '')) AS acct_norm,
             ROW_NUMBER() OVER (PARTITION BY UPPER(REPLACE(TRIM(r.account_iban), ' ', '')) ORDER BY r.history_key) AS rn
      FROM dbo.ref_vendor_bank_history r) h
WHERE h.rn = 1;

/* ---------------- C3. payments the model cannot place (unknown entity / currency / date) go to the reject list, not nowhere ---------------- */
INSERT INTO dbo.rejected_record (reject_id, source_table, source_row_id, source_ref, reject_reason, detail)
SELECT (SELECT COALESCE(MAX(r.reject_id), 0) FROM dbo.rejected_record r) + ROW_NUMBER() OVER (ORDER BY c.row_id),
       'stg_fx_payment', c.row_id, c.payment_id,
       CASE WHEN c.payment_date IS NULL OR d.date_key IS NULL THEN 'INVALID_DATE'
            WHEN en.entity_key IS NULL THEN 'UNKNOWN_ENTITY' ELSE 'UNKNOWN_CURRENCY' END,
       NULL
FROM dbo.wrk_payment_clean c
LEFT JOIN dbo.dim_date d       ON d.full_date = c.payment_date
LEFT JOIN dbo.dim_entity en    ON en.entity_code = c.entity_code
LEFT JOIN dbo.dim_currency cu  ON cu.currency_code = c.currency_code
WHERE d.date_key IS NULL OR en.entity_key IS NULL OR cu.currency_key IS NULL;

/* ---------------- C4. enrich: history, ERP schedule, invoices (correlated look-ups, one row per payment) ---------------- */
INSERT INTO dbo.wrk_payment_enriched (payment_id, hist_key, name_in_history, hist_cur_cnt, cur_in_hist, hist_bop_cnt, bop_in_hist, iban_expected_len,
                                      sched_amount, sched_cnt, instr_total, bop_in_erp, inv_total, inv_blank_bop, inv_distinct_bop)
SELECT c.payment_id,
       h.history_key,
       CASE WHEN EXISTS (SELECT 1 FROM dbo.wrk_history_clean x WHERE x.name_norm = c.name_norm) THEN 1 ELSE 0 END,
       (SELECT COUNT(*) FROM dbo.ref_history_currency hc WHERE hc.history_key = h.history_key),
       CASE WHEN EXISTS (SELECT 1 FROM dbo.ref_history_currency hc WHERE hc.history_key = h.history_key AND hc.currency_code = c.currency_code) THEN 1 ELSE 0 END,
       (SELECT COUNT(*) FROM dbo.ref_history_bop hb WHERE hb.history_key = h.history_key),
       CASE WHEN EXISTS (SELECT 1 FROM dbo.ref_history_bop hb WHERE hb.history_key = h.history_key AND hb.bop_code = c.bop_code) THEN 1 ELSE 0 END,
       il.iban_length,
       (SELECT SUM(a.scheduled_amount) FROM dbo.wrk_ap_clean a WHERE a.account = c.acct_norm AND a.currency_code = c.currency_code AND a.due_date = c.payment_date),
       (SELECT COUNT(*)                FROM dbo.wrk_ap_clean a WHERE a.account = c.acct_norm AND a.currency_code = c.currency_code AND a.due_date = c.payment_date),
       (SELECT SUM(p.payment_amount)   FROM dbo.wrk_payment_clean p WHERE p.acct_norm = c.acct_norm AND p.currency_code = c.currency_code AND p.payment_date = c.payment_date),
       CASE WHEN EXISTS (SELECT 1 FROM dbo.wrk_ap_clean a WHERE a.account = c.acct_norm AND a.bop_code = c.bop_code) THEN 1 ELSE 0 END,
       (SELECT SUM(i.invoice_amount)   FROM dbo.wrk_invoice_clean i WHERE i.invoice_no = c.invoice_no AND i.currency_code = c.currency_code),
       (SELECT COUNT(*)                FROM dbo.wrk_invoice_clean i WHERE i.invoice_no = c.invoice_no AND i.currency_code = c.currency_code AND i.bop_code IS NULL),
       (SELECT COUNT(DISTINCT i.bop_code) FROM dbo.wrk_invoice_clean i WHERE i.invoice_no = c.invoice_no AND i.currency_code = c.currency_code AND i.bop_code IS NOT NULL)
FROM dbo.wrk_payment_clean c
LEFT JOIN dbo.wrk_history_clean h ON h.acct_norm = c.acct_norm
LEFT JOIN dbo.ref_iban_length il  ON il.country_code = SUBSTRING(c.acct_norm, 1, 2) AND c.is_iban = 1;

/* ---------------- C5. payment facts: LEFT JOIN on the vendor, so an unmatched vendor stays visible ---------------- */
INSERT INTO dbo.fact_fx_payment (payment_id, payment_date, entity_key, vendor_key, currency_key, vendor_site_key, invoice_no, request_amount,
                                 scheduled_amount, payment_amount, payment_amount_base, beneficiary_name, beneficiary_account_masked, iban_masked,
                                 swift_code, bank_name, bank_country, bop_code, payment_status)
SELECT c.payment_id, c.payment_date, en.entity_key, v.vendor_key, cu.currency_key, c.vendor_site_key, c.invoice_no, e.inv_total,
       e.sched_amount, c.payment_amount, ROUND(c.payment_amount * cu.reference_rate_jpy, 2), c.name_display, c.acct_masked, c.iban_masked,
       c.swift_full, c.bank_name, c.bank_country, c.bop_code, 'Pending'
FROM dbo.wrk_payment_clean c
JOIN dbo.dim_date d             ON d.full_date = c.payment_date
JOIN dbo.dim_entity en          ON en.entity_code = c.entity_code
JOIN dbo.dim_currency cu        ON cu.currency_code = c.currency_code
JOIN dbo.wrk_payment_enriched e ON e.payment_id = c.payment_id
LEFT JOIN dbo.dim_vendor v      ON v.vendor_site_key = c.vendor_site_key
WHERE c.payment_amount IS NOT NULL;

/* ---------------- C6. every failed rule, one row each (a payment can fail several) ---------------- */
INSERT INTO dbo.fact_payment_exception (payment_id, exception_code)
SELECT r.payment_id, r.exception_code
FROM (
    SELECT payment_id, 'FX02' AS exception_code FROM dbo.vw_payment_rule_base WHERE hist_key IS NULL AND name_in_history = 1
    UNION ALL SELECT payment_id, 'FX03' FROM dbo.vw_payment_rule_base WHERE hist_key IS NULL AND name_in_history = 0
    UNION ALL SELECT payment_id, 'FX01' FROM dbo.vw_payment_rule_base WHERE hist_key IS NOT NULL AND swift8 IS NULL
    UNION ALL SELECT payment_id, 'FX04' FROM dbo.vw_payment_rule_base
              WHERE hist_key IS NOT NULL AND swift8 IS NOT NULL AND h_swift8 IS NOT NULL AND (swift8 <> h_swift8 OR swift3 <> h_swift3)
    UNION ALL SELECT payment_id, 'FX05' FROM dbo.vw_payment_rule_base
              WHERE hist_key IS NOT NULL AND h_bank_country IS NOT NULL AND h_bank_country <> COALESCE(bank_country, '')
    UNION ALL SELECT payment_id, 'FX06' FROM dbo.vw_payment_rule_base
              WHERE hist_key IS NOT NULL AND h_bank_name IS NOT NULL AND UPPER(h_bank_name) <> UPPER(COALESCE(bank_name, ''))
    UNION ALL SELECT payment_id, 'FX07' FROM dbo.vw_payment_rule_base WHERE hist_key IS NOT NULL AND hist_cur_cnt > 0 AND cur_in_hist = 0
    UNION ALL SELECT payment_id, 'FX08' FROM dbo.vw_payment_rule_base WHERE hist_key IS NOT NULL AND hist_bop_cnt > 0 AND bop_in_hist = 0
    UNION ALL SELECT payment_id, 'FX09' FROM dbo.vw_payment_rule_base
              WHERE hist_key IS NOT NULL AND h_bene_country IS NOT NULL AND h_bene_country <> COALESCE(bene_country, '')
    UNION ALL SELECT payment_id, 'FX10' FROM dbo.vw_payment_rule_base
              WHERE hist_key IS NOT NULL AND h_city IS NOT NULL AND UPPER(h_city) <> UPPER(COALESCE(city, ''))
    UNION ALL SELECT payment_id, 'FX24' FROM dbo.vw_payment_rule_base WHERE hist_key IS NOT NULL AND h_name <> COALESCE(name_norm, '')
    UNION ALL SELECT payment_id, 'FX11' FROM dbo.vw_payment_rule_base
              WHERE is_iban = 1 AND SUBSTRING(acct_norm, 1, 2) <> COALESCE(bank_country, '')
    UNION ALL SELECT payment_id, 'FX19' FROM dbo.vw_payment_rule_base
              WHERE is_iban = 1 AND SUBSTRING(acct_norm, 1, 2) = bank_country AND iban_expected_len IS NOT NULL AND LEN(acct_norm) <> iban_expected_len
    UNION ALL SELECT payment_id, 'FX12' FROM dbo.vw_payment_rule_base WHERE bank_country = 'CN' AND currency_code = 'CNY' AND purp_code IS NULL
    UNION ALL SELECT payment_id, 'FX13' FROM dbo.vw_payment_rule_base WHERE sched_cnt = 0
    UNION ALL SELECT payment_id, 'FX20' FROM dbo.vw_payment_rule_base
              WHERE sched_cnt > 0 AND ROUND(COALESCE(instr_total, 0) - COALESCE(sched_amount, 0), 2) <> 0
    UNION ALL SELECT payment_id, 'FX14' FROM dbo.vw_payment_rule_base WHERE bop_in_erp = 0
    UNION ALL SELECT payment_id, 'FX25' FROM dbo.vw_payment_rule_base WHERE vendor_site_key IS NOT NULL AND vendor_key IS NULL
    UNION ALL SELECT payment_id, 'FX22' FROM dbo.vw_payment_rule_base WHERE sched_cnt > 0 AND (inv_blank_bop > 0 OR inv_distinct_bop > 3)
    UNION ALL SELECT payment_id, 'FX23' FROM dbo.vw_payment_rule_base
              WHERE sched_cnt > 0 AND NOT (inv_blank_bop > 0 OR inv_distinct_bop > 3) AND ROUND(COALESCE(inv_total, 0) - payment_amount, 2) <> 0
) r;

/* ---------------- C7. control row per payment: check flags + ONE primary exception for dashboards ---------------- */
WITH ranked AS (
    SELECT x.payment_id, x.exception_code, t.exception_category, t.risk_level,
           ROW_NUMBER() OVER (PARTITION BY x.payment_id ORDER BY t.priority_rank) AS rn,
           COUNT(*)     OVER (PARTITION BY x.payment_id)                          AS n_failed
    FROM dbo.fact_payment_exception x
    JOIN dbo.dim_exception_type t ON t.exception_code = x.exception_code
)
INSERT INTO dbo.fact_payment_control (payment_id, vendor_history_match_flag, account_match_flag, amount_match_flag, currency_match_flag,
                                      swift_match_flag, iban_match_flag, bank_match_flag, bop_match_flag, invoice_match_flag,
                                      exception_count, exception_code, exception_category, risk_level, review_status)
SELECT b.payment_id,
       CASE WHEN b.hist_key IS NOT NULL THEN 1 ELSE 0 END,
       CASE WHEN b.sched_cnt > 0 THEN 1 ELSE 0 END,
       CASE WHEN b.sched_cnt = 0 THEN NULL WHEN ROUND(COALESCE(b.instr_total, 0) - COALESCE(b.sched_amount, 0), 2) = 0 THEN 1 ELSE 0 END,
       CASE WHEN b.hist_key IS NULL OR b.hist_cur_cnt = 0 THEN NULL WHEN b.cur_in_hist = 1 THEN 1 ELSE 0 END,
       CASE WHEN b.hist_key IS NULL THEN NULL
            WHEN b.swift8 IS NULL THEN 0
            WHEN b.h_swift8 IS NULL THEN NULL
            WHEN b.swift8 = b.h_swift8 AND b.swift3 = b.h_swift3 THEN 1 ELSE 0 END,
       CASE WHEN b.is_iban = 0 THEN NULL
            WHEN SUBSTRING(b.acct_norm, 1, 2) <> COALESCE(b.bank_country, '') THEN 0
            WHEN b.iban_expected_len IS NOT NULL AND LEN(b.acct_norm) <> b.iban_expected_len THEN 0 ELSE 1 END,
       CASE WHEN b.hist_key IS NULL THEN NULL
            WHEN (b.h_bank_country IS NOT NULL AND b.h_bank_country <> COALESCE(b.bank_country, ''))
              OR (b.h_bank_name IS NOT NULL AND UPPER(b.h_bank_name) <> UPPER(COALESCE(b.bank_name, ''))) THEN 0 ELSE 1 END,
       CASE WHEN b.bop_in_erp = 0 OR (b.hist_key IS NOT NULL AND b.hist_bop_cnt > 0 AND b.bop_in_hist = 0) THEN 0 ELSE 1 END,
       CASE WHEN b.sched_cnt = 0 THEN NULL
            WHEN (b.inv_blank_bop > 0 OR b.inv_distinct_bop > 3) OR ROUND(COALESCE(b.inv_total, 0) - b.payment_amount, 2) <> 0 THEN 0 ELSE 1 END,
       COALESCE(r.n_failed, 0),
       r.exception_code,
       r.exception_category,
       CASE WHEN r.risk_level IS NULL THEN 'Passed' ELSE r.risk_level END,
       CASE WHEN r.risk_level = 'High' THEN 'Hold for confirmation' WHEN r.risk_level = 'Medium' THEN 'Review required' ELSE 'Passed defined checks' END
FROM dbo.vw_payment_rule_base b
LEFT JOIN ranked r ON r.payment_id = b.payment_id AND r.rn = 1;
-- @@PORTABLE_END
GO
