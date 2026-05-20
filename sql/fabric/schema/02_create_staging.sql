-- ============================================================
-- Staging Layer: cleaned and standardized job data
-- T-SQL version for Fabric Warehouse (translated from Week 2 MySQL DDL)
-- ============================================================

DROP TABLE IF EXISTS dbo.stg_jobs;

CREATE TABLE dbo.stg_jobs
(
    -- Primary key (one row per Adzuna job)
    job_id VARCHAR(50) NOT NULL,

    -- Core job attributes (cleaned)
    title VARCHAR(500) NULL,
    -- Lowercase, trimmed for matching
    title_normalized VARCHAR(500) NULL,
    company_name VARCHAR(255) NULL,
    -- Lowercase, trimmed for dim_company join
    company_normalized VARCHAR(255) NULL,

    -- Location hierarchy (parsed from location.area JSON array)
    location_display VARCHAR(500) NULL,
    country VARCHAR(100) NULL,
    state VARCHAR(100) NULL,
    region VARCHAR(150) NULL,
    city VARCHAR(150) NULL,
    suburb VARCHAR(150) NULL,
    latitude DECIMAL(10, 6) NULL,
    longitude DECIMAL(10, 6) NULL,

    -- Category (Adzuna's classification)
    category_tag VARCHAR(100) NULL,
    category_label VARCHAR(255) NULL,

    -- Contract info
    contract_type VARCHAR(50) NULL,
    contract_time VARCHAR(50) NULL,

    -- Salary (from API native fields)
    salary_min_api DECIMAL(12, 2) NULL,
    salary_max_api DECIMAL(12, 2) NULL,
    -- TINYINT → SMALLINT (Fabric Warehouse doesn't support TINYINT)
    salary_is_predicted SMALLINT NULL,

    -- Salary (extracted from description; per Week 2 decision, left NULL — API-only strategy)
    salary_min_extracted DECIMAL(12, 2) NULL,
    salary_max_extracted DECIMAL(12, 2) NULL,
    salary_period VARCHAR(20) NULL,
    -- Default 'AUD' applied at INSERT time, not in DDL (Fabric Warehouse limitation)
    salary_currency VARCHAR(10) NULL,

    -- Unified salary (coalesced: API value preferred, else extracted)
    salary_min_final DECIMAL(12, 2) NULL,
    salary_max_final DECIMAL(12, 2) NULL,
    salary_avg_final DECIMAL(12, 2) NULL,

    -- Description (cleaned)
    description_raw VARCHAR(MAX) NULL,
    description_clean VARCHAR(MAX) NULL,
    description_length INT NULL,

    -- Posting metadata
    -- DATETIME2 must specify precision 0-6 in Fabric Warehouse
    posted_at DATETIME2(6) NULL,
    posted_date DATE NULL,
    redirect_url VARCHAR(1000) NULL,

    -- Search context (denormalized — JSON stored as VARCHAR(MAX))
    search_terms VARCHAR(MAX) NULL,
    search_term_count INT NULL,

    -- ETL metadata
    first_fetched_at DATETIME2(6) NULL,
    last_fetched_at DATETIME2(6) NULL,
    -- Default SYSUTCDATETIME() applied at INSERT time, not in DDL
    transformed_at DATETIME2(6) NULL
);

-- Primary key: declared but not enforced (Fabric Warehouse limitation)
ALTER TABLE dbo.stg_jobs
ADD CONSTRAINT PK_stg_jobs PRIMARY KEY NONCLUSTERED (job_id)
NOT ENFORCED;

-- Verify structure (expect 38 rows)
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'stg_jobs'
ORDER BY ORDINAL_POSITION;

SELECT COUNT(*) AS row_count
FROM dbo.stg_jobs;