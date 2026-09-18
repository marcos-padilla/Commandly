import Foundation
import Infrastructure

/// Installed only by an authenticated bound bind callback; no caller process identity is accepted.
@MainActor public protocol CompanionAppMenuHandling: Sendable {
    var capabilityState: CompanionCapabilityState { get }
    func connect(session: UUID)
    nonisolated func revoke()
    func cleanupAfterRevocation() async
    func handle(_ request: CompanionAppMenuRequest, session: UUID, deadline: ContinuousClock.Instant) async -> CompanionAppMenuReply
}
/// One authenticated connection's explicitly opted-in menu authority.
@MainActor public final class CompanionMenuController: CompanionAppMenuHandling {
    public nonisolated let lease: CompanionMenuLease
    private let worker: any CompanionMenuWorking
    private let environment: any CompanionMenuEnvironment
    private let now: @Sendable () -> ContinuousClock.Instant
    private var openingContext: CompanionMenuContext?
    private var handles: [CompanionTargetHandle: UUID] = [:]
    private var expires: ContinuousClock.Instant?
    private var expiry: Task<Void, Never>?
    private var busy = false
    public init(lease: CompanionMenuLease, worker: any CompanionMenuWorking, environment: any CompanionMenuEnvironment,
                now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.lease = lease; self.worker = worker; self.environment = environment; self.now = now
    }
    public var capabilityState: CompanionCapabilityState { lease.capabilityState }
    public func connect(session: UUID) {
        environment.stop(); discard(); openingContext = nil; lease.connect(session: session)
    }
    /// The native connection owner must synchronously revoke before scheduling asynchronous cleanup.
    public nonisolated func revoke() { lease.disconnect() }
    public func disconnect() async {
        revoke(); environment.stop(); discard(); openingContext = nil; await worker.clear()
    }
    public func cleanupAfterRevocation() async {
        guard !lease.isConnected else { return }
        environment.stop(); discard(); openingContext = nil; await worker.clear()
    }
    public func handle(_ request: CompanionAppMenuRequest, session: UUID, deadline: ContinuousClock.Instant) async -> CompanionAppMenuReply {
        do {
            try Task.checkCancellation()
            guard now() < deadline else { throw CompanionAppMenuError.timedOut }
            switch request {
            case .setEnabled(let enabled):
                try lease.setEnabled(enabled, session: session)
                discard(); openingContext = nil
                if enabled { environment.start() } else { environment.stop() }
                await worker.clear(); return .enabled(enabled)
            case .release:
                try lease.release(session: session)
                discard(); openingContext = nil; await worker.clear(); return .released
            default: break
            }
            guard !busy else { return .failure(.busy) }
            busy = true; defer { busy = false }
            let context = try lease.snapshot(session: session)
            if let openingContext { guard context == openingContext else { throw CompanionAppMenuError.stale } }
            else { openingContext = context }
            switch request {
            case .snapshot:
                discard()
                let candidates = try await worker.snapshot(context: context, deadline: deadline)
                try lease.validate(context); try Task.checkCancellation()
                guard now() < deadline else { throw CompanionAppMenuError.timedOut }
                guard candidates.count <= 500, Set(candidates.map(\.id)).count == candidates.count else { throw CompanionAppMenuError.tooLarge }
                var newHandles: [CompanionTargetHandle: UUID] = [:]
                let items = try candidates.map { value in
                    guard let leaf = value.path.last else { throw CompanionAppMenuError.invalidData }
                    let handle = CompanionTargetHandle(session: session, target: UUID())
                    newHandles[handle] = value.id
                    return CompanionAppMenuItem(handle: handle, title: leaf.title,
                        ancestors: value.path.dropLast().map(\.title).filter { !$0.isEmpty }, enabled: value.enabled,
                        identity: try value.identity(bundle: context.application.bundleIdentifier))
                }
                let end = now().advanced(by: .seconds(30))
                handles = newHandles; expires = end
                expiry = Task { [weak self] in
                    do { try await ContinuousClock().sleep(until: end) } catch { return }
                    guard let self, self.expires == end else { return }
                    self.discard(); await self.worker.clear()
                }
                let reply = CompanionAppMenuReply.snapshot(.init(bundleIdentifier: context.application.bundleIdentifier, items: items))
                guard try JSONEncoder().encode(reply).count <= 524_288 else { throw CompanionAppMenuError.tooLarge }
                return reply
            case .invoke(let handle):
                guard let end = expires, now() < end else { throw CompanionAppMenuError.expired }
                guard handle.session == session, let id = handles[handle] else { throw CompanionAppMenuError.stale }
                discard()
                return .invoked(try await worker.invoke(id: id, context: context, deadline: min(deadline, end)))
            case .setEnabled, .release: throw CompanionAppMenuError.invalidData
            }
        } catch let error as CompanionAppMenuError {
            if error == .permissionDenied { lease.disconnect(); environment.stop() }
            discard(); await worker.clear(); return .failure(error)
        } catch is CancellationError {
            discard(); await worker.clear(); return .failure(.canceled)
        } catch {
            discard(); await worker.clear(); return .failure(.unavailable)
        }
    }
    private func discard() { handles.removeAll(); expires = nil; expiry?.cancel(); expiry = nil }
}
