-- ============================================================
-- Transform: Load dimensions + fact from stg_jobs
-- T-SQL version for Fabric Warehouse (translated from Week 2 MySQL DML)
-- Order matters: all dims loaded BEFORE fact (FK dependency, though NOT ENFORCED here)
-- dim_skill + bridge_job_skills loaded separately in 05_load_skills
-- Idempotent: TRUNCATE + INSERT pattern
-- ============================================================

-- Fabric Warehouse FKs are NOT ENFORCED → no need for SET FOREIGN_KEY_CHECKS hack
-- TRUNCATE order (children first) kept as defensive practice / dependency docs
-- Fabric Warehouse: FKs (even NOT ENFORCED) block TRUNCATE at metadata level
-- Use DELETE FROM instead. IDENTITY counter won't reset across runs (harmless).
DELETE FROM dbo.bridge_job_skills;
DELETE FROM dbo.fact_job_postings;
DELETE FROM dbo.dim_company;
DELETE FROM dbo.dim_location;
DELETE FROM dbo.dim_date;
DELETE FROM dbo.dim_category;

-- ----- 1. dim_company (one row per distinct normalized company) -----
INSERT INTO dbo.dim_company
    (company_name, company_normalized)
SELECT
    MAX(company_name)   AS company_name,
    company_normalized
FROM dbo.stg_jobs
WHERE company_normalized IS NOT NULL
GROUP BY company_normalized;

-- ----- 2. dim_location (one row per distinct hierarchy combination) -----
INSERT INTO dbo.dim_location
    (country, state, region, city, suburb, latitude, longitude, location_key)
SELECT
    country, state, region, city, suburb,
    MAX(latitude)  AS latitude,
    MAX(longitude) AS longitude,
    CONCAT_WS('|',
        COALESCE(country, ''), COALESCE(state, ''),
        COALESCE(region,  ''), COALESCE(city,  ''),
        COALESCE(suburb,  '')
    ) AS location_key
FROM dbo.stg_jobs
GROUP BY country, state, region, city, suburb;

-- ----- 3. dim_date (one row per distinct posted_date, with parts) -----
-- NOTE: DATENAME returns English in default Fabric Warehouse sessions (us_english).
-- The CASE on DATENAME(WEEKDAY) is DATEFIRST-independent and stable across environments.
INSERT INTO dbo.dim_date
    (date_id, full_date, year, quarter, month, month_name,
    day_of_month, day_of_week, day_name, is_weekend)
SELECT DISTINCT
    CAST(CONVERT(VARCHAR(8), posted_date, 112) AS INT)  AS date_id,
    posted_date                                          AS full_date,
    YEAR(posted_date)                                    AS year,
    DATEPART(QUARTER, posted_date)                       AS quarter,
    MONTH(posted_date)                                   AS month,
    DATENAME(MONTH, posted_date)                         AS month_name,
    DAY(posted_date)                                     AS day_of_month,
    CASE DATENAME(WEEKDAY, posted_date)
        WHEN 'Monday'    THEN 1
        WHEN 'Tuesday'   THEN 2
        WHEN 'Wednesday' THEN 3
        WHEN 'Thursday'  THEN 4
        WHEN 'Friday'    THEN 5
        WHEN 'Saturday'  THEN 6
        WHEN 'Sunday'    THEN 7
    END                                                  AS day_of_week,
    DATENAME(WEEKDAY, posted_date)                       AS day_name,
    -- is_weekend: was DEFAULT 0 in MySQL DDL; set explicitly here
    CASE WHEN DATENAME(WEEKDAY, posted_date) IN ('Saturday', 'Sunday')
         THEN 1 ELSE 0 END                               AS is_weekend
FROM dbo.stg_jobs
WHERE posted_date IS NOT NULL;

-- ----- 4. dim_category (one row per distinct category_tag) -----
INSERT INTO dbo.dim_category
    (category_tag, category_label)
SELECT
    category_tag,
    MAX(category_label) AS category_label
FROM dbo.stg_jobs
WHERE category_tag IS NOT NULL
GROUP BY category_tag;

-- ----- 5. fact_job_postings (grain: one row per job_id) -----
-- Surrogate key lookup via LEFT JOIN on each dim's natural key
INSERT INTO dbo.fact_job_postings
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
    -- has_salary: was DEFAULT 0 in MySQL DDL; set explicitly here
    CASE WHEN s.salary_avg_final IS NOT NULL THEN 1 ELSE 0 END AS has_salary,
    s.contract_type,
    s.contract_time,
    s.search_term_count
FROM dbo.stg_jobs s
    LEFT JOIN dbo.dim_company dc
    ON s.company_normalized = dc.company_normalized
    LEFT JOIN dbo.dim_location dl
    ON dl.location_key = CONCAT_WS('|',
        COALESCE(s.country, ''), COALESCE(s.state, ''),
        COALESCE(s.region,  ''), COALESCE(s.city,  ''),
        COALESCE(s.suburb,  ''))
    LEFT JOIN dbo.dim_date dd
    ON dd.full_date = s.posted_date
    LEFT JOIN dbo.dim_category dcat
    ON s.category_tag = dcat.category_tag;

-- ============================================================
-- Verify: row counts (compare to Week 2 numbers)
-- ============================================================
    SELECT 'dim_company'        AS tbl, COUNT(*) AS cnt
    FROM dbo.dim_company
UNION ALL
    SELECT 'dim_location'             , COUNT(*)
    FROM dbo.dim_location
UNION ALL
    SELECT 'dim_date'                 , COUNT(*)
    FROM dbo.dim_date
UNION ALL
    SELECT 'dim_category'             , COUNT(*)
    FROM dbo.dim_category
UNION ALL
    SELECT 'fact_job_postings'        , COUNT(*)
    FROM dbo.fact_job_postings;

-- ============================================================
-- Integrity: any fact rows that failed to match a dimension?
-- (Week 2 documented "參照完整性 100%" → all 4 missing_* should be 0)
-- ============================================================
SELECT
    'fact integrity'                  AS check_name,
    COUNT(*)                          AS total_facts,
    COUNT(*) - COUNT(company_id)      AS missing_company,
    COUNT(*) - COUNT(location_id)     AS missing_location,
    COUNT(*) - COUNT(date_id)         AS missing_date,
    COUNT(*) - COUNT(category_id)     AS missing_category
FROM dbo.fact_job_postings;