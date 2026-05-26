#!/bin/bash
set -euo pipefail

echo "Building RxAuthSwift for macOS..."
swift build

echo "macOS build succeeded."

# Note: `swift test` is intentionally skipped here. The package targets
# .macOS(.v26), so xctest bundles are linked for macOS 26, which the
# GitHub-hosted `macos-latest` runner cannot load (its OS is older than
# the deployment target). Unit tests run on the self-hosted runner job.
