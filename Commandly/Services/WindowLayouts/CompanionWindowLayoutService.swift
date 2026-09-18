import AppKit
import Foundation
import Infrastructure

/// Uses only the authenticated companion client; this sandboxed adapter never imports ApplicationServices.
@MainActor final class CompanionWindowLayoutService: WindowLayoutApplying {
    private let client: any CompanionWindowLayoutCalling
    private var generation = UUID()
    private var task: Task<Void, Error>?
    private var cleanup: Task<Void, Never>?
    private var cleanupFailed = false
    private var resignToken: NSObjectProtocol?
    init(client: any CompanionWindowLayoutCalling) {
        self.client = client
    }
    func apply(rect: NormalizedWindowRect) async throws {
        guard rect.isValid else { throw CompanionWindowLayoutApplicationError.failure(.invalidGeometry) }
        guard task == nil else { throw CompanionWindowLayoutApplicationError.failure(.unavailable) }
        let invocation = UUID()
        generation = invocation
        await cleanup?.value
        try Task.checkCancellation()
        if cleanupFailed {
            do { cleanupFailed = try await client.requestWindowLayout(.releaseTargets) != .released }
            catch { throw CompanionWindowLayoutApplicationError.failure(.disconnected) }
        }
        guard cleanupFailed == false else { throw CompanionWindowLayoutApplicationError.failure(.disconnected) }
        guard invocation == generation else { throw CancellationError() }
        resignToken = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelPending() }
        }
        let client = client
        let operation = Task { @MainActor [weak self] in
            let capture = try await client.requestWindowLayout(.captureFocused)
            try Task.checkCancellation()
            guard self?.generation == invocation else { throw CancellationError() }
            let handle: CompanionTargetHandle
            switch capture {
            case .captured(let value): handle = value
            case .failure(let error): throw CompanionWindowLayoutApplicationError.failure(error)
            default: throw CompanionWindowLayoutApplicationError.failure(.unavailable)
            }
            let geometry = CompanionNormalizedWindowRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            let result = try await client.requestWindowLayout(.apply(handle: handle, rect: geometry))
            try Task.checkCancellation()
            guard self?.generation == invocation else { throw CancellationError() }
            switch result {
            case .applied(let receipt):
                guard receipt.outcome == .applied else { throw CompanionWindowLayoutApplicationError.receipt(receipt.outcome) }
            case .failure(let error): throw CompanionWindowLayoutApplicationError.failure(error)
            default: throw CompanionWindowLayoutApplicationError.failure(.unavailable)
            }
        }
        task = operation
        defer {
            if generation == invocation { task = nil; removeObserver() }
        }
        do {
            try await withTaskCancellationHandler {
                try await operation.value
            } onCancel: {
            operation.cancel()
            Task { @MainActor [weak self] in
                guard let self, self.generation == invocation else { return }
                self.cancelPending()
            }
            }
        } catch let error as CompanionError {
            throw CompanionWindowLayoutApplicationError.failure(error == .unsupportedOperation ? .disabled : .disconnected)
        }
    }
    /// Launcher close or app deactivation ends this UI invocation and releases any helper handle.
    func cancelPending() {
        generation = UUID(); task?.cancel(); task = nil; removeObserver()
        let previous = cleanup
        let client = client
        cleanup = Task {
            await previous?.value
            do {
                let result = try await client.requestWindowLayout(.releaseTargets)
                cleanupFailed = result != .released
            } catch {
                // Surface cleanup failure by requiring a fresh connection/adapter before another Apply.
                cleanupFailed = true
            }
        }
    }
    private func removeObserver() {
        if let resignToken { NotificationCenter.default.removeObserver(resignToken) }
        resignToken = nil
    }
}

/// Fixed recovery messages do not expose native target metadata.
enum CompanionWindowLayoutApplicationError: LocalizedError {
    case failure(CompanionWindowLayoutError)
    case receipt(CompanionWindowLayoutOutcome)
    var errorDescription: String? {
        switch self {
        case .receipt(.uncertain): return "The window may have changed, but the app did not confirm the operation. Check the window before applying another layout."
        case .receipt(.partial): return "The window resized, but moving it did not finish. Its layout may have changed."
        case .receipt(.unverified): return "The app accepted the layout, but its final bounds could not be verified."
        case .receipt(.constrained): return "The app accepted the layout but kept different window bounds."
        case .receipt: return "The app did not accept the layout."
        case .failure(.permissionDenied): return "Enable Accessibility for Commandly System Companion in System Settings, then try again."
        case .failure(.disabled): return "Enable Window Layouts in System Integration before applying a layout."
        case .failure(.locked): return "The window session ended. Unlock your Mac and reconnect System Integration."
        case .failure(.noExternalApplication): return "Activate an external app, return to Commandly, and apply the layout."
        case .failure(.noFocusedWindow): return "The remembered app has no focused window."
        case .failure(.unsupportedWindow): return "This window does not support this layout."
        case .failure(.staleTarget), .failure(.expiredTarget), .failure(.displayChanged): return "The window or display changed. Apply the layout again."
        case .failure(.canceled): return "The layout was canceled."
        case .failure(.invalidGeometry): return "Keep the layout rectangle inside the screen."
        case .failure(.timedOut): return "The app did not respond in time."
        case .failure: return "Connect System Integration before applying a layout."
        }
    }
}
