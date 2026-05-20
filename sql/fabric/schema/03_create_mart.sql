-- ============================================================
-- Mart Layer: star schema for analytics & Power BI
-- T-SQL version for Fabric Warehouse (translated from Week 2 MySQL DDL)
-- Grain of fact_job_postings: one row per unique job_id
-- ============================================================

-- ---------- Drop in dependency order (children/bridges first) ----------
DROP TABLE IF EXISTS dbo.bridge_job_skills;
DROP TABLE IF EXISTS dbo.fact_job_postings;
DROP TABLE IF EXISTS dbo.dim_company;
DROP TABLE IF EXISTS dbo.dim_location;
DROP TABLE IF EXISTS dbo.dim_date;
DROP TABLE IF EXISTS dbo.dim_category;
DROP TABLE IF EXISTS dbo.dim_skill;

-- ============================================================
-- 1. CREATE TABLEs (no constraints inline; columns + IDENTITY only)
-- ============================================================

-- ---------- dim_company ----------
CREATE TABLE dbo.dim_company (
    company_id          BIGINT          NOT NULL IDENTITY,
    company_name        VARCHAR(255)    NOT NULL,
    -- Lowercase key for matching
    company_normalized  VARCHAR(255)    NOT NULL
);

-- ---------- dim_location  (denormalized hierarchy — star, not snowflake) ----------
CREATE TABLE dbo.dim_location (
    location_id     BIGINT          NOT NULL IDENTITY,
    country         VARCHAR(100)    NULL,
    state           VARCHAR(100)    NULL,
    region          VARCHAR(150)    NULL,
    city            VARCHAR(150)    NULL,
    suburb          VARCHAR(150)    NULL,
    latitude        DECIMAL(10, 6)  NULL,
    longitude       DECIMAL(10, 6)  NULL,
    -- Concatenated hash key for dedup
    location_key    VARCHAR(600)    NOT NULL
);

-- ---------- dim_date ----------
-- date_id is a smart key (YYYYMMDD, e.g. 20260515), NOT IDENTITY — populated by load script
CREATE TABLE dbo.dim_date (
    date_id         INT             NOT NULL,
    full_date       DATE            NOT NULL,
    year            SMALLINT        NOT NULL,
    -- TINYINT → SMALLINT (Fabric Warehouse limitation)
    quarter         SMALLINT        NOT NULL,
    month           SMALLINT        NOT NULL,
    month_name      VARCHAR(20)     NOT NULL,
    day_of_month    SMALLINT        NOT NULL,
    -- 1=Monday ... 7=Sunday
    day_of_week     SMALLINT        NOT NULL,
    day_name        VARCHAR(20)     NOT NULL,
    -- DEFAULT 0 removed (Fabric Warehouse limitation) — set 0/1 explicitly at load time
    is_weekend      SMALLINT        NOT NULL
);

-- ---------- dim_category ----------
CREATE TABLE dbo.dim_category (
    category_id     BIGINT          NOT NULL IDENTITY,
    category_tag    VARCHAR(100)    NOT NULL,
    category_label  VARCHAR(255)    NULL
);

-- ---------- dim_skill ----------
CREATE TABLE dbo.dim_skill (
    skill_id        BIGINT          NOT NULL IDENTITY,
    skill_name      VARCHAR(100)    NOT NULL,
    -- e.g. Language, BI Tool, Cloud, Database
    skill_category  VARCHAR(50)     NULL
);

-- ---------- fact_job_postings  (grain: one row per job_id) ----------
CREATE TABLE dbo.fact_job_postings (
    job_posting_id      BIGINT          NOT NULL IDENTITY,

    -- Degenerate dimension kept in fact (near-unique, no dim benefit)
    job_id              VARCHAR(50)     NOT NULL,
    title               VARCHAR(500)    NULL,

    -- Foreign keys to dimensions (FKs added separately below)
    company_id          BIGINT          NULL,
    location_id         BIGINT          NULL,
    date_id             INT             NULL,
    category_id         BIGINT          NULL,

    -- Measures
    salary_min          DECIMAL(12, 2)  NULL,
    salary_max          DECIMAL(12, 2)  NULL,
    salary_avg          DECIMAL(12, 2)  NULL,
    -- TINYINT → SMALLINT; DEFAULT 0 removed (set explicitly at load time)
    -- 1 if salary_avg present
    has_salary          SMALLINT        NOT NULL,

    -- Contextual attributes
    contract_type       VARCHAR(50)     NULL,
    contract_time       VARCHAR(50)     NULL,
    -- How many search_terms matched this job
    search_term_count   INT             NULL
);

-- ---------- bridge_job_skills  (resolves many-to-many: job <-> skill) ----------
CREATE TABLE dbo.bridge_job_skills (
    job_posting_id  BIGINT  NOT NULL,
    skill_id        BIGINT  NOT NULL
);

-- ============================================================
-- 2. PRIMARY KEY constraints (all 7 tables)
-- ============================================================
ALTER TABLE dbo.dim_company        ADD CONSTRAINT PK_dim_company        PRIMARY KEY NONCLUSTERED (company_id)                  NOT ENFORCED;
ALTER TABLE dbo.dim_location       ADD CONSTRAINT PK_dim_location       PRIMARY KEY NONCLUSTERED (location_id)                 NOT ENFORCED;
ALTER TABLE dbo.dim_date           ADD CONSTRAINT PK_dim_date           PRIMARY KEY NONCLUSTERED (date_id)                     NOT ENFORCED;
ALTER TABLE dbo.dim_category       ADD CONSTRAINT PK_dim_category       PRIMARY KEY NONCLUSTERED (category_id)                 NOT ENFORCED;
ALTER TABLE dbo.dim_skill          ADD CONSTRAINT PK_dim_skill          PRIMARY KEY NONCLUSTERED (skill_id)                    NOT ENFORCED;
ALTER TABLE dbo.fact_job_postings  ADD CONSTRAINT PK_fact_job_postings  PRIMARY KEY NONCLUSTERED (job_posting_id)              NOT ENFORCED;
ALTER TABLE dbo.bridge_job_skills  ADD CONSTRAINT PK_bridge_job_skills  PRIMARY KEY NONCLUSTERED (job_posting_id, skill_id)    NOT ENFORCED;

-- ============================================================
-- 3. UNIQUE constraints (replacing MySQL inline UNIQUE KEY)
-- ============================================================
ALTER TABLE dbo.dim_company        ADD CONSTRAINT UK_dim_company_norm   UNIQUE NONCLUSTERED (company_normalized) NOT ENFORCED;
ALTER TABLE dbo.dim_location       ADD CONSTRAINT UK_dim_location_key   UNIQUE NONCLUSTERED (location_key)       NOT ENFORCED;
ALTER TABLE dbo.dim_date           ADD CONSTRAINT UK_dim_date_full_date UNIQUE NONCLUSTERED (full_date)          NOT ENFORCED;
ALTER TABLE dbo.dim_category       ADD CONSTRAINT UK_dim_category_tag   UNIQUE NONCLUSTERED (category_tag)       NOT ENFORCED;
ALTER TABLE dbo.dim_skill          ADD CONSTRAINT UK_dim_skill_name     UNIQUE NONCLUSTERED (skill_name)         NOT ENFORCED;
ALTER TABLE dbo.fact_job_postings  ADD CONSTRAINT UK_fact_job_id        UNIQUE NONCLUSTERED (job_id)             NOT ENFORCED;

-- ============================================================
-- 4. FOREIGN KEY constraints (declared for documentation; NOT ENFORCED)
-- ============================================================
ALTER TABLE dbo.fact_job_postings  ADD CONSTRAINT FK_fact_company   FOREIGN KEY (company_id)  REFERENCES dbo.dim_company(company_id)   NOT ENFORCED;
ALTER TABLE dbo.fact_job_postings  ADD CONSTRAINT FK_fact_location  FOREIGN KEY (location_id) REFERENCES dbo.dim_location(location_id) NOT ENFORCED;
ALTER TABLE dbo.fact_job_postings  ADD CONSTRAINT FK_fact_date      FOREIGN KEY (date_id)     REFERENCES dbo.dim_date(date_id)         NOT ENFORCED;
ALTER TABLE dbo.fact_job_postings  ADD CONSTRAINT FK_fact_category  FOREIGN KEY (category_id) REFERENCES dbo.dim_category(category_id) NOT ENFORCED;
ALTER TABLE dbo.bridge_job_skills  ADD CONSTRAINT FK_bridge_fact    FOREIGN KEY (job_posting_id) REFERENCES dbo.fact_job_postings(job_posting_id) NOT ENFORCED;
ALTER TABLE dbo.bridge_job_skills  ADD CONSTRAINT FK_bridge_skill   FOREIGN KEY (skill_id)       REFERENCES dbo.dim_skill(skill_id)               NOT ENFORCED;

-- ============================================================
-- 5. Verify all 7 tables created
-- ============================================================
SELECT TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'dbo'
  AND (TABLE_NAME LIKE 'dim_%' OR TABLE_NAME LIKE 'fact_%' OR TABLE_NAME LIKE 'bridge_%')
ORDER BY TABLE_NAME;