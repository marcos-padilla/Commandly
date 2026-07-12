#!/usr/bin/env bash
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

export_developer_dir

echo "Commandly doctor"
echo "================"
echo "macOS version:        $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
echo "Architecture:         $(uname -m)"
echo "Active Xcode path:    ${DEVELOPER_DIR}"
echo "Xcode version:        $(xcodebuild -version | tr '\n' ' ')"
echo "Swift version:        $(swift --version 2>&1 | head -n 1)"
echo "Git version:          $(git --version)"
echo "Project:              ${PROJECT_PATH}"

if xcodebuild -project "${PROJECT_PATH}" -list >/dev/null 2>&1; then
  echo "Project readable:     yes"
  echo "Schemes:"
  xcodebuild -project "${PROJECT_PATH}" -list 2>/dev/null | sed -n '/Schemes:/,$p' | sed 's/^/  /'
else
  echo "Project readable:     no (select Xcode 27+ that supports objectVersion 110)"
fi

if command -v swiftlint >/dev/null 2>&1; then
  echo "SwiftLint:            $(swiftlint version)"
else
  echo "SwiftLint:            not installed (brew install swiftlint)"
fi

if command -v swiftformat >/dev/null 2>&1; then
  echo "SwiftFormat:          $(swiftformat --version)"
else
  echo "SwiftFormat:          not installed (brew install swiftformat)"
fi
