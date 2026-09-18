import Foundation
import Infrastructure

actor SlackEmojiService {
    private struct Inventory { let catalog: SlackEmojiCatalog; let items: [SlackCustomEmoji]; let byName: [String: SlackCustomEmoji] }
    private struct Request { let owner: UUID?; let task: Task<SlackEmojiHTTPResponse, Error> }
    private let credentials: SlackEmojiCredentialStore
    private let transport: any SlackEmojiHTTPTransporting
    private let now: @Sendable () -> Date
    private var inventories: [String: Inventory] = [:]
    private var refreshes: [String: UUID] = [:]
    private var requests: [UUID: Request] = [:]
    private var cooldowns: [String: Date] = [:]
    private var mutating = false
    private var mutationGeneration = UUID()
    private var mutationWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var connectionReadObservers: [CheckedContinuation<Void, Never>] = []
    init(credentials: SlackEmojiCredentialStore, transport: any SlackEmojiHTTPTransporting = SlackEmojiHTTPTransport(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.credentials = credentials; self.transport = transport; self.now = now
    }
    func connections() async throws -> [SlackEmojiWorkspace] {
        // A new launcher model may outlive the model that initiated a secure write. Settlement
        // belongs to this shared service so every reader sees the actual committed connection.
        while true {
            try Task.checkCancellation()
            if mutating { try await waitForMutation(); continue }
            let generation = mutationGeneration
            do {
                let values = try await credentials.workspaces(); try Task.checkCancellation()
                guard !mutating, generation == mutationGeneration else { continue }
                return values
            } catch SlackEmojiError.changedConnection {
                guard mutating || generation != mutationGeneration else { throw SlackEmojiError.changedConnection }
            }
        }
    }
    func connect(token: String, replacing: SlackEmojiWorkspace?) async throws -> SlackEmojiWorkspace {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SlackEmojiCredentialStore.validToken(token) else { throw SlackEmojiError.invalidToken }
        guard !mutating else { throw SlackEmojiError.changedConnection }
        beginMutation(); defer { finishMutation() }
        let existing = try await credentials.workspaces()
        if let replacing { _ = try await credentials.token(for: replacing) }
        else { guard existing.count < 8 else { throw SlackEmojiError.tooManyConnections } }
        let identity = try SlackEmojiIdentity.parse(await api("auth.test", token: token, key: "connect.auth", maximum: 128 * 1_024))
        if let replacing { guard identity.id == replacing.id else { throw SlackEmojiError.identityChanged } }
        else { guard !existing.contains(where: { $0.id == identity.id }) else { throw SlackEmojiError.alreadyConnected } }
        let permissionCheck = try await api("emoji.list", token: token, key: identity.id + ".emoji", maximum: 4 * 1_024 * 1_024)
        _ = try SlackEmojiCatalogParser.parse(permissionCheck, workspace: identity)
        try Task.checkCancellation()
        try await credentials.save(identity, token: token, replacing: replacing)
        return identity
    }
    func disconnect(_ workspace: SlackEmojiWorkspace) async throws {
        guard !mutating else { throw SlackEmojiError.changedConnection }
        beginMutation(); defer { finishMutation() }
        try await credentials.remove(workspace)
    }
    func refresh(_ workspace: SlackEmojiWorkspace) async throws -> SlackEmojiCatalog {
        guard !mutating else { throw SlackEmojiError.changedConnection }
        if let prior = inventories[workspace.id]?.catalog { release(prior) }
        let generation = UUID(); refreshes[workspace.id] = generation
        let token = try await credentials.token(for: workspace)
        guard !mutating, refreshes[workspace.id] == generation else { throw SlackEmojiError.changedConnection }
        let identity = try SlackEmojiIdentity.parse(await api("auth.test", token: token, key: workspace.id + ".auth", maximum: 128 * 1_024))
        guard identity.id == workspace.id, identity.botID == workspace.botID,
              identity.url == workspace.url, identity.enterpriseID == workspace.enterpriseID else { throw SlackEmojiError.identityChanged }
        let data = try await api("emoji.list", token: token, key: workspace.id + ".emoji", maximum: 4 * 1_024 * 1_024)
        try Task.checkCancellation(); _ = try await credentials.token(for: workspace)
        guard !mutating, refreshes[workspace.id] == generation else { throw SlackEmojiError.changedConnection }
        let items = try SlackEmojiCatalogParser.parse(data, workspace: workspace)
        let catalog = SlackEmojiCatalog(id: UUID(), workspace: workspace, count: items.count, refreshedAt: now())
        inventories[workspace.id] = .init(catalog: catalog, items: items, byName: Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) }))
        return catalog
    }
    func search(_ query: String, catalog: SlackEmojiCatalog) throws -> SlackEmojiMatches {
        guard !mutating, let inventory = inventories[catalog.workspace.id], inventory.catalog == catalog else { throw SlackEmojiError.changedConnection }
        return try SlackEmojiCatalogParser.matches(inventory.items, query: query)
    }
    func media(_ item: SlackCustomEmoji, catalog: SlackEmojiCatalog) async throws -> Data {
        try validate(item, catalog: catalog)
        _ = try await credentials.token(for: catalog.workspace)
        guard var url = item.resolution.imageURL else { throw SlackEmojiError.unsafeURL }
        let key = catalog.workspace.id + ".media"
        for hop in 0...3 {
            try validate(item, catalog: catalog); try cooldown(key)
            guard SlackEmojiURLPolicy.media(url, workspace: catalog.workspace) else { throw SlackEmojiError.unsafeURL }
            // Construct every request fresh: no Authorization, Cookie, URL credentials, or inherited headers.
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 25)
            request.setValue("image/png,image/jpeg,image/gif", forHTTPHeaderField: "Accept")
            let response = try await fetch(request, owner: catalog.id, maximum: 8 * 1_024 * 1_024)
            try validate(item, catalog: catalog); _ = try await credentials.token(for: catalog.workspace)
            if (300..<400).contains(response.status) {
                guard hop < 3, [301, 302, 303, 307, 308].contains(response.status), let location = response.location,
                      location.utf8.count <= 4_096, let redirected = URL(string: location, relativeTo: url)?.absoluteURL,
                      SlackEmojiURLPolicy.media(redirected, workspace: catalog.workspace) else { throw SlackEmojiError.unsafeURL }
                url = redirected; continue
            }
            try status(response, key: key)
            guard ["image/png", "image/jpeg", "image/gif", "application/octet-stream"].contains(response.contentType ?? "") else { throw SlackEmojiError.invalidImage }
            try validate(item, catalog: catalog); try Task.checkCancellation(); return response.data
        }
        throw SlackEmojiError.unsafeURL
    }
    func release(_ catalog: SlackEmojiCatalog) {
        if inventories[catalog.workspace.id]?.catalog.id == catalog.id { inventories[catalog.workspace.id] = nil }
        for (id, request) in requests where request.owner == catalog.id { request.task.cancel(); requests[id] = nil }
    }
    private func validate(_ item: SlackCustomEmoji, catalog: SlackEmojiCatalog) throws {
        guard !mutating, let inventory = inventories[catalog.workspace.id], inventory.catalog == catalog,
              inventory.byName[item.name] == item else { throw SlackEmojiError.changedConnection }
    }
    private func invalidateAll() {
        inventories = [:]; refreshes = [:]; requests.values.forEach { $0.task.cancel() }; requests = [:]
    }
    private func beginMutation() {
        mutating = true; mutationGeneration = UUID(); invalidateAll()
    }
    private func finishMutation() {
        mutating = false
        let completed = mutationWaiters; mutationWaiters = [:]
        completed.values.forEach { $0.resume() }
    }
    private func waitForMutation() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Actor serialization makes the state check and waiter registration atomic.
                // Recheck cancellation here so cancellation before registration cannot be lost.
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if mutating {
                    mutationWaiters[id] = continuation
                    connectionReadObservers.forEach { $0.resume() }; connectionReadObservers = []
                }
                else { continuation.resume() }
            }
            try Task.checkCancellation()
        } onCancel: {
            Task { await self.cancelMutationWaiter(id) }
        }
    }
    private func cancelMutationWaiter(_ id: UUID) {
        mutationWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
    // Continuation-based test observation avoids timing sleeps around the actor's waiter boundary.
    func waitForPendingConnectionReadForTesting() async {
        if mutationWaiters.isEmpty { await withCheckedContinuation { connectionReadObservers.append($0) } }
    }
    var pendingConnectionReadCountForTesting: Int { mutationWaiters.count }
    private func api(_ method: String, token: String, key: String, maximum: Int) async throws -> Data {
        try cooldown(key)
        guard ["auth.test", "emoji.list"].contains(method), let url = URL(string: "https://slack.com/api/" + method) else { throw SlackEmojiError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"; request.httpBody = Data()
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: SlackEmojiHTTPResponse
        do { response = try await fetch(request, owner: nil, maximum: maximum) }
        catch SlackEmojiError.responseTooLarge { throw method == "emoji.list" ? SlackEmojiError.catalogTooLarge : SlackEmojiError.invalidResponse }
        try status(response, key: key)
        guard response.contentType == "application/json" else { throw SlackEmojiError.invalidResponse }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: response.data) } catch { throw SlackEmojiError.invalidResponse }
        do { try SlackEmojiAPIValidation.check(ok: envelope.ok, error: envelope.error) }
        catch SlackEmojiError.rateLimited(let seconds) { cooldowns[key] = now().addingTimeInterval(TimeInterval(seconds)); throw SlackEmojiError.rateLimited(seconds: seconds) }
        try SlackEmojiAPIValidation.scopes(response.scopes)
        return response.data
    }
    private func status(_ response: SlackEmojiHTTPResponse, key: String) throws {
        switch response.status {
        case 200: break
        case 429:
            let seconds = response.retryAfter ?? 60; cooldowns[key] = now().addingTimeInterval(TimeInterval(seconds))
            throw SlackEmojiError.rateLimited(seconds: seconds)
        case 401, 403: throw SlackEmojiError.denied
        case 300..<400: throw SlackEmojiError.unsafeURL
        default: throw SlackEmojiError.unavailable
        }
    }
    private func cooldown(_ key: String) throws {
        if let until = cooldowns[key], until > now() { throw SlackEmojiError.rateLimited(seconds: max(1, Int(ceil(until.timeIntervalSince(now()))))) }
        cooldowns[key] = nil
    }
    private func fetch(_ request: URLRequest, owner: UUID?, maximum: Int) async throws -> SlackEmojiHTTPResponse {
        let id = UUID(); let task = Task { [transport] in
            try Task.checkCancellation(); let value = try await transport.send(request, maximumBytes: maximum)
            try Task.checkCancellation(); return value
        }
        requests[id] = .init(owner: owner, task: task); defer { requests[id] = nil }
        return try await withTaskCancellationHandler { let result = try await task.value; try Task.checkCancellation(); return result }
        onCancel: { task.cancel() }
    }
    private struct Envelope: Decodable { let ok: Bool; let error: String? }
}
extension SlackEmojiService: SlackEmojiServing {}
