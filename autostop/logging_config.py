import logging
import sys
from typing import Any, Dict


def setup_logging(level: int = logging.INFO) -> None:
    """Configure logging for the autostop application."""
    logging_config: Dict[str, Any] = {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "standard": {
                "format": "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
            },
        },
        "handlers": {
            "default": {
                "level": level,
                "formatter": "standard",
                "class": "logging.StreamHandler",
                "stream": sys.stdout,
            },
            "file": {
                "level": level,
                "formatter": "standard",
                "class": "logging.FileHandler",
                "filename": "autostop.log",
                "mode": "a",
            },
        },
        "loggers": {
            "": {  # root logger
                "handlers": ["default", "file"],
                "level": level,
                "propagate": True
            }
        }
    }

    logging.config.dictConfig(logging_config)
