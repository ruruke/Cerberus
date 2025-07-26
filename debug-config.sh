#!/bin/bash

# Debug config loading
export SCRIPT_DIR=$(pwd)
export CONFIG_FILE=test-config.toml
export BUILT_DIR=built

# Enable debug logging
export LOG_LEVEL=0

source lib/core/utils.sh
source lib/core/config-simple.sh

echo "Starting config load debug..."
config_load
echo "Config load completed!"