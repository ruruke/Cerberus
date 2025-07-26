#!/bin/bash

# Minimal Cerberus Test - Just check files exist
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Check main files exist
if [[ -f "$SCRIPT_DIR/cerberus.sh" && -f "$SCRIPT_DIR/lib/core/utils.sh" ]]; then
    echo "✅ Core files exist"
    exit 0
else
    echo "❌ Core files missing"
    exit 1
fi