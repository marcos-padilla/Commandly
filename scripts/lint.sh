#!/usr/bin/env bash
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "SwiftLint is not installed."
  echo "Install with: brew install swiftlint"
  exit 0
fi

swiftlint lint --config "${ROOT_DIR}/.swiftlint.yml"
