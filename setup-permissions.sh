#!/bin/bash

# Cerberus Permission Setup Script
# Sets executable permissions for all scripts in the project

set -euo pipefail

echo "🔧 Setting up Cerberus permissions..."
echo "===================================="

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Count of files processed
files_processed=0

echo "📝 Making main CLI executable..."
if [[ -f "cerberus.sh" ]]; then
    chmod +x cerberus.sh
    echo "  ✅ cerberus.sh"
    ((files_processed++))
fi

echo
echo "📝 Making library scripts executable..."
find lib/ -name "*.sh" -type f | while read -r script; do
    chmod +x "$script"  
    echo "  ✅ $script"
    ((files_processed++))
done

echo
echo "📝 Making test scripts executable..."
find tests/ -name "*.sh" -type f | while read -r script; do
    chmod +x "$script"
    echo "  ✅ $script"
    ((files_processed++))
done

echo
echo "📝 Making utility scripts executable..."
for script in setup-permissions.sh; do
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        echo "  ✅ $script"
        ((files_processed++))
    fi
done

# Check if any scripts in root need permissions
echo
echo "📝 Checking root directory scripts..."
find . -maxdepth 1 -name "*.sh" -type f | while read -r script; do
    if [[ "$script" != "./setup-permissions.sh" && "$script" != "./cerberus.sh" ]]; then
        chmod +x "$script"
        echo "  ✅ $script"
        ((files_processed++))
    fi
done

echo
echo "🔍 Verifying permissions..."
echo "=========================="

# Verify main CLI
if [[ -x "cerberus.sh" ]]; then
    echo "  ✅ cerberus.sh is executable"
else
    echo "  ❌ cerberus.sh is not executable"
fi

# Check for non-executable scripts
non_executable=0
find . -name "*.sh" -type f ! -executable | while read -r script; do
    echo "  ⚠️  $script is not executable"
    ((non_executable++))
done

echo
echo "📊 Summary"
echo "=========="
echo "  Scripts processed: $(find . -name "*.sh" -type f | wc -l)"
echo "  Executable scripts: $(find . -name "*.sh" -type f -executable | wc -l)"
echo "  Non-executable: $(find . -name "*.sh" -type f ! -executable | wc -l)"

echo
if [[ $(find . -name "*.sh" -type f ! -executable | wc -l) -eq 0 ]]; then
    echo "🎉 All scripts are now executable!"
    echo
    echo "🚀 You can now run:"
    echo "   ./cerberus.sh --help"
    echo "   ./cerberus.sh test --integration"
    echo "   ./tests/test-minimal.sh"
else
    echo "⚠️  Some scripts are still not executable."
    echo "   You may need to run this script with sudo or check file permissions."
fi

echo
echo "✨ Permission setup complete!"