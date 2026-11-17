/* =====================================================================
   02_load_data.sql  (SQL Server)
   Loads data\processed\*.csv with BULK INSERT.

   $(DataDir) is a sqlcmd variable: the folder that holds the CSV files. The SQL Server SERVICE account must be able to read it
   (files under your own profile are usually NOT readable). scripts\run_sqlserver.ps1 copies the CSVs to a readable folder
   and substitutes the variable for you. With sqlcmd:   sqlcmd -S .\SQLEXPRESS -E -i 02_load_data.sql -v DataDir="C:\data"

   Empty text fields arrive as '' ; the cleanup at the end turns them into NULL.
   ===================================================================== */
USE TreasurySqlPortfolio;
GO
SET NOCOUNT ON;

-- reload from scratch: staging, reference and dimension tables are emptied in dependency order
DELETE FROM dbo.fact_payment_control;   DELETE FROM dbo.fact_payment_exception; DELETE FROM dbo.fact_fx_payment;
DELETE FROM dbo.fact_cashflow;          DELETE FROM dbo.fact_opening_balance;   DELETE FROM dbo.rejected_record;
DELETE FROM dbo.wrk_payment_enriched;   DELETE FROM dbo.wrk_payment_clean;      DELETE FROM dbo.wrk_history_clean;
DELETE FROM dbo.wrk_invoice_clean;      DELETE FROM dbo.wrk_ap_clean;           DELETE FROM dbo.wrk_cashflow_clean;
DELETE FROM dbo.stg_invoice;            DELETE FROM dbo.stg_ap_schedule;        DELETE FROM dbo.stg_fx_payment;   DELETE FROM dbo.stg_cashflow;
DELETE FROM dbo.ref_history_bop;        DELETE FROM dbo.ref_history_currency;   DELETE FROM dbo.ref_vendor_bank_history;
DELETE FROM dbo.ref_iban_length;        DELETE FROM dbo.ref_entity_alias;
DELETE FROM dbo.dim_vendor;             DELETE FROM dbo.dim_exception_type;     DELETE FROM dbo.dim_cashflow_category;
DELETE FROM dbo.dim_currency;           DELETE FROM dbo.dim_entity;             DELETE FROM dbo.dim_date;
GO

BULK INSERT dbo.dim_date               FROM '$(DataDir)\dim_date.csv'               WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.dim_entity             FROM '$(DataDir)\dim_entity.csv'             WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.dim_currency           FROM '$(DataDir)\dim_currency.csv'           WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.dim_cashflow_category  FROM '$(DataDir)\dim_cashflow_category.csv'  WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.dim_vendor             FROM '$(DataDir)\dim_vendor.csv'             WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.dim_exception_type     FROM '$(DataDir)\dim_exception_type.csv'     WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.ref_entity_alias       FROM '$(DataDir)\ref_entity_alias.csv'       WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.ref_iban_length        FROM '$(DataDir)\ref_iban_length.csv'        WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.ref_vendor_bank_history FROM '$(DataDir)\ref_vendor_bank_history.csv' WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.ref_history_currency   FROM '$(DataDir)\ref_history_currency.csv'   WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.ref_history_bop        FROM '$(DataDir)\ref_history_bop.csv'        WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.fact_opening_balance   FROM '$(DataDir)\fact_opening_balance.csv'   WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.stg_cashflow           FROM '$(DataDir)\stg_cashflow.csv'           WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.stg_fx_payment         FROM '$(DataDir)\stg_fx_payment.csv'         WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.stg_ap_schedule        FROM '$(DataDir)\stg_ap_schedule.csv'        WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
BULK INSERT dbo.stg_invoice            FROM '$(DataDir)\stg_invoice.csv'            WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', ROWTERMINATOR = '0x0a', CODEPAGE = '65001');
GO

-- empty text -> NULL in the reference and dimension tables (staging stays raw on purpose)
UPDATE dbo.dim_date SET holiday_name = NULLIF(holiday_name, '');
UPDATE dbo.dim_vendor SET source_note = NULLIF(source_note, '');
UPDATE dbo.ref_vendor_bank_history SET address = NULLIF(address, ''), bank_name = NULLIF(bank_name, ''), bank_address = NULLIF(bank_address, ''),
       swift_code = NULLIF(swift_code, ''), beneficiary_country = NULLIF(beneficiary_country, ''), city = NULLIF(city, ''),
       bank_country = NULLIF(bank_country, ''), note = NULLIF(note, ''), status = NULLIF(status, '');
GO
