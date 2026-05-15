"""
Configuration loader.
Merges YAML settings with environment variables from .env
"""

import os
import yaml
from pathlib import Path
from dotenv import load_dotenv
from typing import Dict, Any


def load_config(config_path: str = "config/config.yaml") -> Dict[str, Any]:
    """
    Load YAML config and merge with environment variables.

    Returns:
        Combined dictionary of all settings.

    Raises:
        FileNotFoundError: If config file is missing.
        ValueError: If required credentials are not set.
    """
    # Load environment variables from .env
    load_dotenv()

    # Read YAML config
    config_file = Path(config_path)
    if not config_file.exists():
        raise FileNotFoundError(f"Config file not found: {config_path}")

    with open(config_file, "r", encoding="utf-8") as f:
        config = yaml.safe_load(f)

    # Inject credentials from environment
    config["credentials"] = {
        "adzuna_app_id": os.getenv("ADZUNA_APP_ID"),
        "adzuna_app_key": os.getenv("ADZUNA_APP_KEY"),
    }

    config["mysql"] = {
        "host": os.getenv("MYSQL_HOST", "localhost"),
        "port": int(os.getenv("MYSQL_PORT", 3306)),
        "user": os.getenv("MYSQL_USER", "root"),
        "password": os.getenv("MYSQL_PASSWORD"),
        "database": os.getenv("MYSQL_DATABASE", "adzuna_jobs"),
    }

    # Validate required credentials
    if not config["credentials"]["adzuna_app_id"]:
        raise ValueError("ADZUNA_APP_ID not found in .env")
    if not config["credentials"]["adzuna_app_key"]:
        raise ValueError("ADZUNA_APP_KEY not found in .env")
    if not config["mysql"]["password"]:
        raise ValueError("MYSQL_PASSWORD not found in .env")

    return config


if __name__ == "__main__":
    # Quick smoke test: run this file directly to verify config loads
    cfg = load_config()
    print("Config loaded successfully")
    print(f"  Adzuna country: {cfg['adzuna']['country']}")
    print(f"  Job titles: {cfg['job_titles']}")
    print(f"  MySQL database: {cfg['mysql']['database']}")
