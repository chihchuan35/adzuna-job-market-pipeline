-- Transform: Load dimensions from stg_jobs
-- Order matters: all dims must be loaded BEFORE fact (FK dependency)
-- This script loads dim_company / dim_location / dim_date / dim_category
-- dim_skill is loaded separately (see skill extraction chunk)
-- Idempotent: TRUNCATE + INSERT pattern
--
-- NOTE: FK constraints require disabling checks during reload,
--       because TRUNCATE on a parent table is blocked while
--       fact references it. We reload in safe order instead.

USE adzuna_jobs;

-- Reload dims: clear fact first (child) so dim TRUNCATE is allowed
SET FOREIGN_KEY_CHECKS
= 0;
TRUNCATE TABLE bridge_job_skills;
TRUNCATE TABLE fact_job_postings;
TRUNCATE TABLE dim_company;
TRUNCATE TABLE dim_location;
TRUNCATE TABLE dim_date;
TRUNCATE TABLE dim_category;
SET FOREIGN_KEY_CHECKS
= 1;

-- ------------------------------------------------------------
-- 1. dim_company  (one row per distinct normalized company)
-- ------------------------------------------------------------
INSERT INTO dim_company
    (company_name, company_normalized)
SELECT
    MAX(company_name)            AS company_name,
    company_normalized
FROM stg_jobs
WHERE company_normalized IS NOT NULL
GROUP BY company_normalized;

-- ------------------------------------------------------------
-- 2. dim_location  (one row per distinct location combination)
--    location_key = concatenated hierarchy used for dedup
-- ------------------------------------------------------------
INSERT INTO dim_location
    (country, state, region, city, suburb, latitude, longitude, location_key)
SELECT
    country, state, region, city, suburb,
    MAX(latitude)  AS latitude,
    MAX(longitude) AS longitude,
    CONCAT_WS('|',
        COALESCE(country, ''), COALESCE(state, ''),
        COALESCE(region, ''),  COALESCE(city, ''),
        COALESCE(suburb, '')
    ) AS location_key
FROM stg_jobs
GROUP BY country, state, region, city, suburb;

-- ------------------------------------------------------------
-- 3. dim_date  (one row per distinct posted_date, with parts)
-- ------------------------------------------------------------
INSERT INTO dim_date
    (
    date_id, full_date, year, quarter, month, month_name,
    day_of_month, day_of_week, day_name, is_weekend
    )
SELECT DISTINCT
    CAST(DATE_FORMAT(posted_date, '%Y%m%d') AS UNSIGNED) AS date_id,
    posted_date                                          AS full_date,
    YEAR(posted_date)                                    AS year,
    QUARTER(posted_date)                                 AS quarter,
    MONTH(posted_date)                                   AS month,
    MONTHNAME(posted_date)                               AS month_name,
    DAYOFMONTH(posted_date)                              AS day_of_month,
    WEEKDAY(posted_date) + 1                              AS day_of_week,
    DAYNAME(posted_date)                                 AS day_name,
    CASE WHEN WEEKDAY(posted_date) >= 5 THEN 1 ELSE 0 END AS is_weekend
FROM stg_jobs
WHERE posted_date IS NOT NULL;

-- ------------------------------------------------------------
-- 4. dim_category  (one row per distinct category_tag)
-- ------------------------------------------------------------
INSERT INTO dim_category
    (category_tag, category_label)
SELECT
    category_tag,
    MAX(category_label) AS category_label
FROM stg_jobs
WHERE category_tag IS NOT NULL
GROUP BY category_tag;

-- ------------------------------------------------------------
-- 5. fact_job_postings  (grain: one row per job_id)
--    Dimension lookup: join staging to each dim to get surrogate keys
-- ------------------------------------------------------------
INSERT INTO fact_job_postings
    (
    job_id, title,
    company_id, location_id, date_id, category_id,
    salary_min, salary_max, salary_avg, has_salary,
    contract_type, contract_time, search_term_count
    )
SELECT
    s.job_id,
    s.title,
    dc.company_id,
    dl.location_id,
    dd.date_id,
    dcat.category_id,
    s.salary_min_final,
    s.salary_max_final,
    s.salary_avg_final,
    CASE WHEN s.salary_avg_final IS NOT NULL THEN 1 ELSE 0 END AS has_salary,
    s.contract_type,
    s.contract_time,
    s.search_term_count
FROM stg_jobs s
    LEFT JOIN dim_company dc
    ON s.company_normalized = dc.company_normalized
    LEFT JOIN dim_location dl
    ON dl.location_key = CONCAT_WS('|',
        COALESCE(s.country, ''), COALESCE(s.state, ''),
        COALESCE(s.region, ''),  COALESCE(s.city, ''),
        COALESCE(s.suburb, ''))
    LEFT JOIN dim_date dd
    ON dd.full_date = s.posted_date
    LEFT JOIN dim_category dcat
    ON s.category_tag = dcat.category_tag;

-- ------------------------------------------------------------
-- Verify: row counts + fact-dimension integrity
-- ------------------------------------------------------------
    SELECT 'dim_company'  AS tbl, COUNT(*) AS cnt
    FROM dim_company
UNION ALL
    SELECT 'dim_location', COUNT(*)
    FROM dim_location
UNION ALL
    SELECT 'dim_date', COUNT(*)
    FROM dim_date
UNION ALL
    SELECT 'dim_category', COUNT(*)
    FROM dim_category
UNION ALL
    SELECT 'fact_job_postings', COUNT(*)
    FROM fact_job_postings;

-- Integrity: any fact rows that failed to match a dimension?
SELECT
    'fact integrity'                        AS check_name,
    COUNT(*)                                AS total_facts,
    SUM(company_id  IS NULL)                AS missing_company,
    SUM(location_id IS NULL)                AS missing_location,
    SUM(date_id     IS NULL)                AS missing_date,
    SUM(category_id IS NULL)                AS missing_category
FROM fact_job_postings;