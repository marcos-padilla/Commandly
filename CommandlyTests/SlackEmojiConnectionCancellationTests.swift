import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

@MainActor struct SlackEmojiConnectionCancellationTests {
    @Test func cancelBeforeAuthenticationSettlesReloadsAnUnchangedConnectionList() async throws {
        let transport = SlackEmojiTestTransport([])
        let storage = SlackEmojiSuspendingSecureStore()
        let service = SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: storage), transport: transport)
        let model = model(service)
        model.load(); await model.waitForLoadForTesting()
        model.openConnections(); model.tokenInput = "xoxb-generated-token"; model.connect(replacing: false)
        await transport.waitForSuspension()
        #expect(model.handleEscape()); #expect(model.isCancellingConnection)
        await transport.complete(try SlackEmojiTestData.auth()); await model.waitForCancellationForTesting()
        #expect(model.workspaces.isEmpty); #expect(await storage.writeCount == 0)
        #expect(!model.isChangingConnection); #expect(!model.showsConnections); #expect(model.tokenInput.isEmpty)
        #expect(model.statusMessage == "Connection check cancelled."); #expect(model.errorMessage == nil)
        model.stop()
    }

    @Test func cancelAfterSecureWriteStartsReloadsTheActuallyCommittedConnection() async throws {
        let transport = SlackEmojiTestTransport([try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog()])
        let storage = SlackEmojiSuspendingSecureStore()
        let service = SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: storage), transport: transport)
        let model = model(service)
        model.load(); await model.waitForLoadForTesting()
        model.openConnections(); model.tokenInput = "xoxb-generated-token"; model.connect(replacing: false)
        await storage.waitForWrite()
        #expect(model.handleEscape()); #expect(model.isChangingConnection); #expect(model.isCancellingConnection)
        #expect(model.workspaces.isEmpty)
        await storage.finishWrite(); await model.waitForCancellationForTesting()
        let saved = try await SlackEmojiCredentialStore(secureStore: storage).workspaces()
        #expect(saved.count == 1); #expect(model.workspaces == saved); #expect(model.workspace == saved.first)
        #expect(model.statusMessage?.contains("finished before cancellation") == true)
        #expect(model.errorMessage == nil); #expect(!model.showsConnections); #expect(model.canRefresh)
        model.stop()
    }

    @Test(arguments: [false, true])
    func freshModelWaitsForRetiredModelsSecureWrite(failing: Bool) async throws {
        let transport = SlackEmojiTestTransport([try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog()])
        let storage = SlackEmojiSuspendingSecureStore()
        let service = SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: storage), transport: transport)
        let retired = model(service)
        retired.load(); await retired.waitForLoadForTesting()
        retired.openConnections(); retired.tokenInput = "xoxb-generated-token"; retired.connect(replacing: false)
        await storage.waitForWrite(); retired.stop()

        let fresh = model(service)
        fresh.load(); await service.waitForPendingConnectionReadForTesting()
        #expect(fresh.isLoading); #expect(fresh.errorMessage == nil); #expect(fresh.workspaces.isEmpty)
        await storage.finishWrite(failing: failing); await fresh.waitForLoadForTesting()
        let actual = try await SlackEmojiCredentialStore(secureStore: storage).workspaces()
        #expect(actual.count == (failing ? 0 : 1)); #expect(fresh.workspaces == actual)
        #expect(!fresh.isLoading); #expect(fresh.errorMessage == nil); #expect(fresh.statusMessage == nil)
        #expect(!fresh.showsConnections); #expect(fresh.canRefresh == !failing)
        #expect(await service.pendingConnectionReadCountForTesting == 0)
        fresh.stop()
    }

    @Test func cancellingAWaitingReaderDoesNotCancelTheSecureWriteOrAnotherReader() async throws {
        let transport = SlackEmojiTestTransport([try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog()])
        let storage = SlackEmojiSuspendingSecureStore()
        let service = SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: storage), transport: transport)
        let writing = Task { try await service.connect(token: "xoxb-generated-token", replacing: nil) }
        await storage.waitForWrite()
        let cancelledReader = Task { try await service.connections() }
        await service.waitForPendingConnectionReadForTesting(); cancelledReader.cancel()
        await #expect(throws: CancellationError.self) { try await cancelledReader.value }
        #expect(await service.pendingConnectionReadCountForTesting == 0)

        let currentReader = Task { try await service.connections() }
        await service.waitForPendingConnectionReadForTesting()
        #expect(await service.pendingConnectionReadCountForTesting == 1)
        await storage.finishWrite()
        let committed = try await writing.value
        #expect(try await currentReader.value == [committed])
        #expect(await service.pendingConnectionReadCountForTesting == 0)
    }

    @Test func alreadyCancelledReaderNeverRegistersAMutationWaiter() async throws {
        let transport = SlackEmojiTestTransport([try SlackEmojiTestData.auth(), try SlackEmojiTestData.responseCatalog()])
        let storage = SlackEmojiSuspendingSecureStore()
        let service = SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: storage), transport: transport)
        let writing = Task { try await service.connect(token: "xoxb-generated-token", replacing: nil) }
        await storage.waitForWrite()
        let cancelledReader = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.connections()
        }
        await #expect(throws: CancellationError.self) { try await cancelledReader.value }
        #expect(await service.pendingConnectionReadCountForTesting == 0)
        await storage.finishWrite(); _ = try await writing.value
    }

    private func model(_ service: any SlackEmojiServing) -> SlackEmojiViewModel {
        .init(services: .init(service: service, decoder: SlackEmojiImageDecoder(),
                             exporter: NativeSlackEmojiExporter(writeName: { _ in false }, writeImage: { _, _ in false },
                                                                chooseDestination: { _, _ in nil }), openURL: { _ in }), onGoBack: {})
    }
}

/// Models a noncancellable secure-storage write that may commit after its caller is cancelled.
/// It is memory-only and never calls Keychain or retains data outside the test instance.
private actor SlackEmojiSuspendingSecureStore: SecureStoring {
    private var values: [SecureStoreKey: Data] = [:]
    private var pending: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var writeCount = 0
    private var writeFails = false
    func read(_ key: SecureStoreKey) -> Data? { values[key] }
    func delete(_ key: SecureStoreKey) { values[key] = nil }
    func write(_ key: SecureStoreKey, value: Data) async throws {
        writeCount += 1
        waiters.forEach { $0.resume() }; waiters = []
        await withCheckedContinuation { pending = $0 }
        if writeFails { throw SecureStoreError.operationFailed }
        values[key] = value
    }
    func waitForWrite() async {
        if pending == nil { await withCheckedContinuation { waiters.append($0) } }
    }
    func finishWrite(failing: Bool = false) { writeFails = failing; pending?.resume(); pending = nil }
}
