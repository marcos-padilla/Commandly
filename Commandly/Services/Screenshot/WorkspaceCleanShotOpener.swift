import AppKit
import Darwin
import Foundation
import Infrastructure
import Security

@MainActor
protocol CleanShotApplicationOpening: Sendable {
    func destination() async throws -> CleanShotDestination
    /// Check cancellation before dispatch. Once dispatched, do not report cancellation as if
    /// the receiving app had not seen the request; its file lease must survive that boundary.
    func open(_ url: URL, in destination: CleanShotDestination) async throws
}

@MainActor
struct WorkspaceCleanShotOpener: CleanShotApplicationOpening {
    var resolve: @MainActor (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    var inspect: @Sendable (URL) async throws -> Void = { try await CleanShotBundleInspector().validate($0) }
    var dispatch: @MainActor (URL, URL) async throws -> Void = { url, application in
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration) { _, error in
                if error != nil { continuation.resume(throwing: ScreenshotAnnotationError.openFailed) }
                else { continuation.resume() }
            }
        }
    }

    func destination() async throws -> CleanShotDestination {
        try Task.checkCancellation()
        guard let application = resolve(try CleanShotAnnotationURL.probe()), application.isFileURL else {
            throw ScreenshotAnnotationError.applicationUnavailable
        }
        try await inspect(application)
        try Task.checkCancellation()
        return CleanShotDestination(applicationURL: application)
    }

    func open(_ url: URL, in destination: CleanShotDestination) async throws {
        try Task.checkCancellation()
        // Pin the inspected application instead of resolving the scheme a second time after
        // the private file is written. No fallback browser or alternative editor is opened.
        try await dispatch(url, destination.applicationURL)
    }
}

actor CleanShotBundleInspector {
    private let validateSignature: @Sendable (URL) throws -> Void
    init(validateSignature: @escaping @Sendable (URL) throws -> Void = CleanShotCodeSignature.validate) {
        self.validateSignature = validateSignature
    }
    func validate(_ application: URL) throws {
        try Task.checkCancellation()
        guard application.isFileURL, application.pathExtension == "app" else {
            throw ScreenshotAnnotationError.unexpectedApplication
        }
        let info = application.appendingPathComponent("Contents/Info.plist")
        let data = try boundedMetadata(at: info)
        guard let metadata = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ScreenshotAnnotationError.unexpectedApplication
        }
        let types = metadata["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        try CleanShotApplicationMetadata.validate(
            bundleIdentifier: metadata["CFBundleIdentifier"] as? String,
            name: metadata["CFBundleDisplayName"] as? String ?? metadata["CFBundleName"] as? String,
            version: metadata["CFBundleShortVersionString"] as? String, schemes: schemes)
        try validateSignature(application)
        try Task.checkCancellation()
    }

    private func boundedMetadata(at url: URL) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw ScreenshotAnnotationError.unexpectedApplication }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        let limit = 1_048_576
        guard Darwin.fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size > 0, metadata.st_size <= limit else { throw ScreenshotAnnotationError.unexpectedApplication }
        var data = Data(count: limit + 1)
        let count = try data.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { throw ScreenshotAnnotationError.unexpectedApplication }
            var total = 0
            while total <= limit {
                try Task.checkCancellation()
                let received = Darwin.read(descriptor, base.advanced(by: total), limit + 1 - total)
                if received < 0, errno == EINTR { continue }
                guard received >= 0 else { throw ScreenshotAnnotationError.unexpectedApplication }
                if received == 0 { break }
                total += received
            }
            return total
        }
        guard count > 0, count <= limit else { throw ScreenshotAnnotationError.unexpectedApplication }
        data.count = count
        return data
    }
}
