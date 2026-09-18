import Foundation
import Infrastructure
import os

/// Native input is created only by configure, after the authenticated session and explicit UI opt-in.
public protocol CompanionKeyboardDriving: Sendable {
    func start(configuration: CompanionKeyboardConfiguration, authorized: @escaping @Sendable () -> Bool,
               activation: @escaping @Sendable (UUID) -> Void, stopped: @escaping @Sendable () -> Void) async throws
    func stop() async
}
/// Synchronous revocation is consulted inside each native callback before consuming or transforming input.
public final class CompanionKeyboardLease: Sendable {
    private struct State { var session: UUID?; var revision: UUID?; var expires: ContinuousClock.Instant? }
    private let state = OSAllocatedUnfairLock(initialState: State())
    public init() {}
    public func connect(session: UUID) { state.withLock { $0 = State(session: session) } }
    public func enable(session: UUID, revision: UUID, until: ContinuousClock.Instant) throws {
        try state.withLock {
            guard $0.session == session else { throw CompanionKeyboardError.disconnected }
            $0.revision = revision; $0.expires = until
        }
    }
    public func permits(session: UUID, revision: UUID) -> Bool {
        state.withLock { $0.session == session && $0.revision == revision && $0.expires.map { ContinuousClock().now < $0 } == true }
    }
    public func matches(session: UUID) -> Bool { state.withLock { $0.session == session } }
    public func disable(session: UUID, revision: UUID) {
        state.withLock { if $0.session == session && $0.revision == revision { $0.revision = nil; $0.expires = nil } }
    }
    public func disable() { state.withLock { $0.revision = nil; $0.expires = nil } }
    public func revoke() { state.withLock { $0 = State() } }
}

/// Bind only on the anonymous authenticated action endpoint. Named metadata endpoints receive no controller.
@MainActor public protocol CompanionKeyboardTriggerHandling: Sendable {
    var capabilityState: CompanionCapabilityState { get }
    func connect(session: UUID)
    nonisolated func revoke()
    func cleanupAfterRevocation() async
    func handle(_ request: CompanionKeyboardTriggerRequest, session: UUID,
                deadline: ContinuousClock.Instant) async -> CompanionKeyboardTriggerReply
}

@MainActor public final class CompanionKeyboardController: CompanionKeyboardTriggerHandling {
    public nonisolated let lease: CompanionKeyboardLease
    private let driver: any CompanionKeyboardDriving
    private var sessionExpires = ContinuousClock().now
    private var revision: UUID?
    private var busy = false
    private var activations: [CompanionKeyboardActivation] = []
    private var waiter: CheckedContinuation<CompanionKeyboardTriggerReply, Never>?
    private var waiterID: UUID?
    private var expiry: Task<Void, Never>?
    public init(driver: any CompanionKeyboardDriving, lease: CompanionKeyboardLease = .init()) {
        self.driver = driver; self.lease = lease
    }
    public var capabilityState: CompanionCapabilityState { revision == nil ? .disabled : .available }
    public func connect(session: UUID) { revoke(); lease.connect(session: session); sessionExpires = ContinuousClock().now.advanced(by: .seconds(CompanionLimits.sessionSeconds)); revision = nil; activations = [] }
    public nonisolated func revoke() { lease.revoke() }
    public func cleanupAfterRevocation() async {
        revision = nil; activations = []; expiry?.cancel(); expiry = nil
        finishWaiter(.failure(.disconnected)); await driver.stop()
    }
    public func handle(_ request: CompanionKeyboardTriggerRequest, session: UUID,
                       deadline: ContinuousClock.Instant) async -> CompanionKeyboardTriggerReply {
        guard lease.matches(session: session) else { return .failure(.disconnected) }
        guard ContinuousClock().now < deadline else { return .failure(.expired) }
        if case .nextActivations = request {
            guard let revision, lease.permits(session: session, revision: revision) else { return .failure(.disabled) }
            if !activations.isEmpty { let values = activations; activations = []; return .activations(values) }
            guard waiter == nil else { return .failure(.unavailable) }
            let id = UUID()
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled { continuation.resume(returning: .failure(.canceled)); return }
                    waiter = continuation; waiterID = id
                    let limit = min(deadline, ContinuousClock().now.advanced(by: .seconds(3)))
                    Task { [weak self] in
                        do { try await ContinuousClock().sleep(until: limit) } catch { return }
                        self?.finishWaiter(.activations([]), matching: id)
                    }
                }
            } onCancel: { Task { @MainActor [weak self] in self?.finishWaiter(.failure(.canceled), matching: id) } }
        }
        guard !busy else { return .failure(.unavailable) }
        busy = true; defer { busy = false }
        lease.disable(); revision = nil; activations = []; expiry?.cancel(); expiry = nil
        finishWaiter(.failure(.disabled)); await driver.stop()
        guard lease.matches(session: session), !Task.isCancelled else { return .failure(.disconnected) }
        switch request {
        case .stop: return .stopped
        case .nextActivations: return .failure(.unavailable)
        case .configure(let configuration):
            guard configuration.isValid else { return .failure(.invalidConfiguration) }
            do {
                // A five-minute session lease bounds idle taps even if a peer stops polling without disconnecting.
                let until = sessionExpires
                try lease.enable(session: session, revision: configuration.revision, until: until)
                let lease = lease
                try await driver.start(configuration: configuration,
                    authorized: { lease.permits(session: session, revision: configuration.revision) },
                    activation: { [weak self] id in
                        Task { @MainActor in self?.enqueue(id, session: session, revision: configuration.revision) }
                    }, stopped: { [weak self] in
                        lease.disable(session: session, revision: configuration.revision)
                        Task { @MainActor in
                            guard let self, self.revision == configuration.revision else { return }
                            self.revision = nil; self.activations = []
                            self.finishWaiter(.failure(.unavailable))
                        }
                    })
                try Task.checkCancellation()
                guard lease.permits(session: session, revision: configuration.revision), ContinuousClock().now < deadline else {
                    throw CompanionKeyboardError.expired
                }
                revision = configuration.revision
                expiry = Task { [weak self] in
                    do { try await ContinuousClock().sleep(until: until) } catch { return }
                    guard let self, self.revision == configuration.revision else { return }
                    self.lease.disable(); self.revision = nil; self.activations = []
                    self.finishWaiter(.failure(.expired)); await self.driver.stop()
                }
                return .configured(configuration.revision)
            } catch {
                lease.disable(); await driver.stop()
                return .failure(error as? CompanionKeyboardError ?? (error is CancellationError ? .canceled : .unavailable))
            }
        }
    }
    private func enqueue(_ binding: UUID, session: UUID, revision: UUID) {
        guard self.revision == revision, lease.permits(session: session, revision: revision) else { return }
        let value = CompanionKeyboardActivation(bindingID: binding, revision: revision)
        if waiter != nil { finishWaiter(.activations([value])); return }
        guard activations.count < 32 else {
            // Never replay a delayed command backlog. Overflow disables interception and requires explicit re-enable.
            lease.disable(); self.revision = nil; activations = []
            Task { await driver.stop() }; return
        }
        activations.append(value)
    }
    private func finishWaiter(_ value: CompanionKeyboardTriggerReply, matching id: UUID? = nil) {
        guard id == nil || waiterID == id else { return }
        let old = waiter; waiter = nil; waiterID = nil; old?.resume(returning: value)
    }
}
