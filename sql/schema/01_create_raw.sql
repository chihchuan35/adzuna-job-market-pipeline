-- ============================================================
-- Raw Layer: stores complete JSON responses from Adzuna API
-- ============================================================
-- Design principles:
-- 1. Preserve original API data for idempotent reprocessing
-- 2. Index commonly queried fields for query performance
-- 3. Track ingestion metadata for debugging and auditing
-- ============================================================

USE adzuna_jobs;

CREATE TABLE
IF NOT EXISTS raw_jobs
(
    -- Primary identifiers
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    job_id VARCHAR
(50) NOT NULL COMMENT 'Adzuna unique job ID',

    -- Searchable fields extracted from JSON for fast queries
    title VARCHAR
(500),
    company_name VARCHAR
(255),
    location_display VARCHAR
(500),
    category_tag VARCHAR
(100),
    contract_type VARCHAR
(50),
    contract_time VARCHAR
(50),

    -- Salary fields (often NULL in Adzuna AU data)
    salary_min DECIMAL
(12, 2),
    salary_max DECIMAL
(12, 2),
    salary_is_predicted TINYINT,

    -- Geo coordinates for map visualisations
    latitude DECIMAL
(10, 6),
    longitude DECIMAL
(10, 6),

    -- Posting timestamps
    created_at DATETIME COMMENT 'When Adzuna posted the job',

    -- Full JSON payload as source of truth
    raw_data JSON NOT NULL COMMENT 'Complete API response for this job',

    -- ETL metadata
    search_term VARCHAR
(100) NOT NULL COMMENT 'Which keyword found this job',
    fetched_at DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT 'When we ingested it',

    -- Indexes for query performance
    UNIQUE KEY uk_job_search
(job_id, search_term),
    INDEX idx_created_at
(created_at),
    INDEX idx_company
(company_name),
    INDEX idx_category
(category_tag),
    INDEX idx_search_term
(search_term)
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='Raw layer: complete API responses from Adzuna';

-- Verify table created
SHOW
CREATE TABLE raw_jobs;