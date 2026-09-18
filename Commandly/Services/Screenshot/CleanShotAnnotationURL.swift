import Foundation
import Infrastructure

/// The only CleanShot action Commandly constructs. See https://cleanshot.com/docs-api.
nonisolated enum CleanShotAnnotationURL {
    static func probe() throws -> URL {
        var components = URLComponents()
        components.scheme = "cleanshot"
        components.host = "open-annotate"
        guard let url = components.url else { throw ScreenshotAnnotationError.openFailed }
        return url
    }

    static func make(fileURL: URL) throws -> URL {
        guard fileURL.isFileURL, fileURL.host == nil || fileURL.host == "localhost",
              fileURL.path.hasPrefix("/"), fileURL.pathExtension.lowercased() == "png",
              fileURL.path.utf8.contains(0) == false else { throw ScreenshotAnnotationError.invalidImage }
        var components = URLComponents(url: try probe(), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "filepath", value: fileURL.path)]
        guard let url = components?.url else { throw ScreenshotAnnotationError.openFailed }
        return url
    }
}

nonisolated struct CleanShotDestination: Sendable, Equatable {
    let applicationURL: URL
}

nonisolated enum CleanShotApplicationMetadata {
    // Verified from the signed official 4.8.10 release; see CLEANSHOT_HANDOFF.md.
    static let bundleIdentifier = "pl.maketheweb.cleanshotx"
    static func validate(bundleIdentifier: String?, name: String?, version: String?, schemes: [String]) throws {
        guard bundleIdentifier == Self.bundleIdentifier, name == "CleanShot X" || name == "CleanShot",
              schemes.contains(where: { $0.lowercased() == "cleanshot" }) else {
            throw ScreenshotAnnotationError.unexpectedApplication
        }
        guard let version, version.utf8.count <= 64 else { throw ScreenshotAnnotationError.applicationOutdated }
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(components.count), components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let major = Int(components[0]), let minor = Int(components[1]) else { throw ScreenshotAnnotationError.applicationOutdated }
        let patch = components.count > 2 ? Int(components[2]) : 0
        guard let patch, major > 3 || (major == 3 && (minor > 8 || (minor == 8 && patch >= 1))) else {
            throw ScreenshotAnnotationError.applicationOutdated
        }
    }
}
