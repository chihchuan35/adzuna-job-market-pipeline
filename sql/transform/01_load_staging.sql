-- ============================================================
-- Transform: Load raw_jobs -> stg_jobs
-- ============================================================
-- This script:
-- 1. Deduplicates jobs (one job_id may appear under multiple search_terms)
-- 2. Extracts fields from raw_data JSON
-- 3. Parses location.area array into hierarchy levels
-- 4. Cleans text fields
-- NOTE: Salary regex extraction handled in next script (02_extract_salary.sql)
-- Idempotent: safe to re-run (TRUNCATE + INSERT pattern)
--
-- Dedup strategy:
--   Step 1 (CTE search_agg): aggregate search_terms per job_id
--   Step 2 (CTE ranked):     pick ONE representative raw row per job_id
--   Step 3 (INSERT):         join the two, parse the representative JSON
-- ============================================================

USE adzuna_jobs;

-- Clear staging before reload (idempotent)
TRUNCATE TABLE stg_jobs;

INSERT INTO stg_jobs
    (
    job_id,
    title,
    title_normalized,
    company_name,
    company_normalized,
    location_display,
    country,
    state,
    region,
    city,
    suburb,
    latitude,
    longitude,
    category_tag,
    category_label,
    contract_type,
    contract_time,
    salary_min_api,
    salary_max_api,
    salary_is_predicted,
    description_raw,
    description_clean,
    description_length,
    posted_at,
    posted_date,
    redirect_url,
    search_terms,
    search_term_count,
    first_fetched_at,
    last_fetched_at
    )
WITH
    -- Step 1: aggregate all search_terms + fetch timestamps per job_id
    search_agg
    AS
    (
        SELECT
            job_id,
            JSON_ARRAYAGG(search_term)        AS search_terms,
            COUNT(DISTINCT search_term)       AS search_term_count,
            MIN(fetched_at)                   AS first_fetched_at,
            MAX(fetched_at)                   AS last_fetched_at
        FROM raw_jobs
        GROUP BY job_id
    ),
    -- Step 2: pick ONE representative raw row per job_id
    --         (row_number = 1; tie-break by latest fetched_at then highest id)
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
        FROM raw_jobs
    )
SELECT
    rk.job_id,

    -- Core fields (from the representative raw_data JSON)
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.title'))                   AS title,
    LOWER(TRIM(JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.title'))))      AS title_normalized,
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.company.display_name'))    AS company_name,
    LOWER(TRIM(JSON_UNQUOTE(
        JSON_EXTRACT(rk.raw_data, '$.company.display_name'))))           AS company_normalized,

    -- Location: display + parsed hierarchy
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.location.display_name'))   AS location_display,
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.location.area[0]'))        AS country,
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.location.area[1]'))        AS state,
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.location.area[2]'))        AS region,
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.location.area[3]'))        AS city,
    -- suburb = last non-null element (handles variable depth 1-6)
    JSON_UNQUOTE(JSON_EXTRACT(
        rk.raw_data,
        CONCAT('$.location.area[',
               JSON_LENGTH(JSON_EXTRACT(rk.raw_data, '$.location.area')) - 1,
               ']')
    ))                                                                  AS suburb,

    -- Geo
    CAST(JSON_EXTRACT(rk.raw_data, '$.latitude')  AS DECIMAL(10,6))      AS latitude,
    CAST(JSON_EXTRACT(rk.raw_data, '$.longitude') AS DECIMAL(10,6))      AS longitude,

    -- Category
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.category.tag'))            AS category_tag,
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.category.label'))          AS category_label,

    -- Contract
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.contract_type'))           AS contract_type,
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.contract_time'))           AS contract_time,

    -- Salary (API native - often NULL, regex extraction in next script)
    CAST(JSON_EXTRACT(rk.raw_data, '$.salary_min') AS DECIMAL(12,2))     AS salary_min_api,
    CAST(JSON_EXTRACT(rk.raw_data, '$.salary_max') AS DECIMAL(12,2))     AS salary_max_api,
    CAST(JSON_EXTRACT(rk.raw_data, '$.salary_is_predicted') AS UNSIGNED) AS salary_is_predicted,

    -- Description: raw + cleaned
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.description'))             AS description_raw,
    TRIM(REGEXP_REPLACE(
        JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.description')),
        '\\s+', ' '))                                                   AS description_clean,
    CHAR_LENGTH(JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.description'))) AS description_length,

    -- Posting time
    STR_TO_DATE(
        JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.created')),
        '%Y-%m-%dT%H:%i:%sZ')                                           AS posted_at,
    DATE(STR_TO_DATE(
        JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.created')),
        '%Y-%m-%dT%H:%i:%sZ'))                                          AS posted_date,
    JSON_UNQUOTE(JSON_EXTRACT(rk.raw_data, '$.redirect_url'))            AS redirect_url,

    -- Search context (from search_agg CTE)
    sa.search_terms,
    sa.search_term_count,

    -- ETL metadata (from search_agg CTE)
    sa.first_fetched_at,
    sa.last_fetched_at

FROM ranked rk
    JOIN search_agg sa ON sa.job_id = rk.job_id
WHERE rk.rn = 1;

-- Verify load
SELECT COUNT(*) AS staged_rows
FROM stg_jobs;
SELECT
    COUNT(*)                                            AS total,
    COUNT(state)                                        AS has_state,
    COUNT(suburb)                                       AS has_suburb,
    COUNT(CASE WHEN search_term_count > 1 THEN 1 END)   AS multi_search_jobs,
    MAX(search_term_count)                              AS max_search_terms
FROM stg_jobs;