import Foundation
import Infrastructure
import Testing
@testable import SystemCompanionKit

struct CompanionSetupTests {
    @Test func openingAndReadingOwnerStateNeverRegisterAndOnlyExplicitEnableDoes() async throws {
        let native = SetupFixtureRegistration(); let validation = TestCompanionValidator()
        let service = CompanionSetupService(registration: native, validation: validation)
        #expect(await native.registrations == 0)
        #expect(await service.snapshot().state == .disabled)
        #expect(await validation.calls == 0)
        #expect(try await service.enable().state == .enabled)
        #expect(await native.registrations == 1)
        #expect(try await service.enable().state == .enabled)
        #expect(await native.registrations == 1)
        #expect(try await service.disable().state == .disabled)
        #expect(await native.unregistrations == 1)
    }
    @Test func approvalErrorRetainsRealPendingApprovalAndDoesNotReregister() async throws {
        let native = SetupFixtureRegistration(); await native.setApprovalOnRegister()
        let service = CompanionSetupService(registration: native, validation: TestCompanionValidator())
        #expect(try await service.enable().state == .needsApproval)
        #expect(try await service.enable().state == .needsApproval)
        #expect(await native.registrations == 1)
        await service.openApprovalSettings(); #expect(await native.settings == 1)
    }
    @Test func failedUnregisterDoesNotClaimDisabledAndDiagnosticsDiscardPrivateFields() async throws {
        let native = SetupFixtureRegistration()
        let service = CompanionSetupService(registration: native, validation: TestCompanionValidator())
        _ = try await service.enable(); await native.failUnregister()
        await #expect(throws: CompanionSetupFailure.self) { try await service.disable() }
        let snapshot = await service.snapshot()
        #expect(snapshot.state == .enabled)
        #expect(snapshot.error == .unregistrationFailed)
        #expect(snapshot.diagnostic?.domain == .other)
        #expect(snapshot.diagnostic?.code == 123)
        let known = CompanionNativeDiagnostic(error: NSError(domain: "SMAppServiceErrorDomain", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "/generated/private/path", NSUnderlyingErrorKey: "private text"]))
        #expect(known.domain == .serviceManagement && known.code == 1)
    }
    @Test func invalidOwnerSignaturePreventsRegistration() async throws {
        let native = SetupFixtureRegistration(); let validation = TestCompanionValidator(); await validation.fail(.invalidSignature)
        let service = CompanionSetupService(registration: native, validation: validation)
        await #expect(throws: CompanionSetupFailure.self) { try await service.enable() }
        #expect(await native.registrations == 0)
        #expect(await service.snapshot().error == .invalidSignature)
    }
    @Test func canceledValidationAndConcurrentRequestCannotRegisterLate() async throws {
        let native = SetupFixtureRegistration(); let validation = SetupPausedValidator()
        let service = CompanionSetupService(registration: native, validation: validation)
        let pending = Task { try await service.enable() }
        await validation.waitUntilPaused()
        await #expect(throws: CompanionError.tooManyRequests) { try await service.disable() }
        pending.cancel(); await validation.resume()
        await #expect(throws: CompanionSetupFailure.self) { try await pending.value }
        #expect(await native.registrations == 0)
        #expect(await service.snapshot().error == .canceled)
    }
    @Test func boundedManifestReaderUsesOwnedGeneratedRegularFileAndRejectsSymlinksAndOversize() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Commandly-setup-fixture-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("generated.plist")
        let bytes = Data("generated fixture".utf8)
        try bytes.write(to: file)
        #expect(try CompanionSetupManifestReader.read(at: file) == bytes)
        let link = folder.appendingPathComponent("link.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: CompanionError.invalidConfiguration) { try CompanionSetupManifestReader.read(at: link) }
        try Data(repeating: 65, count: 16_385).write(to: file)
        #expect(throws: CompanionError.invalidConfiguration) { try CompanionSetupManifestReader.read(at: file) }
        #expect(throws: CompanionError.invalidConfiguration) { try CompanionSetupManifestReader.read(at: folder) }
    }
    @Test func launchModesAndOwnedManifestFailClosed() throws {
        #expect(try CompanionLaunchMode.resolve(arguments: []) == .setup)
        #expect(try CompanionLaunchMode.resolve(arguments: ["--service"]) == .service)
        #expect(throws: CompanionError.invalidConfiguration) { try CompanionLaunchMode.resolve(arguments: ["--service", "--enable"]) }
        var value: [String: Any] = ["Label": CompanionIdentity.helper, "BundleProgram": CompanionSetupManifest.program,
            "ProgramArguments": CompanionSetupManifest.arguments, "MachServices": [CompanionIdentity.machService: true],
            "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive"]
        try CompanionSetupManifest.validate(PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0))
        value["RunAtLoad"] = true
        #expect(throws: CompanionError.invalidConfiguration) { try CompanionSetupManifest.validate(PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)) }
        #expect(throws: CompanionError.invalidConfiguration) { try CompanionSetupManifest.validate(Data("not a plist".utf8)) }
        #expect(throws: CompanionError.oversizedMessage) { try CompanionSetupManifest.validate(Data(repeating: 0, count: 16_385)) }
    }
}

actor SetupFixtureRegistration: CompanionServiceRegistering {
    private var current: CompanionInstallationState = .disabled
    private var approval = false; private var unregisterFails = false
    var registrations = 0; var unregistrations = 0; var settings = 0
    func state() -> CompanionInstallationState { current }
    func register() throws {
        registrations += 1
        current = approval ? .needsApproval : .enabled
        if approval { throw NSError(domain: "SMAppServiceErrorDomain", code: 1) }
    }
    func unregister() throws {
        unregistrations += 1
        if unregisterFails { throw NSError(domain: "/generated/private/domain", code: 123, userInfo: [NSLocalizedDescriptionKey: "generated private data"]) }
        current = .disabled
    }
    func openApprovalSettings() { settings += 1 }
    func setApprovalOnRegister() { approval = true }
    func failUnregister() { unregisterFails = true }
}
actor SetupPausedValidator: CompanionInstallationValidating {
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func validate() async -> String {
        await withCheckedContinuation { pending = $0; observer?.resume(); observer = nil }
        return "1"
    }
    func waitUntilPaused() async { if pending != nil { return }; await withCheckedContinuation { observer = $0 } }
    func resume() { let old = pending; pending = nil; old?.resume() }
}
