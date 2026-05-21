-- ============================================================
-- Data Quality Report: stg_jobs
-- T-SQL version for Fabric Warehouse (translated from Week 2 MySQL DQ)
-- Read-only profiling. Does NOT modify data.
-- Run after 02_finalize_salary, before building mart layer.
-- ============================================================

-- ----- CHECK 1: Row count & PK uniqueness -----
SELECT
    '1. PK uniqueness'                                  AS check_name,
    COUNT(*)                                            AS total_rows,
    COUNT(DISTINCT job_id)                              AS distinct_job_ids,
    COUNT(*) - COUNT(DISTINCT job_id)                   AS duplicate_pks,
    CASE WHEN COUNT(*) = COUNT(DISTINCT job_id)
         THEN 'PASS' ELSE 'FAIL' END                    AS status
FROM dbo.stg_jobs;

-- ----- CHECK 2: NULL completeness of key fields -----
-- SUM(col IS NULL) → COUNT(*) - COUNT(col) is the cleanest T-SQL idiom
SELECT
    '2. NULL completeness'                              AS check_name,
    COUNT(*)                                            AS total,
    COUNT(*) - COUNT(title)                             AS null_title,
    COUNT(*) - COUNT(company_name)                      AS null_company,
    COUNT(*) - COUNT(state)                             AS null_state,
    COUNT(*) - COUNT(posted_date)                       AS null_posted_date,
    SUM(CASE WHEN description_clean IS NULL OR description_clean = '' THEN 1 ELSE 0 END) AS null_description
FROM dbo.stg_jobs;

-- ----- CHECK 3: Location hierarchy completeness -----
-- SUM(col IS NOT NULL) → COUNT(col)
SELECT
    '3. Location completeness'                          AS check_name,
    COUNT(*)                                            AS total,
    COUNT(country)                                      AS has_country,
    COUNT(state)                                        AS has_state,
    COUNT(region)                                       AS has_region,
    COUNT(city)                                         AS has_city,
    COUNT(suburb)                                       AS has_suburb,
    ROUND(100.0 * (COUNT(*) - COUNT(state)) / COUNT(*), 1) AS pct_missing_state
FROM dbo.stg_jobs;

-- ----- CHECK 4: Date validity -----
-- CURDATE() → CAST(GETDATE() AS DATE)
SELECT
    '4. Date validity'                                  AS check_name,
    COUNT(*)                                            AS total,
    COUNT(*) - COUNT(posted_date)                       AS failed_parse,
    SUM(CASE WHEN posted_date > CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) AS future_dates,
    MIN(posted_date)                                    AS earliest,
    MAX(posted_date)                                    AS latest,
    CASE WHEN (COUNT(*) - COUNT(posted_date)) = 0
        AND SUM(CASE WHEN posted_date > CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) = 0
         THEN 'PASS' ELSE 'REVIEW' END                  AS status
FROM dbo.stg_jobs;

-- ----- CHECK 5b: Fuzzy duplicate detection (tightened) -----
-- ⚠ DATEDIFF signature is different in T-SQL:
--   MySQL: DATEDIFF(end, start)           → days
--   T-SQL: DATEDIFF(DAY, start, end)      → days  (unit required, args swapped)
SELECT
    '5b. Fuzzy dup (tightened)'                         AS check_name,
    COUNT(*)                                            AS fuzzy_dup_pairs,
    ROUND(100.0 * COUNT(*) /
        (SELECT COUNT(*)
    FROM dbo.stg_jobs), 1)         AS pct_of_total
FROM (
    SELECT
        a.job_id AS id_a,
        b.job_id AS id_b
    FROM dbo.stg_jobs a
        JOIN dbo.stg_jobs b
        ON  a.title_normalized   = b.title_normalized
            AND a.company_normalized = b.company_normalized
            AND a.state              = b.state
            AND a.suburb             = b.suburb
            AND a.job_id < b.job_id
            AND ABS(DATEDIFF(DAY, b.posted_date, a.posted_date)) <= 7
) AS tight_pairs;

-- ----- CHECK 6: Category diversity -----
SELECT
    '6. Category diversity'                             AS check_name,
    category_tag,
    COUNT(*)                                            AS job_count,
    ROUND(100.0 * COUNT(*) /
        (SELECT COUNT(*)
    FROM dbo.stg_jobs), 1)         AS pct
FROM dbo.stg_jobs
GROUP BY category_tag
ORDER BY job_count DESC;

-- ----- CHECK 7: Salary availability -----
SELECT
    '7. Salary availability'                            AS check_name,
    COUNT(*)                                            AS total,
    COUNT(salary_min_api)                               AS has_api_salary_min,
    COUNT(salary_max_api)                               AS has_api_salary_max,
    ROUND(100.0 * (COUNT(*) - COUNT(salary_min_api)) / COUNT(*), 1) AS pct_missing_api_salary,
    SUM(CASE WHEN description_clean LIKE '%$%' THEN 1 ELSE 0 END) AS desc_contains_dollar
FROM dbo.stg_jobs;