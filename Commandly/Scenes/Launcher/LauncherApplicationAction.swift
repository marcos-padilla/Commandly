import Foundation
import CommandKit

/// A single row in the application actions panel.
struct LauncherApplicationAction: Identifiable, Sendable, Equatable, Hashable {
    let id: CommandActionID
    let title: String
    let systemImage: String
    let keyHint: CommandKeyHint?
    let isDestructive: Bool
    let section: Section

    enum Section: Int, Sendable, Equatable, Hashable, Comparable {
        case primary
        case finder
        case clipboard
        case manage
        case ranking

        static func < (lhs: Section, rhs: Section) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    var descriptor: CommandActionDescriptor {
        CommandActionDescriptor(
            id: id,
            title: title,
            isPrimary: section == .primary,
            keyHint: keyHint,
            isEnabled: true
        )
    }
}
