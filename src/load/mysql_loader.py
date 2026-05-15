"""
MySQL loader.
Inserts job records into the raw_jobs table with idempotent upsert.
"""

import json
from datetime import datetime
from typing import Dict, List, Any
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from src.utils.logger import log


class MySQLLoader:
    """Handles writing raw API responses to the MySQL raw layer."""

    def __init__(self, host: str, port: int, user: str, password: str, database: str):
        """
        Initialise the MySQL loader and create a SQLAlchemy engine.

        Args:
            host: MySQL host.
            port: MySQL port.
            user: MySQL username.
            password: MySQL password.
            database: Target database name.
        """
        connection_string = (
            f"mysql+pymysql://{user}:{password}@{host}:{port}/{database}"
            "?charset=utf8mb4"
        )
        self.engine: Engine = create_engine(connection_string, pool_pre_ping=True)
        self.database = database
        log.info(f"MySQL engine created for {host}:{port}/{database}")

    def test_connection(self) -> bool:
        """Run a simple query to verify the connection works."""
        try:
            with self.engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            log.info("MySQL connection test passed")
            return True
        except Exception as e:
            log.error(f"MySQL connection test failed: {e}")
            return False

    def insert_jobs(self, jobs: List[Dict[str, Any]], search_term: str) -> int:
        """
        Insert a batch of jobs into raw_jobs.

        Uses ON DUPLICATE KEY UPDATE for idempotency: re-running the
        pipeline updates existing records instead of failing.

        Args:
            jobs: List of job dicts from the Adzuna API.
            search_term: The keyword used to find these jobs.

        Returns:
            Number of rows affected (inserted + updated).
        """
        if not jobs:
            log.warning(f"No jobs to insert for '{search_term}'")
            return 0

        insert_sql = text("""
            INSERT INTO raw_jobs (
                job_id, title, company_name, location_display,
                category_tag, contract_type, contract_time,
                salary_min, salary_max, salary_is_predicted,
                latitude, longitude, created_at,
                raw_data, search_term, fetched_at
            )
            VALUES (
                :job_id, :title, :company_name, :location_display,
                :category_tag, :contract_type, :contract_time,
                :salary_min, :salary_max, :salary_is_predicted,
                :latitude, :longitude, :created_at,
                :raw_data, :search_term, :fetched_at
            )
            ON DUPLICATE KEY UPDATE
                title = VALUES(title),
                company_name = VALUES(company_name),
                location_display = VALUES(location_display),
                category_tag = VALUES(category_tag),
                contract_type = VALUES(contract_type),
                contract_time = VALUES(contract_time),
                salary_min = VALUES(salary_min),
                salary_max = VALUES(salary_max),
                salary_is_predicted = VALUES(salary_is_predicted),
                latitude = VALUES(latitude),
                longitude = VALUES(longitude),
                created_at = VALUES(created_at),
                raw_data = VALUES(raw_data),
                fetched_at = VALUES(fetched_at)
        """)

        records = [self._to_record(job, search_term) for job in jobs]

        with self.engine.begin() as conn:
            result = conn.execute(insert_sql, records)
            row_count = result.rowcount

        log.info(f"Inserted/updated {row_count} rows for '{search_term}'")
        return row_count

    def _to_record(self, job: Dict[str, Any], search_term: str) -> Dict[str, Any]:
        """
        Convert an Adzuna job dict into a flat record for raw_jobs.

        Safely handles missing fields (Adzuna often omits salary, contract_type, etc).
        """
        company = job.get("company") or {}
        category = job.get("category") or {}
        location = job.get("location") or {}

        created_str = job.get("created")
        created_at = None
        if created_str:
            try:
                # Adzuna format: "2026-03-25T21:23:49Z"
                created_at = datetime.strptime(created_str, "%Y-%m-%dT%H:%M:%SZ")
            except ValueError:
                log.warning(f"Could not parse created date: {created_str}")

        return {
            "job_id": str(job.get("id", "")),
            "title": job.get("title"),
            "company_name": company.get("display_name"),
            "location_display": location.get("display_name"),
            "category_tag": category.get("tag"),
            "contract_type": job.get("contract_type"),
            "contract_time": job.get("contract_time"),
            "salary_min": job.get("salary_min"),
            "salary_max": job.get("salary_max"),
            "salary_is_predicted": job.get("salary_is_predicted"),
            "latitude": job.get("latitude"),
            "longitude": job.get("longitude"),
            "created_at": created_at,
            "raw_data": json.dumps(job, ensure_ascii=False),
            "search_term": search_term,
            "fetched_at": datetime.utcnow(),
        }
