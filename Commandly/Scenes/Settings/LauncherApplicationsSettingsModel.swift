import CommandKit
import Foundation
import Observation

struct LauncherApplicationSettingsRow: Identifiable {
    let definition: LauncherApplicationDefinition
    let depth: Int
    let hasChildren: Bool
    let childCount: Int
    let isExpanded: Bool
    let isEffectivelyEnabled: Bool
    let settings: LauncherApplicationResolvedSettings

    var id: CommandID { definition.id }
}

@Observable
@MainActor
final class LauncherApplicationsSettingsModel {
    private let registry: LauncherApplicationRegistry
    @ObservationIgnored
    private let onPreferencesChange: () -> Void
    @ObservationIgnored
    private let hotkeyIssues: () -> [CommandID: ApplicationHotkeyRegistrationIssue]

    var query = ""
    var kindFilter: LauncherApplicationKind?
    var selectedID: CommandID?
    var expandedIDs: Set<CommandID>
    private var revision = 0

    init(
        registry: LauncherApplicationRegistry,
        onPreferencesChange: @escaping () -> Void = {},
        hotkeyIssues: @escaping () -> [CommandID: ApplicationHotkeyRegistrationIssue] = { [:] }
    ) {
        self.registry = registry
        self.onPreferencesChange = onPreferencesChange
        self.hotkeyIssues = hotkeyIssues
        self.expandedIDs = Set(
            registry.allDefinitions()
                .filter { $0.kind == .group }
                .map(\.id)
        )
        self.selectedID = registry.allDefinitions().first(where: {
            $0.kind != .group && $0.kind != .tool
        })?.id
    }

    var rows: [LauncherApplicationSettingsRow] {
        _ = revision
        return registry.rootDefinitions().flatMap { rows(for: $0, depth: 0) }
    }

    var selectedDefinition: LauncherApplicationDefinition? {
        guard let selectedID else { return nil }
        return registry.definition(for: selectedID)
    }

    var selectedSettings: LauncherApplicationResolvedSettings? {
        _ = revision
        guard let selectedID else { return nil }
        return registry.resolvedSettings(for: selectedID)
    }

    var selectedPreferences: LauncherApplicationPreferences {
        _ = revision
        guard let selectedID else { return .empty }
        return registry.preferences(for: selectedID)
    }

    var selectedIsEffectivelyEnabled: Bool {
        _ = revision
        guard let selectedID else { return false }
        return registry.isEffectivelyEnabled(selectedID)
    }

    func select(_ id: CommandID) {
        selectedID = id
    }

    func toggleExpansion(_ id: CommandID) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    func setAlias(_ alias: String, for id: CommandID) {
        updatePreferences(for: id) { $0.alias = alias }
    }

    func setTags(_ tags: [String], for id: CommandID) {
        let builtInKeys = Set(
            (registry.definition(for: id)?.defaultTags ?? []).map(Self.normalizedTagKey)
        )
        let normalized = Self.normalizedTags(tags).filter {
            builtInKeys.contains(Self.normalizedTagKey($0)) == false
        }
        updatePreferences(for: id) {
            $0.tags = normalized
            // Alias is the legacy single-tag field. Once the plural editor is used, the
            // visible tag list becomes authoritative so removing a migrated alias really
            // removes it from discovery.
            $0.alias = nil
        }
    }

    func setEnabled(_ isEnabled: Bool, for id: CommandID) {
        updatePreferences(for: id) { $0.isEnabled = isEnabled }
    }

    func setHotKey(_ hotKey: LauncherHotKey?, for id: CommandID) {
        updatePreferences(for: id) {
            $0.hotKey = hotKey
            $0.hasHotKeyOverride = true
        }
    }

    func setConfiguration(
        _ value: LauncherConfigurationValue,
        variable: String,
        for id: CommandID
    ) {
        guard let field = registry.definition(for: id)?.configurationFields.first(where: {
            $0.variable == variable
        }), field.kind.accepts(value) else {
            return
        }
        updatePreferences(for: id) { $0.configuration[variable] = value }
    }

    func resetSelectedApplication() {
        guard let selectedID else { return }
        registry.resetPreferences(for: selectedID)
        revision += 1
        onPreferencesChange()
    }

    func hotkeyIssue(for id: CommandID) -> String? {
        guard let issue = hotkeyIssues()[id] else { return nil }
        if case .duplicate(let ownerID) = issue,
           let owner = registry.definition(for: ownerID) {
            return "This shortcut is already assigned to \(owner.title)."
        }
        return issue.message
    }

    func hotkeyDescription(for id: CommandID) -> String {
        if registry.isBackgroundInvokingCommand(id) {
            return "Run this tool directly from anywhere without opening Commandly."
        }
        if registry.definition(for: id)?.kind == .tool {
            return "Open this tool directly from anywhere."
        }
        return "Open this application directly from anywhere."
    }

    func commands(for id: CommandID) -> [LauncherApplicationCommandDefinition] {
        registry.commands(for: id)
    }

    private func updatePreferences(
        for id: CommandID,
        update: (inout LauncherApplicationPreferences) -> Void
    ) {
        var preferences = registry.preferences(for: id)
        update(&preferences)
        registry.savePreferences(preferences, for: id)
        revision += 1
        onPreferencesChange()
    }

    private func rows(
        for definition: LauncherApplicationDefinition,
        depth: Int
    ) -> [LauncherApplicationSettingsRow] {
        let children = registry.children(of: definition.id)
        let matches = matchesFilter(definition)
        let descendantRows = children.flatMap { rows(for: $0, depth: depth + 1) }
        let isFiltering = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || kindFilter != nil
        guard matches || descendantRows.isEmpty == false || isFiltering == false else { return [] }
        guard let settings = registry.resolvedSettings(for: definition.id) else { return [] }

        let expanded = isFiltering || expandedIDs.contains(definition.id)
        let row = LauncherApplicationSettingsRow(
            definition: definition,
            depth: depth,
            hasChildren: children.isEmpty == false,
            childCount: children.count,
            isExpanded: expanded,
            isEffectivelyEnabled: registry.isEffectivelyEnabled(definition.id),
            settings: settings
        )
        return expanded ? [row] + descendantRows : [row]
    }

    private func matchesFilter(_ definition: LauncherApplicationDefinition) -> Bool {
        if let kindFilter, definition.kind != kindFilter { return false }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.isEmpty == false else { return true }
        let settings = registry.resolvedSettings(for: definition.id)
        return definition.title.localizedCaseInsensitiveContains(needle)
            || (definition.subtitle?.localizedCaseInsensitiveContains(needle) ?? false)
            || (settings?.alias.localizedCaseInsensitiveContains(needle) ?? false)
            || (settings?.tags.contains(where: {
                $0.localizedCaseInsensitiveContains(needle)
            }) ?? false)
            || definition.kind.title.localizedCaseInsensitiveContains(needle)
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in tags {
            let tag = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(64)
            guard tag.isEmpty == false else { continue }
            let normalized = String(tag)
            let key = normalized.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else { continue }
            result.append(normalized)
            if result.count == 32 { break }
        }
        return result
    }

    private static func normalizedTagKey(_ tag: String) -> String {
        tag.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}
