import Foundation
import SecurityKit
import Infrastructure

/// A permission row shown during onboarding.
enum OnboardingPermissionItem: String, CaseIterable, Identifiable, Sendable {
    case calendarAndContacts
    case filesAndFolders
    case accessibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendarAndContacts:
            return "Calendar and Contacts"
        case .filesAndFolders:
            return "Files and Folders"
        case .accessibility:
            return "Accessibility"
        }
    }

    var subtitle: String {
        switch self {
        case .calendarAndContacts:
            return "Check upcoming meetings and find people without leaving the keyboard."
        case .filesAndFolders:
            return "Search documents and folders you explicitly allow Commandly to use."
        case .accessibility:
            return "Enable window layouts and deeper keyboard automation when you need them."
        }
    }

    var systemImage: String {
        switch self {
        case .calendarAndContacts:
            return "calendar"
        case .filesAndFolders:
            return "folder.fill"
        case .accessibility:
            return "accessibility"
        }
    }

    var permissionKinds: [PermissionKind] {
        switch self {
        case .calendarAndContacts:
            return [.calendar, .contacts]
        case .filesAndFolders:
            return [.files]
        case .accessibility:
            return [.accessibility]
        }
    }

    var recoveryPane: PrivacySettingsPane {
        switch self {
        case .calendarAndContacts:
            return .calendars
        case .filesAndFolders:
            return .filesAndFolders
        case .accessibility:
            return .accessibility
        }
    }
}

/// Aggregated UI state for an onboarding permission row.
struct OnboardingPermissionStatus: Equatable, Sendable {
    var state: PermissionState
    var isRequesting: Bool

    static let idle = OnboardingPermissionStatus(state: .notDetermined, isRequesting: false)

    var actionTitle: String {
        switch state {
        case .authorized:
            return "Granted"
        case .denied, .restricted:
            return "Open Settings"
        case .notDetermined:
            return "Grant Access"
        }
    }

    var showsActionAsEnabled: Bool {
        state != .authorized && !isRequesting
    }
}
