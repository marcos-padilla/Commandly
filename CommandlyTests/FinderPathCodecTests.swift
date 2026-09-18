import CoreServices
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct FinderPathCodecTests {
    @Test func fileURLDecodingPreservesPlainPOSIXCharactersWithoutResolvingFiles() throws {
        #expect(try FinderPathValidation.path(from: "file:///generated/Hello%20%F0%9F%8C%8D/%23%25%22.txt") == "/generated/Hello 🌍/#%\".txt")
        #expect(try FinderPathValidation.path(from: "file://localhost/Volumes/Generated/test.txt") == "/Volumes/Generated/test.txt")
        #expect(try FinderPathValidation.path(from: "file:///generated/a%2520b") == "/generated/a%20b")
        #expect(try FinderPathValidation.path(from: "file:///") == "/")
    }
    @Test(arguments: ["https://example.com/a", "relative/path", "file://remote/path", "file://user@localhost/path",
                       "file://localhost:123/path", "file:///tmp/test?query", "file:///tmp/test#fragment", "file:///tmp/%00a",
                       "file:///tmp/a%0Ab", "file:///tmp/a%0Db", "file:///tmp/../a", "file:///tmp/%2E%2E/a",
                       "file:///tmp/./a", String(repeating: "x", count: 16_385)])
    func rejectsNonlocalAmbiguousOrOversizedLocations(_ value: String) {
        #expect(throws: FinderPathError.unsupportedLocation) { try FinderPathValidation.path(from: value) }
    }
    @Test func requestsAreFixedGetDataDescriptorsWithPinnedProcessAndBoundedReference() throws {
        let window = try FinderAppleEventCodec.event(.frontWindowID, pid: 123)
        #expect(window.eventClass == FinderAppleEventCodec.core && window.eventID == FinderAppleEventCodec.getData)
        let direct = try #require(window.paramDescriptor(forKeyword: FinderAppleEventCodec.directObject))
        #expect(direct.descriptorType == FinderAppleEventCodec.object)
        #expect(direct.forKeyword(0x73656C64)?.typeCodeValue == FinderAppleEventCodec.windowIDProperty)
        let container = try #require(direct.forKeyword(0x66726F6D))
        #expect(container.forKeyword(0x77616E74)?.typeCodeValue == FinderAppleEventCodec.windowClass)
        #expect(container.forKeyword(0x73656C64)?.int32Value == 1)
        let byID = try FinderAppleEventCodec.event(.folderURL(windowID: 42), pid: 123)
        let url = try #require(byID.paramDescriptor(forKeyword: FinderAppleEventCodec.directObject))
        #expect(url.forKeyword(0x73656C64)?.typeCodeValue == FinderAppleEventCodec.urlProperty)
        #expect(url.forKeyword(0x66726F6D)?.forKeyword(0x73656C64)?.typeCodeValue == FinderAppleEventCodec.targetProperty)
        #expect(url.forKeyword(0x66726F6D)?.forKeyword(0x66726F6D)?.forKeyword(0x73656C64)?.int32Value == 42)
        #expect(throws: FinderPathError.finderUnavailable) { try FinderAppleEventCodec.event(.selection, pid: 0) }
        #expect(throws: FinderPathError.noWindow) { try FinderAppleEventCodec.event(.folderURL(windowID: -1), pid: 123) }
        #expect(throws: FinderPathError.invalidReply) { try FinderAppleEventCodec.event(.selectedURL(reference: Data(repeating: 1, count: 32_769)), pid: 123) }
    }
    @Test func decodesExactZeroSingleAndMultipleSelectionCardinality() throws {
        let list = NSAppleEventDescriptor.list()
        #expect(try FinderAppleEventCodec.decode(reply(list), query: .selection) == .selection(nil))
        let spec = try #require(FinderAppleEventCodec.event(.frontWindowID, pid: 123).paramDescriptor(forKeyword: FinderAppleEventCodec.directObject))
        list.insert(spec, at: 1)
        #expect(try FinderAppleEventCodec.decode(reply(list), query: .selection) == .selection(spec.data))
        list.insert(spec, at: 2)
        #expect(throws: FinderPathError.multipleSelection) { try FinderAppleEventCodec.decode(reply(list), query: .selection) }
        let malformed = NSAppleEventDescriptor.list(); malformed.insert(.init(string: "not a Finder item"), at: 1)
        #expect(throws: FinderPathError.invalidReply) { try FinderAppleEventCodec.decode(reply(malformed), query: .selection) }
    }
    @Test func typedRepliesAndErrorsNeverExposeRawFinderMessages() throws {
        #expect(try FinderAppleEventCodec.decode(reply(.init(int32: 42)), query: .frontWindowID) == .integer(42))
        #expect(throws: FinderPathError.unsupportedLocation) { try FinderAppleEventCodec.decode(reply(.init(int32: 3)), query: .folderURL(windowID: 42)) }
        #expect(throws: FinderPathError.invalidReply) { try FinderAppleEventCodec.decode(reply(.init(string: String(repeating: "x", count: 70_000))), query: .selection) }
        let denied = reply(.null()); denied.setParam(.init(int32: -1743), forKeyword: FinderAppleEventCodec.errorNumber)
        denied.setParam(.init(string: "/generated/private-name"), forKeyword: 0x65727273)
        #expect(throws: FinderPathError.permissionDenied) { try FinderAppleEventCodec.decode(denied, query: .selection) }
        #expect(FinderAppleEventCodec.mapError(-1728, query: .frontWindowID) == .noWindow)
        #expect(FinderAppleEventCodec.mapError(-1712, query: .selection) == .timedOut)
        #expect(try FinderAppleEventCodec.authorization(-1744) == .requiresConsent)
        #expect(try FinderAppleEventCodec.authorization(-1743) == .denied)
        #expect(try FinderAppleEventCodec.authorization(-600) == .finderUnavailable)
        #expect(throws: FinderPathError.unavailable) { try FinderAppleEventCodec.authorization(-50) }
    }
    private func reply(_ value: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let result = NSAppleEventDescriptor(eventClass: 0x61657674, eventID: 0x616E7372, targetDescriptor: nil, returnID: 0, transactionID: 0)
        result.setParam(value, forKeyword: FinderAppleEventCodec.directObject)
        return result
    }
}
