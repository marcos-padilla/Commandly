import AppKit
import Darwin
import Dispatch
import Foundation
import Infrastructure

nonisolated struct FinderRunningApplication: Sendable {
    let pid: Int32
    let bundleID: String?
    let bundleURL: URL?
    let isTerminated: Bool
}

nonisolated struct FinderProcessMetadata: Sendable, Equatable {
    let pid: Int32
    let startTime: FinderProcessStartTime
    let executablePath: String
}

nonisolated protocol FinderProcessMetadataReading: Sendable {
    func read(pid: Int32) async throws -> FinderProcessMetadata
}

/// Finder can start outside LaunchServices, for which NSRunningApplication.launchDate is nil.
/// Its kernel birth time remains the single lifetime source, independent of that optional metadata.
@MainActor struct NativeFinderProcessProvider: FinderProcessProviding {
    private let metadata: any FinderProcessMetadataReading
    private let applications: @MainActor @Sendable () -> [FinderRunningApplication]

    init(metadata: any FinderProcessMetadataReading = NativeFinderProcessMetadataReader(),
         applications: @escaping @MainActor @Sendable () -> [FinderRunningApplication] = {
             NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").map {
                 .init(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier, bundleURL: $0.bundleURL,
                       isTerminated: $0.isTerminated)
             }
         }) {
        self.metadata = metadata; self.applications = applications
    }

    func current() async throws -> FinderProcessIdentity {
        try Task.checkCancellation()
        let first = try trustedApplication()
        let before = try await metadata.read(pid: first.pid)
        try Task.checkCancellation(); try validate(before, pid: first.pid)
        let second = try trustedApplication()
        guard first.pid == second.pid else { throw FinderPathError.changedContext }
        let after = try await metadata.read(pid: second.pid)
        try Task.checkCancellation(); try validate(after, pid: second.pid)
        guard before == after else { throw FinderPathError.changedContext }
        return .init(pid: after.pid, startTime: after.startTime)
    }

    private func trustedApplication() throws -> FinderRunningApplication {
        let fixedURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)
        let matches = applications().filter {
            !$0.isTerminated && $0.bundleID == "com.apple.finder" && $0.bundleURL?.standardizedFileURL == fixedURL
        }
        guard matches.count == 1, let app = matches.first, app.pid > 0 else { throw FinderPathError.finderUnavailable }
        return app
    }

    private func validate(_ value: FinderProcessMetadata, pid: Int32) throws {
        guard value.pid == pid, value.startTime.isValid,
              value.executablePath == "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder" else {
            throw FinderPathError.finderUnavailable
        }
    }
}

/// Public libproc metadata calls run away from MainActor and cooperative workers. These read no
/// Finder window, selection, file contents, or Automation state and never request a permission.
actor NativeFinderProcessMetadataReader: FinderProcessMetadataReading {
    nonisolated private let queue = DispatchSerialQueue(label: "com.commandly.finder-process", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    func read(pid: Int32) throws -> FinderProcessMetadata {
        try Task.checkCancellation()
        guard pid > 0 else { throw FinderPathError.finderUnavailable }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              let actualPID = Int32(exactly: info.pbi_pid), actualPID == pid else { throw FinderPathError.finderUnavailable }
        // PROC_PIDPATHINFO_MAXSIZE is (4 * MAXPATHLEN) in the public SDK; that expression macro
        // is not imported by Swift, so preserve its documented bound here.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let byteCount = proc_pidpath(pid, &path, UInt32(path.count))
        guard byteCount > 0, Int(byteCount) < path.count, let end = path.firstIndex(of: 0), end > 0,
              end <= Int(byteCount) else {
            throw FinderPathError.finderUnavailable
        }
        let bytes = path[..<end].map { UInt8(bitPattern: $0) }
        guard let executable = String(bytes: bytes, encoding: .utf8) else { throw FinderPathError.finderUnavailable }
        try Task.checkCancellation()
        return .init(pid: actualPID, startTime: .init(seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec),
                     executablePath: executable)
    }
}
