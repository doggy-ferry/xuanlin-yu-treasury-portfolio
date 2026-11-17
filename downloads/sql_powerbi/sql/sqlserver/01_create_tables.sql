/* =====================================================================
   01_create_tables.sql  (SQL Server)
   Creates database TreasurySqlPortfolio and every table. Safe to run again: it drops and re-creates the tables.

   Layers
     dim_*    dimensions (who / what / when)
     ref_*    small reference tables (vendor bank history, IBAN lengths, entity alias)
     stg_*    staging: raw text exactly as received, no constraints on content
     wrk_*    work tables used by 03_transform.sql (cleaned and typed copies)
     fact_*   facts that the views and Power BI read
   Amount sign convention: inflow +, outflow -  (fact_cashflow.amount_base)
   ===================================================================== */
IF DB_ID('TreasurySqlPortfolio') IS NULL CREATE DATABASE TreasurySqlPortfolio;
GO
USE TreasurySqlPortfolio;
GO

DROP VIEW IF EXISTS dbo.vw_payment_exception_summary;
DROP VIEW IF EXISTS dbo.vw_fx_payment_control;
DROP VIEW IF EXISTS dbo.vw_cash_forecast_variance;
DROP VIEW IF EXISTS dbo.vw_cash_position_daily;
DROP TABLE IF EXISTS dbo.fact_payment_control;
DROP TABLE IF EXISTS dbo.fact_payment_exception;
DROP TABLE IF EXISTS dbo.fact_fx_payment;
DROP TABLE IF EXISTS dbo.fact_cashflow;
DROP TABLE IF EXISTS dbo.fact_opening_balance;
DROP TABLE IF EXISTS dbo.rejected_record;
DROP TABLE IF EXISTS dbo.wrk_payment_enriched;
DROP TABLE IF EXISTS dbo.wrk_payment_clean;
DROP TABLE IF EXISTS dbo.wrk_history_clean;
DROP TABLE IF EXISTS dbo.wrk_invoice_clean;
DROP TABLE IF EXISTS dbo.wrk_ap_clean;
DROP TABLE IF EXISTS dbo.wrk_cashflow_clean;
DROP TABLE IF EXISTS dbo.stg_invoice;
DROP TABLE IF EXISTS dbo.stg_ap_schedule;
DROP TABLE IF EXISTS dbo.stg_fx_payment;
DROP TABLE IF EXISTS dbo.stg_cashflow;
DROP TABLE IF EXISTS dbo.ref_history_bop;
DROP TABLE IF EXISTS dbo.ref_history_currency;
DROP TABLE IF EXISTS dbo.ref_vendor_bank_history;
DROP TABLE IF EXISTS dbo.ref_iban_length;
DROP TABLE IF EXISTS dbo.ref_entity_alias;
DROP TABLE IF EXISTS dbo.dim_vendor;
DROP TABLE IF EXISTS dbo.dim_exception_type;
DROP TABLE IF EXISTS dbo.dim_cashflow_category;
DROP TABLE IF EXISTS dbo.dim_currency;
DROP TABLE IF EXISTS dbo.dim_entity;
DROP TABLE IF EXISTS dbo.dim_date;
GO

/* ---------------- dimensions ---------------- */
CREATE TABLE dbo.dim_date (
    date_key        INT          NOT NULL PRIMARY KEY,          -- yyyymmdd
    full_date       DATE         NOT NULL UNIQUE,
    year_num        SMALLINT     NOT NULL,
    quarter_num     SMALLINT     NOT NULL,
    month_num       SMALLINT     NOT NULL,
    year_month      CHAR(7)      NOT NULL,                      -- 2026-03
    month_name      VARCHAR(12)  NOT NULL,
    weekday_name    VARCHAR(12)  NOT NULL,
    is_weekend      SMALLINT     NOT NULL,
    is_holiday      SMALLINT     NOT NULL,
    holiday_name    VARCHAR(80)  NULL,
    is_business_day SMALLINT     NOT NULL
);
CREATE TABLE dbo.dim_entity (
    entity_key                SMALLINT    NOT NULL PRIMARY KEY,
    entity_code               VARCHAR(10) NOT NULL UNIQUE,
    entity_name               VARCHAR(60) NOT NULL,
    functional_currency_code  CHAR(3)     NOT NULL
);
CREATE TABLE dbo.dim_currency (
    currency_key       SMALLINT      NOT NULL PRIMARY KEY,
    currency_code      CHAR(3)       NOT NULL UNIQUE,
    currency_name      VARCHAR(40)   NOT NULL,
    decimal_places     SMALLINT      NOT NULL,
    reference_rate_jpy DECIMAL(18,6) NOT NULL,                  -- planning rate, 1 unit of currency in JPY
    is_base            SMALLINT      NOT NULL
);
CREATE TABLE dbo.dim_cashflow_category (
    category_key   SMALLINT    NOT NULL PRIMARY KEY,
    category_code  VARCHAR(20) NOT NULL UNIQUE,
    category_name  VARCHAR(40) NOT NULL,
    direction      VARCHAR(10) NOT NULL,                        -- Inflow / Outflow / Funding
    category_group VARCHAR(20) NOT NULL,                        -- Receipts / Payments / Funding
    expected_sign  SMALLINT    NOT NULL CHECK (expected_sign IN (-1, 0, 1))
);
CREATE TABLE dbo.dim_vendor (
    vendor_key        INT          NOT NULL PRIMARY KEY,
    vendor_site_key   VARCHAR(20)  NOT NULL UNIQUE,             -- supplier code in the Excel workbook
    vendor_name       VARCHAR(80)  NOT NULL,
    beneficiary_name  VARCHAR(80)  NOT NULL,
    vendor_country    CHAR(2)      NOT NULL,
    source_note       VARCHAR(60)  NULL
);
CREATE TABLE dbo.dim_exception_type (
    exception_code     VARCHAR(6)   NOT NULL PRIMARY KEY,
    exception_name     VARCHAR(100) NOT NULL,
    exception_category VARCHAR(30)  NOT NULL,
    risk_level         VARCHAR(10)  NOT NULL CHECK (risk_level IN ('High', 'Medium')),
    priority_rank      SMALLINT     NOT NULL UNIQUE,            -- lower = more serious = wins when several checks fail
    excel_rule_ref     VARCHAR(40)  NULL
);

/* ---------------- reference tables ---------------- */
CREATE TABLE dbo.ref_entity_alias (
    alias_code  VARCHAR(10)  NOT NULL PRIMARY KEY,
    entity_code VARCHAR(10)  NOT NULL,
    note        VARCHAR(200) NULL
);
CREATE TABLE dbo.ref_iban_length (
    country_code CHAR(2)  NOT NULL PRIMARY KEY,
    iban_length  SMALLINT NOT NULL
);
CREATE TABLE dbo.ref_vendor_bank_history (
    history_key         INT          NOT NULL PRIMARY KEY,
    beneficiary_name    VARCHAR(80)  NOT NULL,
    account_iban        VARCHAR(40)  NOT NULL,
    address             VARCHAR(80)  NULL,
    bank_name           VARCHAR(60)  NULL,
    bank_address        VARCHAR(60)  NULL,
    swift_code          VARCHAR(11)  NULL,
    beneficiary_country CHAR(2)      NULL,
    city                VARCHAR(40)  NULL,
    bank_country        CHAR(2)      NULL,
    note                VARCHAR(60)  NULL,
    status              VARCHAR(20)  NULL
);
CREATE TABLE dbo.ref_history_currency (
    history_key   INT     NOT NULL REFERENCES dbo.ref_vendor_bank_history (history_key),
    currency_code CHAR(3) NOT NULL,
    PRIMARY KEY (history_key, currency_code)
);
CREATE TABLE dbo.ref_history_bop (
    history_key INT         NOT NULL REFERENCES dbo.ref_vendor_bank_history (history_key),
    bop_code    VARCHAR(6)  NOT NULL,
    PRIMARY KEY (history_key, bop_code)
);

/* ---------------- staging: raw text as received ---------------- */
CREATE TABLE dbo.stg_cashflow (
    row_id               INT          NOT NULL PRIMARY KEY,
    transaction_ref      VARCHAR(30)  NULL,
    transaction_date_raw VARCHAR(20)  NULL,
    entity_code_raw      VARCHAR(20)  NULL,
    currency_code_raw    VARCHAR(10)  NULL,
    category_code_raw    VARCHAR(30)  NULL,
    scenario_raw         VARCHAR(12)  NULL,
    amount_original_raw  VARCHAR(30)  NULL,
    fx_rate_raw          VARCHAR(20)  NULL,
    amount_base_raw      VARCHAR(30)  NULL,
    source_type          VARCHAR(20)  NULL,
    memo                 VARCHAR(120) NULL
);
CREATE TABLE dbo.stg_fx_payment (
    row_id                  INT          NOT NULL PRIMARY KEY,
    payment_ref             VARCHAR(12)  NULL,
    payment_date_raw        VARCHAR(20)  NULL,
    entity_code_raw         VARCHAR(20)  NULL,
    vendor_site_key_raw     VARCHAR(20)  NULL,
    currency_code_raw       VARCHAR(10)  NULL,
    payment_amount_raw      VARCHAR(30)  NULL,
    beneficiary_name_raw    VARCHAR(80)  NULL,
    beneficiary_account_raw VARCHAR(60)  NULL,
    bank_name_raw           VARCHAR(60)  NULL,
    bank_country_raw        VARCHAR(10)  NULL,
    swift_raw               VARCHAR(20)  NULL,
    beneficiary_country_raw VARCHAR(10)  NULL,
    city_raw                VARCHAR(40)  NULL,
    bop_code_raw            VARCHAR(10)  NULL,
    purp_code_raw           VARCHAR(20)  NULL,
    invoice_no_raw          VARCHAR(30)  NULL
);
CREATE TABLE dbo.stg_ap_schedule (
    row_id              INT         NOT NULL PRIMARY KEY,
    legal_entity_code   VARCHAR(10) NULL,
    payment_due_date_raw VARCHAR(20) NULL,
    supplier_code       VARCHAR(20) NULL,
    supplier_name       VARCHAR(80) NULL,
    currency_code_raw   VARCHAR(10) NULL,
    scheduled_amount_raw VARCHAR(30) NULL,
    bop_code_raw        VARCHAR(10) NULL,
    bank_account_raw    VARCHAR(60) NULL
);
CREATE TABLE dbo.stg_invoice (
    row_id              INT         NOT NULL PRIMARY KEY,
    invoice_no          VARCHAR(30) NULL,
    supplier_code       VARCHAR(20) NULL,
    currency_code_raw   VARCHAR(10) NULL,
    invoice_amount_raw  VARCHAR(30) NULL,
    bop_code_raw        VARCHAR(10) NULL
);

/* ---------------- work tables (typed, cleaned; refilled by 03_transform.sql) ---------------- */
CREATE TABLE dbo.wrk_cashflow_clean (
    row_id          INT PRIMARY KEY,
    transaction_ref VARCHAR(30)  NULL,
    txn_date        DATE         NULL,
    entity_key      SMALLINT     NULL,
    currency_key    SMALLINT     NULL,
    category_key    SMALLINT     NULL,
    scenario        VARCHAR(8)   NULL,
    amount_original DECIMAL(18,2) NULL,
    fx_rate         DECIMAL(18,6) NULL,
    amount_base     DECIMAL(18,2) NULL,
    source_type     VARCHAR(20)  NULL,
    memo            VARCHAR(120) NULL,
    reject_reason   VARCHAR(30)  NULL
);
CREATE TABLE dbo.wrk_ap_clean (
    row_id           INT PRIMARY KEY,
    account          VARCHAR(40)  NULL,
    currency_code    CHAR(3)      NULL,
    due_date         DATE         NULL,
    scheduled_amount DECIMAL(18,2) NULL,
    bop_code         VARCHAR(6)   NULL,
    supplier_code    VARCHAR(20)  NULL
);
CREATE TABLE dbo.wrk_invoice_clean (
    row_id         INT PRIMARY KEY,
    invoice_no     VARCHAR(30)  NULL,
    currency_code  CHAR(3)      NULL,
    invoice_amount DECIMAL(18,2) NULL,
    bop_code       VARCHAR(6)   NULL                              -- NULL = declaration missing
);
CREATE TABLE dbo.wrk_history_clean (
    history_key  INT PRIMARY KEY,
    name_norm    VARCHAR(80) NOT NULL,
    acct_norm    VARCHAR(40) NOT NULL,
    bank_name    VARCHAR(60) NULL,
    bank_country CHAR(2)     NULL,
    swift8       VARCHAR(8)  NULL,
    swift3       VARCHAR(3)  NULL,
    bene_country CHAR(2)     NULL,
    city         VARCHAR(40) NULL
);
CREATE TABLE dbo.wrk_payment_clean (
    row_id        INT PRIMARY KEY,
    payment_id    VARCHAR(12)  NOT NULL,
    payment_date  DATE         NULL,
    entity_code   VARCHAR(10)  NULL,
    vendor_site_key VARCHAR(20) NULL,
    currency_code CHAR(3)      NULL,
    payment_amount DECIMAL(18,2) NULL,
    name_norm     VARCHAR(80)  NULL,
    name_display  VARCHAR(80)  NULL,
    acct_norm     VARCHAR(40)  NULL,
    acct_masked   VARCHAR(40)  NULL,
    iban_masked   VARCHAR(40)  NULL,
    is_iban       SMALLINT     NOT NULL,
    bank_name     VARCHAR(60)  NULL,
    bank_country  CHAR(2)      NULL,
    swift_full    VARCHAR(11)  NULL,
    swift8        VARCHAR(8)   NULL,
    swift3        VARCHAR(3)   NULL,
    bene_country  CHAR(2)      NULL,
    city          VARCHAR(40)  NULL,
    bop_code      VARCHAR(6)   NULL,
    purp_code     VARCHAR(20)  NULL,
    invoice_no    VARCHAR(30)  NULL
);
CREATE TABLE dbo.wrk_payment_enriched (
    payment_id     VARCHAR(12)  NOT NULL PRIMARY KEY,
    hist_key       INT          NULL,
    name_in_history SMALLINT    NOT NULL,
    hist_cur_cnt   INT          NOT NULL,
    cur_in_hist    SMALLINT     NOT NULL,
    hist_bop_cnt   INT          NOT NULL,
    bop_in_hist    SMALLINT     NOT NULL,
    iban_expected_len SMALLINT  NULL,
    sched_amount   DECIMAL(18,2) NULL,
    sched_cnt      INT          NOT NULL,
    instr_total    DECIMAL(18,2) NULL,
    bop_in_erp     SMALLINT     NOT NULL,
    inv_total      DECIMAL(18,2) NULL,
    inv_blank_bop  INT          NOT NULL,
    inv_distinct_bop INT        NOT NULL
);

/* ---------------- facts ---------------- */
CREATE TABLE dbo.rejected_record (
    reject_id     INT          NOT NULL PRIMARY KEY,
    source_table  VARCHAR(30)  NOT NULL,
    source_row_id INT          NOT NULL,
    source_ref    VARCHAR(30)  NULL,
    reject_reason VARCHAR(30)  NOT NULL,
    detail        VARCHAR(120) NULL
);
CREATE TABLE dbo.fact_opening_balance (
    entity_key   SMALLINT      NOT NULL REFERENCES dbo.dim_entity (entity_key),
    balance_date DATE          NOT NULL REFERENCES dbo.dim_date (full_date),
    amount_base  DECIMAL(18,2) NOT NULL,                          -- JPY, balance before the first day's flows
    PRIMARY KEY (entity_key, balance_date)
);
CREATE TABLE dbo.fact_cashflow (
    transaction_id   INT           NOT NULL PRIMARY KEY,
    transaction_ref  VARCHAR(30)   NOT NULL UNIQUE,
    transaction_date DATE          NOT NULL REFERENCES dbo.dim_date (full_date),
    entity_key       SMALLINT      NOT NULL REFERENCES dbo.dim_entity (entity_key),
    currency_key     SMALLINT      NOT NULL REFERENCES dbo.dim_currency (currency_key),
    category_key     SMALLINT      NOT NULL REFERENCES dbo.dim_cashflow_category (category_key),
    scenario         VARCHAR(8)    NOT NULL CHECK (scenario IN ('Actual', 'Forecast')),
    amount_original  DECIMAL(18,2) NOT NULL,                      -- in the transaction currency; never add across currencies
    fx_rate          DECIMAL(18,6) NOT NULL,                      -- JPY per 1 unit of currency
    amount_base      DECIMAL(18,2) NOT NULL,                      -- JPY; use this for cross-currency totals
    source_type      VARCHAR(20)   NULL,
    memo             VARCHAR(120)  NULL
);
CREATE INDEX ix_fact_cashflow_date ON dbo.fact_cashflow (transaction_date, entity_key);
CREATE TABLE dbo.fact_fx_payment (
    payment_id                VARCHAR(12)   NOT NULL PRIMARY KEY,
    payment_date              DATE          NOT NULL REFERENCES dbo.dim_date (full_date),
    entity_key                SMALLINT      NOT NULL REFERENCES dbo.dim_entity (entity_key),
    vendor_key                INT           NULL REFERENCES dbo.dim_vendor (vendor_key),   -- NULL = could not be matched; the row is kept
    currency_key              SMALLINT      NOT NULL REFERENCES dbo.dim_currency (currency_key),
    vendor_site_key           VARCHAR(20)   NULL,                 -- key as received, kept for unmatched analysis
    invoice_no                VARCHAR(30)   NULL,
    request_amount            DECIMAL(18,2) NULL,                 -- invoice total (the request)
    scheduled_amount          DECIMAL(18,2) NULL,                 -- ERP AP schedule total (the plan)
    payment_amount            DECIMAL(18,2) NOT NULL,             -- the payment instruction
    payment_amount_base       DECIMAL(18,2) NOT NULL,             -- JPY at the planning rate
    beneficiary_name          VARCHAR(80)   NULL,
    beneficiary_account_masked VARCHAR(40)  NULL,
    iban_masked               VARCHAR(40)   NULL,
    swift_code                VARCHAR(11)   NULL,
    bank_name                 VARCHAR(60)   NULL,
    bank_country              CHAR(2)       NULL,
    bop_code                  VARCHAR(6)    NULL,
    payment_status            VARCHAR(20)   NOT NULL CHECK (payment_status IN ('Pending'))
);
CREATE TABLE dbo.fact_payment_exception (
    payment_id     VARCHAR(12) NOT NULL REFERENCES dbo.fact_fx_payment (payment_id),
    exception_code VARCHAR(6)  NOT NULL REFERENCES dbo.dim_exception_type (exception_code),
    PRIMARY KEY (payment_id, exception_code)
);
CREATE TABLE dbo.fact_payment_control (
    payment_id               VARCHAR(12) NOT NULL PRIMARY KEY REFERENCES dbo.fact_fx_payment (payment_id),
    vendor_history_match_flag SMALLINT NULL,       -- 1 = account found in history, 0 = not found
    account_match_flag       SMALLINT NULL,        -- 1 = ERP schedule found for account + currency + date
    amount_match_flag        SMALLINT NULL,        -- 1 = payment total equals ERP schedule total (NULL when no ERP match)
    currency_match_flag      SMALLINT NULL,        -- 1 = currency used before for this account (NULL when no history)
    swift_match_flag         SMALLINT NULL,        -- 1 = SWIFT agrees with history (0 also when missing)
    iban_match_flag          SMALLINT NULL,        -- 1 = IBAN country and length are valid (NULL when not an IBAN)
    bank_match_flag          SMALLINT NULL,        -- 1 = bank name and bank country agree with history
    bop_match_flag           SMALLINT NULL,        -- 1 = BOP code known to ERP and history
    invoice_match_flag       SMALLINT NULL,        -- 1 = invoice breakdown complete and total equals payment (NULL when no ERP match)
    exception_count          INT         NOT NULL, -- number of failed rules (all of them are in fact_payment_exception)
    exception_code           VARCHAR(6)  NULL REFERENCES dbo.dim_exception_type (exception_code),   -- primary (most serious) rule
    exception_category       VARCHAR(30) NULL,
    risk_level               VARCHAR(10) NOT NULL CHECK (risk_level IN ('High', 'Medium', 'Passed')),
    review_status            VARCHAR(30) NOT NULL
);
GO
