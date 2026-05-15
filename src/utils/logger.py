"""
Logger setup for the ETL pipeline.
Provides consistent, color-coded logging across all modules.
"""

from loguru import logger
import sys
from pathlib import Path


def setup_logger(log_file: str = "logs/pipeline.log", level: str = "INFO"):
    """
    Configure the logger with console + file output.

    Args:
        log_file: Path to log file
        level: Logging level (DEBUG, INFO, WARNING, ERROR)
    """
    # Remove default handler
    logger.remove()

    # Console output (colored)
    logger.add(
        sys.stdout,
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "
        "<level>{level: <8}</level> | "
        "<cyan>{name}</cyan> - <level>{message}</level>",
        level=level,
        colorize=True,
    )

    # File output (no colors, with rotation)
    log_path = Path(log_file)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    logger.add(
        log_file,
        format="{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {name} - {message}",
        level=level,
        rotation="10 MB",  # 檔案超過 10MB 就分割
        retention="30 days",  # 保留 30 天
        encoding="utf-8",
    )

    return logger


# 預設 logger，import 進來就能用
log = setup_logger()
