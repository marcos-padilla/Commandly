#!/usr/bin/env bash
#
# Enforces the module-system dependency boundaries described in docs/ARCHITECTURE.md.
#
# Two complementary checks run here:
#
#   1. Manifest checks — read Packages/Package.swift and assert the declared target graph.
#      These are exact: SwiftPM will not link anything a target does not declare.
#   2. Source import checks — scan `import` lines for rules the manifest cannot express,
#      such as "no feature target may import the Commandly executable".
#
# Known limitation of (2): it is a line scanner, not a compiler. It does not resolve
# conditional compilation, `@_implementationOnly`, or transitive imports. The manifest
# checks in (1) are the authoritative ones; the scanner catches the mistakes a manifest
# cannot see.
#
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

MANIFEST="${PACKAGE_PATH}/Package.swift"
FEATURE_MODULES_DIR="${PACKAGE_PATH}/Modules"

failures=0

fail() {
  echo "  ✗ $1" >&2
  failures=$((failures + 1))
}

pass() {
  echo "  ✓ $1"
}

# Prints the dependency list declared for a target in Package.swift.
target_dependencies() {
  local target="$1"
  python3 - "$MANIFEST" "$target" <<'PY'
import re, sys
manifest, target = sys.argv[1], sys.argv[2]
source = open(manifest).read()
# Find `name: "<target>"` and take the `dependencies: [...]` that follows it.
match = re.search(r'name:\s*"%s"\s*,\s*dependencies:\s*\[([^\]]*)\]' % re.escape(target), source)
if not match:
    sys.exit(0)
for name in re.findall(r'"([^"]+)"', match.group(1)):
    print(name)
PY
}

# Prints every module imported by Swift sources under a directory.
imports_under() {
  local directory="$1"
  [[ -d "${directory}" ]] || return 0
  grep -rhoE '^[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' \
    --include='*.swift' "${directory}" 2>/dev/null \
    | awk '{print $NF}' | sort -u
}

echo "Commandly module boundaries"
echo "==========================="

echo "1) Manifest: contract targets stay free of feature and runtime dependencies"

for forbidden in ModuleRuntime AICommandBridge; do
  if target_dependencies ModuleKit | grep -qx "${forbidden}"; then
    fail "ModuleKit must not depend on ${forbidden}"
  else
    pass "ModuleKit does not depend on ${forbidden}"
  fi
done

if target_dependencies ModuleKit | grep -qxE 'AIKit|SwiftUI'; then
  fail "ModuleKit must not depend on AI-provider or UI targets"
else
  pass "ModuleKit has no AI-provider or UI dependency"
fi

echo "2) Manifest: the host and the AI bridge never depend on a feature target"

feature_targets=()
if [[ -d "${FEATURE_MODULES_DIR}" ]]; then
  while IFS= read -r module_dir; do
    feature_targets+=("$(basename "${module_dir}")")
  done < <(find "${FEATURE_MODULES_DIR}" -mindepth 3 -maxdepth 3 -type d -path '*/Sources/*' | sort)
fi

if [[ ${#feature_targets[@]} -eq 0 ]]; then
  echo "  (no feature targets under Packages/Modules yet)"
fi

for generic in ModuleRuntime AICommandBridge; do
  violation=0
  for feature in "${feature_targets[@]}"; do
    if target_dependencies "${generic}" | grep -qx "${feature}"; then
      fail "${generic} must not depend on the feature target ${feature}"
      violation=1
    fi
  done
  [[ ${violation} -eq 0 ]] && pass "${generic} depends on no feature target"
done

echo "3) Manifest: feature targets depend on contracts only"

for feature in "${feature_targets[@]}"; do
  deps="$(target_dependencies "${feature}")"
  if [[ -z "${deps}" ]]; then
    fail "${feature} declares no dependencies (is it wired into Package.swift?)"
    continue
  fi
  violation=0
  for forbidden in ModuleRuntime AICommandBridge; do
    if grep -qx "${forbidden}" <<<"${deps}"; then
      fail "${feature} must not depend on ${forbidden}"
      violation=1
    fi
  done
  # A feature must not depend on another feature target.
  for other in "${feature_targets[@]}"; do
    [[ "${other}" == "${feature}" ]] && continue
    if grep -qx "${other}" <<<"${deps}"; then
      fail "${feature} must not depend on the feature target ${other}"
      violation=1
    fi
  done
  [[ ${violation} -eq 0 ]] && pass "${feature} depends on contracts only"
done

echo "4) Sources: no package target imports the Commandly executable"

executable_violation=0
for directory in "${PACKAGE_PATH}/Sources" "${FEATURE_MODULES_DIR}"; do
  [[ -d "${directory}" ]] || continue
  if imports_under "${directory}" | grep -qx "Commandly"; then
    fail "a package source under ${directory#"${ROOT_DIR}/"} imports the Commandly app target"
    executable_violation=1
  fi
done
[[ ${executable_violation} -eq 0 ]] && pass "no package source imports Commandly"

echo "5) Sources: the generic host and bridge import no feature target"

for generic in ModuleRuntime AICommandBridge; do
  violation=0
  generic_imports="$(imports_under "${PACKAGE_PATH}/Sources/${generic}")"
  for feature in "${feature_targets[@]}"; do
    if grep -qx "${feature}" <<<"${generic_imports}"; then
      fail "${generic} sources import the feature target ${feature}"
      violation=1
    fi
  done
  if grep -qx "SwiftUI" <<<"${generic_imports}"; then
    fail "${generic} sources must not import SwiftUI"
    violation=1
  fi
  [[ ${violation} -eq 0 ]] && pass "${generic} sources import no feature target and no SwiftUI"
done

echo "6) Sources: ModuleKit stays free of SwiftUI and AI-provider types"

module_kit_imports="$(imports_under "${PACKAGE_PATH}/Sources/ModuleKit")"
if grep -qxE 'SwiftUI|AppKit|AIKit' <<<"${module_kit_imports}"; then
  fail "ModuleKit must not import SwiftUI, AppKit, or AIKit"
else
  pass "ModuleKit imports only domain-neutral contracts"
fi

echo "7) Production code does not depend on test support"

production_dirs=("${PACKAGE_PATH}/Sources" "${ROOT_DIR}/Commandly")
# Only a feature module's Sources tree is production; its Tests tree is not.
for feature in "${feature_targets[@]}"; do
  while IFS= read -r source_dir; do
    production_dirs+=("${source_dir}")
  done < <(find "${FEATURE_MODULES_DIR}" -mindepth 3 -maxdepth 3 -type d \
    -path "*/Sources/${feature}" 2>/dev/null)
done

test_support_violation=0
for directory in "${production_dirs[@]}"; do
  [[ -d "${directory}" ]] || continue
  if imports_under "${directory}" | grep -qxE 'XCTest|Testing'; then
    fail "production sources under ${directory#"${ROOT_DIR}/"} import a testing framework"
    test_support_violation=1
  fi
done
[[ ${test_support_violation} -eq 0 ]] && pass "no production source imports XCTest or Testing"

echo "8) Every feature module target is wired into the build graph"

for feature in "${feature_targets[@]}"; do
  if grep -q "name: \"${feature}\"" "${MANIFEST}"; then
    pass "${feature} is declared in Package.swift"
  else
    fail "${feature} exists on disk but is not declared in Package.swift"
  fi
  if grep -q "name: \"${feature}Tests\"" "${MANIFEST}"; then
    pass "${feature}Tests is declared in Package.swift"
  else
    fail "${feature} has no test target declared in Package.swift"
  fi
done

echo
if [[ ${failures} -eq 0 ]]; then
  echo "MODULE BOUNDARIES OK"
  exit 0
fi

echo "MODULE BOUNDARIES FAILED (${failures} violation(s))" >&2
exit 1
