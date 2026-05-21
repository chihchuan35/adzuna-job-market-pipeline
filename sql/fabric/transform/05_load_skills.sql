-- ============================================================
-- Transform: Load skill dimension and job-skill bridge
-- T-SQL version for Fabric Warehouse (translated from Week 2 MySQL DML)
-- Strategy: controlled vocabulary of 31 low-ambiguity DA skills.
-- Matching: PATINDEX with [^a-zA-Z0-9] character class for word boundaries
-- (Fabric Warehouse has no REGEXP; this is the closest semantic equivalent)
-- Idempotent: DELETE + INSERT pattern
-- ============================================================

-- ----- Step 1: pattern dictionary in a #temp table -----
-- (Why #temp instead of adding match_pattern to dim_skill:
--  patterns are load-script implementation, not part of the analytics model)
DROP TABLE IF EXISTS #skill_defs;
CREATE TABLE #skill_defs
(
    skill_name VARCHAR(100) NOT NULL,
    skill_category VARCHAR(50) NOT NULL,
    pattern VARCHAR(100) NOT NULL
)
WITH (DISTRIBUTION = ROUND_ROBIN);

INSERT INTO #skill_defs
    (skill_name, skill_category, pattern)
VALUES
    -- Single-pattern skills (28)
    ('SQL', 'Database', 'SQL'),
    ('Python', 'Language', 'Python'),
    ('Tableau', 'BI Tool', 'Tableau'),
    ('Excel', 'Spreadsheet', 'Excel'),
    ('Looker', 'BI Tool', 'Looker'),
    ('SAS', 'Analytics', 'SAS'),
    ('AWS', 'Cloud', 'AWS'),
    ('Azure', 'Cloud', 'Azure'),
    ('GCP', 'Cloud', 'GCP'),
    ('Snowflake', 'Database', 'Snowflake'),
    ('Spark', 'Big Data', 'Spark'),
    ('Hadoop', 'Big Data', 'Hadoop'),
    ('Databricks', 'Platform', 'Databricks'),
    ('Airflow', 'Orchestration', 'Airflow'),
    ('dbt', 'Transformation', 'dbt'),
    ('ETL', 'Concept', 'ETL'),
    ('Microsoft Fabric', 'Platform', 'Fabric'),
    -- name != pattern (by design)
    ('Git', 'Version Control', 'Git'),
    ('Docker', 'DevOps', 'Docker'),
    ('Kafka', 'Streaming', 'Kafka'),
    ('NoSQL', 'Database', 'NoSQL'),
    ('MongoDB', 'Database', 'MongoDB'),
    ('PostgreSQL', 'Database', 'PostgreSQL'),
    ('Machine Learning', 'Concept', 'Machine Learning'),
    ('Lakehouse', 'Architecture', 'Lakehouse'),
    ('Data Pipeline', 'Concept', 'Data Pipeline'),
    ('DAX', 'BI Tool', 'DAX'),
    ('Synapse', 'Cloud', 'Synapse'),
    -- Skills with optional-space variants (3 skills, 2 patterns each)
    ('Power BI', 'BI Tool', 'Power BI'),
    ('Power BI', 'BI Tool', 'PowerBI'),
    ('Data Warehouse', 'Architecture', 'Data Warehouse'),
    ('Data Warehouse', 'Architecture', 'DataWarehouse'),
    ('Power Query', 'BI Tool', 'Power Query'),
    ('Power Query', 'BI Tool', 'PowerQuery');

-- ----- Step 2: reload dim_skill (DELETE because bridge FK blocks TRUNCATE) -----
DELETE FROM dbo.bridge_job_skills;
-- clear bridge first
DELETE FROM dbo.dim_skill;
-- now safe to clear dim

-- Distinct skill_name only (31 rows); skill_category picked deterministically
INSERT INTO dbo.dim_skill
    (skill_name, skill_category)
SELECT skill_name, MIN(skill_category) AS skill_category
FROM #skill_defs
GROUP BY skill_name;

-- Verify dim_skill
SELECT COUNT(*) AS skill_count
FROM dbo.dim_skill;
-- expect 31
SELECT skill_category, COUNT(*) AS cnt
FROM dbo.dim_skill
GROUP BY skill_category
ORDER BY cnt DESC;

-- ============================================================
-- BATCH 2: match skills against descriptions, load bridge
-- ============================================================

-- Match each (job, pattern) pair with PATINDEX word-boundary check;
-- DISTINCT collapses duplicate matches (e.g. Power BI matched via both patterns)
INSERT INTO dbo.bridge_job_skills
    (job_posting_id, skill_id)
SELECT DISTINCT
    f.job_posting_id,
    ds.skill_id
FROM dbo.fact_job_postings f
    JOIN dbo.stg_jobs s
    ON f.job_id = s.job_id
CROSS JOIN #skill_defs sd
    JOIN dbo.dim_skill ds
    ON ds.skill_name = sd.skill_name
WHERE s.description_clean IS NOT NULL
    AND PATINDEX(
        '%[^a-zA-Z0-9]' + sd.pattern + '[^a-zA-Z0-9]%',
        ' ' + s.description_clean + ' '
      ) > 0;

-- ----- Verify: bridge row count + integrity -----
SELECT
    'bridge summary'                                  AS check_name,
    COUNT(*)                                          AS total_links,
    COUNT(DISTINCT job_posting_id)                    AS jobs_with_skills,
    COUNT(DISTINCT skill_id)                          AS skills_matched,
    -- Cast to NUMERIC to avoid integer division
    ROUND(CAST(COUNT(*) AS NUMERIC(10,2))
        / NULLIF(COUNT(DISTINCT job_posting_id), 0), 2) AS avg_skills_per_job
FROM dbo.bridge_job_skills;

-- Coverage: how many of the 2,142 jobs got at least one skill?
SELECT
    'skill coverage'                                  AS check_name,
    (SELECT COUNT(*)
    FROM dbo.fact_job_postings)      AS total_jobs,
    COUNT(DISTINCT job_posting_id)                    AS jobs_with_skill,
    ROUND(100.0 * COUNT(DISTINCT job_posting_id)
        / (SELECT COUNT(*)
    FROM dbo.fact_job_postings), 1) AS pct_coverage
FROM dbo.bridge_job_skills;

-- Top skills (the portfolio money chart preview)
SELECT
    ds.skill_name,
    ds.skill_category,
    COUNT(*) AS demand_count,
    ROUND(100.0 * COUNT(*)
        / (SELECT COUNT(*)
    FROM dbo.fact_job_postings), 1) AS pct_of_jobs
FROM dbo.bridge_job_skills b
    JOIN dbo.dim_skill ds ON b.skill_id = ds.skill_id
GROUP BY ds.skill_id, ds.skill_name, ds.skill_category
ORDER BY demand_count DESC;

-- ----- DQ: document the skill-coverage limitation -----
-- Root cause: Adzuna free API truncates description at 500 chars;
-- skill sections (typically mid/late in posting) are often cut off.
-- This caps achievable skill coverage; NOT a matching-logic defect.
SELECT
    'skill extraction limitation'                    AS check_name,
    (SELECT COUNT(*)
    FROM dbo.stg_jobs)              AS total_jobs,
    (SELECT ROUND(AVG(CAST(description_length AS NUMERIC(10,2))), 0)
    FROM dbo.stg_jobs)                              AS avg_desc_length,
    (SELECT SUM(CASE
            WHEN description_clean LIKE '%…%'
            OR description_clean LIKE '%...%'
            THEN 1 ELSE 0 END)
    FROM dbo.stg_jobs)                              AS truncated_descriptions,
    (SELECT COUNT(DISTINCT job_posting_id)
    FROM dbo.bridge_job_skills)                     AS jobs_with_skill,
    ROUND(100.0 * (SELECT COUNT(DISTINCT job_posting_id)
    FROM dbo.bridge_job_skills)
        / (SELECT COUNT(*)
    FROM dbo.stg_jobs), 1)    AS pct_coverage,
    'API truncation at 500 chars limits coverage'    AS interpretation;