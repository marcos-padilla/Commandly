import Foundation
import CommandKit

nonisolated enum InstalledApplicationShortcutActionID {
    static let edit = CommandActionID(rawValue: "app.edit-global-shortcut")
}

/// Keeps installed-app shortcuts in the existing preferences and unified registration owner.
@MainActor
enum InstalledApplicationShortcuts {
    static let maximumAssignments = 128

    static func bindings(in preferences: ApplicationPreferences) -> [(String, LauncherHotKey)] {
        Array(preferences.hotKeys.sorted { $0.key < $1.key }.compactMap { bundleID, hotKey in
            guard isValidBundleIdentifier(bundleID), isSupported(hotKey),
                  !preferences.isDisabled(bundleID) else { return nil }
            return (bundleID, hotKey)
        }.prefix(maximumAssignments))
    }

    /// Existing successful owners precede newly enabled assignments, so enabling an app cannot
    /// silently take a shortcut from another installed app. A fresh launch uses bundle-ID order.
    static func orderedBindings(
        in preferences: ApplicationPreferences,
        previousOwners: [String]
    ) -> [(String, LauncherHotKey)] {
        let candidates = bindings(in: preferences)
        let ranks = Dictionary(uniqueKeysWithValues: previousOwners.enumerated().map { ($0.element, $0.offset) })
        return candidates.sorted {
            let left = ranks[$0.0] ?? Int.max
            let right = ranks[$1.0] ?? Int.max
            return left == right ? $0.0 < $1.0 : left < right
        }
    }

    nonisolated static func isSupported(_ hotKey: LauncherHotKey) -> Bool {
        hotKey.isValid && !hotKey.modifiers.intersection([.command, .option, .control]).isEmpty
            && hotKey.modifiers.subtracting([.command, .option, .control, .shift]).isEmpty
    }

    nonisolated static func isValidBundleIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" || $0 == "_"
            }
    }

    /// Registration and rollback run synchronously on MainActor, with no intermediate input turn.
    /// A conflicting or system-reserved shortcut never replaces the prior saved assignment.
    static func save(
        _ hotKey: LauncherHotKey?,
        for bundleID: String,
        store: any ApplicationPreferencesStoring,
        refreshRegistrations: () -> [String: GlobalShortcutRegistrationIssue]
    ) -> String? {
        guard isValidBundleIdentifier(bundleID) else { return "That application is unavailable." }
        var preferences = store.load()
        let previous = preferences.hotKeys[bundleID]
        if let hotKey {
            guard isSupported(hotKey) else { return "Use a supported key with Command, Option, or Control." }
            guard !preferences.isDisabled(bundleID) else { return "Enable this application before assigning a shortcut." }
            guard previous != nil || preferences.hotKeys.count < maximumAssignments else {
                return "Remove an existing application shortcut before adding another."
            }
            guard !preferences.hotKeys.contains(where: {
                $0.key != bundleID && $0.value == hotKey && !preferences.isDisabled($0.key)
            }) else { return "Another installed application already uses this shortcut." }
        }
        preferences.hotKeys[bundleID] = hotKey
        store.save(preferences)
        let issues = refreshRegistrations()
        guard hotKey != nil, let issue = issues[bundleID] else { return nil }
        // Preserve unrelated preferences even if a registration adapter also updated metadata.
        var restored = store.load()
        restored.hotKeys[bundleID] = previous
        store.save(restored)
        _ = refreshRegistrations()
        return message(for: issue)
    }

    static func message(for issue: GlobalShortcutRegistrationIssue) -> String {
        switch issue {
        case .duplicate:
            return "This shortcut is already used by a Commandly command or Command Wheel."
        case .duplicateID, .unavailable:
            return "This shortcut is reserved by macOS or another application. Choose a different shortcut."
        }
    }
}
