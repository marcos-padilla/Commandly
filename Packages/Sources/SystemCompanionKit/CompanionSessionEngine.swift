import Foundation
import Infrastructure

/// Metadata is the only native handler in this foundation. It cannot receive future action payloads.
public protocol CompanionMetadataProviding: Sendable { func status() async throws -> CompanionStatus }
/// Explicit capability evidence: connection metadata works; cross-application capabilities do not yet exist.
public struct FoundationCompanionMetadata: CompanionMetadataProviding {
    public let build: String
    public init(build: String) { self.build = build }
    public func status() -> CompanionStatus {
        .init(build: build, protocolVersion: CompanionLimits.protocolVersion,
            capabilities: CompanionCapability.allCases.map { .init(capability: $0, state: $0 == .metadata ? .available : .notImplemented) })
    }
}

/// One authenticated connection's replay ledger, expiring session, bounded work, and cancellation owner.
public actor CompanionSessionEngine {
    private let build: String
    private let metadata: any CompanionMetadataProviding
    private let clock: any CompanionDeadlineClock
    private var keyboardTriggers: (any CompanionKeyboardTriggerHandling)?
    private var appMenus: (any CompanionAppMenuHandling)?
    private var windowLayouts: (any CompanionWindowLayoutHandling)?
    private var negotiated = false
    private var negotiating = false
    private var isInvalid = false
    private var session: UUID?
    private var sessionDeadline: ContinuousClock.Instant?
    private var requestIDs: Set<UUID> = []
    private var sequences: Set<UInt64> = []
    private var tasks: [UUID: Task<CompanionReplyValue, Never>] = [:]
    public init(build: String, metadata: any CompanionMetadataProviding, clock: any CompanionDeadlineClock = NativeCompanionDeadlineClock(), windowLayouts: (any CompanionWindowLayoutHandling)? = nil, appMenus: (any CompanionAppMenuHandling)? = nil) {
        self.build = build; self.metadata = metadata; self.clock = clock; self.windowLayouts = windowLayouts; self.appMenus = appMenus
    }
    /// Called only by an authenticated bound bind callback before the metadata handshake.
    func installBoundAppMenus(_ handler: any CompanionAppMenuHandling) throws {
        guard isInvalid == false, negotiated == false, negotiating == false, session == nil, appMenus == nil else {
            handler.revoke(); throw CompanionError.disconnected
        }
        appMenus = handler
    }
    /// Called only by an authenticated bound bind callback before the metadata handshake.
    func installBoundWindowLayouts(_ handler: any CompanionWindowLayoutHandling) throws {
        guard isInvalid == false, negotiated == false, negotiating == false, session == nil, windowLayouts == nil else {
            handler.revoke(); throw CompanionError.disconnected
        }
        windowLayouts = handler
    }
    func installBoundKeyboardTriggers(_ handler: any CompanionKeyboardTriggerHandling) throws {
        guard !isInvalid, !negotiated, !negotiating, session == nil, keyboardTriggers == nil else {
            handler.revoke(); throw CompanionError.disconnected
        }
        keyboardTriggers = handler
    }
    public func receive(_ request: CompanionRequest) async -> CompanionReply {
        do {
            _ = try CompanionWireCodec.encode(request)
            try authorize(request)
            let value: CompanionReplyValue
            switch request.operation {
            case .handshake:
                guard negotiated == false, negotiating == false, request.session == nil else { throw CompanionError.malformedMessage }
                negotiating = true
                defer { negotiating = false }
                let status = try await timedStatus(request)
                guard isInvalid == false else { throw CompanionError.disconnected }
                negotiated = true
                value = .status(status)
            case .openSession:
                guard request.session == nil else { throw CompanionError.malformedMessage }
                guard session == nil else { throw CompanionError.tooManyRequests }
                let token = UUID(); session = token; sessionDeadline = clock.now().advanced(by: .seconds(CompanionLimits.sessionSeconds))
                await keyboardTriggers?.connect(session: token)
                await appMenus?.connect(session: token)
                await windowLayouts?.connect(session: token)
                guard isInvalid == false, session == token else { keyboardTriggers?.revoke(); windowLayouts?.revoke(); appMenus?.revoke(); throw CompanionError.disconnected }
                try requireSession(token)
                value = .session(token)
            case .closeSession:
                try requireSession(request.session)
                endSession(); value = .acknowledged
            case .cancel:
                try requireSession(request.session)
                guard let id = request.cancelRequestID else { throw CompanionError.malformedMessage }
                tasks[id]?.cancel(); value = .acknowledged
            case .status:
                try requireSession(request.session)
                let status = try await timedStatus(request)
                try requireSession(request.session)
                value = .status(status)
            case .keyboardTriggerAction:
                try requireSession(request.session)
                guard let keyboardTriggers, let token = request.session, let sessionDeadline,
                      case .keyboardTrigger(let action) = request.action else { throw CompanionError.unsupportedOperation }
                guard tasks.count < CompanionLimits.inFlightRequests else { throw CompanionError.tooManyRequests }
                let deadline = min(sessionDeadline, clock.now().advanced(by: .milliseconds(request.timeoutMilliseconds)))
                let task = Task<CompanionReplyValue, Never> { .keyboardTrigger(await keyboardTriggers.handle(action, session: token, deadline: deadline)) }
                tasks[request.id] = task; value = await task.value; tasks[request.id] = nil
                try requireSession(token)
            case .appMenuAction:
                try requireSession(request.session)
                guard let appMenus, let token = request.session, let sessionDeadline,
                      case .appMenu(let action) = request.action else { throw CompanionError.unsupportedOperation }
                guard tasks.count < CompanionLimits.inFlightRequests else { throw CompanionError.tooManyRequests }
                let deadline = min(sessionDeadline, clock.now().advanced(by: .milliseconds(request.timeoutMilliseconds)))
                let task = Task<CompanionReplyValue, Never> {
                    .appMenu(await appMenus.handle(action, session: token, deadline: deadline))
                }
                tasks[request.id] = task
                value = await task.value
                tasks[request.id] = nil
                // The worker checks this same bounded deadline before every write. Never automatically retry.
                try requireSession(token)
            case .windowLayoutAction:
                try requireSession(request.session)
                guard let windowLayouts, let token = request.session, let sessionDeadline,
                      case .windowLayout(let action) = request.action else { throw CompanionError.unsupportedOperation }
                guard tasks.count < CompanionLimits.inFlightRequests else { throw CompanionError.tooManyRequests }
                let deadline = min(sessionDeadline, clock.now().advanced(by: .milliseconds(request.timeoutMilliseconds)))
                let task = Task<CompanionReplyValue, Never> {
                    .windowLayout(await windowLayouts.handle(action, session: token, deadline: deadline))
                }
                tasks[request.id] = task
                value = await task.value
                tasks[request.id] = nil
                // The worker checks this same bounded deadline before every write. Never automatically retry.
                try requireSession(token)
            case .windowAction, .menuAction, .selectionAction, .triggerAction, .lifecycleAction:
                try requireSession(request.session)
                throw CompanionError.unsupportedOperation
            }
            guard isInvalid == false else { throw CompanionError.disconnected }
            return .init(requestID: request.id, value: value)
        } catch let error as CompanionError { return .init(requestID: request.id, value: .failure(error)) }
        catch is CancellationError { return .init(requestID: request.id, value: .failure(.canceled)) }
        catch { return .init(requestID: request.id, value: .failure(.unavailable)) }
    }
    /// Invoked on both XPC interruption and invalidation, not just graceful session close.
    public func invalidate() { isInvalid = true; endSession() }
    public var activeRequestCount: Int { tasks.count }
    public var hasSession: Bool { session != nil }

    private func authorize(_ request: CompanionRequest) throws {
        guard isInvalid == false else { throw CompanionError.disconnected }
        guard request.version == CompanionLimits.protocolVersion else { throw CompanionError.unsupportedVersion }
        guard request.build == build else { throw CompanionError.versionMismatch }
        guard request.operation == .handshake || negotiated else { throw CompanionError.unknownSession }
        // At most 256 requests per connection. No eviction ever makes an old request replayable.
        guard requestIDs.count < 256 else { invalidate(); throw CompanionError.expiredSession }
        guard requestIDs.insert(request.id).inserted, sequences.insert(request.sequence).inserted else { throw CompanionError.replayedRequest }
    }
    private func requireSession(_ value: UUID?) throws {
        guard let session, session == value, let deadline = sessionDeadline else { throw CompanionError.unknownSession }
        guard clock.now() < deadline else { endSession(); throw CompanionError.expiredSession }
    }
    private func endSession() {
        keyboardTriggers?.revoke()
        if let keyboardTriggers { Task { await keyboardTriggers.cleanupAfterRevocation() } }
        appMenus?.revoke()
        if let appMenus { Task { await appMenus.cleanupAfterRevocation() } }
        windowLayouts?.revoke()
        if let windowLayouts { Task { await windowLayouts.cleanupAfterRevocation() } }
        session = nil; sessionDeadline = nil
        for task in tasks.values { task.cancel() }
    }
    private func timedStatus(_ request: CompanionRequest) async throws -> CompanionStatus {
        guard tasks.count < CompanionLimits.inFlightRequests else { throw CompanionError.tooManyRequests }
        let metadata = metadata; let clock = clock; let windowLayouts = windowLayouts; let appMenus = appMenus; let keyboardTriggers = keyboardTriggers
        let deadline = clock.now().advanced(by: .milliseconds(request.timeoutMilliseconds))
        let task = Task<CompanionReplyValue, Never> {
            do {
                let status = try await withThrowingTaskGroup(of: CompanionStatus.self) { group in
                    group.addTask {
                        try Task.checkCancellation()
                        let status = try await metadata.status()
                        let windowState = await windowLayouts?.capabilityState
                        let menuState = await appMenus?.capabilityState
                        let keyboardState = await keyboardTriggers?.capabilityState
                        return CompanionStatus(build: status.build, protocolVersion: status.protocolVersion,
                            capabilities: status.capabilities.map {
                                if $0.capability == .windows, let windowState { return .init(capability: .windows, state: windowState) }
                                if $0.capability == .configuredTriggers, let keyboardState { return .init(capability: .configuredTriggers, state: keyboardState) }
                                if $0.capability == .menus, let menuState { return .init(capability: .menus, state: menuState) }
                                return $0
                            })
                    }
                    group.addTask { try await clock.sleep(until: deadline); throw CompanionError.timedOut }
                    defer { group.cancelAll() }
                    guard let value = try await group.next() else { throw CompanionError.canceled }
                    return value
                }
                try Task.checkCancellation()
                return .status(status)
            } catch let error as CompanionError { return .failure(error) }
            catch is CancellationError { return .failure(.canceled) }
            catch { return .failure(.unavailable) }
        }
        tasks[request.id] = task
        let value = await task.value
        tasks[request.id] = nil
        if case .status(let status) = value { return status }
        if case .failure(let error) = value { throw error }
        throw CompanionError.unavailable
    }
}
