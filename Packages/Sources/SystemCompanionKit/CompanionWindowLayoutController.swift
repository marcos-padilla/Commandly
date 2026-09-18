import Foundation
import Infrastructure

/// Inject only into the authenticated anonymous-endpoint engine after its bind proof succeeds.
@MainActor public protocol CompanionWindowLayoutHandling: Sendable {
    var capabilityState: CompanionCapabilityState { get }
    func connect(session: UUID)
    nonisolated func revoke()
    func disconnect() async
    func cleanupAfterRevocation() async
    func handle(_ request: CompanionWindowLayoutRequest, session: UUID, deadline: ContinuousClock.Instant) async -> CompanionWindowLayoutReply
}

/// Routes only authenticated bound-session requests. Construction performs no observation or native access.
/// An engine must call `connect` after opening its authenticated session and revoke before connection teardown.
@MainActor public final class CompanionWindowLayoutController: CompanionWindowLayoutHandling {
    private struct Pending {
        let handle: CompanionTargetHandle
        let context: CompanionWindowLayoutContext
        let expires: ContinuousClock.Instant
    }
    public nonisolated let lease: CompanionWindowLayoutLease
    private let worker: any CompanionWindowLayoutWorking
    private let observer: any CompanionWindowLayoutObserving
    private let now: @Sendable () -> ContinuousClock.Instant
    private var pending: Pending?
    private var busy = false
    private var expiryTask: Task<Void, Never>?
    public init(lease: CompanionWindowLayoutLease, worker: any CompanionWindowLayoutWorking,
                observer: any CompanionWindowLayoutObserving,
                now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now }) {
        self.lease = lease; self.worker = worker; self.observer = observer; self.now = now
    }
    public var capabilityState: CompanionCapabilityState { lease.capabilityState }
    public func connect(session: UUID) {
        observer.stop(); pending = nil; expiryTask?.cancel(); lease.connect(session: session)
    }
    /// Must be called synchronously by the connection owner, even before main-actor cleanup is scheduled.
    public nonisolated func revoke() { lease.disconnect() }
    public func disconnect() async {
        revoke(); observer.stop(); pending = nil; expiryTask?.cancel()
        await worker.clear()
    }
    public func cleanupAfterRevocation() async {
        guard lease.isConnected == false else { return }
        observer.stop(); pending = nil; expiryTask?.cancel()
        await worker.clear()
    }
    public func handle(_ request: CompanionWindowLayoutRequest, session: UUID, deadline: ContinuousClock.Instant) async -> CompanionWindowLayoutReply {
        do {
            try Task.checkCancellation()
            guard now() < deadline else { throw CompanionWindowLayoutError.timedOut }
            if case .setEnabled(let enabled) = request {
                try lease.setEnabled(enabled, session: session)
                pending = nil; expiryTask?.cancel()
                if enabled { observer.start() } else { observer.stop() }
                await worker.clear()
                return .enabled(enabled)
            }
            if case .releaseTargets = request {
                try lease.releaseTargets(session: session)
                pending = nil; expiryTask?.cancel()
                await worker.clear()
                return .released
            }
            guard busy == false else { return .failure(.unavailable) }
            busy = true
            defer { busy = false }
            let context = try lease.snapshot(session: session)
            switch request {
            case .setEnabled, .releaseTargets: throw CompanionWindowLayoutError.unavailable
            case .captureFocused:
                pending = nil; expiryTask?.cancel()
                let handle = CompanionTargetHandle(session: session, target: UUID())
                let expires = min(deadline, now().advanced(by: .seconds(3)))
                try await worker.capture(context: context, handle: handle, expires: expires)
                try lease.validate(context)
                try Task.checkCancellation()
                guard now() < expires else { throw CompanionWindowLayoutError.expiredTarget }
                pending = Pending(handle: handle, context: context, expires: expires)
                expiryTask = Task { [weak self] in
                    do { try await ContinuousClock().sleep(until: expires) } catch { return }
                    guard let self, self.pending?.handle == handle else { return }
                    self.pending = nil
                    await self.worker.clear()
                }
                return .captured(handle)
            case .apply(let handle, let rect):
                guard rect.isValid else { throw CompanionWindowLayoutError.invalidGeometry }
                guard let captured = pending, handle.session == session, captured.handle == handle,
                      captured.context == context else { throw CompanionWindowLayoutError.staleTarget }
                pending = nil; expiryTask?.cancel()
                guard now() < captured.expires else { throw CompanionWindowLayoutError.expiredTarget }
                let receipt = try await worker.apply(context: context, handle: handle, rect: rect, deadline: min(deadline, captured.expires))
                if lease.isConnected == false { observer.stop() }
                return .applied(receipt)
            }
        } catch let error as CompanionWindowLayoutError {
            if error == .permissionDenied {
                // Revoked permission ends authority synchronously; reconnection and explicit opt-in are required.
                lease.disconnect(); observer.stop()
            }
            pending = nil; expiryTask?.cancel()
            await worker.clear()
            return .failure(error)
        } catch is CancellationError {
            pending = nil; expiryTask?.cancel()
            await worker.clear()
            return .failure(.canceled)
        } catch {
            pending = nil; expiryTask?.cancel()
            await worker.clear()
            return .failure(.unavailable)
        }
    }
}
