# 🇦🇺 Adzuna Job Market Pipeline

End-to-end ETL pipeline analyzing the Australian data job market.

> ✅ **Status**: Week 2 in progress - Staging layer & data quality complete (2,142 unique jobs)

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

## 📋 Data Quality

Staging layer validated with 8 automated DQ checks:

- **Deduplication**: 2,622 raw rows → 2,142 unique jobs (PK uniqueness verified)
- **Completeness**: 0 NULLs in title/company/date; 10.6% missing state (Adzuna source limitation)
- **Fuzzy duplicates**: Detected & quantified (loose 27.3% → tightened ~5.1%); recorded as known limitation
- **Salary gap**: 90.2% of jobs lack API salary → justifies regex extraction (next phase)

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
│   ├── schema/     # Table definitions (raw, staging)
│   └── transform/  # ELT transform + DQ scripts
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
