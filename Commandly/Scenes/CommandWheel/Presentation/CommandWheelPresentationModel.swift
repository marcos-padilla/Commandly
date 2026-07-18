import CommandKit
import CoreGraphics
import Foundation
import Observation

nonisolated enum CommandWheelPresentedSegmentKind: Sendable, Equatable {
    case command(CommandReference)
    case submenu(pageID: UUID)
    case empty
}

nonisolated enum CommandWheelPresentedSegmentState: Sendable, Equatable {
    case available
    case unavailable(CommandUnavailableReason)
    case missing
    case loading
    case error
    case empty

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// Frozen visual/runtime representation of one radial slot for one invocation.
nonisolated struct CommandWheelPresentedSegment: Identifiable, Sendable, Equatable {
    let sourceSegmentID: UUID
    let pageID: UUID
    let slotIndex: Int
    let kind: CommandWheelPresentedSegmentKind
    let state: CommandWheelPresentedSegmentState
    let title: String
    let subtitle: String?
    let systemImage: String
    let isDynamic: Bool
    let usesCustomIcon: Bool
    let applicationIconPath: String?

    init(
        sourceSegmentID: UUID,
        pageID: UUID,
        slotIndex: Int,
        kind: CommandWheelPresentedSegmentKind,
        state: CommandWheelPresentedSegmentState,
        title: String,
        subtitle: String?,
        systemImage: String,
        isDynamic: Bool,
        usesCustomIcon: Bool = false,
        applicationIconPath: String? = nil
    ) {
        self.sourceSegmentID = sourceSegmentID
        self.pageID = pageID
        self.slotIndex = slotIndex
        self.kind = kind
        self.state = state
        self.title = title
        self.subtitle = subtitle
        self.systemImage = CommandWheelSystemSymbol.resolvedName(
            systemImage,
            fallback: CommandWheelSystemSymbol.guaranteedFallback
        )
        self.isDynamic = isDynamic
        self.usesCustomIcon = usesCustomIcon && CommandWheelSystemSymbol.isValid(systemImage)
        let normalizedPath = applicationIconPath?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.applicationIconPath = normalizedPath?.isEmpty == false ? normalizedPath : nil
    }

    var id: String {
        "\(sourceSegmentID.uuidString).\(slotIndex)"
    }

    var isSelectable: Bool {
        state.isAvailable && kind != .empty
    }

    var accessibilityIdentifier: String {
        "command-wheel.segment.\(id)"
    }

    var accessibilityLabel: String {
        let kindDescription: String
        switch kind {
        case .command:
            kindDescription = "command"
        case .submenu:
            kindDescription = "submenu"
        case .empty:
            kindDescription = "empty slot"
        }
        return "\(title), \(kindDescription), position \(slotIndex + 1)"
    }

    func accessibilityValue(isSelected: Bool) -> String {
        var values = [String]()
        if isSelected { values.append("selected") }
        switch state {
        case .available:
            values.append("available")
        case .unavailable(let reason):
            values.append("unavailable, \(Self.description(for: reason))")
        case .missing:
            values.append("missing command")
        case .loading:
            values.append("loading")
        case .error:
            values.append("could not load")
        case .empty:
            values.append("not assigned")
        }
        return values.joined(separator: ", ")
    }

    var accessibilityHint: String {
        guard state.isAvailable else { return "This segment cannot be activated." }
        switch kind {
        case .command:
            return "Runs this command."
        case .submenu:
            return "Opens this submenu."
        case .empty:
            return "No command is assigned."
        }
    }

    private static func description(for reason: CommandUnavailableReason) -> String {
        switch reason {
        case .disabled:
            return "disabled"
        case .missingPermission:
            return "permission required"
        case .missingDependency:
            return "dependency unavailable"
        case .invalidContext:
            return "not available in this context"
        case .temporarilyUnavailable:
            return "temporarily unavailable"
        case .unsupported:
            return "unsupported"
        }
    }
}

nonisolated enum CommandWheelCenterAction: Sendable, Equatable {
    case cancel
    case back

    var title: String {
        switch self {
        case .cancel: return "Cancel"
        case .back: return "Back"
        }
    }

    var systemImage: String {
        switch self {
        case .cancel: return "xmark"
        case .back: return "arrow.uturn.backward"
        }
    }
}

nonisolated enum CommandWheelVisualPhase: Sendable, Equatable {
    case appearing
    case visible
    case dismissing
}

/// Observable SwiftUI-facing state. Runtime content is replaced only by explicit page transitions;
/// usage-history changes never reorder this model during an invocation.
@MainActor
@Observable
final class CommandWheelPresentationModel {
    let profileID: UUID
    let profileName: String
    let appearance: CommandWheelAppearanceConfiguration
    let interaction: CommandWheelInteractionConfiguration

    private(set) var pageID: UUID
    private(set) var pageName: String
    private(set) var pageDepth: Int
    private(set) var segments: [CommandWheelPresentedSegment]
    var selectedSlotIndex: Int?
    var pressedSlotIndex: Int?
    var isTransitioning = false
    var visualPhase: CommandWheelVisualPhase = .appearing

    init(
        profileID: UUID,
        profileName: String,
        pageID: UUID,
        pageName: String,
        pageDepth: Int = 0,
        appearance: CommandWheelAppearanceConfiguration,
        interaction: CommandWheelInteractionConfiguration,
        segments: [CommandWheelPresentedSegment]
    ) {
        self.profileID = profileID
        self.profileName = profileName
        self.pageID = pageID
        self.pageName = pageName
        self.pageDepth = max(0, pageDepth)
        self.appearance = appearance
        self.interaction = interaction
        self.segments = segments.sorted { $0.slotIndex < $1.slotIndex }
    }

    var centerAction: CommandWheelCenterAction {
        pageDepth == 0 ? .cancel : .back
    }

    var contentSize: CGSize {
        let margin: CGFloat = 72
        let edge = CGFloat(max(80, appearance.wheelRadius)) * 2 + margin * 2
        return CGSize(width: edge, height: edge)
    }

    var selectableSlotIndices: Set<Int> {
        Set(segments.lazy.filter(\.isSelectable).map(\.slotIndex))
    }

    var selectedSegment: CommandWheelPresentedSegment? {
        selectedSlotIndex.flatMap(segment(at:))
    }

    func segment(at slotIndex: Int) -> CommandWheelPresentedSegment? {
        segments.first { $0.slotIndex == slotIndex }
    }

    func replacePage(
        pageID: UUID,
        pageName: String,
        pageDepth: Int,
        segments: [CommandWheelPresentedSegment]
    ) {
        self.pageID = pageID
        self.pageName = pageName
        self.pageDepth = max(0, pageDepth)
        self.segments = segments.sorted { $0.slotIndex < $1.slotIndex }
        selectedSlotIndex = nil
        pressedSlotIndex = nil
    }
}
