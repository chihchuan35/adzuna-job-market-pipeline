"""
Main extract pipeline.
Fetches job data from Adzuna for each configured keyword
and loads it into MySQL raw_jobs.

Usage:
    python pipelines/run_extract.py
"""

import sys
from pathlib import Path

# Add project root to Python path so 'src' imports work when running this script
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.utils.config_loader import load_config
from src.utils.logger import log
from src.extract.adzuna_client import AdzunaClient
from src.load.mysql_loader import MySQLLoader


def main():
    """Run the full extract pipeline."""
    log.info("=" * 60)
    log.info("Starting Adzuna extract pipeline")
    log.info("=" * 60)

    # 1. Load configuration
    cfg = load_config()
    adzuna_cfg = cfg["adzuna"]
    mysql_cfg = cfg["mysql"]
    creds = cfg["credentials"]

    # 2. Initialise clients
    client = AdzunaClient(
        app_id=creds["adzuna_app_id"],
        app_key=creds["adzuna_app_key"],
        base_url=adzuna_cfg["base_url"],
    )

    loader = MySQLLoader(
        host=mysql_cfg["host"],
        port=mysql_cfg["port"],
        user=mysql_cfg["user"],
        password=mysql_cfg["password"],
        database=mysql_cfg["database"],
    )

    # 3. Sanity check the database connection before hitting the API
    if not loader.test_connection():
        log.error("Cannot connect to MySQL. Aborting.")
        sys.exit(1)

    # 4. Loop through each keyword and fetch + load
    total_inserted = 0
    for keyword in cfg["job_titles"]:
        log.info(f"--- Processing: {keyword} ---")

        try:
            jobs = client.fetch_all_pages(
                country=adzuna_cfg["country"],
                keyword=keyword,
                max_pages=adzuna_cfg["max_pages"],
                results_per_page=adzuna_cfg["results_per_page"],
                salary_include_unknown=adzuna_cfg["salary_include_unknown"],
                sort_by=adzuna_cfg["sort_by"],
            )

            log.info(f"Fetched {len(jobs)} jobs for '{keyword}'")

            rows = loader.insert_jobs(jobs, search_term=keyword)
            total_inserted += rows

        except Exception as e:
            log.error(f"Failed to process '{keyword}': {e}")
            # Continue with next keyword instead of aborting the whole pipeline
            continue

    # 5. Summary
    log.info("=" * 60)
    log.info(f"Pipeline completed. Total rows affected: {total_inserted}")
    log.info("=" * 60)


if __name__ == "__main__":
    main()
