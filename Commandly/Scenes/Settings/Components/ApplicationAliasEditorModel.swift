import Foundation
import Observation

/// Edits a nickname for one installed application; no alias is persisted until Save.
@MainActor
@Observable
final class ApplicationAliasEditorModel: Identifiable {
    let bundleIdentifier: String
    let applicationName: String
    var id: String { bundleIdentifier }
    var alias: String {
        didSet { saveError = nil }
    }
    private(set) var saveError: String?

    @ObservationIgnored private let preferencesStore: any ApplicationPreferencesStoring
    @ObservationIgnored private let onSaved: (String?) -> Void
    @ObservationIgnored private let onCancel: () -> Void

    init(
        bundleIdentifier: String,
        applicationName: String,
        preferencesStore: any ApplicationPreferencesStoring,
        onSaved: @escaping (String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.preferencesStore = preferencesStore
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.alias = preferencesStore.load().alias(for: bundleIdentifier) ?? ""
    }

    var validationMessage: String? {
        do {
            _ = try validatedAlias()
            return nil
        } catch let error as ApplicationAlias.ValidationError {
            return error.message
        } catch {
            return "This alias couldn’t be saved."
        }
    }

    var canSave: Bool {
        guard validationMessage == nil else { return false }
        let normalized = try? ApplicationAlias.normalized(alias)
        return normalized != preferencesStore.load().alias(for: bundleIdentifier)
    }

    var removesAlias: Bool {
        preferencesStore.load().alias(for: bundleIdentifier) != nil
            && alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save() {
        guard canSave else { return }
        do {
            // Reload so a ranking/favorite change made while the sheet is open remains intact.
            var preferences = preferencesStore.load()
            let normalized = try ApplicationAlias.validate(
                alias, for: bundleIdentifier, aliases: preferences.aliases
            )
            preferences.aliases[bundleIdentifier] = normalized
            preferencesStore.save(preferences)
            saveError = nil
            onSaved(normalized)
        } catch let error as ApplicationAlias.ValidationError {
            saveError = error.message
        } catch {
            saveError = "This alias couldn’t be saved."
        }
    }

    func cancel() {
        onCancel()
    }

    private func validatedAlias() throws -> String? {
        try ApplicationAlias.validate(
            alias, for: bundleIdentifier, aliases: preferencesStore.load().aliases
        )
    }
}
