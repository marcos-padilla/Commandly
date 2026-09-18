import Darwin
import Dispatch
import Foundation

/// Kernel birth stamp remains available for apps launched outside LaunchServices, including login-time Finder.
public enum CompanionProcessIdentityError: Error, Sendable { case unavailable }

public struct CompanionProcessBirth: Equatable, Sendable {
    public let seconds: UInt64
    public let microseconds: UInt64
    public init(seconds: UInt64, microseconds: UInt64) { self.seconds = seconds; self.microseconds = microseconds }
    public var isValid: Bool { seconds > 0 && microseconds < 1_000_000 }
}
public struct CompanionProcessMetadata: Equatable, Sendable {
    public let pid: Int32
    public let birth: CompanionProcessBirth
    public let executablePath: String
    public init(pid: Int32, birth: CompanionProcessBirth, executablePath: String) {
        self.pid = pid; self.birth = birth; self.executablePath = executablePath
    }
}
public protocol CompanionProcessMetadataReading: Sendable {
    func read(pid: Int32) async throws -> CompanionProcessMetadata
}
/// Public bounded libproc reads on a dedicated serial queue. No AX, window content or permission prompt.
public actor NativeCompanionProcessMetadataReader: CompanionProcessMetadataReading {
    nonisolated private let queue = DispatchSerialQueue(label: "com.commandly.companion.process-identity", qos: .userInitiated)
    nonisolated public var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    public init() {}
    public func read(pid: Int32) throws -> CompanionProcessMetadata {
        try Task.checkCancellation()
        guard pid > 0 else { throw CompanionProcessIdentityError.unavailable }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              let actualPID = Int32(exactly: info.pbi_pid), actualPID == pid else { throw CompanionProcessIdentityError.unavailable }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let count = proc_pidpath(pid, &path, UInt32(path.count))
        guard count > 0, Int(count) < path.count, let end = path.firstIndex(of: 0), end > 0, end <= Int(count),
              let executable = String(bytes: path[..<end].map({ UInt8(bitPattern: $0) }), encoding: .utf8) else {
            throw CompanionProcessIdentityError.unavailable
        }
        let birth = CompanionProcessBirth(seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
        guard birth.isValid else { throw CompanionProcessIdentityError.unavailable }
        try Task.checkCancellation()
        return .init(pid: pid, birth: birth, executablePath: executable)
    }
}
