-- ============================================================
-- Data Quality Report: stg_jobs
-- ============================================================
-- Read-only profiling. Does NOT modify data.
-- Run after 01_load_staging.sql, before building mart layer.
--
-- Each check outputs: check_name | metric | status
-- Review all results before proceeding to mart layer.
-- ============================================================

USE adzuna_jobs;

-- ------------------------------------------------------------
-- CHECK 1: Row count & uniqueness of primary key
-- Expectation: job_id is unique (dedup worked), 0 duplicates
-- ------------------------------------------------------------
SELECT
    '1. PK uniqueness'                                  AS check_name,
    COUNT(*)                                            AS total_rows,
    COUNT(DISTINCT job_id)                              AS distinct_job_ids,
    COUNT(*) - COUNT(DISTINCT job_id)                   AS duplicate_pks,
    CASE WHEN COUNT(*) = COUNT(DISTINCT job_id)
         THEN 'PASS' ELSE 'FAIL' END                    AS status
FROM stg_jobs;

-- ------------------------------------------------------------
-- CHECK 2: NULL completeness of key fields
-- Expectation: core fields mostly non-null; quantify gaps
-- ------------------------------------------------------------
SELECT
    '2. NULL completeness'                              AS check_name,
    COUNT(*)                                            AS total,
    SUM(title IS NULL)                                  AS null_title,
    SUM(company_name IS NULL)                            AS null_company,
    SUM(state IS NULL)                                  AS null_state,
    SUM(posted_date IS NULL)                             AS null_posted_date,
    SUM(description_clean IS NULL OR description_clean = '') AS null_description
FROM stg_jobs;

-- ------------------------------------------------------------
-- CHECK 3: Location hierarchy completeness
-- Expectation: documents the 228 country-only records found earlier
-- ------------------------------------------------------------
SELECT
    '3. Location completeness'                          AS check_name,
    COUNT(*)                                            AS total,
    SUM(country IS NOT NULL)                            AS has_country,
    SUM(state   IS NOT NULL)                            AS has_state,
    SUM(region  IS NOT NULL)                            AS has_region,
    SUM(city    IS NOT NULL)                            AS has_city,
    SUM(suburb  IS NOT NULL)                            AS has_suburb,
    ROUND(100.0 * SUM(state IS NULL) / COUNT(*), 1)     AS pct_missing_state
FROM stg_jobs;

-- ------------------------------------------------------------
-- CHECK 4: Date validity
-- Expectation: no NULLs from failed parse, no future dates
-- ------------------------------------------------------------
SELECT
    '4. Date validity'                                  AS check_name,
    COUNT(*)                                            AS total,
    SUM(posted_date IS NULL)                            AS failed_parse,
    SUM(posted_date > CURDATE())                        AS future_dates,
    MIN(posted_date)                                    AS earliest,
    MAX(posted_date)                                    AS latest,
    CASE WHEN SUM(posted_date IS NULL) = 0
        AND SUM(posted_date > CURDATE()) = 0
         THEN 'PASS' ELSE 'REVIEW' END                  AS status
FROM stg_jobs;

-- ------------------------------------------------------------
-- CHECK 5b: Fuzzy duplicate detection (TIGHTENED)
-- Adds suburb match + posted within 7 days of each other.
-- This narrows the loose 27.3% upper bound toward a credible
-- estimate of true Adzuna re-postings of the same job.
-- ------------------------------------------------------------
SELECT
    '5b. Fuzzy dup (tightened)'                         AS check_name,
    COUNT(*)                                            AS fuzzy_dup_pairs,
    ROUND(100.0 * COUNT(*) /
        (SELECT COUNT(*)
    FROM stg_jobs), 1)             AS pct_of_total
FROM (
    SELECT
        a.job_id AS id_a,
        b.job_id AS id_b
    FROM stg_jobs a
        JOIN stg_jobs b
        ON  a.title_normalized   = b.title_normalized
            AND a.company_normalized = b.company_normalized
            AND a.state              = b.state
            AND a.suburb             = b.suburb
            AND a.job_id < b.job_id
            AND ABS(DATEDIFF(a.posted_date, b.posted_date)) <= 7
) AS tight_pairs;
-- ------------------------------------------------------------
-- CHECK 6: Category diversity
-- Expectation: multiple categories (validates EDA finding)
-- ------------------------------------------------------------
SELECT
    '6. Category diversity'                             AS check_name,
    category_tag,
    COUNT(*)                                            AS job_count,
    ROUND(100.0 * COUNT(*) /
        (SELECT COUNT(*)
    FROM stg_jobs), 1)             AS pct
FROM stg_jobs
GROUP BY category_tag
ORDER BY job_count DESC;

-- ------------------------------------------------------------
-- CHECK 7: Salary availability (prep for next chunk: regex extraction)
-- Expectation: API salary mostly NULL -> justifies regex approach
-- ------------------------------------------------------------
SELECT
    '7. Salary availability'                            AS check_name,
    COUNT(*)                                            AS total,
    SUM(salary_min_api IS NOT NULL)                     AS has_api_salary_min,
    SUM(salary_max_api IS NOT NULL)                     AS has_api_salary_max,
    ROUND(100.0 * SUM(salary_min_api IS NULL) / COUNT(*), 1)
                                                        AS pct_missing_api_salary,
    SUM(description_clean LIKE '%$%')                    AS desc_contains_dollar
FROM stg_jobs;