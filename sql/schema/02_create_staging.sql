-- ============================================================
-- Staging Layer: cleaned and standardized job data
-- ============================================================
-- Design principles:
-- 1. One row per unique job_id (deduplicated across search_terms)
-- 2. Parsed location hierarchy (country -> state -> region -> city)
-- 3. Cleaned text fields (HTML stripped, whitespace normalized)
-- 4. Salary fields ready for mart layer (regex extraction from description)
-- 5. Preserves traceability back to raw layer via job_id
-- ============================================================

USE adzuna_jobs;

DROP TABLE IF EXISTS stg_jobs;

CREATE TABLE stg_jobs (
    -- Primary key (one row per Adzuna job)
    job_id              VARCHAR(50)     NOT NULL PRIMARY KEY,
    
    -- Core job attributes (cleaned)
    title               VARCHAR(500),
    title_normalized    VARCHAR(500)    COMMENT 'Lowercase, trimmed for matching',
    company_name        VARCHAR(255),
    company_normalized  VARCHAR(255)    COMMENT 'Lowercase, trimmed for dim_company join',
    
    -- Location hierarchy (parsed from location.area JSON array)
    location_display    VARCHAR(500)    COMMENT 'Full display string from API',
    country             VARCHAR(100)    COMMENT 'Level 0: e.g. Australia',
    state               VARCHAR(100)    COMMENT 'Level 1: e.g. South Australia',
    region              VARCHAR(150)    COMMENT 'Level 2: e.g. Adelaide',
    city                VARCHAR(150)    COMMENT 'Level 3: e.g. Adelaide CBD',
    suburb              VARCHAR(150)    COMMENT 'Level 4: most granular',
    latitude            DECIMAL(10, 6),
    longitude           DECIMAL(10, 6),
    
    -- Category (Adzuna's classification)
    category_tag        VARCHAR(100)    COMMENT 'Adzuna industry category',
    category_label      VARCHAR(255)    COMMENT 'Human-readable category name',
    
    -- Contract info
    contract_type       VARCHAR(50)     COMMENT 'permanent / contract',
    contract_time       VARCHAR(50)     COMMENT 'full_time / part_time',
    
    -- Salary (from API native fields)
    salary_min_api      DECIMAL(12, 2),
    salary_max_api      DECIMAL(12, 2),
    salary_is_predicted TINYINT,
    
    -- Salary (extracted from description via regex - filled in next chunk)
    salary_min_extracted DECIMAL(12, 2) COMMENT 'Parsed from description text',
    salary_max_extracted DECIMAL(12, 2) COMMENT 'Parsed from description text',
    salary_period       VARCHAR(20)     COMMENT 'annual / hourly / daily',
    salary_currency     VARCHAR(10)     DEFAULT 'AUD',
    
    -- Unified salary (coalesced: API value preferred, else extracted)
    salary_min_final    DECIMAL(12, 2),
    salary_max_final    DECIMAL(12, 2),
    salary_avg_final    DECIMAL(12, 2)  COMMENT '(min + max) / 2 for analysis',
    
    -- Description (cleaned)
    description_raw     TEXT            COMMENT 'Original description from API',
    description_clean   TEXT            COMMENT 'HTML stripped, whitespace normalized',
    description_length  INT             COMMENT 'Character count for DQ check',
    
    -- Posting metadata
    posted_at           DATETIME        COMMENT 'When Adzuna posted the job',
    posted_date         DATE            COMMENT 'Date portion for dim_date join',
    redirect_url        VARCHAR(1000)   COMMENT 'Link back to original posting',
    
    -- Search context (denormalized - which search_terms found this job)
    search_terms        JSON            COMMENT 'Array of search_terms that returned this job',
    search_term_count   INT             COMMENT 'How many search_terms matched (1-7)',
    
    -- ETL metadata
    first_fetched_at    DATETIME        COMMENT 'Earliest fetched_at across all raw rows',
    last_fetched_at     DATETIME        COMMENT 'Latest fetched_at across all raw rows',
    transformed_at      DATETIME        DEFAULT CURRENT_TIMESTAMP,
    
    -- Indexes for downstream mart loads
    INDEX idx_company   (company_normalized),
    INDEX idx_state     (state),
    INDEX idx_city      (city),
    INDEX idx_category  (category_tag),
    INDEX idx_posted    (posted_date),
    INDEX idx_salary    (salary_avg_final)
    
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='Staging layer: cleaned and parsed job data, one row per job_id';

-- Verify
SHOW CREATE TABLE stg_jobs;
SELECT COUNT(*) AS row_count FROM stg_jobs;