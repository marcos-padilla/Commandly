import AppKit
import Dispatch
import Foundation
import Infrastructure

@MainActor protocol FinderProcessProviding: Sendable {
    func current() async throws -> FinderProcessIdentity
}

/// TCC may block for user consent; a dedicated queue prevents blocking UI/cooperative executors.
/// Apple-event descriptors remain local to synchronous codec/transport calls on this executor.
actor NativeFinderPathProbe: FinderPathProbing {
    nonisolated private let queue = DispatchSerialQueue(label: "com.commandly.finder-path", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    private let processes: any FinderProcessProviding
    private let transport: any FinderAppleEventTransport
    init(processes: any FinderProcessProviding, transport: any FinderAppleEventTransport = NativeFinderAppleEventTransport()) {
        self.processes = processes; self.transport = transport
    }
    func authorization(allowPrompt: Bool) async throws -> FinderPathAuthorization {
        try Task.checkCancellation()
        let process: FinderProcessIdentity
        do { process = try await processes.current() }
        catch is CancellationError { throw CancellationError() }
        catch { return .finderUnavailable }
        try Task.checkCancellation()
        return try transport.authorization(pid: process.pid, allowPrompt: allowPrompt)
    }
    func read() async throws -> FinderPathContext {
        try Task.checkCancellation()
        let process = try await processes.current()
        try Task.checkCancellation()
        switch try transport.authorization(pid: process.pid, allowPrompt: false) {
        case .authorized: break
        case .requiresConsent: throw FinderPathError.permissionRequired
        case .denied: throw FinderPathError.permissionDenied
        case .finderUnavailable: throw FinderPathError.finderUnavailable
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        func readValue(_ query: FinderEventQuery) throws -> FinderEventValue {
            try Task.checkCancellation()
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { throw FinderPathError.timedOut }
            let seconds = Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18
            return try transport.read(query, pid: process.pid, timeout: min(1.5, seconds))
        }
        guard case .integer(let windowID) = try readValue(.frontWindowID), windowID > 0 else { throw FinderPathError.noWindow }
        guard case .selection(let reference) = try readValue(.selection) else { throw FinderPathError.invalidReply }
        let result: FinderEventValue
        if let reference {
            guard !reference.isEmpty, reference.count <= FinderAppleEventCodec.maximumReferenceBytes else { throw FinderPathError.invalidReply }
            result = try readValue(.selectedURL(reference: reference))
        } else {
            guard case .typeCode(let code) = try readValue(.folderClass(windowID: windowID)),
                  [UInt32(0x63666F6C), 0x63646973, 0x6364736B].contains(code) else { // cfol, cdis, cdsk
                throw FinderPathError.unsupportedLocation
            }
            result = try readValue(.folderURL(windowID: windowID))
        }
        guard case .text(let url) = result else { throw FinderPathError.invalidReply }
        let path = try FinderPathValidation.path(from: url)
        try Task.checkCancellation()
        guard try await processes.current() == process else { throw FinderPathError.changedContext }
        try Task.checkCancellation()
        return .init(process: process, windowID: windowID, selectionReference: reference, path: path)
    }
}
