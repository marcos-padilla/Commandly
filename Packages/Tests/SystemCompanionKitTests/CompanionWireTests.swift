import Foundation
import Infrastructure
import Testing
@testable import SystemCompanionKit

struct CompanionWireTests {
    @Test func canonicalMessagesRejectUnknownKeysDuplicateKeysAndEnumCases() throws {
        let request = CompanionRequest(sequence: 1, build: "1", operation: .handshake)
        let bytes = try CompanionWireCodec.encode(request)
        #expect(try CompanionWireCodec.decodeRequest(bytes) == request)
        let json = try #require(String(data: bytes, encoding: .utf8))
        for malformed in [" " + json, json.replacingOccurrences(of: "{", with: "{\"extra\":true,", range: json.startIndex..<json.index(after: json.startIndex)),
                          json.replacingOccurrences(of: "\"sequence\":1", with: "\"sequence\":1,\"sequence\":1"),
                          json.replacingOccurrences(of: "handshake", with: "runShell")] {
            #expect(throws: CompanionError.malformedMessage) { try CompanionWireCodec.decodeRequest(Data(malformed.utf8)) }
        }
    }
    @Test func boundsRejectOversizedPayloadsDeepNestingAndUnboundActions() throws {
        #expect(throws: CompanionError.oversizedMessage) { try CompanionWireCodec.decodeRequest(Data(repeating: 65, count: CompanionLimits.requestBytes + 1)) }
        #expect(throws: CompanionError.malformedMessage) { try CompanionWireCodec.decodeRequest(Data((String(repeating: "[", count: 18) + String(repeating: "]", count: 18)).utf8)) }
        let session = UUID()
        let action = CompanionAction.selection(.replace(handle: .init(session: session, target: UUID()), revision: UUID(), reviewedText: String(repeating: "🙂", count: 16_385)))
        #expect(throws: CompanionError.oversizedMessage) { try CompanionWireCodec.encode(.init(sequence: 1, build: "1", session: session, operation: .selectionAction, action: action)) }
        let wrong = CompanionAction.window(.init(handle: .init(session: UUID(), target: UUID()), action: .close))
        #expect(throws: CompanionError.malformedMessage) { try CompanionWireCodec.encode(.init(sequence: 1, build: "1", session: session, operation: .windowAction, action: wrong)) }
    }
    @Test func requirementsAreExactAndSyntaxValidatedWithoutCheckingAnyKeysOrNativePeers() throws {
        let policy = try CompanionSigningPolicy()
        #expect(policy.applicationRequirement.contains("anchor apple generic"))
        #expect(policy.applicationRequirement.contains("RLF9X72HRT"))
        #expect(policy.helperRequirement.contains("identifier \"com.businessmate360.Commandly.SystemCompanion\""))
        #expect(throws: CompanionError.invalidConfiguration) { try CompanionSigningPolicy.requirement(team: "TEAM\" OR ", bundle: CompanionIdentity.app) }
        #expect(throws: CompanionError.invalidConfiguration) { try CompanionSigningPolicy.requirement(team: CompanionIdentity.team, bundle: "com.example\" or true") }
        let context = CompanionUserSession(effectiveUser: 501, auditSession: 123)
        #expect(context.permits(context))
        #expect(context.permits(.init(effectiveUser: 502, auditSession: 123)) == false)
        #expect(context.permits(.init(effectiveUser: 501, auditSession: 124)) == false)
        #expect(CompanionUserSession(effectiveUser: 0, auditSession: 123).permits(.init(effectiveUser: 0, auditSession: 123)) == false)
        #expect(CompanionIdentity.machService == CompanionIdentity.appGroup + ".SystemCompanion")
    }
}
