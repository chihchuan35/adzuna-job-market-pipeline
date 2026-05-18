-- Mart Layer: star schema for analytics & Power BI
-- Grain of fact_job_postings: one row per unique job_id
-- Design: star schema (denormalized dims) for Power BI performance
-- Surrogate keys (AUTO_INCREMENT) used throughout
-- Skills modeled as bridge (many-to-many): fact <- bridge -> dim_skill
-- Schema only - no data loaded here (see 04_load_mart.sql)

USE adzuna_jobs;

-- Drop in dependency order (children/bridges before parents)
DROP TABLE IF EXISTS bridge_job_skills;
DROP TABLE IF EXISTS fact_job_postings;
DROP TABLE IF EXISTS dim_company;
DROP TABLE IF EXISTS dim_location;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_category;
DROP TABLE IF EXISTS dim_skill;

-- ------------------------------------------------------------
-- dim_company
-- ------------------------------------------------------------
CREATE TABLE dim_company (
    company_id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    company_name        VARCHAR(255) NOT NULL,
    company_normalized  VARCHAR(255) NOT NULL COMMENT 'Lowercase key for matching',
    UNIQUE KEY uk_company_norm (company_normalized)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Company dimension (one row per distinct company)';

-- ------------------------------------------------------------
-- dim_location  (denormalized hierarchy - star, not snowflake)
-- ------------------------------------------------------------
CREATE TABLE dim_location (
    location_id     BIGINT AUTO_INCREMENT PRIMARY KEY,
    country         VARCHAR(100),
    state           VARCHAR(100),
    region          VARCHAR(150),
    city            VARCHAR(150),
    suburb          VARCHAR(150),
    latitude        DECIMAL(10, 6),
    longitude       DECIMAL(10, 6),
    location_key    VARCHAR(600) NOT NULL COMMENT 'Concatenated hash key for dedup',
    UNIQUE KEY uk_location_key (location_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Location dimension (denormalized hierarchy for Power BI maps)';

-- ------------------------------------------------------------
-- dim_date
-- ------------------------------------------------------------
CREATE TABLE dim_date (
    date_id         INT PRIMARY KEY COMMENT 'YYYYMMDD integer (e.g. 20260515)',
    full_date       DATE NOT NULL,
    year            SMALLINT NOT NULL,
    quarter         TINYINT NOT NULL,
    month           TINYINT NOT NULL,
    month_name      VARCHAR(20) NOT NULL,
    day_of_month    TINYINT NOT NULL,
    day_of_week     TINYINT NOT NULL COMMENT '1=Monday ... 7=Sunday',
    day_name        VARCHAR(20) NOT NULL,
    is_weekend      TINYINT NOT NULL DEFAULT 0,
    UNIQUE KEY uk_full_date (full_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Date dimension for time-series analysis';

-- ------------------------------------------------------------
-- dim_category
-- ------------------------------------------------------------
CREATE TABLE dim_category (
    category_id     BIGINT AUTO_INCREMENT PRIMARY KEY,
    category_tag    VARCHAR(100) NOT NULL,
    category_label  VARCHAR(255),
    UNIQUE KEY uk_category_tag (category_tag)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Adzuna category dimension (company industry classification)';

-- ------------------------------------------------------------
-- dim_skill
-- ------------------------------------------------------------
CREATE TABLE dim_skill (
    skill_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
    skill_name      VARCHAR(100) NOT NULL,
    skill_category  VARCHAR(50) COMMENT 'e.g. Language, BI Tool, Cloud, Database',
    UNIQUE KEY uk_skill_name (skill_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Skill dimension (controlled vocabulary, ~25 standard DA skills)';

-- ------------------------------------------------------------
-- fact_job_postings  (grain: one row per job_id)
-- ------------------------------------------------------------
CREATE TABLE fact_job_postings (
    job_posting_id      BIGINT AUTO_INCREMENT PRIMARY KEY,

    -- Degenerate dimensions (kept in fact - near-unique, no dim benefit)
    job_id              VARCHAR(50) NOT NULL,
    title               VARCHAR(500),

    -- Foreign keys to dimensions
    company_id          BIGINT,
    location_id         BIGINT,
    date_id             INT,
    category_id         BIGINT,

    -- Measures (the numeric facts)
    salary_min          DECIMAL(12, 2),
    salary_max          DECIMAL(12, 2),
    salary_avg          DECIMAL(12, 2),
    has_salary          TINYINT NOT NULL DEFAULT 0 COMMENT '1 if salary_avg present',

    -- Contextual attributes (low cardinality, kept in fact)
    contract_type       VARCHAR(50),
    contract_time       VARCHAR(50),
    search_term_count   INT COMMENT 'How many search_terms matched this job',

    UNIQUE KEY uk_job_id (job_id),
    INDEX idx_company  (company_id),
    INDEX idx_location (location_id),
    INDEX idx_date     (date_id),
    INDEX idx_category (category_id),

    CONSTRAINT fk_fact_company
        FOREIGN KEY (company_id)  REFERENCES dim_company(company_id),
    CONSTRAINT fk_fact_location
        FOREIGN KEY (location_id) REFERENCES dim_location(location_id),
    CONSTRAINT fk_fact_date
        FOREIGN KEY (date_id)     REFERENCES dim_date(date_id),
    CONSTRAINT fk_fact_category
        FOREIGN KEY (category_id) REFERENCES dim_category(category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Fact table: one row per job posting (grain = job_id)';

-- ------------------------------------------------------------
-- bridge_job_skills  (resolves many-to-many: job <-> skill)
-- ------------------------------------------------------------
CREATE TABLE bridge_job_skills (
    job_posting_id  BIGINT NOT NULL,
    skill_id        BIGINT NOT NULL,
    PRIMARY KEY (job_posting_id, skill_id),
    CONSTRAINT fk_bridge_fact
        FOREIGN KEY (job_posting_id) REFERENCES fact_job_postings(job_posting_id),
    CONSTRAINT fk_bridge_skill
        FOREIGN KEY (skill_id)       REFERENCES dim_skill(skill_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Bridge table: many-to-many between job postings and skills';

-- Verify all 7 tables created
SHOW TABLES LIKE 'dim_%';
SHOW TABLES LIKE 'fact_%';
SHOW TABLES LIKE 'bridge_%';