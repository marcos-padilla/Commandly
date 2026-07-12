#!/usr/bin/env bash
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "SwiftFormat is not installed."
  echo "Install with: brew install swiftformat"
  exit 0
fi

MODE="${1:-format}"
if [[ "${MODE}" == "lint" ]]; then
  swiftformat --lint --config "${ROOT_DIR}/.swiftformat" "${ROOT_DIR}/Commandly" "${ROOT_DIR}/CommandlyTests" "${ROOT_DIR}/Packages"
else
  swiftformat --config "${ROOT_DIR}/.swiftformat" "${ROOT_DIR}/Commandly" "${ROOT_DIR}/CommandlyTests" "${ROOT_DIR}/Packages"
fi
