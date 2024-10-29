#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Start code-server
nohup code-server --bind-addr 0.0.0.0:8080 &

# Auto-stop after inactivity
IDLE_TIMEOUT=5400 # Idle timeout in seconds (1.5 hours)
INSTANCE_NAME="${INSTANCE_NAME:-default-notebook}"

while true; do
	last_activity=$(date +%s -r /proc/$(pgrep -o jupyter-notebook)/)
	current_time=$(date +%s)
	idle_time=$((current_time - last_activity))

	if [[ $idle_time -ge $IDLE_TIMEOUT ]]; then
		echo "Notebook idle for $IDLE_TIMEOUT seconds. Stopping instance..."
		aws sagemaker stop-notebook-instance --notebook-instance-name $INSTANCE_NAME
		break
	fi
	sleep 300
done
