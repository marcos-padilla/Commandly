#!/usr/bin/env bash
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

export_developer_dir

echo "Bootstrapping Commandly..."

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is required" >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift is required" >&2
  exit 1
fi

LOCAL_CONFIG="${ROOT_DIR}/config/Local.xcconfig"
EXAMPLE_CONFIG="${ROOT_DIR}/config/Local.example.xcconfig"
if [[ ! -f "${LOCAL_CONFIG}" ]]; then
  cp "${EXAMPLE_CONFIG}" "${LOCAL_CONFIG}"
  echo "Created config/Local.xcconfig from example"
else
  echo "Preserved existing config/Local.xcconfig"
fi

echo "Resolving Swift packages..."
swift package --package-path "${PACKAGE_PATH}" resolve
xcodebuild -resolvePackageDependencies -project "${PROJECT_PATH}" -scheme "${SCHEME}" -derivedDataPath "${DERIVED_DATA_PATH}" >/dev/null

echo "Bootstrap complete."
