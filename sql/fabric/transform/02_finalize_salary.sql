-- ============================================================
-- Transform: Finalize salary fields (API-only strategy)
-- T-SQL version for Fabric Warehouse (translated from Week 2 MySQL DML)
-- Design (Week 2):
--   AU job market: ~90% of postings omit salary
--   Regex extraction abandoned (low yield + noise risk)
--   Strategy: API-only + sanity cleanup; document coverage limitation
-- Idempotent: UPDATE pattern, safe to re-run
-- ============================================================

-- Step 0 (added in T-SQL): apply salary_currency = 'AUD' globally
-- (was DEFAULT 'AUD' in MySQL DDL; Fabric Warehouse can't declare DEFAULT)
UPDATE dbo.stg_jobs
SET salary_currency = 'AUD'
WHERE salary_currency IS NULL;

-- Step 1: copy API salary into final fields, with sanity guards
UPDATE dbo.stg_jobs
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
        WHEN salary_min_api IS NOT NULL OR salary_max_api IS NOT NULL THEN 'annual'
        ELSE NULL
    END
WHERE job_id IS NOT NULL;

-- Step 2: fix inverted ranges (min > max)
-- T-SQL swap idiom: SET right-hand-sides use OLD row values, so direct swap works
-- (replaces MySQL's LEAST/GREATEST pattern)
UPDATE dbo.stg_jobs
SET
    salary_min_final = salary_max_final,
    salary_max_final = salary_min_final
WHERE salary_min_final IS NOT NULL
    AND salary_max_final IS NOT NULL
    AND salary_min_final > salary_max_final;

-- Step 3: compute average where bounds exist
UPDATE dbo.stg_jobs
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

-- Step 4: invalidate sub-threshold salaries (< 30,000 AUD = likely API error)
-- AU full-time annual realistically >= 30k; below = data error (e.g. hourly stored as annual)
UPDATE dbo.stg_jobs
SET
    salary_min_final = NULL,
    salary_max_final = NULL,
    salary_avg_final = NULL,
    salary_period    = NULL
WHERE salary_avg_final IS NOT NULL
    AND salary_avg_final < 30000;

-- ============================================================
-- Verify: salary coverage after finalization
-- (T-SQL: SUM(col IS NOT NULL) → COUNT(col))
-- ============================================================
SELECT
    'Salary coverage'                                    AS check_name,
    COUNT(*)                                             AS total_jobs,
    COUNT(salary_avg_final)                              AS has_salary,
    ROUND(100.0 * COUNT(salary_avg_final) / COUNT(*), 1) AS pct_with_salary,
    ROUND(MIN(salary_avg_final), 0)                      AS min_salary,
    ROUND(AVG(salary_avg_final), 0)                      AS avg_salary,
    ROUND(MAX(salary_avg_final), 0)                      AS max_salary
FROM dbo.stg_jobs;

-- Verify: sanity check
-- (T-SQL: SUM(boolean) → SUM(CASE WHEN ... THEN 1 ELSE 0 END))
SELECT
    'Salary sanity'                                                                          AS check_name,
    SUM(CASE WHEN salary_min_final > salary_max_final                          THEN 1 ELSE 0 END) AS inverted_ranges,
    SUM(CASE WHEN salary_avg_final > 1000000                                   THEN 1 ELSE 0 END) AS over_1m,
    SUM(CASE WHEN salary_avg_final < 20000 AND salary_avg_final IS NOT NULL    THEN 1 ELSE 0 END) AS under_20k
FROM dbo.stg_jobs;