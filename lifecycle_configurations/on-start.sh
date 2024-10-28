#!/bin/bash
set -e

# Configure logging
exec 1> >(logger -s -t $(basename $0)) 2>&1

echo "Starting instance services..."

# Start autostop monitoring
nohup python3 /home/ec2-user/SageMaker/autostop/autostop.py >/home/ec2-user/SageMaker/autostop.log 2>&1 &

echo "Instance startup completed"
