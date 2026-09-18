import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor struct FinderProcessIdentityTests {
    @Test func trustedFinderUsesExactKernelBirthWithoutLaunchServicesDate() async throws {
        let application = try FinderProcessTestData.application()
        let value = FinderProcessTestData.metadata(microseconds: 987_654)
        let metadata = FinderProcessTestMetadata([.success(value), .success(value)])
        let provider = NativeFinderProcessProvider(metadata: metadata, applications: { [application] })
        let identity = try await provider.current()
        #expect(identity == .init(pid: 123, startTime: .init(seconds: 1_789_143_190, microseconds: 987_654)))
        #expect(await metadata.requests == [123, 123])
    }

    @Test(arguments: ["absent", "duplicate", "bundle-id", "bundle-path", "terminated", "invalid-pid"])
    func rejectsUntrustedApplicationWithoutKernelRead(reason: String) async throws {
        let original = try FinderProcessTestData.application()
        let app = try FinderProcessTestData.application(pid: reason == "invalid-pid" ? 0 : 123,
            bundleID: reason == "bundle-id" ? "com.generated.fake" : "com.apple.finder",
            path: reason == "bundle-path" ? "/generated/Finder.app" : "/System/Library/CoreServices/Finder.app",
            terminated: reason == "terminated")
        let apps = reason == "absent" ? [] : reason == "duplicate" ? [original, original] : [app]
        let metadata = FinderProcessTestMetadata([])
        let provider = NativeFinderProcessProvider(metadata: metadata, applications: { apps })
        await #expect(throws: FinderPathError.finderUnavailable) { try await provider.current() }
        #expect(await metadata.requests.isEmpty)
    }

    @Test(arguments: ["pid", "executable", "zero-start", "invalid-microseconds"])
    func rejectsInvalidKernelIdentity(reason: String) async throws {
        let application = try FinderProcessTestData.application()
        let value = FinderProcessTestData.metadata(pid: reason == "pid" ? 124 : 123,
            seconds: reason == "zero-start" ? 0 : 1_789_143_190,
            microseconds: reason == "invalid-microseconds" ? 1_000_000 : 1,
            path: reason == "executable" ? "/generated/Finder.app/Contents/MacOS/Finder" : FinderProcessTestData.executable)
        let metadata = FinderProcessTestMetadata([.success(value)])
        let provider = NativeFinderProcessProvider(metadata: metadata, applications: { [application] })
        await #expect(throws: FinderPathError.finderUnavailable) { try await provider.current() }
        #expect(await metadata.requests == [123])
    }

    @Test func reusedPIDDuringIdentityReadIsRejectedAtMicrosecondPrecision() async throws {
        let application = try FinderProcessTestData.application()
        let metadata = FinderProcessTestMetadata([.success(FinderProcessTestData.metadata(microseconds: 1)),
                                                 .success(FinderProcessTestData.metadata(microseconds: 2))])
        let provider = NativeFinderProcessProvider(metadata: metadata, applications: { [application] })
        await #expect(throws: FinderPathError.changedContext) { try await provider.current() }
        #expect(await metadata.requests == [123, 123])
    }

    @Test func applicationRestartOrDisappearanceDuringReadCannotReturnOldIdentity() async throws {
        let first = try FinderProcessTestData.application()
        let second = try FinderProcessTestData.application(pid: 124)
        let applications = FinderProcessTestApplications([[first], [second]])
        let metadata = FinderProcessTestMetadata([.success(FinderProcessTestData.metadata())])
        let provider = NativeFinderProcessProvider(metadata: metadata, applications: { applications.next() })
        await #expect(throws: FinderPathError.changedContext) { try await provider.current() }
        #expect(await metadata.requests == [123])
    }

    @Test func deniedProcessMetadataAndAlreadyCancelledRequestsFailWithoutPermissionFallback() async throws {
        let application = try FinderProcessTestData.application()
        let metadata = FinderProcessTestMetadata([.failure(.finderUnavailable)])
        let provider = NativeFinderProcessProvider(metadata: metadata, applications: { [application] })
        await #expect(throws: FinderPathError.finderUnavailable) { try await provider.current() }
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await provider.current()
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(await metadata.requests == [123])
    }
}

nonisolated private enum FinderProcessTestData {
    static let executable = "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"
    static func application(pid: Int32 = 123, bundleID: String = "com.apple.finder",
                            path: String = "/System/Library/CoreServices/Finder.app", terminated: Bool = false) throws -> FinderRunningApplication {
        .init(pid: pid, bundleID: bundleID, bundleURL: URL(fileURLWithPath: path, isDirectory: true), isTerminated: terminated)
    }
    static func metadata(pid: Int32 = 123, seconds: UInt64 = 1_789_143_190, microseconds: UInt64 = 1,
                         path: String = executable) -> FinderProcessMetadata {
        .init(pid: pid, startTime: .init(seconds: seconds, microseconds: microseconds), executablePath: path)
    }
}

private actor FinderProcessTestMetadata: FinderProcessMetadataReading {
    private var values: [Result<FinderProcessMetadata, FinderPathError>]
    private(set) var requests: [Int32] = []
    init(_ values: [Result<FinderProcessMetadata, FinderPathError>]) { self.values = values }
    func read(pid: Int32) throws -> FinderProcessMetadata {
        requests.append(pid)
        guard !values.isEmpty else { throw FinderPathError.finderUnavailable }
        return try values.removeFirst().get()
    }
}

@MainActor private final class FinderProcessTestApplications {
    private var values: [[FinderRunningApplication]]
    init(_ values: [[FinderRunningApplication]]) { self.values = values }
    func next() -> [FinderRunningApplication] { values.isEmpty ? [] : values.removeFirst() }
}
