#!/usr/bin/env bash
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

echo "Cleaning repository-local build artifacts..."
rm -rf "${DERIVED_DATA_PATH}"
rm -rf "${PACKAGE_PATH}/.build"
rm -rf "${ROOT_DIR}/.swiftpm"
find "${ROOT_DIR}" -name "*.xcresult" -type d -prune -exec rm -rf {} +
echo "Clean complete."
