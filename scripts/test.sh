#!/usr/bin/env bash
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

export_developer_dir
status=0

echo "Running package tests..."
if ! swift test --package-path "${PACKAGE_PATH}"; then
  echo "Package tests failed" >&2
  status=1
fi

echo "Running Xcode unit tests..."
if ! xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -only-testing:CommandlyTests \
  test; then
  echo "Xcode tests failed" >&2
  status=1
fi

if [[ "${status}" -ne 0 ]]; then
  exit "${status}"
fi

echo "All requested tests passed."
