import Foundation
import Infrastructure

/// Reads only fixed OS metadata after explicit navigation. Production roots are in the sealed
/// system volume; injectable roots exist for generated-file tests, never for user-supplied URLs.
actor NativeSystemSettingsResolver: SystemSettingsResolving {
    private let applicationURL: URL
    private let extensionsURL: URL
    private let maximumMetadataBytes = 131_072

    init(
        applicationURL: URL = URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true),
        extensionsURL: URL = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions", isDirectory: true)
    ) {
        self.applicationURL = applicationURL
        self.extensionsURL = extensionsURL
    }

    func resolve(_ pane: SystemSettingsPane?) async throws -> SystemSettingsNavigationPlan {
        try Task.checkCancellation()
        guard applicationURL.isFileURL, extensionsURL.isFileURL,
              (applicationURL.host == nil || applicationURL.host == "localhost"),
              (extensionsURL.host == nil || extensionsURL.host == "localhost"),
              applicationURL.lastPathComponent == "System Settings.app",
              isRegularDirectory(applicationURL),
              let app = readMetadata(applicationURL.appending(path: "Contents/Info.plist")),
              app["CFBundleIdentifier"] as? String == "com.apple.systempreferences" else {
            throw SystemSettingsNavigationError.unavailable
        }
        guard let pane else { return .init(applicationURL: applicationURL, paneURL: nil) }
        let types = app["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let supportsPublicScheme = types.contains {
            ($0["CFBundleURLSchemes"] as? [String])?.contains("x-apple.systempreferences") == true
                && ($0["CFBundleURLIsPrivate"] as? Bool) != true
        }
        let route = SystemSettingsPaneRoute.forPane(pane)
        let extensionURL = extensionsURL.appending(component: route.extensionName, directoryHint: .isDirectory)
        guard supportsPublicScheme, isRegularDirectory(extensionsURL), isRegularDirectory(extensionURL),
              let metadata = readMetadata(extensionURL.appending(path: "Contents/Info.plist")),
              metadata["CFBundleIdentifier"] as? String == route.bundleIdentifier,
              let url = route.url else {
            return .init(applicationURL: applicationURL, paneURL: nil)
        }
        try Task.checkCancellation()
        return .init(applicationURL: applicationURL, paneURL: url)
    }

    private func isRegularDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func readMetadata(_ url: URL) -> [String: Any]? {
        // System-owned immutable plists are bounded before and after reading. No caller-selected
        // file or executable is accepted, and bundle code is never loaded to read metadata.
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumMetadataBytes,
              let data = try? Data(contentsOf: url), data.count <= maximumMetadataBytes,
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        return object as? [String: Any]
    }
}
