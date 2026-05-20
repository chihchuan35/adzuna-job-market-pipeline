-- ============================================================
-- Transform: Load raw_jobs -> stg_jobs
-- T-SQL version for Fabric Warehouse (translated from Week 2 MySQL DML)
-- Source: [adzuna_bronze].[dbo].[raw_jobs] (Lakehouse, cross-DB query)
-- Target: dbo.stg_jobs (this Warehouse)
-- Expected output: 2,142 rows after dedup
-- ============================================================

-- Idempotent: clear staging before reload
TRUNCATE TABLE dbo.stg_jobs;

-- CTEs must come BEFORE the INSERT in T-SQL (opposite of MySQL)
WITH
    -- Step 1: aggregate all search_terms + fetch timestamps per job_id
    search_agg
    AS
    (
        SELECT
            job_id,
            -- JSON_ARRAYAGG → manual JSON array via STRING_AGG
            '[' + STRING_AGG('"' + search_term + '"', ',') + ']' AS search_terms,
            COUNT(DISTINCT search_term) AS search_term_count,
            MIN(fetched_at)             AS first_fetched_at,
            MAX(fetched_at)             AS last_fetched_at
        FROM [adzuna_bronze].[dbo].[raw_jobs]
        GROUP BY job_id
    ),
    -- Step 2: pick ONE representative raw row per job_id
    --         (tie-break by latest fetched_at then highest id)
    ranked
    AS
    (
        SELECT
            job_id,
            raw_data,
            ROW_NUMBER() OVER (
                PARTITION BY job_id
                ORDER BY fetched_at DESC, id DESC
            ) AS rn
        FROM [adzuna_bronze].[dbo].[raw_jobs]
    )

INSERT INTO dbo.stg_jobs
    (
    job_id, title, title_normalized, company_name, company_normalized,
    location_display, country, state, region, city, suburb, latitude, longitude,
    category_tag, category_label,
    contract_type, contract_time,
    salary_min_api, salary_max_api, salary_is_predicted,
    description_raw, description_clean, description_length,
    posted_at, posted_date, redirect_url,
    search_terms, search_term_count,
    first_fetched_at, last_fetched_at,
    transformed_at -- was DEFAULT CURRENT_TIMESTAMP in MySQL; set explicitly here
    )
SELECT
    rk.job_id,

    -- Core fields (JSON_UNQUOTE(JSON_EXTRACT(...)) → JSON_VALUE(...))
    JSON_VALUE(rk.raw_data, '$.title')                                AS title,
    LOWER(LTRIM(RTRIM(JSON_VALUE(rk.raw_data, '$.title'))))           AS title_normalized,
    JSON_VALUE(rk.raw_data, '$.company.display_name')                 AS company_name,
    LOWER(LTRIM(RTRIM(JSON_VALUE(rk.raw_data, '$.company.display_name')))) AS company_normalized,

    -- Location hierarchy (path indexing identical to MySQL)
    JSON_VALUE(rk.raw_data, '$.location.display_name')                AS location_display,
    JSON_VALUE(rk.raw_data, '$.location.area[0]')                     AS country,
    JSON_VALUE(rk.raw_data, '$.location.area[1]')                     AS state,
    JSON_VALUE(rk.raw_data, '$.location.area[2]')                     AS region,
    JSON_VALUE(rk.raw_data, '$.location.area[3]')                     AS city,
    -- suburb = last non-null element (reverse-COALESCE from depth 5 down to 0)
    COALESCE(
        JSON_VALUE(rk.raw_data, '$.location.area[5]'),
        JSON_VALUE(rk.raw_data, '$.location.area[4]'),
        JSON_VALUE(rk.raw_data, '$.location.area[3]'),
        JSON_VALUE(rk.raw_data, '$.location.area[2]'),
        JSON_VALUE(rk.raw_data, '$.location.area[1]'),
        JSON_VALUE(rk.raw_data, '$.location.area[0]')
    )                                                                  AS suburb,

    -- Geo (TRY_CAST safely returns NULL on malformed values)
    TRY_CAST(JSON_VALUE(rk.raw_data, '$.latitude')  AS DECIMAL(10,6)) AS latitude,
    TRY_CAST(JSON_VALUE(rk.raw_data, '$.longitude') AS DECIMAL(10,6)) AS longitude,

    -- Category
    JSON_VALUE(rk.raw_data, '$.category.tag')                         AS category_tag,
    JSON_VALUE(rk.raw_data, '$.category.label')                       AS category_label,

    -- Contract
    JSON_VALUE(rk.raw_data, '$.contract_type')                        AS contract_type,
    JSON_VALUE(rk.raw_data, '$.contract_time')                        AS contract_time,

    -- Salary (API native; UNSIGNED → SMALLINT)
    TRY_CAST(JSON_VALUE(rk.raw_data, '$.salary_min')           AS DECIMAL(12,2)) AS salary_min_api,
    TRY_CAST(JSON_VALUE(rk.raw_data, '$.salary_max')           AS DECIMAL(12,2)) AS salary_max_api,
    TRY_CAST(JSON_VALUE(rk.raw_data, '$.salary_is_predicted')  AS SMALLINT)      AS salary_is_predicted,

    -- Description: raw + lightweight cleanup
    JSON_VALUE(rk.raw_data, '$.description')                          AS description_raw,
    -- Original MySQL: TRIM(REGEXP_REPLACE(x, '\s+', ' '))
    -- Fabric Warehouse has no regex; substitute CR/LF/TAB with space + trim.
    -- True multi-space collapse not implemented (documented dialect limitation).
    LTRIM(RTRIM(
        REPLACE(REPLACE(REPLACE(
            JSON_VALUE(rk.raw_data, '$.description'),
            CHAR(13), ' '),
            CHAR(10), ' '),
            CHAR(9), ' ')
    ))                                                                AS description_clean,
    LEN(JSON_VALUE(rk.raw_data, '$.description'))                     AS description_length,

    -- Posting time: ISO-8601 → DATETIME2(6) directly (T-SQL parses ISO natively)
    TRY_CAST(JSON_VALUE(rk.raw_data, '$.created') AS DATETIME2(6))    AS posted_at,
    CAST(TRY_CAST(JSON_VALUE(rk.raw_data, '$.created') AS DATETIME2(6)) AS DATE) AS posted_date,
    JSON_VALUE(rk.raw_data, '$.redirect_url')                         AS redirect_url,

    -- Search context (from search_agg CTE)
    sa.search_terms,
    sa.search_term_count,

    -- ETL metadata
    sa.first_fetched_at,
    sa.last_fetched_at,
    -- transformed_at: was DEFAULT CURRENT_TIMESTAMP in MySQL; set explicitly here
    SYSUTCDATETIME()                                                  AS transformed_at

FROM ranked rk
    JOIN search_agg sa ON sa.job_id = rk.job_id
WHERE rk.rn = 1;

-- Verify load (expected: 2,142)
SELECT COUNT(*) AS staged_rows
FROM dbo.stg_jobs;

-- DQ snapshot (sanity checks, mirrors Week 2 verification)
SELECT
    COUNT(*)                                            AS total,
    COUNT(state)                                        AS has_state,
    COUNT(suburb)                                       AS has_suburb,
    COUNT(CASE WHEN search_term_count > 1 THEN 1 END)   AS multi_search_jobs,
    MAX(search_term_count)                              AS max_search_terms
FROM dbo.stg_jobs;