#!/usr/bin/env bash
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

export_developer_dir

echo "Building Commandly (Debug) with DEVELOPER_DIR=${DEVELOPER_DIR}"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build
