#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Install code-server or any other tools
curl -fsSL https://code-server.dev/install.sh | sh
