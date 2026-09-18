import Infrastructure

/// Registration runs only in the companion's own process. Opening a window and reading state are inert.
public actor CompanionSetupService: CompanionSetupManaging {
    private let registration: any CompanionServiceRegistering
    private let validation: any CompanionInstallationValidating
    private var changing = false
    private var failure: CompanionSetupFailure?
    public init(registration: any CompanionServiceRegistering, validation: any CompanionInstallationValidating) {
        self.registration = registration; self.validation = validation
    }
    public func snapshot() async -> CompanionSetupSnapshot {
        let state = await registration.state()
        return .init(state: state, error: failure?.reason, diagnostic: failure?.diagnostic)
    }
    public func enable() async throws -> CompanionSetupSnapshot {
        guard changing == false else { throw CompanionError.tooManyRequests }
        changing = true; defer { changing = false }
        do {
            try Task.checkCancellation()
            _ = try await validation.validate()
            try Task.checkCancellation()
            let before = await registration.state()
            if before != .enabled && before != .needsApproval {
                do { try await registration.register() }
                catch {
                    // macOS can return a consent error after creating a registration. Preserve that real state.
                    let after = await registration.state()
                    if after != .enabled && after != .needsApproval { throw error }
                }
            }
            failure = nil
            return await snapshot()
        } catch {
            let value = Self.failure(error, fallback: .registrationFailed); failure = value
            throw value
        }
    }
    public func disable() async throws -> CompanionSetupSnapshot {
        guard changing == false else { throw CompanionError.tooManyRequests }
        changing = true; defer { changing = false }
        do {
            try Task.checkCancellation()
            _ = try await validation.validate()
            try Task.checkCancellation()
            if await registration.state() != .disabled { try await registration.unregister() }
            failure = nil
            return await snapshot()
        } catch {
            let value = Self.failure(error, fallback: .unregistrationFailed); failure = value
            throw value
        }
    }
    public func openApprovalSettings() async { await registration.openApprovalSettings() }
    private static func failure(_ error: any Error, fallback: CompanionError) -> CompanionSetupFailure {
        if error is CancellationError { return .init(reason: .canceled) }
        if let value = error as? CompanionSetupFailure { return value }
        if let value = error as? CompanionError { return .init(reason: value) }
        return .init(reason: fallback, diagnostic: CompanionNativeDiagnostic(error: error))
    }
}
