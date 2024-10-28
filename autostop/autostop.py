#!/usr/bin/env python3

import logging
import os
import sys
import time
from datetime import datetime

import boto3
import psutil


def setup_logging() -> logging.Logger:
    """
    Set up the logging configuration for the script.

    Returns:
        logging.Logger: The logger object.
    """
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
        handlers=[
            logging.StreamHandler(),
            logging.FileHandler("/home/ec2-user/SageMaker/autostop.log")
        ]
    )
    return logging.getLogger(__name__)

def load_config() -> dict:
    """
    Load configuration from a file or default settings.

    Returns:
        dict: A dictionary containing the loaded or default configuration values.
    """
    config = {
        "IDLE_TIME": 3600,
        "CPU_THRESHOLD": 5.0,
        "ACTIVE_HOURS_START": 7,
        "ACTIVE_HOURS_END": 19,
        "CHECK_INTERVAL": 300
    }

    config_file = os.path.join(os.path.dirname(__file__), "autostop_config.env")
    if os.path.exists(config_file):
        with open(config_file, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    key, value = line.split("=", 1)
                    config[key.strip()] = float(value.strip())

    return config

def is_cpu_idle(threshold: float, duration: int = 300) -> bool:
    """
    Check if CPU usage is below the specified threshold for a given duration.

    Args:
        threshold (float): The CPU usage threshold percentage.
        duration (int): The time in seconds to check for CPU idle state.

    Returns:
        bool: True if CPU is below the threshold for the duration, False otherwise.
    """
    start_time = time.time()
    while time.time() - start_time < duration:
        cpu_percent = psutil.cpu_percent(interval=1)
        if cpu_percent > threshold:
            return False
    return True

def is_within_active_hours(start_hour: int, end_hour: int) -> bool:
    """
    Check if the current time is within the active hours.

    Args:
        start_hour (int): Start hour of the active period.
        end_hour (int): End hour of the active period.

    Returns:
        bool: True if the current time is within active hours, False otherwise.
    """
    current_hour = datetime.now().hour
    return start_hour <= current_hour < end_hour

def stop_instance() -> None:
    """
    Stop the SageMaker notebook instance.
    """
    try:
        instance_name = os.environ.get("NOTEBOOK_NAME")
        if not instance_name:
            raise ValueError("NOTEBOOK_NAME environment variable not set")

        region = os.environ.get("AWS_REGION", "us-west-2")
        sagemaker = boto3.client("sagemaker", region_name=region)

        sagemaker.stop_notebook_instance(NotebookInstanceName=instance_name)
        logging.info(f"Successfully initiated shutdown of notebook instance: {instance_name}")

    except Exception as e:
        logging.error(f"Failed to stop notebook instance: {str(e)}")
        sys.exit(1)

def main() -> None:
    """
    Main function to run the autostop logic.
    """
    logger = setup_logging()
    config = load_config()

    while True:
        try:
            # Check if we're within active hours
            if not is_within_active_hours(
                config["ACTIVE_HOURS_START"],
                config["ACTIVE_HOURS_END"]
            ):
                logger.info("Outside active hours, checking CPU usage")

                # Check if CPU is idle
                if is_cpu_idle(config["CPU_THRESHOLD"]):
                    logger.info("CPU is idle, initiating shutdown")
                    stop_instance()
                    break

            # Wait before next check
            time.sleep(config["CHECK_INTERVAL"])

        except Exception as e:
            logger.error(f"Error in autostop monitoring: {str(e)}")
            sys.exit(1)

if __name__ == "__main__":
    main()
