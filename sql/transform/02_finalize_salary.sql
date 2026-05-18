-- Transform: Finalize salary fields (API-only strategy)
-- Design decision (Week 2):
--   Australian job market: ~90% of postings omit salary.
--   Text regex extraction abandoned: low yield + noise risk
--   (e.g. funding amounts misread as salary).
--   Strategy: use Adzuna API native salary only, document limitation.
--   Idempotent (UPDATE pattern, safe to re-run).

USE adzuna_jobs;

-- Step 1: copy API salary into final fields, with sanity guards
UPDATE stg_jobs
SET
    salary_min_final = CASE
        WHEN salary_min_api IS NULL OR salary_min_api <= 0 THEN NULL
        ELSE salary_min_api
    END,
    salary_max_final = CASE
        WHEN salary_max_api IS NULL OR salary_max_api <= 0 THEN NULL
        ELSE salary_max_api
    END,
    salary_period = CASE
        WHEN salary_min_api IS NOT NULL OR salary_max_api IS NOT NULL
        THEN 'annual'
        ELSE NULL
    END
WHERE job_id IS NOT NULL;

-- Step 2: fix inverted ranges (min > max) via LEAST/GREATEST
UPDATE stg_jobs
SET
    salary_min_final = LEAST(salary_min_final, salary_max_final),
    salary_max_final = GREATEST(salary_min_final, salary_max_final)
WHERE salary_min_final IS NOT NULL
    AND salary_max_final IS NOT NULL
    AND salary_min_final > salary_max_final;

-- Step 3: compute average where bounds exist
UPDATE stg_jobs
SET salary_avg_final = CASE
    WHEN salary_min_final IS NOT NULL AND salary_max_final IS NOT NULL
        THEN (salary_min_final + salary_max_final) / 2
    WHEN salary_min_final IS NOT NULL
        THEN salary_min_final
    WHEN salary_max_final IS NOT NULL
        THEN salary_max_final
    ELSE NULL
END
WHERE job_id IS NOT NULL;

-- Step 4: invalidate sub-threshold salaries (API data errors)
-- AU full-time annual realistically >= 30,000 AUD; below = API error
-- (e.g. hourly rate stored as annual). Clear all salary fields.
UPDATE stg_jobs
SET
    salary_min_final = NULL,
    salary_max_final = NULL,
    salary_avg_final = NULL,
    salary_period    = NULL
WHERE salary_avg_final IS NOT NULL
    AND salary_avg_final < 30000;

-- Verify: salary coverage after finalization
SELECT
    'Salary coverage'                       AS check_name,
    COUNT(*)                                AS total_jobs,
    SUM(salary_avg_final IS NOT NULL)       AS has_salary,
    ROUND(100.0 * SUM(salary_avg_final IS NOT NULL)
        / COUNT(*), 1)                      AS pct_with_salary,
    ROUND(MIN(salary_avg_final), 0)         AS min_salary,
    ROUND(AVG(salary_avg_final), 0)         AS avg_salary,
    ROUND(MAX(salary_avg_final), 0)         AS max_salary
FROM stg_jobs;

-- Verify: sanity check
SELECT
    'Salary sanity'                         AS check_name,
    SUM(salary_min_final > salary_max_final) AS inverted_ranges,
    SUM(salary_avg_final > 1000000)         AS over_1m,
    SUM(salary_avg_final < 20000
        AND salary_avg_final IS NOT NULL)   AS under_20k
FROM stg_jobs;