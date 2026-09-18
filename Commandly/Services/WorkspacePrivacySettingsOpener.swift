import AppKit
import Foundation
import Infrastructure

/// Opens System Settings privacy panes via documented preference URLs.
struct WorkspacePrivacySettingsOpener: PrivacySettingsOpening, Sendable {
    init() {}

    func open(_ pane: PrivacySettingsPane) async {
        guard let url = Self.url(for: pane) else { return }
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }

    static func url(for pane: PrivacySettingsPane) -> URL? {
        let urlString: String
        switch pane {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .calendars:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .camera:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case .contacts:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
        case .filesAndFolders:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }

        return URL(string: urlString)
    }
}
