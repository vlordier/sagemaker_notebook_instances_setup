import boto3
import logging
import os
import requests
import time
from typing import Optional, List, Dict, Any
import psutil
from botocore.exceptions import BotoCoreError, ClientError

from logging_config import setup_logging

logger = logging.getLogger(__name__)

class AutoStop:
    """Manages automatic stopping of idle AWS resources."""

    def __init__(self, idle_time: int = 3600, check_interval: int = 300) -> None:
        """
        Initialize AutoStop with configuration.

        Args:
            idle_time: Seconds of idle time before stopping (default: 1 hour)
            check_interval: Seconds between checks (default: 5 minutes)
        """
        setup_logging()
        self.idle_time = idle_time
        self.check_interval = check_interval
        self.session = boto3.Session()
        self.ec2 = self.session.client('ec2')
        
        logger.info("AutoStop initialized with idle_time=%d, check_interval=%d", 
                   idle_time, check_interval)

    def get_instance_id(self) -> Optional[str]:
        """Get the current EC2 instance ID."""
        try:
            response = requests.get(
                'http://169.254.169.254/latest/meta-data/instance-id',
                timeout=2
            )
            instance_id = response.text
            logger.debug("Retrieved instance ID: %s", instance_id)
            return instance_id
        except Exception as e:
            logger.error("Failed to get instance ID: %s", str(e))
            return None

    def get_system_load(self) -> float:
        """Get current system CPU utilization."""
        try:
            return psutil.cpu_percent(interval=1)
        except Exception as e:
            logger.error("Failed to get CPU utilization: %s", str(e))
            return 0.0

    def stop_instance(self, instance_id: str) -> bool:
        """
        Stop the specified EC2 instance.

        Args:
            instance_id: The ID of the instance to stop

        Returns:
            bool: True if stop succeeded, False otherwise
        """
        try:
            self.ec2.stop_instances(InstanceIds=[instance_id])
            logger.info("Successfully initiated stop for instance %s", instance_id)
            return True
        except (BotoCoreError, ClientError) as e:
            logger.error("Failed to stop instance %s: %s", instance_id, str(e))
            return False

    def run(self) -> None:
        """Main monitoring loop."""
        logger.info("Starting AutoStop monitoring")
        
        instance_id = self.get_instance_id()
        if not instance_id:
            logger.error("Could not determine instance ID, exiting")
            return

        while True:
            try:
                cpu_percent = self.get_system_load()
                logger.info("Current CPU utilization: %.1f%%", cpu_percent)

                if cpu_percent < 5.0:  # Consider idle if CPU < 5%
                    logger.warning(
                        "System appears idle (CPU: %.1f%%), will stop in %d seconds if continues",
                        cpu_percent, self.idle_time
                    )
                    
                    # Double check after idle_time
                    time.sleep(self.idle_time)
                    
                    current_cpu = self.get_system_load()
                    if current_cpu < 5.0:
                        logger.warning(
                            "System still idle after %d seconds, stopping instance",
                            self.idle_time
                        )
                        if self.stop_instance(instance_id):
                            break
                
                time.sleep(self.check_interval)
                
            except Exception as e:
                logger.error("Error in monitoring loop: %s", str(e))
                time.sleep(self.check_interval)

def main() -> None:
    """Entry point for the autostop utility."""
    # Get configuration from environment or use defaults
    idle_time = int(os.getenv('AUTOSTOP_IDLE_TIME', '3600'))
    check_interval = int(os.getenv('AUTOSTOP_CHECK_INTERVAL', '300'))
    
    auto_stop = AutoStop(idle_time=idle_time, check_interval=check_interval)
    auto_stop.run()

if __name__ == '__main__':
    main()
