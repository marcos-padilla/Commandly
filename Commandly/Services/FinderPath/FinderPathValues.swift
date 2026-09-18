import Foundation
import Infrastructure

nonisolated struct FinderProcessIdentity: Sendable, Equatable {
    let pid: Int32
    let startTime: FinderProcessStartTime
}

/// Exact kernel process birth time, kept as integers so PID reuse cannot lose microsecond precision.
nonisolated struct FinderProcessStartTime: Sendable, Equatable {
    let seconds: UInt64
    let microseconds: UInt64
    var isValid: Bool { seconds > 0 && microseconds < 1_000_000 }
}

nonisolated struct FinderPathContext: Sendable, Equatable {
    let process: FinderProcessIdentity
    let windowID: Int32
    let selectionReference: Data?
    let path: String
    var origin: FinderPathOrigin { selectionReference == nil ? .currentFolder : .selectedItem }
}

nonisolated protocol FinderPathProbing: Sendable {
    func authorization(allowPrompt: Bool) async throws -> FinderPathAuthorization
    func read() async throws -> FinderPathContext
}

nonisolated enum FinderPathValidation {
    static let maximumURLBytes = 16_384
    static func path(from string: String) throws -> String {
        guard !string.isEmpty, string.utf8.count <= maximumURLBytes,
              let components = URLComponents(string: string), components.scheme?.lowercased() == "file",
              components.host == nil || components.host == "" || components.host?.lowercased() == "localhost",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              let url = components.url, url.isFileURL else { throw FinderPathError.unsupportedLocation }
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix("/"), !path.isEmpty, path.utf8.count <= maximumURLBytes,
              !path.unicodeScalars.contains(where: { $0.value == 0 || $0.value == 10 || $0.value == 13 }),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }) else {
            throw FinderPathError.unsupportedLocation
        }
        return path
    }
}
