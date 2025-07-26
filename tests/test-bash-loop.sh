#!/bin/bash

# Test bash loop behavior

set -euo pipefail

echo "Testing bash for loop..."

# Simple test
echo "Test 1: Simple loop"
for ((i=0; i<3; i++)); do
    echo "i = $i"
done

echo
echo "Test 2: Loop with variable modification"
count=3
for ((i=0; i<count; i++)); do
    echo "i = $i (count = $count)"
    # Accidentally modifying i somewhere?
    if [[ $i -eq 1 ]]; then
        echo "  Processing i=1..."
    fi
done

echo
echo "Test 3: Check for variable collision"
i=999
echo "Before loop: i = $i"
for ((i=0; i<3; i++)); do
    echo "In loop: i = $i"
done
echo "After loop: i = $i"