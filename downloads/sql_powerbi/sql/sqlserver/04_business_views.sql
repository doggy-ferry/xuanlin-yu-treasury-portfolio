/* =====================================================================
   04_business_views.sql  (SQL Server)
   Four analysis views. Power BI and the demo queries read these; the logic lives here, not in the report.

   vw_cash_position_daily         one row per entity and calendar day: opening, inflow, outflow, closing  (Actual only, JPY)
   vw_cash_forecast_variance      one row per month, entity, currency, category: Actual vs Forecast and the variance
   vw_fx_payment_control          one row per payment: amounts, check flags, primary exception, risk level
   vw_payment_exception_summary   payments and amounts by exception category and risk level

   Rules: amounts in different currencies are never added in original currency; JPY (amount_base) is the cross-currency total.
   Variance = Actual - Forecast. Variance % divides by NULLIF(...), so a zero forecast gives NULL instead of an error.
   ===================================================================== */
USE TreasurySqlPortfolio;
GO

-- @@PORTABLE_BEGIN
CREATE OR ALTER VIEW dbo.vw_cash_position_daily AS
WITH bounds AS (
    SELECT MIN(ob.balance_date) AS start_date,
           (SELECT MAX(f.transaction_date) FROM dbo.fact_cashflow f WHERE f.scenario = 'Actual') AS end_date
    FROM dbo.fact_opening_balance ob
),
cal AS (                                                        -- every entity on every day, so days without flows still show a balance
    SELECT d.date_key, d.full_date, d.year_month, e.entity_key, e.entity_code
    FROM dbo.dim_date d
    CROSS JOIN dbo.dim_entity e
    CROSS JOIN bounds b
    WHERE d.full_date BETWEEN b.start_date AND b.end_date
),
flows AS (                                                      -- aggregate to the join grain BEFORE joining (no fan-out)
    SELECT f.transaction_date, f.entity_key,
           SUM(CASE WHEN f.amount_base > 0 THEN f.amount_base ELSE 0 END) AS inflow_base,
           SUM(CASE WHEN f.amount_base < 0 THEN f.amount_base ELSE 0 END) AS outflow_base,
           COUNT(*) AS transaction_count
    FROM dbo.fact_cashflow f
    WHERE f.scenario = 'Actual'
    GROUP BY f.transaction_date, f.entity_key
),
daily AS (
    SELECT cal.date_key, cal.full_date, cal.year_month, cal.entity_key, cal.entity_code,
           COALESCE(fl.inflow_base, 0)  AS inflow_base,
           COALESCE(fl.outflow_base, 0) AS outflow_base,
           COALESCE(fl.transaction_count, 0) AS transaction_count,
           SUM(COALESCE(fl.inflow_base, 0) + COALESCE(fl.outflow_base, 0))
               OVER (PARTITION BY cal.entity_key ORDER BY cal.full_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_net_base
    FROM cal
    LEFT JOIN flows fl ON fl.transaction_date = cal.full_date AND fl.entity_key = cal.entity_key
)
SELECT d.date_key, d.full_date, d.year_month, d.entity_key, d.entity_code,
       ob.amount_base + d.cumulative_net_base - (d.inflow_base + d.outflow_base) AS opening_balance_base,
       d.inflow_base,
       d.outflow_base,
       d.inflow_base + d.outflow_base                                            AS net_cash_flow_base,
       ob.amount_base + d.cumulative_net_base                                    AS closing_balance_base,
       d.transaction_count
FROM daily d
JOIN dbo.fact_opening_balance ob ON ob.entity_key = d.entity_key;
GO

CREATE OR ALTER VIEW dbo.vw_cash_forecast_variance AS
WITH g AS (                                                     -- one row per month x entity x currency x category, Actual and Forecast side by side
    SELECT d.year_month, f.entity_key, f.currency_key, f.category_key,
           SUM(CASE WHEN f.scenario = 'Forecast' THEN f.amount_original ELSE 0 END) AS forecast_amount_original,
           SUM(CASE WHEN f.scenario = 'Actual'   THEN f.amount_original ELSE 0 END) AS actual_amount_original,
           SUM(CASE WHEN f.scenario = 'Forecast' THEN f.amount_base ELSE 0 END)     AS forecast_amount_base,
           SUM(CASE WHEN f.scenario = 'Actual'   THEN f.amount_base ELSE 0 END)     AS actual_amount_base,
           SUM(CASE WHEN f.scenario = 'Forecast' THEN 1 ELSE 0 END)                 AS forecast_lines,
           SUM(CASE WHEN f.scenario = 'Actual'   THEN 1 ELSE 0 END)                 AS actual_lines
    FROM dbo.fact_cashflow f
    JOIN dbo.dim_date d ON d.full_date = f.transaction_date
    GROUP BY d.year_month, f.entity_key, f.currency_key, f.category_key
)
SELECT g.year_month, e.entity_code, e.entity_name, c.currency_code, k.category_code, k.category_name, k.category_group,
       g.forecast_amount_original, g.actual_amount_original,
       g.actual_amount_original - g.forecast_amount_original                                   AS variance_original,   -- same currency, so it can be added within one currency
       g.forecast_amount_base, g.actual_amount_base,
       g.actual_amount_base - g.forecast_amount_base                                           AS variance_base,
       (g.actual_amount_base - g.forecast_amount_base) * 1.0 / NULLIF(ABS(g.forecast_amount_base), 0) AS variance_pct,
       g.forecast_lines, g.actual_lines,
       CASE WHEN g.forecast_lines = 0 THEN 'Unplanned'
            WHEN g.actual_lines   = 0 THEN 'Not realised'
            WHEN ABS(g.actual_amount_base - g.forecast_amount_base) >= 3000000
             AND ABS(g.actual_amount_base - g.forecast_amount_base) * 1.0 / NULLIF(ABS(g.forecast_amount_base), 0) >= 0.2 THEN 'Large variance'
            ELSE 'Within range' END                                                            AS variance_status
FROM g
JOIN dbo.dim_entity e            ON e.entity_key = g.entity_key
JOIN dbo.dim_currency c          ON c.currency_key = g.currency_key
JOIN dbo.dim_cashflow_category k ON k.category_key = g.category_key;
GO

CREATE OR ALTER VIEW dbo.vw_fx_payment_control AS
SELECT p.payment_id, p.payment_date, p.entity_key, p.currency_key, p.vendor_key,       -- keys for the Power BI star schema
       en.entity_code,
       COALESCE(v.vendor_name, 'Unmatched vendor')                       AS vendor_name,
       p.vendor_site_key,
       CASE WHEN p.vendor_key IS NULL THEN 0 ELSE 1 END                  AS vendor_matched_flag,
       cu.currency_code,
       p.request_amount, p.scheduled_amount, p.payment_amount, p.payment_amount_base,
       p.beneficiary_name, p.beneficiary_account_masked, p.iban_masked, p.swift_code, p.bank_name, p.bank_country, p.bop_code, p.invoice_no,
       c.vendor_history_match_flag, c.account_match_flag, c.amount_match_flag, c.currency_match_flag, c.swift_match_flag,
       c.iban_match_flag, c.bank_match_flag, c.bop_match_flag, c.invoice_match_flag,
       c.exception_count, c.exception_code, t.exception_name, c.exception_category, c.risk_level, c.review_status
FROM dbo.fact_fx_payment p
JOIN dbo.fact_payment_control c   ON c.payment_id = p.payment_id
JOIN dbo.dim_entity en            ON en.entity_key = p.entity_key
JOIN dbo.dim_currency cu          ON cu.currency_key = p.currency_key
LEFT JOIN dbo.dim_vendor v        ON v.vendor_key = p.vendor_key                -- LEFT: an unmatched vendor must not drop the payment
LEFT JOIN dbo.dim_exception_type t ON t.exception_code = c.exception_code;
GO

CREATE OR ALTER VIEW dbo.vw_payment_exception_summary AS
SELECT COALESCE(c.exception_category, 'None')                         AS exception_category,
       c.risk_level,
       COALESCE(c.exception_code, '-')                                AS exception_code,
       COALESCE(t.exception_name, 'Passed defined checks')            AS exception_name,
       COUNT(*)                                                       AS payment_count,
       SUM(p.payment_amount_base)                                     AS payment_amount_base,
       COUNT(*) * 1.0 / SUM(COUNT(*)) OVER ()                         AS share_of_payments,
       RANK() OVER (ORDER BY COUNT(*) DESC)                           AS volume_rank
FROM dbo.fact_payment_control c
JOIN dbo.fact_fx_payment p          ON p.payment_id = c.payment_id
LEFT JOIN dbo.dim_exception_type t  ON t.exception_code = c.exception_code
GROUP BY c.exception_category, c.risk_level, c.exception_code, t.exception_name;
GO
-- @@PORTABLE_END
