-- Transform: Load skill dimension and job-skill bridge
-- Strategy: controlled vocabulary of 31 low-ambiguity DA skills.
-- High-ambiguity single-letter skills (R, C, Go) deliberately
-- excluded to keep skill statistics credible (documented limitation).
-- Matching: case-insensitive REGEXP with word boundaries
-- to avoid substring false positives (e.g. Excel vs Excellent).
-- BATCH 1: load dim_skill only. Bridge loaded in batch 2.
-- Idempotent: ALTER guarded, dim_skill TRUNCATE + INSERT.

USE adzuna_jobs;

-- Schema evolution: add match_pattern column if not present
-- (stores each skill's regex so matching logic stays data-driven)
SET @col_exists = (
    SELECT COUNT(*)
FROM information_schema.columns
WHERE table_schema = 'adzuna_jobs'
    AND table_name   = 'dim_skill'
    AND column_name  = 'match_pattern'
);
SET @ddl =
IF(@col_exists = 0,
    'ALTER TABLE dim_skill ADD COLUMN match_pattern VARCHAR(200) NOT NULL DEFAULT '''' AFTER skill_category',
    'SELECT "match_pattern column already exists" AS note');
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Reload skill dimension (bridge references it; clear bridge first)
SET FOREIGN_KEY_CHECKS
= 0;
TRUNCATE TABLE bridge_job_skills;
TRUNCATE TABLE dim_skill;
SET FOREIGN_KEY_CHECKS
= 1;

-- Load 31 controlled-vocabulary skills with their match patterns
INSERT INTO dim_skill
    (skill_name, skill_category, match_pattern)
VALUES
    ('SQL', 'Database', '\\bSQL\\b'),
    ('Python', 'Language', '\\bPython\\b'),
    ('Power BI', 'BI Tool', '\\bPower ?BI\\b'),
    ('Tableau', 'BI Tool', '\\bTableau\\b'),
    ('Excel', 'Spreadsheet', '\\bExcel\\b'),
    ('Looker', 'BI Tool', '\\bLooker\\b'),
    ('SAS', 'Analytics', '\\bSAS\\b'),
    ('AWS', 'Cloud', '\\bAWS\\b'),
    ('Azure', 'Cloud', '\\bAzure\\b'),
    ('GCP', 'Cloud', '\\bGCP\\b'),
    ('Snowflake', 'Database', '\\bSnowflake\\b'),
    ('Spark', 'Big Data', '\\bSpark\\b'),
    ('Hadoop', 'Big Data', '\\bHadoop\\b'),
    ('Databricks', 'Platform', '\\bDatabricks\\b'),
    ('Airflow', 'Orchestration', '\\bAirflow\\b'),
    ('dbt', 'Transformation', '\\bdbt\\b'),
    ('ETL', 'Concept', '\\bETL\\b'),
    ('Microsoft Fabric', 'Platform', '\\bFabric\\b'),
    ('Git', 'Version Control', '\\bGit\\b'),
    ('Docker', 'DevOps', '\\bDocker\\b'),
    ('Kafka', 'Streaming', '\\bKafka\\b'),
    ('NoSQL', 'Database', '\\bNoSQL\\b'),
    ('MongoDB', 'Database', '\\bMongoDB\\b'),
    ('PostgreSQL', 'Database', '\\bPostgreSQL\\b'),
    ('Machine Learning', 'Concept', '\\bMachine Learning\\b'),
    ('Lakehouse', 'Architecture', '\\bLakehouse\\b'),
    ('Data Warehouse', 'Architecture', '\\bData ?Warehouse\\b'),
    ('Data Pipeline', 'Concept', '\\bData Pipeline\\b'),
    ('Power Query', 'BI Tool', '\\bPower ?Query\\b'),
    ('DAX', 'BI Tool', '\\bDAX\\b'),
    ('Synapse', 'Cloud', '\\bSynapse\\b');

-- Verify
SELECT COUNT(*) AS skill_count
FROM dim_skill;
SELECT skill_category, COUNT(*) AS cnt
FROM dim_skill
GROUP BY skill_category
ORDER BY cnt DESC;

-- ============================================================
-- BATCH 2: match skills against descriptions, load bridge
-- ============================================================

-- Clear bridge before reload (idempotent)
TRUNCATE TABLE bridge_job_skills;

-- Match: for each job x each skill, test description against pattern
INSERT INTO bridge_job_skills
    (job_posting_id, skill_id)
SELECT DISTINCT
    f.job_posting_id,
    sk.skill_id
FROM fact_job_postings f
    JOIN stg_jobs s
    ON f.job_id = s.job_id
CROSS JOIN dim_skill sk
WHERE s.description_clean IS NOT NULL
    AND s.description_clean
REGEXP sk.match_pattern;

-- ------------------------------------------------------------
-- Verify: bridge row count + integrity
-- ------------------------------------------------------------
SELECT
    'bridge summary'                                AS check_name,
    COUNT(*)                                        AS total_links,
    COUNT(DISTINCT job_posting_id)                  AS jobs_with_skills,
    COUNT(DISTINCT skill_id)                        AS skills_matched,
    ROUND(COUNT(*) / COUNT(DISTINCT job_posting_id), 2)
                                                    AS avg_skills_per_job
FROM bridge_job_skills;

-- Coverage: how many of the 2142 jobs got at least one skill?
SELECT
    'skill coverage'                                AS check_name,
    (SELECT COUNT(*)
    FROM fact_job_postings)        AS total_jobs,
    COUNT(DISTINCT job_posting_id)                  AS jobs_with_skill,
    ROUND(100.0 * COUNT(DISTINCT job_posting_id)
        / (SELECT COUNT(*)
    FROM fact_job_postings), 1)
                                                    AS pct_coverage
FROM bridge_job_skills;

-- Top skills (the portfolio money chart preview)
SELECT
    ds.skill_name,
    ds.skill_category,
    COUNT(*) AS demand_count,
    ROUND(100.0 * COUNT(*)
        / (SELECT COUNT(*)
    FROM fact_job_postings), 1) AS pct_of_jobs
FROM bridge_job_skills b
    JOIN dim_skill ds ON b.skill_id = ds.skill_id
GROUP BY ds.skill_id, ds.skill_name, ds.skill_category
ORDER BY demand_count DESC;

-- ------------------------------------------------------------
-- DQ: document skill extraction limitation
-- Root cause: Adzuna free API truncates description at 500 chars,
-- so skill sections (usually mid/late in posting) are often cut off.
-- This caps achievable skill coverage; NOT a matching-logic defect.
-- ------------------------------------------------------------
SELECT
    'skill extraction limitation'                       AS check_name,
    (SELECT COUNT(*)
    FROM stg_jobs)                     AS total_jobs,
    (SELECT ROUND(AVG(description_length),0)
    FROM stg_jobs)                                  AS avg_desc_length,
    (SELECT SUM(description_clean LIKE '%…%'
            OR description_clean LIKE '%...%')
    FROM stg_jobs)                                  AS truncated_descriptions,
    (SELECT COUNT(DISTINCT job_posting_id)
    FROM bridge_job_skills)                         AS jobs_with_skill,
    ROUND(100.0 * (SELECT COUNT(DISTINCT job_posting_id)
    FROM bridge_job_skills)
        / (SELECT COUNT(*)
    FROM stg_jobs), 1)           AS pct_coverage,
    'API truncation at 500 chars limits coverage'       AS interpretation
FROM dual;