import Foundation
import Infrastructure
import Synchronization
import Testing
@testable import Commandly

@MainActor struct FinderPathNativeProbeTests {
    @Test func selectedItemUsesFixedQueriesOnDedicatedExecutorWithoutPromptOrFileRead() async throws {
        let transport = FinderTestEventTransport(values: [.integer(42), .selection(Data([1, 2])), .text("file:///generated/item%20one.txt")])
        let native = NativeFinderPathProbe(processes: FinderTestProcessProvider(), transport: transport)
        let value = try await native.read()
        #expect(value.path == "/generated/item one.txt" && value.origin == .selectedItem && value.windowID == 42)
        let calls = transport.recorded
        #expect(calls.queries == [.frontWindowID, .selection, .selectedURL(reference: Data([1, 2]))])
        #expect(calls.prompts == [false]); #expect(!calls.usedMainThread)
        #expect(calls.timeouts.allSatisfy { $0 > 0 && $0 <= 1.5 })
    }
    @Test func emptySelectionUsesConcreteFolderTargetAndRejectsVirtualClass() async throws {
        let transport = FinderTestEventTransport(values: [.integer(42), .selection(nil), .typeCode(0x63666F6C), .text("file:///generated/folder/")])
        let native = NativeFinderPathProbe(processes: FinderTestProcessProvider(), transport: transport)
        #expect(try await native.read().origin == .currentFolder)
        #expect(transport.recorded.queries == [.frontWindowID, .selection, .folderClass(windowID: 42), .folderURL(windowID: 42)])
        let virtual = FinderTestEventTransport(values: [.integer(42), .selection(nil), .typeCode(0x63636D70)])
        await #expect(throws: FinderPathError.unsupportedLocation) { try await NativeFinderPathProbe(processes: FinderTestProcessProvider(), transport: virtual).read() }
        #expect(virtual.recorded.queries.count == 3)
    }
    @Test func deniedMissingProcessAndQueuedCancellationDoNotReadFinderData() async throws {
        let denied = FinderTestEventTransport(state: .denied, values: [])
        await #expect(throws: FinderPathError.permissionDenied) { try await NativeFinderPathProbe(processes: FinderTestProcessProvider(), transport: denied).read() }
        #expect(denied.recorded.queries.isEmpty)
        let missing = FinderTestEventTransport(values: [])
        let native = NativeFinderPathProbe(processes: FinderTestProcessProvider(missing: true), transport: missing)
        #expect(try await native.authorization(allowPrompt: false) == .finderUnavailable)
        #expect(missing.recorded.prompts.isEmpty)
        let cancelled = Task { try await native.read() }; cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(missing.recorded.queries.isEmpty)
    }
    @Test func explicitPermissionPromptAndFinderRestartAreTracked() async throws {
        let transport = FinderTestEventTransport(values: [.integer(42), .selection(Data([1])), .text("file:///generated/item")])
        let provider = FinderTestProcessProvider(changes: true)
        let native = NativeFinderPathProbe(processes: provider, transport: transport)
        #expect(try await native.authorization(allowPrompt: true) == .authorized)
        #expect(transport.recorded.prompts == [true])
        provider.calls = 0
        await #expect(throws: FinderPathError.changedContext) { try await native.read() }
    }
}

@MainActor private final class FinderTestProcessProvider: FinderProcessProviding {
    let missing: Bool; let changes: Bool; var calls = 0
    init(missing: Bool = false, changes: Bool = false) { self.missing = missing; self.changes = changes }
    func current() throws -> FinderProcessIdentity {
        if missing { throw FinderPathError.finderUnavailable }
        calls += 1
        return .init(pid: 123, startTime: .init(seconds: changes && calls > 1 ? 2 : 1, microseconds: 0))
    }
}
nonisolated private final class FinderTestEventTransport: FinderAppleEventTransport {
    struct Record: Sendable {
        var queries: [FinderEventQuery] = []; var prompts: [Bool] = []; var timeouts: [TimeInterval] = []
        var usedMainThread = false; var values: [FinderEventValue]
    }
    let state: FinderPathAuthorization
    private let storage: Mutex<Record>
    init(state: FinderPathAuthorization = .authorized, values: [FinderEventValue]) { self.state = state; storage = Mutex(Record(values: values)) }
    var recorded: Record { storage.withLock { $0 } }
    func authorization(pid: Int32, allowPrompt: Bool) -> FinderPathAuthorization {
        storage.withLock { $0.prompts.append(allowPrompt); $0.usedMainThread = $0.usedMainThread || Thread.isMainThread }
        return state
    }
    func read(_ query: FinderEventQuery, pid: Int32, timeout: TimeInterval) throws -> FinderEventValue {
        try storage.withLock {
            $0.queries.append(query); $0.timeouts.append(timeout); $0.usedMainThread = $0.usedMainThread || Thread.isMainThread
            guard !$0.values.isEmpty else { throw FinderPathError.invalidReply }
            return $0.values.removeFirst()
        }
    }
}
