import AppKit
import Foundation
import Infrastructure

/// Opens System Settings privacy panes via documented preference URLs.
struct WorkspacePrivacySettingsOpener: PrivacySettingsOpening, Sendable {
    init() {}

    func open(_ pane: PrivacySettingsPane) async {
        let urlString: String
        switch pane {
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .calendars:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .contacts:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts"
        case .filesAndFolders:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        }

        guard let url = URL(string: urlString) else { return }
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }
}
