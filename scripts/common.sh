#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DERIVED_DATA_PATH="${ROOT_DIR}/.derivedData"
PROJECT_PATH="${ROOT_DIR}/Commandly.xcodeproj"
SCHEME="Commandly"
PACKAGE_PATH="${ROOT_DIR}/Packages"

can_open_project() {
  local developer_dir="$1"
  [[ -x "${developer_dir}/usr/bin/xcodebuild" ]] || return 1
  DEVELOPER_DIR="${developer_dir}" "${developer_dir}/usr/bin/xcodebuild" -project "${PROJECT_PATH}" -list >/dev/null 2>&1
}

resolve_developer_dir() {
  if [[ -n "${COMMANDLY_DEVELOPER_DIR:-}" && -d "${COMMANDLY_DEVELOPER_DIR}" ]]; then
    echo "${COMMANDLY_DEVELOPER_DIR}"
    return
  fi

  if [[ -n "${DEVELOPER_DIR:-}" && -d "${DEVELOPER_DIR}" ]] && can_open_project "${DEVELOPER_DIR}"; then
    echo "${DEVELOPER_DIR}"
    return
  fi

  local candidate
  # Prefer explicitly installed apps that can read this project (objectVersion 110 / Xcode 27+).
  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    if can_open_project "${candidate}"; then
      echo "${candidate}"
      return
    fi
  done < <(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | while read -r app; do
    echo "${app}/Contents/Developer"
  done)

  for candidate in \
    "/Applications/Xcode-beta.app/Contents/Developer" \
    "/Applications/Xcode.app/Contents/Developer"; do
    if can_open_project "${candidate}"; then
      echo "${candidate}"
      return
    fi
  done

  xcode-select -p
}

export_developer_dir() {
  export DEVELOPER_DIR
  DEVELOPER_DIR="$(resolve_developer_dir)"
}
