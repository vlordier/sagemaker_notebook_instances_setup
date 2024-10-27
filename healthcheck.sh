#!/bin/bash

# Health check script to monitor critical services
set -euo pipefail
IFS=$'\n\t'

# Ensure script has proper permissions
if [ ! -x "$0" ]; then
    echo "❌ Error: Script must be executable"
    chmod +x "$0" || { echo "Failed to set executable permission"; exit 1; }
fi

# Verify permissions of critical files
check_file_permissions() {
    local file=$1
    local expected_perms=$2

    if [ ! -f "$file" ]; then
        echo "❌ Error: File not found: $file"
        return 1
    }

    local actual_perms
    actual_perms=$(stat -f "%Lp" "$file")

    if [ "$actual_perms" != "$expected_perms" ]; then
        echo "⚠️ Warning: Incorrect permissions on $file: $actual_perms (expected $expected_perms)"
        chmod "$expected_perms" "$file" || {
            echo "❌ Error: Failed to set permissions on $file"
            return 1
        }
    fi
    return 0
}

# Check permissions of critical files
critical_files=(
    "/usr/local/bin/autostop.py:755"
    "/home/ec2-user/.config/code-server/config.yaml:600"
    "/opt/ml/certificates/mykey.key:600"
    "/opt/ml/certificates/mycert.crt:644"
)

for file_entry in "${critical_files[@]}"; do
    IFS=':' read -r file perms <<< "$file_entry"
    check_file_permissions "$file" "$perms" || echo "⚠️ Warning: Permission check failed for $file"
done

# Configure logging
exec 1> >(logger -s -t "$(basename "$0")") 2>&1

check_service() {
	local service=$1
	if ! systemctl is-active --quiet "$service"; then
		echo "❌ ERROR: $service is not running"
		return 1
	fi
	echo "✅ OK: $service is running"
	return 0
}

check_endpoint() {
	local url=$1
	local max_retries=3
	local retry=0

	while [ $retry -lt $max_retries ]; do
		if curl -sf "$url" >/dev/null; then
			echo "✅ OK: $url is responding"
			return 0
		fi
		retry=$((retry + 1))
		echo "⚠️ Attempt $retry of $max_retries: $url not responding"
		sleep 2
	done

	echo "❌ ERROR: $url is not responding after $max_retries attempts"
	return 1
}

# Check critical services
check_service "code-server"
check_service "nginx"

# Check endpoints
check_endpoint "https://localhost/health"

# Check disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 85 ]; then
	echo "⚠️ WARNING: Disk usage is at ${DISK_USAGE}%"
fi

# Check memory usage
MEM_USAGE=$(free | awk '/Mem:/ {printf("%.0f", $3/$2 * 100)}')
if [ "$MEM_USAGE" -gt 90 ]; then
	echo "⚠️ WARNING: Memory usage is at ${MEM_USAGE}%"
fi
