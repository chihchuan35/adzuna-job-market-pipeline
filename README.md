# 🇦🇺 Adzuna Job Market Pipeline

End-to-end ETL pipeline analyzing the Australian data job market.

> ✅ **Status**: Week 1 complete - Extract pipeline operational (2,622 records ingested)

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

.
├── config/ # Configuration files
├── src/ # Source code (extract, load, utils)
├── pipelines/ # Pipeline orchestration scripts
├── sql/ # SQL scripts (schema, transforms)
├── notebooks/ # Exploratory analysis
└── data/ # Local data storage (gitignored)

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
