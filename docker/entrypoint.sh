#!/bin/bash
# entrypoint.sh — IT-Stack graylog container entrypoint
set -euo pipefail

echo "Starting IT-Stack GRAYLOG (Module 20)..."

# Source any environment overrides
if [ -f /opt/it-stack/graylog/config.env ]; then
    # shellcheck source=/dev/null
    source /opt/it-stack/graylog/config.env
fi

# Execute the upstream entrypoint or command
exec "$$@"
