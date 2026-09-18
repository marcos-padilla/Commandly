import Foundation
import Infrastructure
import ServiceManagement

/// Narrow injectable Service Management boundary. Only explicit setup methods may mutate registration.
public protocol CompanionServiceRegistering: Sendable {
    func state() async -> CompanionInstallationState
    func register() async throws
    func unregister() async throws
    func openApprovalSettings() async
}
/// Bundle validation is separate from OS registration so fixtures never need signing, profiles, or native services.
public protocol CompanionInstallationValidating: Sendable { func validate() async throws -> String }

/// `SMAppService` objects are acquired lazily on this actor; initialization has no OS side effects.
public actor NativeCompanionRegistration: CompanionServiceRegistering {
    public init() {}
    public func state() -> CompanionInstallationState {
        switch SMAppService.agent(plistName: CompanionIdentity.agentPlist).status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .needsApproval
        case .notFound: .notInstalled
        @unknown default: .unavailable
        }
    }
    public func register() throws {
        do { try SMAppService.agent(plistName: CompanionIdentity.agentPlist).register() }
        catch { throw CompanionSetupFailure(reason: .registrationFailed, diagnostic: .init(error: error)) }
    }
    public func unregister() async throws {
        do { try await SMAppService.agent(plistName: CompanionIdentity.agentPlist).unregister() }
        catch { throw CompanionSetupFailure(reason: .unregistrationFailed, diagnostic: .init(error: error)) }
    }
    public func openApprovalSettings() async { await MainActor.run { SMAppService.openSystemSettingsLoginItems() } }
}

/// Optional setup lifecycle. Reads never register, connect, access another app, or request privacy grants.
public actor SystemCompanionService: SystemCompanionManaging {
    private let registration: any CompanionServiceRegistering
    private let validation: any CompanionInstallationValidating
    private let clientFactory: @Sendable (String) -> CompanionClient
    private var client: CompanionClient?
    private var checkedStatus: CompanionStatus?
    private var lastError: CompanionError?
    private var isChanging = false
    private var generation = UUID()
    public init(registration: any CompanionServiceRegistering, validation: any CompanionInstallationValidating,
                clientFactory: @escaping @Sendable (String) -> CompanionClient) {
        self.registration = registration; self.validation = validation; self.clientFactory = clientFactory
    }
    public func installation() async -> CompanionInstallationSnapshot {
        let token = generation
        let state = await registration.state()
        guard token == generation else { return .init(state: .unavailable, error: .canceled) }
        guard state == .enabled else {
            await disconnect()
            return .init(state: state, error: lastError)
        }
        if let status = checkedStatus, let candidate = client {
            let connected = await candidate.isConnected()
            guard token == generation, client === candidate else { return .init(state: .unavailable, error: .canceled) }
            if connected { return .init(state: .ready, status: status) }
        }
        checkedStatus = nil
        return .init(state: lastError == .versionMismatch || lastError == .unsupportedVersion ? .versionMismatch : .enabled, error: lastError)
    }
    public func enable() async throws -> CompanionInstallationSnapshot {
        guard isChanging == false else { throw CompanionError.tooManyRequests }
        isChanging = true; defer { isChanging = false }
        let token = generation
        _ = try await validation.validate()
        guard token == generation else { throw CompanionError.canceled }
        let state = await registration.state()
        guard token == generation else { throw CompanionError.canceled }
        if state != .enabled && state != .needsApproval { try await registration.register() }
        lastError = nil
        // Registration may start the agent; this action still does not silently grant any capability.
        return await installation()
    }
    public func disable() async throws -> CompanionInstallationSnapshot {
        guard isChanging == false else { throw CompanionError.tooManyRequests }
        isChanging = true; defer { isChanging = false }
        await disconnect()
        if await registration.state() != .disabled { try await registration.unregister() }
        lastError = nil
        return await installation()
    }
    public func checkConnection() async throws -> CompanionStatus {
        guard isChanging == false else { throw CompanionError.tooManyRequests }
        isChanging = true; defer { isChanging = false }
        guard await registration.state() == .enabled else { throw CompanionError.unavailable }
        let token = generation
        do {
            let build = try await validation.validate()
            guard token == generation else { throw CompanionError.canceled }
            let old = client; client = nil; checkedStatus = nil
            await old?.disconnect()
            guard token == generation else { throw CompanionError.canceled }
            let value = clientFactory(build); client = value
            let status = try await value.check()
            guard token == generation else { throw CompanionError.canceled }
            checkedStatus = status; lastError = nil
            return status
        } catch {
            await disconnect()
            let typed = (error as? CompanionError) ?? .unavailable
            lastError = typed
            throw typed
        }
    }
    public func openApprovalSettings() async { await registration.openApprovalSettings() }
    public func disconnect() async {
        generation = UUID()
        let old = client; client = nil; checkedStatus = nil
        await old?.disconnect()
    }
}
