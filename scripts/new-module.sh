#!/usr/bin/env bash
#
# Scaffolds a new Commandly feature module.
#
#   ./scripts/new-module.sh Bookmarks
#   make new-module NAME=Bookmarks
#
# Creates Packages/Modules/<Name>/ with a manifest, an assembly, one command definition, and a
# test target, then wires both targets into Packages/Package.swift.
#
# It never overwrites an existing module and refuses colliding names and paths. Generated files
# are deliberately minimal: a small feature should stay small, so no empty Domain/, Adapters/, or
# Resources/ directories are created.
#
# The generated module is NOT registered with the application. Registering it is one explicit
# line in Commandly/Composition/BuiltInModules.swift, which the script prints at the end.
#
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

NAME="${1:-}"

if [[ -z "${NAME}" ]]; then
  echo "usage: ./scripts/new-module.sh <Name>   (e.g. Bookmarks)" >&2
  exit 2
fi

if [[ ! "${NAME}" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
  echo "error: module name must be UpperCamelCase letters and digits, e.g. Bookmarks" >&2
  exit 2
fi

TARGET="${NAME}Module"
MODULE_DIR="${PACKAGE_PATH}/Modules/${NAME}"
MANIFEST="${PACKAGE_PATH}/Package.swift"
# Lowercased identifier prefix, e.g. Bookmarks -> bookmarks
SLUG="$(echo "${NAME}" | tr '[:upper:]' '[:lower:]')"

if [[ -e "${MODULE_DIR}" ]]; then
  echo "error: ${MODULE_DIR#"${ROOT_DIR}/"} already exists; refusing to overwrite it" >&2
  exit 1
fi

if grep -q "name: \"${TARGET}\"" "${MANIFEST}"; then
  echo "error: target ${TARGET} is already declared in Package.swift" >&2
  exit 1
fi

if [[ -e "${PACKAGE_PATH}/Sources/${TARGET}" ]]; then
  echo "error: ${TARGET} collides with an existing target under Packages/Sources" >&2
  exit 1
fi

mkdir -p "${MODULE_DIR}/Sources/${TARGET}" "${MODULE_DIR}/Tests/${TARGET}Tests" "${MODULE_DIR}/Docs"

cat > "${MODULE_DIR}/Sources/${TARGET}/${TARGET}.swift" <<SWIFT
import CommandKit
import Foundation
import ModuleKit

/// Stable identifiers owned by the ${NAME} module.
///
/// These values are persisted in Command Wheel profiles, menu-bar pins, shortcut overrides, and
/// usage history. They must not change once the module ships.
public enum ${NAME}ModuleIdentifiers {
    /// The module itself.
    public static let module = ModuleID(rawValue: "${SLUG}")
    /// The module's first command. Rename it to something the feature actually does.
    public static let exampleCommand = CommandID(rawValue: "${SLUG}.example")
}

/// Canonical command definitions for the ${NAME} module.
///
/// Launcher metadata, documentation, and AI tool schemas are all derived from these values.
public enum ${NAME}Commands {
    /// Replace this with the module's real operation.
    public static let example = ModuleCommandDefinition(
        manifest: CommandManifest(
            id: ${NAME}ModuleIdentifiers.exampleCommand,
            title: "${NAME} Example",
            subtitle: "Describe what this command does",
            systemImage: "circle",
            category: .productivity,
            mode: .action,
            keywords: ["${SLUG}"],
            badgeTitle: "Tool"
        ),
        summary: "Describe the operation in one sentence.",
        policy: ModuleCommandPolicy(
            executionMode: .direct,
            effect: .readOnly,
            // AI exposure is default-deny. Change it to .reviewed only after an explicit review,
            // and record that review in the module's documentation.
            aiExposure: .hidden,
            isIdempotent: true
        )
    )

    /// Every command the module owns, in stable order.
    public static let all: [ModuleCommandDefinition] = [example]
}

/// Static manifest for the ${NAME} module.
public enum ${NAME}ModuleManifest {
    /// Module metadata. Reading it constructs nothing.
    public static let value = ModuleManifest(
        id: ${NAME}ModuleIdentifiers.module,
        title: "${NAME}",
        summary: "Describe the feature in one sentence.",
        status: .shipping,
        ownedApplicationIDs: [],
        ownedCommandIDs: ${NAME}Commands.all.map(\\.id),
        capabilities: [],
        activationPolicy: .onDemand,
        configurationVersion: 1,
        documentationArticleIDs: []
    )
}
SWIFT

cat > "${MODULE_DIR}/Sources/${TARGET}/${NAME}Assembly.swift" <<SWIFT
import CommandKit
import Foundation
import ModuleKit

/// Narrow assembly for the ${NAME} module.
///
/// Give this initializer only the interfaces the module needs. Do not accept a general-purpose
/// service container.
///
/// Everything outside \`activate()\` is metadata: constructing the assembly and reading its
/// manifest, commands, settings, or documentation must start no service, request no permission,
/// open no connection, and read no private data.
@MainActor
public struct ${NAME}Assembly: ModuleAssembly {
    /// Creates the assembly.
    public init() {}

    public var manifest: ModuleManifest { ${NAME}ModuleManifest.value }

    public var commandDefinitions: [ModuleCommandDefinition] { ${NAME}Commands.all }

    public func activate() async throws -> ModuleActivation {
        ModuleActivation(
            handlers: [
                ${NAME}ModuleIdentifiers.exampleCommand: ${NAME}ExampleHandler()
            ]
        )
    }
}

/// Handler for \`${SLUG}.example\`.
///
/// Call the module's own domain services here. Never build a view or a launcher session in order
/// to perform headless work.
@MainActor
struct ${NAME}ExampleHandler: ModuleCommandHandling {
    func execute(_ invocation: ModuleCommandInvocation) async -> ModuleCommandOutcome {
        guard invocation.grants.satisfy(${NAME}Commands.example.policy) else {
            return .denied(
                reason: .missingCallerGrant,
                message: "This caller isn’t allowed to run that command."
            )
        }
        return .succeeded(message: nil, output: .empty)
    }
}
SWIFT

cat > "${MODULE_DIR}/Tests/${TARGET}Tests/${TARGET}Tests.swift" <<SWIFT
import CommandKit
import Foundation
import ModuleKit
import ModuleRuntime
import Testing
@testable import ${TARGET}

@MainActor
struct ${NAME}ModuleTests {
    @Test func theModuleRegistersAndValidates() throws {
        let host = ModuleHost()
        #expect(throws: Never.self) { try host.register(${NAME}Assembly()) }
        #expect(host.commandDefinitions().map(\\.id) == ${NAME}Commands.all.map(\\.id))
    }

    @Test func metadataDiscoveryDoesNotActivateTheModule() throws {
        let host = ModuleHost()
        try host.register(${NAME}Assembly())
        _ = host.commandDefinitions()
        _ = host.settingsContributions()
        _ = host.documentationContributions()
        #expect(host.isActivated(${NAME}ModuleIdentifiers.module) == false)
    }

    @Test func commandsAreHiddenFromAIUntilExplicitlyReviewed() {
        // Remove this test only when a command is genuinely reviewed for AI exposure.
        #expect(${NAME}Commands.all.allSatisfy { \$0.policy.aiExposure == .hidden })
    }

    @Test func anUngrantedCallerIsDenied() async throws {
        let host = ModuleHost()
        try host.register(${NAME}Assembly())
        let handler = try await host.handler(for: ${NAME}ModuleIdentifiers.exampleCommand)
        let outcome = await handler.execute(
            ModuleCommandInvocation(
                commandID: ${NAME}ModuleIdentifiers.exampleCommand,
                arguments: .empty,
                context: CommandInvocationContext(source: .search),
                grants: []
            )
        )
        guard case .denied = outcome else {
            Issue.record("Expected an ungranted caller to be denied. Got \\(outcome).")
            return
        }
    }
}
SWIFT

cat > "${MODULE_DIR}/Docs/README.md" <<MARKDOWN
# ${NAME} module

Owner: _fill in_

## What it does

_One paragraph._

## Commands

| Command ID | Meaning | Mode | AI exposure |
|------------|---------|------|-------------|
| \`${SLUG}.example\` | _fill in_ | direct | hidden |

## Capabilities

_List permissions, account connections, or folder grants, or state that there are none._

## Storage

_Name the storage the module owns, or state that it persists nothing._

## AI exposure review

No command in this module is exposed to AI. Exposing one requires recording the review here:
what it does, what it can disclose, and why it is safe for a model to call.
MARKDOWN

python3 - "${MANIFEST}" "${TARGET}" "${NAME}" <<'PY'
import sys
manifest_path, target, name = sys.argv[1], sys.argv[2], sys.argv[3]
source = open(manifest_path).read()

product = '        .library(name: "%s", targets: ["%s"]),\n' % (target, target)
anchor = '        .library(name: "ModuleKit", targets: ["ModuleKit"]),\n'
assert anchor in source, "expected the ModuleKit product declaration in Package.swift"
source = source.replace(anchor, product + anchor, 1)

target_decl = (
    '        .target(\n'
    '            name: "%s",\n'
    '            dependencies: ["ModuleKit", "CommandKit", "AppCore"],\n'
    '            path: "Modules/%s/Sources/%s"\n'
    '        ),\n' % (target, name, target)
)
anchor = '        .testTarget(name: "ModuleKitTests", dependencies: ["ModuleKit", "CommandKit"]),\n'
assert anchor in source, "expected the ModuleKitTests declaration in Package.swift"
source = source.replace(anchor, target_decl + '\n' + anchor, 1)

test_decl = (
    '        .testTarget(\n'
    '            name: "%sTests",\n'
    '            dependencies: ["%s", "ModuleKit", "ModuleRuntime", "CommandKit"],\n'
    '            path: "Modules/%s/Tests/%sTests"\n'
    '        ),\n' % (target, target, name, target)
)
source = source.replace(anchor, anchor + test_decl, 1)

open(manifest_path, "w").write(source)
PY

echo "Created ${MODULE_DIR#"${ROOT_DIR}/"}"
echo "Wired ${TARGET} and ${TARGET}Tests into Packages/Package.swift"
echo
echo "Next steps:"
echo "  1. Replace the example command in ${TARGET}.swift with the module's real operation."
echo "  2. Register the module with the application by adding ONE line to"
echo "     Commandly/Composition/BuiltInModules.swift:"
echo
echo "         ${NAME}Assembly()"
echo
echo "  3. Add ${TARGET} to the Commandly target's package product dependencies in"
echo "     Commandly.xcodeproj only if the app target needs to import it directly."
echo "  4. Run: ./scripts/check-module-boundaries.sh && make verify"
