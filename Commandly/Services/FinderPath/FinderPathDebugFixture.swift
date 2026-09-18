#if DEBUG
import Foundation
import Infrastructure

/// Clearly labeled, nonexistent generated path; no Finder, TCC, file, or network read is performed.
@MainActor enum FinderPathDebugFixture {
    static func services(initialAuthorization: FinderPathAuthorization = .requiresConsent,
                         copier: (any FinderPathCopying)? = nil) -> FinderPathApplicationServices {
        .init(reader: FinderPathReader(probe: GeneratedFinderPathProbe(state: initialAuthorization)),
              copier: copier ?? NativeFinderPathCopier(), openSettings: { throw FinderPathError.unavailable },
              fixtureLabel: "Generated UI fixture — no Finder read or permission request")
    }
}
private actor GeneratedFinderPathProbe: FinderPathProbing {
    private var state: FinderPathAuthorization
    init(state: FinderPathAuthorization) { self.state = state }
    func authorization(allowPrompt: Bool) -> FinderPathAuthorization {
        if allowPrompt, state == .requiresConsent { state = .authorized }
        return state
    }
    func read() throws -> FinderPathContext {
        guard state == .authorized else { throw FinderPathError.permissionRequired }
        return .init(process: .init(pid: 123, startTime: .init(seconds: 1, microseconds: 0)), windowID: 42,
                     selectionReference: Data([1]), path: "/Generated Commandly Fixture/Example.txt")
    }
}
#endif
