# 🇦🇺 Adzuna Job Market Pipeline

End-to-end ETL pipeline analyzing the Australian data job market, implemented in two parallel SQL dialects (MySQL on-prem and Microsoft Fabric Warehouse) sharing a single design.

> ✅ **Status**: Week 3 complete — full pipeline ported to Microsoft Fabric (Lakehouse bronze + Warehouse silver/gold). Power BI Direct Lake dashboard coming in Week 4.

## 🎯 Business Questions

This project answers:

- Which cities and companies are hiring data professionals in Australia?
- How do salary ranges compare across Data Analyst, Data Engineer, and Data Scientist roles?
- What are the most in-demand technical skills?
- How does demand trend over time?

## 🏗️ Architecture

Two parallel implementations of the same medallion pipeline sharing one design:

```
Local pipeline (Week 1-2):
  Adzuna API → Python (Extract) → MySQL raw → MySQL staging
                                  → MySQL star schema → Power BI Desktop

Cloud pipeline (Week 3):
  MySQL raw → On-prem Data Gateway → Fabric Copy Pipeline
            → Lakehouse adzuna_bronze (raw)
                  ↓ cross-DB read via 3-part naming
            → Fabric Warehouse adzuna_warehouse
                  (T-SQL: staging + star schema)
            → Power BI Direct Lake (Week 4)
```

Both paths land on the same 7-table star schema with **100% referential integrity**. The Fabric implementation reuses the design but required full MySQL → T-SQL dialect translation; the catalogue of differences encountered is documented in [`docs/migration-mysql-to-fabric-warehouse.md`](docs/migration-mysql-to-fabric-warehouse.md).

**Pipeline flow**: 2,622 raw API rows → 2,142 deduplicated staging rows → star schema (1 fact + 5 dimensions + 1 bridge).

## 📋 Data Quality & Engineering Decisions

The pipeline validates every layer and documents source-data
limitations rather than over-claiming completeness:

- **Deduplication**: 2,622 raw rows → 2,142 unique jobs
  (ROW_NUMBER dedup; PK uniqueness verified).
- **Fuzzy duplicates**: detected and quantified — loose match
  27.3% upper bound tightened to ~5.1%; recorded as known
  limitation rather than risk false removals.
- **Salary**: Adzuna AU API omits salary for ~90% of postings.
  Text regex extraction was evaluated and rejected (low yield +
  noise risk, e.g. funding amounts). Strategy: API-native salary
  only with sanity cleaning (sub-30k AUD values invalidated as
  errors). Final coverage 9.2%, documented as market limitation.
- **Skills**: 31 curated low-ambiguity skills matched via
  word-boundary REGEXP (MySQL) / PATINDEX character class
  (Fabric Warehouse). Coverage capped at ~14% because the
  Adzuna free API truncates descriptions at 500 characters,
  cutting off skill sections — a source limitation, not a
  matching defect.
- **Cross-dialect parity** (Week 3): 7 of 8 tables in Fabric
  Warehouse match the MySQL row counts exactly; `dim_company`
  differs by +1 (812 vs 811, +0.12%), traced to a subtle
  unicode-whitespace handling difference between MySQL `TRIM()`
  and T-SQL `LTRIM(RTRIM())`. Documented as a known dialect
  quirk rather than masked.

The consistent approach — _quantify the limitation, then make a
defensible scoping decision_ — runs through salary, skills,
duplicate handling, and cross-engine parity.

## 🛠️ Tech Stack

| Layer           | Tool                                             |
| --------------- | ------------------------------------------------ |
| Extract         | Python (requests)                                |
| Storage (local) | MySQL 8                                          |
| Storage (cloud) | Microsoft Fabric — OneLake, Lakehouse, Warehouse |
| Transform       | SQL (ELT pattern): MySQL DML + T-SQL DML         |
| Connectivity    | On-premises Data Gateway (MySQL → Fabric)        |
| Orchestration   | Fabric Data Pipeline (Copy data activity)        |
| Visualization   | Power BI Desktop (Week 2) + Direct Lake (Week 4) |
| Version Control | Git + GitHub                                     |

## 📁 Project Structure

```
.
├── config/                  # Configuration files
├── src/                     # Source code (extract, load, utils)
├── pipelines/               # Pipeline orchestration scripts
├── sql/
│   ├── schema/              # MySQL table definitions (raw, staging, mart)
│   ├── transform/           # MySQL ELT scripts (staging load, DQ, mart, skills)
│   └── fabric/              # T-SQL versions for Fabric Warehouse
│       ├── schema/          # Fabric DDL (staging, mart star schema)
│       └── transform/       # Fabric DML (staging load, DQ, mart, skills)
├── docs/                    # Migration notes & design documentation
├── notebooks/               # Exploratory analysis
└── data/                    # Local data storage (gitignored)
```

## 🚀 Setup

```bash
# Clone repository
git clone https://github.com/chihchuan35/adzuna-job-market-pipeline.git
cd adzuna-job-market-pipeline

# Create virtual environment
python -m venv venv
venv\Scripts\activate  # Windows
# source venv/bin/activate  # Mac/Linux

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env
# Edit .env with your credentials
```

## 📊 Dashboards

_Coming in Week 4 — Power BI Direct Lake connection to Fabric Warehouse, leveraging OneLake shared storage for zero-copy analytics._

## 📝 License

MIT
