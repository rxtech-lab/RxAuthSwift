#!/bin/bash
set -euo pipefail

echo "Building RxAuthSwift for iOS..."
xcodebuild build \
  -scheme RxAuthSwift-Package \
  -destination 'generic/platform=iOS' \
  -skipPackagePluginValidation \
  | xcpretty || xcodebuild build \
  -scheme RxAuthSwift-Package \
  -destination 'generic/platform=iOS' \
  -skipPackagePluginValidation

echo "iOS build succeeded."
