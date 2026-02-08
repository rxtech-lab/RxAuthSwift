#!/bin/bash
set -euo pipefail

echo "Building RxAuthSwift for macOS..."
swift build

echo "macOS build succeeded."

echo "Running tests..."
swift test

echo "All tests passed."
