/* =====================================================================
   06_demo_queries.sql  (SQL Server)
   Eight short queries for an interview or a walkthrough. Each one shows one idea; read the comment first.
   ===================================================================== */
USE TreasurySqlPortfolio;
GO

-- @@PORTABLE_BEGIN
-- Q1  Monthly Actual vs Forecast by entity (JPY). GROUP BY on a view; variance and safe variance %.
SELECT year_month, entity_code,
       SUM(forecast_amount_base) AS forecast_base, SUM(actual_amount_base) AS actual_base,
       SUM(variance_base)        AS variance_base,
       SUM(variance_base) * 1.0 / NULLIF(ABS(SUM(forecast_amount_base)), 0) AS variance_pct
FROM dbo.vw_cash_forecast_variance
GROUP BY year_month, entity_code
ORDER BY year_month, entity_code;

-- Q2  The ten largest variances, with a rank. ROW_NUMBER() over an ordered set.
SELECT q.*
FROM (SELECT year_month, entity_code, currency_code, category_code, forecast_amount_base, actual_amount_base, variance_base, variance_status,
             ROW_NUMBER() OVER (ORDER BY ABS(variance_base) DESC) AS variance_rank
      FROM dbo.vw_cash_forecast_variance) q
WHERE q.variance_rank <= 10
ORDER BY q.variance_rank;

-- Q3  Three-month rolling net cash flow per entity. Window function with a frame; month totals come from a CTE.
WITH m AS (
    SELECT year_month, entity_code, SUM(net_cash_flow_base) AS net_base
    FROM dbo.vw_cash_position_daily
    GROUP BY year_month, entity_code
)
SELECT year_month, entity_code, net_base,
       SUM(net_base) OVER (PARTITION BY entity_code ORDER BY year_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_3m_net_base
FROM m
ORDER BY entity_code, year_month;

-- Q4  Month-end closing cash by entity. The last day of each month via ROW_NUMBER(), then totalled across entities.
WITH ranked AS (
    SELECT year_month, entity_code, closing_balance_base,
           ROW_NUMBER() OVER (PARTITION BY year_month, entity_code ORDER BY full_date DESC) AS rn
    FROM dbo.vw_cash_position_daily
)
SELECT year_month, SUM(closing_balance_base) AS closing_cash_base, COUNT(*) AS entities
FROM ranked
WHERE rn = 1
GROUP BY year_month
ORDER BY year_month;

-- Q5  Currency mix of Actual cash flow in JPY. Original-currency amounts are NOT added together; amount_base is.
SELECT c.currency_code,
       SUM(CASE WHEN f.amount_base > 0 THEN f.amount_base ELSE 0 END) AS inflow_base,
       SUM(CASE WHEN f.amount_base < 0 THEN f.amount_base ELSE 0 END) AS outflow_base,
       SUM(f.amount_base)                                             AS net_base
FROM dbo.fact_cashflow f
JOIN dbo.dim_currency c ON c.currency_key = f.currency_key
WHERE f.scenario = 'Actual'
GROUP BY c.currency_code
ORDER BY net_base DESC;

-- Q6  Payment exceptions by category and risk level, with share of all payments.
SELECT exception_category, risk_level, exception_code, payment_count, payment_amount_base, ROUND(share_of_payments * 100, 1) AS share_pct
FROM dbo.vw_payment_exception_summary
ORDER BY volume_rank, exception_code;

-- Q7  Payments that must be held for confirmation, largest first. One primary exception per payment, all failed rules counted.
SELECT payment_id, payment_date, entity_code, vendor_name, currency_code, payment_amount, payment_amount_base,
       exception_code, exception_name, exception_count
FROM dbo.vw_fx_payment_control
WHERE risk_level = 'High'
ORDER BY payment_amount_base DESC, payment_id;

-- Q8  Why LEFT JOIN matters: an INNER JOIN to the vendor master would silently drop unmatched payments.
SELECT (SELECT COUNT(*) FROM dbo.fact_fx_payment) AS payments_total,
       (SELECT COUNT(*) FROM dbo.fact_fx_payment p JOIN dbo.dim_vendor v ON v.vendor_key = p.vendor_key) AS with_inner_join,
       (SELECT COUNT(*) FROM dbo.fact_fx_payment p LEFT JOIN dbo.dim_vendor v ON v.vendor_key = p.vendor_key) AS with_left_join;
-- @@PORTABLE_END
