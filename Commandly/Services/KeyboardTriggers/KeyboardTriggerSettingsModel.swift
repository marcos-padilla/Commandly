import CommandKit
import Foundation
import Infrastructure
import Observation

@MainActor struct KeyboardTriggerCommandOption: Identifiable {
    let reference: CommandReference
    let title: String
    var id: String { reference.commandID.rawValue }
}
@Observable @MainActor final class KeyboardTriggerSettingsModel {
    private(set) var preferences = KeyboardTriggerPreferences()
    private(set) var libraryItems: [ProductivityLibraryItem] = []
    private(set) var commands: [KeyboardTriggerCommandOption] = []
    private(set) var isEnabled = false
    private(set) var isBusy = false
    private(set) var message: String?
    @ObservationIgnored private let operation: any CompanionKeyboardTriggerOperating
    @ObservationIgnored private let persistence: any KeyboardTriggerPreferencesStoring
    @ObservationIgnored private let library: any ProductivityLibraryPersisting
    @ObservationIgnored private let executor: any SharedCommandExecutionCoordinating
    @ObservationIgnored private let opener: any URLOpening
    @ObservationIgnored private let commandOptions: @MainActor () -> [KeyboardTriggerCommandOption]
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var workID = UUID()
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeRevision: UUID?
    @ObservationIgnored private var handled: Set<UUID> = []
    init(operation: any CompanionKeyboardTriggerOperating, persistence: any KeyboardTriggerPreferencesStoring,
         library: any ProductivityLibraryPersisting, executor: any SharedCommandExecutionCoordinating,
         opener: any URLOpening, commandOptions: @escaping @MainActor () -> [KeyboardTriggerCommandOption]) {
        self.operation = operation; self.persistence = persistence; self.library = library
        self.executor = executor; self.opener = opener; self.commandOptions = commandOptions
    }
    func refresh() {
        guard !isBusy else { return }
        isBusy = true
        let operationID = UUID(); workID = operationID
        work = Task { [weak self] in
            guard let self else { return }; defer { finishWork(operationID) }
            do { preferences = try await persistence.load(); libraryItems = try await library.loadItems(); commands = commandOptions() }
            catch { message = "Keyboard trigger settings could not be loaded." }
        }
    }
    var canEnable: Bool { !isBusy && (preferences.hyperEnabled || !preferences.assignments.isEmpty || preferences.expansionsEnabled && !preferences.expansions.isEmpty) }
    func setHyper(_ value: Bool) { edit { $0.hyperEnabled = value; if !value { $0.assignments.removeAll { $0.requiresHyper } } } }
    func setPreserveCapsTap(_ value: Bool) { edit { $0.preserveCapsLockTap = value } }
    func setExpansions(_ value: Bool) { edit { $0.expansionsEnabled = value } }
    func addKey(_ key: CompanionTriggerKey, hyper: Bool, destination: KeyboardTriggerDestination) {
        edit { $0.assignments.append(.init(id: UUID(), key: key, doubleTap: nil, requiresHyper: hyper, destination: destination)) }
    }
    func addDoubleTap(_ key: CompanionDoubleTapKey, quicklink: UUID) {
        edit { $0.assignments.append(.init(id: UUID(), key: nil, doubleTap: key, requiresHyper: false, destination: .quicklink(quicklink))) }
    }
    func addExpansion(keyword: String, itemID: UUID) {
        edit { $0.expansions.append(.init(id: UUID(), itemID: itemID, keyword: keyword)) }
    }
    func remove(_ id: UUID) { edit { $0.assignments.removeAll { $0.id == id }; $0.expansions.removeAll { $0.id == id } } }
    private func edit(_ mutation: (inout KeyboardTriggerPreferences) -> Void) {
        guard !isBusy, !isEnabled else { return }
        mutation(&preferences)
        isBusy = true
        let value = preferences
        let operationID = UUID(); workID = operationID
        work = Task { [weak self] in
            guard let self else { return }; defer { finishWork(operationID) }
            do { try await persistence.save(value); message = nil }
            catch { message = "Keyboard trigger settings could not be saved." }
        }
    }
    func enable() {
        guard canEnable, !isEnabled else { return }
        isBusy = true; message = nil
        let token = UUID(); generation = token
        let operationID = UUID(); workID = operationID
        work = Task { [weak self] in
            guard let self else { return }; defer { finishWork(operationID) }
            do {
                libraryItems = try await library.loadItems(); commands = commandOptions()
                let configuration = try makeConfiguration()
                let reply = try await operation.keyboardTriggers(.configure(configuration))
                guard generation == token else { return }
                guard case .configured(let revision) = reply, revision == configuration.revision else { throw Self.failure(reply) }
                activeRevision = revision; isEnabled = true; handled = []
                message = "Keyboard triggers are on for this connection. They stop on disconnect, permission changes, or session expiry."
                poll(token: token)
            } catch { message = Self.message(error) }
        }
    }
    func disable() {
        generation = UUID(); isEnabled = false; activeRevision = nil; polling?.cancel(); polling = nil
        let settling = work; settling?.cancel()
        isBusy = true
        let operationID = UUID(); workID = operationID
        work = Task { [weak self] in
            await settling?.value
            guard let self else { return }; defer { finishWork(operationID) }
            do { _ = try await operation.keyboardTriggers(.stop); message = "Keyboard triggers are off." }
            catch { message = "The trigger connection ended. Reconnect before enabling again." }
        }
    }
    private func finishWork(_ id: UUID) {
        guard workID == id else { return }; isBusy = false; work = nil
    }
    private func makeConfiguration() throws -> CompanionKeyboardConfiguration {
        for binding in preferences.assignments {
            guard (binding.key != nil) != (binding.doubleTap != nil) else { throw CompanionKeyboardError.invalidConfiguration }
            switch binding.destination {
            case .command(let reference):
                guard binding.doubleTap == nil, commands.contains(where: { $0.reference == reference }) else { throw CompanionKeyboardError.invalidConfiguration }
            case .quicklink(let id):
                guard let item = libraryItems.first(where: { $0.id == id && $0.kind == .quicklink }) else { throw CompanionKeyboardError.invalidConfiguration }
                let url = try ProductivityQuicklinkValidator().validatedURL(from: item.content)
                if binding.doubleTap != nil && !url.isFileURL { throw CompanionKeyboardError.invalidConfiguration }
            }
        }
        let expansions = try (preferences.expansionsEnabled ? preferences.expansions : []).map { assignment in
            guard let item = libraryItems.first(where: { $0.id == assignment.itemID }),
                  item.kind == .snippet || item.kind == .emojiKeyword,
                  !item.content.contains("{{") else { throw CompanionKeyboardError.invalidConfiguration }
            return CompanionKeywordExpansion(id: assignment.id, keyword: assignment.keyword, replacement: item.content)
        }
        let configuration = CompanionKeyboardConfiguration(hyperEnabled: preferences.hyperEnabled,
            preserveCapsLockTap: preferences.preserveCapsLockTap,
            keys: preferences.assignments.compactMap { value in value.key.map { .init(id: value.id, key: $0, requiresHyper: value.requiresHyper) } },
            doubleTaps: preferences.assignments.compactMap { value in value.doubleTap.map { .init(id: value.id, key: $0) } }, expansions: expansions)
        guard configuration.isValid else { throw CompanionKeyboardError.invalidConfiguration }
        return configuration
    }
    private func poll(token: UUID) {
        polling = Task { [weak self] in
            guard let self else { return }
            do {
                while generation == token, isEnabled {
                    let reply = try await operation.keyboardTriggers(.nextActivations)
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    guard case .activations(let values) = reply, values.count <= 32 else { throw Self.failure(reply) }
                    for value in values {
                        guard value.revision == activeRevision, handled.insert(value.id).inserted,
                              handled.count <= 256,
                              let binding = preferences.assignments.first(where: { $0.id == value.bindingID }) else { throw CompanionKeyboardError.invalidConfiguration }
                        try await dispatch(binding.destination)
                    }
                }
            } catch {
                guard generation == token else { return }
                isEnabled = false; activeRevision = nil; message = Self.message(error)
                _ = try? await operation.keyboardTriggers(.stop)
            }
        }
    }
    private func dispatch(_ destination: KeyboardTriggerDestination) async throws {
        try Task.checkCancellation()
        switch destination {
        case .command(let reference):
            _ = try await executor.execute(reference: reference, context: .init(source: .applicationHotKey))
        case .quicklink(let id):
            let current = try await library.loadItems()
            guard let item = current.first(where: { $0.id == id && $0.kind == .quicklink }) else { throw CompanionKeyboardError.invalidConfiguration }
            let url = try ProductivityQuicklinkValidator().validatedURL(from: item.content)
            try Task.checkCancellation()
            try await opener.openURL(url)
        }
    }
    func title(for destination: KeyboardTriggerDestination) -> String {
        switch destination {
        case .command(let reference): commands.first(where: { $0.reference == reference })?.title ?? "Unavailable command"
        case .quicklink(let id): libraryItems.first(where: { $0.id == id })?.title ?? "Unavailable Quicklink"
        }
    }
    private static func failure(_ reply: CompanionKeyboardTriggerReply) -> CompanionKeyboardError {
        if case .failure(let error) = reply { return error }; return .unavailable
    }
    private static func message(_ error: any Error) -> String {
        switch error as? CompanionKeyboardError {
        case .permissionDenied: "Open Companion Setup and review Input Monitoring and Accessibility access before enabling."
        case .secureInput: "Secure Input is active. Finish the protected input, then enable again."
        case .unsupportedKeyboard: "Physical Caps Lock input is unavailable. Turn Hyper off or use a supported keyboard."
        case .invalidConfiguration: "Review duplicate keys, unavailable commands and Quicklinks. Expansion keywords need 2–32 ASCII characters starting with punctuation; use literal snippets under 8 KB."
        case .expired: "The keyboard session expired. Enable again to continue."
        default: "Keyboard triggers stopped. Check the companion connection and permissions, then enable again."
        }
    }
}
