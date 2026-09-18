import Foundation
import Infrastructure

/// Sandboxed-app facade. It never creates an SMAppService or claims to know another app's registration.
/// Setup opening and metadata connection checks are separate explicit actions; constructors/read-only status are inert.
public actor CompanionMainService: SystemCompanionManaging, CompanionWindowLayoutCalling, CompanionAppMenuCalling, CompanionKeyboardTriggerOperating {
    private let opening: any CompanionSetupOpening
    private let validation: any CompanionInstallationValidating
    private let clientFactory: @Sendable (String) -> CompanionClient
    private var client: CompanionClient?
    private var checked: CompanionStatus?
    private var error: CompanionError?
    private var generation = UUID()
    private var changing = false
    public init(opening: any CompanionSetupOpening, validation: any CompanionInstallationValidating,
                clientFactory: @escaping @Sendable (String) -> CompanionClient) {
        self.opening = opening; self.validation = validation; self.clientFactory = clientFactory
    }
    public func installation() async -> CompanionInstallationSnapshot {
        let token = generation
        if let candidate = client, let status = checked {
            let connected = await candidate.isConnected()
            guard token == generation, client === candidate else { return .init(state: .managedByCompanion) }
            if connected { return .init(state: .ready, status: status) }
            checked = nil
        }
        if error == .versionMismatch || error == .unsupportedVersion { return .init(state: .versionMismatch, error: error) }
        return .init(state: .managedByCompanion, error: error)
    }
    public func openSetup() async throws {
        guard changing == false else { throw CompanionError.tooManyRequests }
        changing = true; defer { changing = false }
        let token = generation
        _ = try await validation.validate()
        try check(token)
        try await opening.openSetup()
        try check(token)
    }
    public func checkConnection() async throws -> CompanionStatus {
        guard changing == false else { throw CompanionError.tooManyRequests }
        changing = true; defer { changing = false }
        let token = generation
        do {
            let build = try await validation.validate(); try check(token)
            let old = client; client = nil; checked = nil
            await old?.disconnect(); try check(token)
            let value = clientFactory(build); client = value
            let status = try await value.check(); try check(token)
            checked = status; error = nil
            return status
        } catch {
            if generation == token {
                await disconnect()
                self.error = (error as? CompanionError) ?? .unavailable
            }
            throw error
        }
    }
    /// Registration belongs to companion setup; old main-app call sites fail visibly instead of reporting success.
    public func enable() throws -> CompanionInstallationSnapshot { throw CompanionError.unsupportedOperation }
    public func disable() throws -> CompanionInstallationSnapshot { throw CompanionError.unsupportedOperation }
    public func openApprovalSettings() async { await opening.openApprovalSettings() }
    /// Disconnect closes only this app's metadata channel. It does not stop the service or revoke OS permissions.
    public func disconnect() async {
        generation = UUID(); let old = client; client = nil; checked = nil; error = nil
        await old?.disconnect()
    }
    public func keyboardTriggers(_ request: CompanionKeyboardTriggerRequest) async throws -> CompanionKeyboardTriggerReply {
        guard changing == false, let client, checked != nil else { throw CompanionError.disconnected }
        let token = generation
        let reply = try await client.keyboardTriggers(request)
        try check(token)
        return reply
    }
    public func requestAppMenu(_ request: CompanionAppMenuRequest) async throws -> CompanionAppMenuReply {
        guard changing == false, let client, checked != nil else { throw CompanionError.disconnected }
        let token = generation
        let reply = try await client.requestAppMenu(request)
        try check(token)
        if case .enabled(let enabled) = reply, let status = checked {
            checked = .init(build: status.build, protocolVersion: status.protocolVersion,
                capabilities: status.capabilities.map { $0.capability == .menus ? .init(capability: .menus, state: enabled ? .available : .disabled) : $0 })
        }
        return reply
    }
    public func requestWindowLayout(_ request: CompanionWindowLayoutRequest) async throws -> CompanionWindowLayoutReply {
        guard changing == false, let client, checked != nil else { throw CompanionError.disconnected }
        let token = generation
        let reply = try await client.requestWindowLayout(request)
        try check(token)
        if case .enabled(let enabled) = reply, let status = checked {
            checked = .init(build: status.build, protocolVersion: status.protocolVersion,
                capabilities: status.capabilities.map { $0.capability == .windows ? .init(capability: .windows, state: enabled ? .available : .disabled) : $0 })
        }
        return reply
    }
    private func check(_ token: UUID) throws {
        try Task.checkCancellation()
        guard token == generation else { throw CompanionError.canceled }
    }
}
