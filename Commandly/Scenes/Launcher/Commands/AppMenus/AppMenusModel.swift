import Foundation
import Infrastructure
import Observation

/// Search/favorites operate only on the explicit current snapshot; invocation sends only an opaque handle.
@Observable @MainActor public final class AppMenusModel {
    public enum State: Equatable { case idle, loading, ready, invoking, ended, failure(CompanionAppMenuError) }
    public private(set) var state: State = .idle
    public private(set) var items: [CompanionAppMenuItem] = []
    public private(set) var bundleIdentifier = ""
    public private(set) var favorites: Set<CompanionMenuIdentity> = []
    public private(set) var message: String?
    public private(set) var isSavingFavorite = false
    public private(set) var favoritesLoaded = false
    public var showsActionsMenu = false
    public var query = ""
    public var favoritesOnly = false
    public var selection: CompanionTargetHandle?
    @ObservationIgnored private let client: any CompanionAppMenuCalling
    @ObservationIgnored private let store: any CompanionMenuFavoritesStoring
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var favoritesTask: Task<Void, Never>?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cleanupFailed = false
    @ObservationIgnored private var expiry: Task<Void, Never>?
    public init(client: any CompanionAppMenuCalling, favorites: any CompanionMenuFavoritesStoring) { self.client = client; self.store = favorites }
    public var isWorking: Bool { state == .loading || state == .invoking }
    public var filteredItems: [CompanionAppMenuItem] {
        let terms = query.prefix(256).split(whereSeparator: \.isWhitespace).map(String.init)
        return items.filter { item in
            (!favoritesOnly || favorites.contains(item.identity)) && terms.allSatisfy {
                ([item.title] + item.ancestors).joined(separator: " ").localizedStandardContains($0)
            }
        }.sorted {
            let left = favorites.contains($0.identity); let right = favorites.contains($1.identity)
            if left != right { return left }
            return (items.firstIndex(of: $0) ?? 0) < (items.firstIndex(of: $1) ?? 0)
        }
    }
    public func open() {
        let token = generation
        favoritesTask?.cancel()
        favoritesTask = Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await store.load()
                guard token == generation, !Task.isCancelled else { return }
                favorites = saved; favoritesLoaded = true
            } catch {
                guard token == generation else { return }
                message = "Favorites could not be loaded. Stored favorites have not been changed."
            }
        }
    }
    /// Explicit opt-in observes activation identities, but never prompts or captures menus automatically.
    public func enable() { submit(.setEnabled(true)) }
    public func readMenus() { submit(.snapshot) }
    public func disable() { submit(.setEnabled(false)) }
    public func invokeSelection() {
        guard state == .ready, let selected = filteredItems.first(where: { $0.handle == selection }), selected.enabled else { return }
        submit(.invoke(selected.handle))
    }
    public func toggleFavorite(_ item: CompanionAppMenuItem) {
        guard favoritesLoaded, !isWorking, !isSavingFavorite, items.contains(item), item.identity.isValid else { return }
        let token = generation
        var proposed = favorites
        if !proposed.insert(item.identity).inserted { proposed.remove(item.identity) }
        guard proposed.count <= 100 else { message = "You can save up to 100 app-menu favorites."; return }
        isSavingFavorite = true
        favoritesTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await store.save(proposed)
                guard token == generation, !Task.isCancelled else { return }
                favorites = proposed; isSavingFavorite = false
            } catch {
                guard token == generation else { return }
                isSavingFavorite = false; message = "The favorite could not be saved."
            }
        }
    }
    /// Launcher close/deactivation invalidates local work before sending a serialized handle release.
    public func stop() {
        generation = UUID(); task?.cancel(); favoritesTask?.cancel(); expiry?.cancel(); expiry = nil
        items = []; selection = nil; query = ""; bundleIdentifier = ""; state = .ended; isSavingFavorite = false
        let previous = cleanup; let client = client
        cleanup = Task { [weak self] in
            await previous?.value
            do { let result = try await client.requestAppMenu(.release); self?.cleanupFailed = result != .released }
            catch { self?.cleanupFailed = true }
        }
    }
    public func waitForOperationForTesting() async { await task?.value }
    public func waitForFavoritesForTesting() async { await favoritesTask?.value }
    private func submit(_ request: CompanionAppMenuRequest) {
        guard !isWorking, !isSavingFavorite else { return }
        let token = generation
        task?.cancel(); expiry?.cancel(); items = []; selection = nil; message = nil
        if case .invoke = request { state = .invoking } else { state = .loading }
        task = Task { [weak self] in
            guard let self else { return }
            await cleanup?.value
            guard token == generation, !Task.isCancelled else { return }
            guard !cleanupFailed else { state = .failure(.disconnected); return }
            do {
                let reply = try await client.requestAppMenu(request)
                guard token == generation, !Task.isCancelled else { return }
                guard Self.matches(request, reply) else { state = .failure(.invalidData); return }
                switch reply {
                case .snapshot(let snapshot):
                    guard snapshot.items.count <= 500, Set(snapshot.items.map(\.handle)).count == snapshot.items.count,
                          snapshot.items.allSatisfy({ $0.identity.isValid && $0.identity.bundleIdentifier == snapshot.bundleIdentifier
                              && $0.title.utf8.count <= 512 && $0.ancestors.count <= 12 && $0.ancestors.allSatisfy { $0.utf8.count <= 512 } }) else {
                        state = .failure(.invalidData); return
                    }
                    items = snapshot.items; bundleIdentifier = snapshot.bundleIdentifier; state = .ready
                    selection = filteredItems.first?.handle
                    expiry = Task { [weak self] in
                        do { try await ContinuousClock().sleep(for: .seconds(30)) } catch { return }
                        guard let self, token == self.generation else { return }
                        self.items = []; self.selection = nil; self.state = .failure(.expired)
                    }
                case .enabled(let value): state = .idle; message = value ? "App Menus enabled. Choose Read Menus to capture the current app." : "App Menus disabled."
                case .invoked(let outcome):
                    state = .idle
                    message = outcome == .accepted ? "The app accepted the menu action." : "The action may have run. Check the app before trying again."
                case .released: state = .idle
                case .failure(let error): state = .failure(error)
                }
            } catch {
                guard token == generation else { return }
                state = .failure(.unavailable)
            }
        }
    }
    private static func matches(_ request: CompanionAppMenuRequest, _ reply: CompanionAppMenuReply) -> Bool {
        switch (request, reply) {
        case (_, .failure), (.snapshot, .snapshot), (.invoke, .invoked), (.release, .released): true
        case (.setEnabled(let requested), .enabled(let actual)): requested == actual
        default: false
        }
    }
    public var recoveryMessage: String? {
        guard case .failure(let error) = state else { return message }
        switch error {
        case .permissionDenied: return "Enable Accessibility for Commandly System Companion in System Settings, then reconnect."
        case .disabled: return "Enable App Menus before reading the current app’s menu."
        case .noApplication: return "Activate an external app, return to Commandly, and read its menus."
        case .stale: return "The app or menu changed. Close App Menus and open it again."
        case .expired: return "This menu snapshot expired. Read Menus to refresh it."
        case .locked, .disconnected: return "The companion session ended. Reconnect System Integration."
        case .tooLarge: return "This app’s menu exceeds the supported size. Nothing was invoked."
        case .unsupported: return "This app does not expose a supported accessible menu."
        case .timedOut: return "The app did not respond before the menu deadline."
        default: return "App Menus is unavailable. Reconnect System Integration and try again."
        }
    }
}
