# 🇦🇺 Adzuna Job Market Pipeline

End-to-end ETL pipeline analyzing the Australian data job market.

> ✅ **Status**: Week 2 complete — ELT transform & star schema operational (raw → staging → mart)

## 🎯 Business Questions

This project answers:

- Which cities and companies are hiring data professionals in Australia?
- How do salary ranges compare across Data Analyst, Data Engineer, and Data Scientist roles?
- What are the most in-demand technical skills?
- How does demand trend over time?

## 🏗️ Architecture

Adzuna API → Python (Extract) → MySQL (Raw Layer)
↓
SQL (Transform: Staging → Mart)
↓
Power BI Dashboard

Dual deployment:

- **Local**: MySQL + Power BI Desktop
- **Cloud**: Microsoft Fabric Lakehouse + Power BI Service
  **Pipeline flow**: 2,622 raw API rows → 2,142 deduplicated staging rows → star schema (1 fact + 5 dimensions + 1 bridge), 100% referential integrity.

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
  word-boundary REGEXP. Coverage capped at ~14% because the
  Adzuna free API truncates descriptions at 500 characters,
  cutting off skill sections — a source limitation, not a
  matching defect.

The consistent approach — _quantify the limitation, then make a
defensible scoping decision_ — runs through salary, skills, and
duplicate handling.

## 🛠️ Tech Stack

| Layer           | Tool                     |
| --------------- | ------------------------ |
| Extract         | Python (requests)        |
| Storage         | MySQL / Microsoft Fabric |
| Transform       | SQL (ELT pattern)        |
| Visualization   | Power BI                 |
| Orchestration   | Fabric Data Pipeline     |
| Version Control | Git + GitHub             |

## 📁 Project Structure

```
.
├── config/         # Configuration files
├── src/            # Source code (extract, load, utils)
├── pipelines/      # Pipeline orchestration scripts
├── sql/
│   ├── schema/      # Table definitions (raw, staging, mart)
│   └── transform/   # ELT scripts (staging load, DQ, mart load, skills)
├── notebooks/      # Exploratory analysis
└── data/           # Local data storage (gitignored)
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

_Coming in Week 4_

## 📝 License

MIT
