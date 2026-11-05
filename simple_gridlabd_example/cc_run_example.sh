#!/bin/bash
# Backward-compatibility wrapper for run_mission1.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/run_mission1.sh" "$@"
