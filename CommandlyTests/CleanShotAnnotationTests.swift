import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("CleanShot local annotation", .timeLimit(.minutes(1)))
struct CleanShotAnnotationTests {
    @Test
    func exactOfficialURLPercentEncodesFilePathAsOneParameter() throws {
        let file = URL(fileURLWithPath: "/tmp/a &action=upload?x=#ü +%.png")
        let url = try CleanShotAnnotationURL.make(fileURL: file)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "cleanshot" && components.host == "open-annotate")
        #expect(components.queryItems == [URLQueryItem(name: "filepath", value: file.path)])
        #expect(components.fragment == nil && components.user == nil && components.password == nil)
        for invalid in [URL(string: "https://example.com/image.png"), URL(string: "file://remote/tmp/image.png"), URL(fileURLWithPath: "/tmp/image.jpeg")] {
            let invalid = try #require(invalid)
            #expect(throws: ScreenshotAnnotationError.invalidImage) { try CleanShotAnnotationURL.make(fileURL: invalid) }
        }
    }

    @Test
    func handlerIdentityAndDocumentedMinimumVersionAreRequired() throws {
        for version in ["3.8.1", "3.9", "4.8.10", "5.0"] {
            try CleanShotApplicationMetadata.validate(bundleIdentifier: "pl.maketheweb.cleanshotx", name: "CleanShot X", version: version, schemes: ["cleanshot"])
        }
        for version in ["3.8", "3.8.0", "2.99.99", "4.beta", "4", "4.1beta", "-4.2", ""] {
            #expect(throws: ScreenshotAnnotationError.applicationOutdated) {
                try CleanShotApplicationMetadata.validate(bundleIdentifier: "pl.maketheweb.cleanshotx", name: "CleanShot X", version: version, schemes: ["cleanshot"])
            }
        }
        #expect(throws: ScreenshotAnnotationError.unexpectedApplication) {
            try CleanShotApplicationMetadata.validate(bundleIdentifier: "example.impostor", name: "CleanShot X", version: "4.8.10", schemes: ["cleanshot"])
        }
        #expect(throws: ScreenshotAnnotationError.unexpectedApplication) {
            try CleanShotApplicationMetadata.validate(bundleIdentifier: "pl.maketheweb.cleanshotx", name: "Other Editor", version: "9.0", schemes: ["cleanshot"])
        }
        #expect(throws: ScreenshotAnnotationError.unexpectedApplication) {
            try CleanShotApplicationMetadata.validate(bundleIdentifier: "pl.maketheweb.cleanshotx", name: "CleanShot X", version: "4.8", schemes: ["https"])
        }
    }

    @MainActor @Test
    func nativeWorkspaceAdapterInspectsThenPinsTheResolvedAppWithoutOpeningDuringLookup() async throws {
        let app = URL(fileURLWithPath: "/fixture/CleanShot X.app")
        let recorder = CleanShotWorkspaceRecorder()
        var opener = WorkspaceCleanShotOpener()
        opener.resolve = { url in recorder.probes.append(url); return app }
        opener.inspect = { url in try await recorder.inspect(url) }
        opener.dispatch = { url, application in recorder.dispatched.append((url, application)) }
        #expect(recorder.probes.isEmpty && recorder.dispatched.isEmpty)
        let destination = try await opener.destination()
        #expect(recorder.probes == [try CleanShotAnnotationURL.probe()] && recorder.dispatched.isEmpty)
        #expect(recorder.inspected == [app])
        let command = try CleanShotAnnotationURL.make(fileURL: URL(fileURLWithPath: "/fixture/local.png"))
        try await opener.open(command, in: destination)
        #expect(recorder.dispatched.count == 1 && recorder.dispatched.first?.0 == command && recorder.dispatched.first?.1 == app)
        opener.resolve = { _ in nil }
        await #expect(throws: ScreenshotAnnotationError.applicationUnavailable) { try await opener.destination() }
        #expect(recorder.dispatched.count == 1)
    }

    @Test
    func nativeBundleInspectionValidatesGeneratedMetadataAndRejectsLargeOrLinkedFiles() async throws {
        let temporary = try CleanShotTestFiles(); defer { temporary.remove() }
        let application = temporary.directory.appendingPathComponent("CleanShot X.app", isDirectory: true)
        let contents = application.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = contents.appendingPathComponent("Info.plist")
        let metadata: [String: Any] = ["CFBundleIdentifier": "pl.maketheweb.cleanshotx", "CFBundleName": "CleanShot X", "CFBundleShortVersionString": "4.8.10",
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["cleanshot"]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0)
        try data.write(to: info)
        // Generated metadata alone is not a valid signed vendor application.
        await #expect(throws: ScreenshotAnnotationError.unexpectedApplication) { try await CleanShotBundleInspector().validate(application) }
        let inspector = CleanShotBundleInspector(validateSignature: { _ in })
        try await inspector.validate(application)
        try Data(repeating: 0, count: 1_048_577).write(to: info)
        await #expect(throws: ScreenshotAnnotationError.unexpectedApplication) { try await inspector.validate(application) }
        try FileManager.default.removeItem(at: info)
        let outside = temporary.directory.appendingPathComponent("outside.plist")
        try data.write(to: outside)
        try FileManager.default.createSymbolicLink(at: info, withDestinationURL: outside)
        await #expect(throws: ScreenshotAnnotationError.unexpectedApplication) { try await inspector.validate(application) }
        #expect(try Data(contentsOf: outside) == data)
    }

    @MainActor @Test
    func unavailableOutdatedOrUnexpectedAppReceivesNoFile() async throws {
        let image = try await CleanShotTestImageFactory().image()
        for error in [ScreenshotAnnotationError.applicationUnavailable, .applicationOutdated, .unexpectedApplication] {
            let temporary = try CleanShotTestFiles(); defer { temporary.remove() }
            let opener = CleanShotOpenerFake(); opener.destinationError = error
            let store = CleanShotTemporaryStore(temporaryDirectory: temporary.directory)
            let service = CleanShotAnnotationService(opener: opener, files: store)
            await #expect(throws: error) { try await service.openInCleanShot(image) }
            #expect(opener.opened.isEmpty && FileManager.default.fileExists(atPath: store.rootURL.path) == false)
        }
    }

    @MainActor @Test
    func rejectedDispatchDeletesStagedPNGAndAllowsRetry() async throws {
        let temporary = try CleanShotTestFiles(); defer { temporary.remove() }
        let clock = CleanShotTestClock(); defer { clock.finish() }
        let opener = CleanShotOpenerFake(); opener.openError = .openFailed
        let store = CleanShotTemporaryStore(temporaryDirectory: temporary.directory, clock: clock.clock)
        let image = try await CleanShotTestImageFactory().image()
        let service = CleanShotAnnotationService(opener: opener, files: store)
        await #expect(throws: ScreenshotAnnotationError.openFailed) { try await service.openInCleanShot(image) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.rootURL.path).isEmpty)
        opener.openError = nil
        try await service.openInCleanShot(image)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.rootURL.path)
        #expect(opener.opened.count == 2 && files.count == 1)
    }

    @MainActor @Test
    func cancellationBeforeDispatchNeverWritesOrOpensAnything() async throws {
        let temporary = try CleanShotTestFiles(); defer { temporary.remove() }
        let opener = CleanShotOpenerFake(); opener.blocksDestination = true
        let store = CleanShotTemporaryStore(temporaryDirectory: temporary.directory)
        let service = CleanShotAnnotationService(opener: opener, files: store)
        let image = try await CleanShotTestImageFactory().image()
        let task = Task { try await service.openInCleanShot(image) }
        await opener.waitUntilDestination()
        task.cancel(); opener.releaseDestination()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(opener.opened.isEmpty && FileManager.default.fileExists(atPath: store.rootURL.path) == false)
    }

    @MainActor @Test
    func cancellationAfterDispatchKeepsExactPNGUntilIndependentDeadline() async throws {
        let temporary = try CleanShotTestFiles(); defer { temporary.remove() }
        let clock = CleanShotTestClock(); defer { clock.finish() }
        let opener = CleanShotOpenerFake(); opener.blocksOpen = true
        let store = CleanShotTemporaryStore(temporaryDirectory: temporary.directory, clock: clock.clock)
        let service = CleanShotAnnotationService(opener: opener, files: store)
        let image = try await CleanShotTestImageFactory().image()
        let task = Task { try await service.openInCleanShot(image) }
        await opener.waitUntilOpen(); await clock.waitUntilScheduled()
        let url = try #require(opener.opened.first?.0)
        let path = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
        let file = URL(fileURLWithPath: path)
        let id = try #require(UUID(uuidString: file.deletingPathExtension().lastPathComponent))
        task.cancel(); opener.releaseOpen()
        try await task.value
        #expect(try temporary.content(file) == image.pngData)
        clock.advance(by: 599)
        #expect(FileManager.default.fileExists(atPath: path))
        clock.advance(by: 1)
        await store.waitForRetirementForTesting(CleanShotFileLease(id: id, fileURL: file))
        #expect(FileManager.default.fileExists(atPath: path) == false)
    }
}

@MainActor private final class CleanShotWorkspaceRecorder {
    var probes: [URL] = []
    var inspected: [URL] = []
    var dispatched: [(URL, URL)] = []
    func inspect(_ url: URL) throws { inspected.append(url) }
}
