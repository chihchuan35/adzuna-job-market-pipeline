"""
Adzuna API client.
Handles authentication, pagination, and retry logic.
"""

import time
import requests
from typing import Dict, List, Any
from src.utils.logger import log


class AdzunaClient:
    """Client for fetching job postings from the Adzuna API."""

    def __init__(self, app_id: str, app_key: str, base_url: str):
        """
        Initialise the Adzuna API client.

        Args:
            app_id: Adzuna application ID.
            app_key: Adzuna application key.
            base_url: Adzuna API base URL.
        """
        self.app_id = app_id
        self.app_key = app_key
        self.base_url = base_url

    def search_jobs(
        self,
        country: str,
        keyword: str,
        page: int = 1,
        results_per_page: int = 50,
        salary_include_unknown: int = 1,
        sort_by: str = "date",
        max_retries: int = 3,
        backoff_seconds: int = 2,
    ) -> Dict[str, Any]:
        """
        Search jobs from Adzuna API for a single page.

        Args:
            country: Country code (e.g. 'au').
            keyword: Job title keyword to search.
            page: Page number (1-based).
            results_per_page: Results per page (max 50).
            salary_include_unknown: 1 to include jobs without salary.
            sort_by: Sort order ('date', 'salary', 'relevance').
            max_retries: Maximum retry attempts on failure.
            backoff_seconds: Seconds to wait between retries.

        Returns:
            JSON response from the API.

        Raises:
            requests.RequestException: If all retries fail.
        """
        url = f"{self.base_url}/{country}/search/{page}"
        params = {
            "app_id": self.app_id,
            "app_key": self.app_key,
            "results_per_page": results_per_page,
            "what": keyword,
            "salary_include_unknown": salary_include_unknown,
            "sort_by": sort_by,
        }

        for attempt in range(1, max_retries + 1):
            try:
                log.info(f"Fetching '{keyword}' page {page} (attempt {attempt})")
                response = requests.get(url, params=params, timeout=30)
                response.raise_for_status()
                return response.json()

            except requests.RequestException as e:
                log.warning(f"Attempt {attempt} failed: {e}")
                if attempt < max_retries:
                    sleep_time = backoff_seconds * attempt
                    log.info(f"Retrying in {sleep_time}s...")
                    time.sleep(sleep_time)
                else:
                    log.error(
                        f"All {max_retries} attempts failed for '{keyword}' page {page}"
                    )
                    raise

    def fetch_all_pages(
        self,
        country: str,
        keyword: str,
        max_pages: int,
        **kwargs,
    ) -> List[Dict[str, Any]]:
        """
        Fetch all pages of results for a given keyword.

        Args:
            country: Country code.
            keyword: Job title keyword.
            max_pages: Maximum number of pages to fetch.
            **kwargs: Additional parameters passed to search_jobs.

        Returns:
            Combined list of all job results across pages.
        """
        all_jobs = []
        for page in range(1, max_pages + 1):
            response = self.search_jobs(
                country=country, keyword=keyword, page=page, **kwargs
            )
            jobs = response.get("results", [])

            if not jobs:
                log.info(f"No more results at page {page}, stopping.")
                break

            all_jobs.extend(jobs)
            log.info(
                f"Page {page}: collected {len(jobs)} jobs (total: {len(all_jobs)})"
            )

            # Be polite — avoid hammering the API
            time.sleep(0.5)

        return all_jobs
