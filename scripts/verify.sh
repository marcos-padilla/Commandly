#!/usr/bin/env bash
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

export_developer_dir

echo "Verifying Commandly foundation"
echo "=============================="

fail() {
  echo "VERIFY FAILED: $1" >&2
  exit 1
}

echo "1) Structural checks"
[[ -f "${ROOT_DIR}/AGENTS.md" ]] || fail "AGENTS.md missing"
[[ -f "${PROJECT_PATH}/project.pbxproj" ]] || fail "Xcode project missing"
[[ -f "${PACKAGE_PATH}/Package.swift" ]] || fail "Package.swift missing"
[[ -f "${ROOT_DIR}/Commandly/Application/CommandlyApp.swift" ]] || fail "App entry point missing"

echo "2) Package resolution"
swift package --package-path "${PACKAGE_PATH}" resolve || fail "package resolve failed"
xcodebuild -resolvePackageDependencies -project "${PROJECT_PATH}" -scheme "${SCHEME}" -derivedDataPath "${DERIVED_DATA_PATH}" >/dev/null || fail "xcode package resolve failed"

echo "3) Formatting check (optional)"
if command -v swiftformat >/dev/null 2>&1; then
  "${ROOT_DIR}/scripts/format.sh" lint || fail "swiftformat lint failed"
else
  echo "SwiftFormat not installed; skipping"
fi

echo "4) Linting (optional)"
if command -v swiftlint >/dev/null 2>&1; then
  "${ROOT_DIR}/scripts/lint.sh" || fail "swiftlint failed"
else
  echo "SwiftLint not installed; skipping"
fi

echo "5) Package tests"
swift test --package-path "${PACKAGE_PATH}" || fail "package tests failed"

echo "6) App tests"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -only-testing:CommandlyTests \
  test || fail "app tests failed"

echo "7) App build"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build || fail "app build failed"

echo "VERIFY PASSED"
