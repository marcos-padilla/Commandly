import Foundation
import Infrastructure
import Testing
@testable import SystemCompanionKit

struct CompanionBoundChannelTests {
    @Test func constructionIsInertAndOnlyVerifiedEndpointReceivesMetadata() async throws {
        let connector = BoundFixtureConnector()
        let transport = CompanionBoundTransport(build: "1", connector: connector)
        #expect(await transport.isConnected() == false)
        #expect(await connector.bootstrapCalls == 0)
        let client = CompanionClient(transport: transport, build: "1")
        let status = try await client.check()
        #expect(status.capabilities.filter { $0.state == .available }.map(\.capability) == [.metadata])
        #expect(await connector.bootstrapCalls == 1)
        #expect(await connector.bindCalls == 1)
        #expect(await connector.metadataCalls == 3)
        #expect(await client.isConnected())
        let named = await connector.namedBytes
        #expect(named.count == 1)
        let first = try #require(named.first)
        #expect(try CompanionBoundWire.hello(first).build == "1")
    }
    @Test(arguments: [BoundFixtureConnector.Mode.wrongSigner, .wrongUser, .replacedTicket, .replacedEndpoint, .invalidEndpoint])
    func rejectedBootstrapOrEndpointNeverReceivesAnApplicationRequest(_ mode: BoundFixtureConnector.Mode) async throws {
        let connector = BoundFixtureConnector(mode)
        let transport = CompanionBoundTransport(build: "1", connector: connector)
        await #expect(throws: CompanionError.self) { try await transport.exchange(handshake()) }
        #expect(await connector.metadataCalls == 0)
        #expect(await transport.isConnected() == false)
        await #expect(throws: CompanionError.disconnected) { try await transport.exchange(handshake()) }
        #expect(await connector.bootstrapCalls == 1)
    }
    @Test func futureSelectionTextIsRejectedBeforeBootstrapAndAfterBinding() async throws {
        let connector = BoundFixtureConnector()
        let transport = CompanionBoundTransport(build: "1", connector: connector)
        let session = UUID(); let sentinel = "Generated private-payload sentinel 7842"
        let data = try CompanionWireCodec.encode(CompanionRequest(sequence: 9, build: "1", session: session, operation: .selectionAction,
            action: .selection(.replace(handle: .init(session: session, target: UUID()), revision: UUID(), reviewedText: sentinel))))
        await #expect(throws: CompanionError.unsupportedOperation) { try await transport.exchange(data) }
        #expect(await connector.bootstrapCalls == 0)
        let client = CompanionClient(transport: transport, build: "1"); _ = try await client.check()
        let before = await connector.metadataCalls
        await #expect(throws: CompanionError.unsupportedOperation) { try await transport.exchange(data) }
        #expect(await connector.metadataCalls == before)
        for packet in await connector.namedBytes { #expect(String(decoding: packet, as: UTF8.self).contains(sentinel) == false) }
        // These native calls stop at a typed local guard: no signing, launchd, permissions, or connection is touched.
        let native = NativeCompanionBoundConnector()
        await #expect(throws: CompanionError.unsupportedOperation) { try await native.exchangeMetadata(data) }
        #expect(await native.isConnected() == false)
    }
    @Test(arguments: [BoundFixtureConnector.Stage.bootstrap, .bind])
    func staleResponseCannotReviveAnInvalidatedInstance(_ stage: BoundFixtureConnector.Stage) async throws {
        let connector = BoundFixtureConnector(); await connector.pause(at: stage)
        let transport = CompanionBoundTransport(build: "1", connector: connector)
        let operation = Task { try await transport.exchange(handshake()) }
        await connector.waitUntilPaused(); await transport.invalidate(); await connector.resume()
        await #expect(throws: CompanionError.disconnected) { try await operation.value }
        #expect(await connector.metadataCalls == 0)
        #expect(await transport.isConnected() == false)
    }
    @Test func cancellationAfterBootstrapDiscardsLateEndpointAndDoesNotDiscloseRequests() async throws {
        let connector = BoundFixtureConnector(); await connector.pause(at: .bootstrap)
        let transport = CompanionBoundTransport(build: "1", connector: connector)
        let operation = Task { try await transport.exchange(handshake()) }
        await connector.waitUntilPaused(); operation.cancel(); await connector.resume()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await connector.bindCalls == 0)
        #expect(await connector.metadataCalls == 0)
        #expect(await connector.invalidations == 1)
    }
    @Test func replySubstitutionClosesInstanceWithoutNamedServiceRediscovery() async throws {
        let connector = BoundFixtureConnector(.malformedEcho)
        let transport = CompanionBoundTransport(build: "1", connector: connector)
        await #expect(throws: CompanionError.malformedMessage) { try await transport.exchange(handshake()) }
        await #expect(throws: CompanionError.disconnected) { try await transport.exchange(handshake()) }
        #expect(await connector.bootstrapCalls == 1)
        #expect(await connector.bindCalls == 1)
        #expect(await connector.metadataCalls == 1)
    }
    @Test func inFlightMetadataReplyCannotOutliveAnInvalidatedEndpoint() async throws {
        let connector = BoundFixtureConnector(); await connector.pause(at: .metadata)
        let transport = CompanionBoundTransport(build: "1", connector: connector)
        let operation = Task { try await transport.exchange(handshake()) }
        await connector.waitUntilPaused(); await transport.invalidate(); await connector.resume()
        await #expect(throws: CompanionError.disconnected) { try await operation.value }
        #expect(await connector.metadataCalls == 1)
        #expect(await transport.isConnected() == false)
        await #expect(throws: CompanionError.disconnected) { try await transport.exchange(handshake()) }
        #expect(await connector.bootstrapCalls == 1)
    }
    @Test func connectedSnapshotCannotOutliveInvalidation() async throws {
        let connector = BoundFixtureConnector(); let transport = CompanionBoundTransport(build: "1", connector: connector)
        _ = try await transport.exchange(handshake())
        await connector.pause(at: .connected)
        let snapshot = Task { await transport.isConnected() }
        await connector.waitUntilPaused(); await transport.invalidate(); await connector.resume()
        #expect(await snapshot.value == false)
    }
    private func handshake() throws -> Data { try CompanionWireCodec.encode(.init(sequence: 1, build: "1", operation: .handshake)) }
}
