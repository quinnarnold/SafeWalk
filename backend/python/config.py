"""Configuration for Python compute layer."""
import os

from dotenv import load_dotenv

load_dotenv()


class Settings:
    """Application settings loaded from environment variables."""

    CITY_NAME: str = os.getenv("CITY_NAME", "boston")
    DATA_DIR: str = os.getenv("DATA_DIR", "/app/data")
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO").upper()

    DEFAULT_SPEED_MPS: float = float(os.getenv("DEFAULT_SPEED_MPS", "1.4"))
    MODERATE_ALPHA: float = float(os.getenv("MODERATE_ALPHA", "75000.0"))
    SAFEST_ALPHA: float = float(os.getenv("SAFEST_ALPHA", "200000.0"))


settings = Settings()
