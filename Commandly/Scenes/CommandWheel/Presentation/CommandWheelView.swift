import CommandKit
import DesignSystem
import SwiftUI

/// An original compact radial arrangement of coherent command petals around one center action.
/// Decorative material and guides are hidden from accessibility; each segment is one element.
struct CommandWheelView: View {
    @Bindable var model: CommandWheelPresentationModel
    var onActivateSlot: (Int) -> Void
    var onActivateCenter: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            wheelSurface
                .accessibilityHidden(true)

            slotPetals
                .accessibilityHidden(true)
                .allowsHitTesting(false)

            ForEach(0 ..< model.interaction.visibleSlotCount, id: \.self) { slotIndex in
                if let segment = model.segment(at: slotIndex) {
                    segmentButton(segment)
                        .offset(offset(for: slotIndex))
                }
            }

            centerButton
        }
        .frame(width: model.contentSize.width, height: model.contentSize.height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(wheelAccessibilityLabel)
        .accessibilityValue(accessibilityEnvironmentSummary)
        .accessibilityIdentifier("command-wheel")
        .scaleEffect(presentationScale)
        .opacity(presentationOpacity)
        .animation(presentationAnimation, value: model.visualPhase)
        .animation(selectionAnimation, value: model.selectedSlotIndex)
        .animation(pageAnimation, value: model.pageID)
    }

    @ViewBuilder
    private var wheelSurface: some View {
        let diameter = CGFloat(model.appearance.wheelRadius) * 2
        if usesReducedTransparency {
            Circle()
                .fill(SemanticColors.color(for: .background))
                .frame(width: diameter, height: diameter)
                .overlay(surfaceStroke)
        } else {
            Circle()
                .fill(.regularMaterial)
                .frame(width: diameter, height: diameter)
                .overlay(surfaceStroke)
        }
    }

    private var surfaceStroke: some View {
        Circle()
            .strokeBorder(
                SemanticColors.color(for: .primaryText)
                    .opacity(usesIncreasedContrast ? 0.42 : 0.15),
                lineWidth: usesIncreasedContrast ? 2 : 1
            )
    }

    private var slotPetals: some View {
        ZStack {
            ForEach(0 ..< model.interaction.visibleSlotCount, id: \.self) { slotIndex in
                let selected = model.selectedSlotIndex == slotIndex
                CommandWheelPetalShape(
                    slotIndex: slotIndex,
                    slotCount: model.interaction.visibleSlotCount,
                    startAngleDegrees: model.appearance.startAngleDegrees,
                    innerRadius: Double(segmentLayout.centerDiameter / 2 + 4),
                    outerRadius: max(
                        Double(segmentLayout.centerDiameter / 2 + 5),
                        model.appearance.wheelRadius - 7
                    ),
                    angularInsetDegrees: 1.5
                )
                .fill(
                    selected
                        ? SemanticColors.color(for: .accent).opacity(0.16)
                        : SemanticColors.color(for: .secondaryBackground).opacity(0.2)
                )
                .overlay {
                    CommandWheelPetalShape(
                        slotIndex: slotIndex,
                        slotCount: model.interaction.visibleSlotCount,
                        startAngleDegrees: model.appearance.startAngleDegrees,
                        innerRadius: Double(segmentLayout.centerDiameter / 2 + 4),
                        outerRadius: max(
                            Double(segmentLayout.centerDiameter / 2 + 5),
                            model.appearance.wheelRadius - 7
                        ),
                        angularInsetDegrees: 1.5
                    )
                    .stroke(
                        selected
                            ? SemanticColors.color(for: .accent).opacity(0.6)
                            : SemanticColors.color(for: .primaryText).opacity(
                                usesIncreasedContrast ? 0.28 : 0.09
                            ),
                        lineWidth: selected || usesIncreasedContrast ? 1.5 : 1
                    )
                }
            }
        }
        .frame(
            width: CGFloat(model.appearance.wheelRadius) * 2,
            height: CGFloat(model.appearance.wheelRadius) * 2
        )
    }

    private func segmentButton(_ segment: CommandWheelPresentedSegment) -> some View {
        let selected = model.selectedSlotIndex == segment.slotIndex
        let pressed = model.pressedSlotIndex == segment.slotIndex
        return Button {
            onActivateSlot(segment.slotIndex)
        } label: {
            CommandWheelSegmentLabel(
                segment: segment,
                selected: selected,
                pressed: pressed,
                keyboardHint: keyboardHint(for: segment.slotIndex),
                increasedContrast: usesIncreasedContrast,
                layout: segmentLayout
            )
        }
        .buttonStyle(.plain)
        .disabled(segment.isSelectable == false)
        .scaleEffect(pressed ? 0.96 : (selected && usesReducedMotion == false ? 1.04 : 1))
        .opacity(segment.state == .empty ? 0.42 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segment.accessibilityLabel)
        .accessibilityValue(segment.accessibilityValue(isSelected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(segment.accessibilityHint)
        .accessibilityIdentifier(segment.accessibilityIdentifier)
    }

    private var centerButton: some View {
        Button(action: onActivateCenter) {
            VStack(spacing: Spacing.xxs.rawValue) {
                Image(systemName: model.centerAction.systemImage)
                    .font(.system(
                        size: min(15, segmentLayout.centerDiameter * 0.34),
                        weight: .semibold
                    ))
                if segmentLayout.centerDiameter >= 52 {
                    Text(model.centerAction.title)
                        .font(.caption.weight(.medium))
                }
            }
            .foregroundStyle(SemanticColors.color(for: .primaryText))
            .frame(
                width: segmentLayout.centerDiameter,
                height: segmentLayout.centerDiameter
            )
            .background(.thinMaterial, in: Circle())
            .overlay(
                Circle().strokeBorder(
                    SemanticColors.color(for: .primaryText)
                        .opacity(usesIncreasedContrast ? 0.5 : 0.2),
                    lineWidth: usesIncreasedContrast ? 2 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Center, \(model.centerAction.title)")
        .accessibilityHint(
            model.centerAction == .back
                ? "Returns to the parent wheel."
                : "Closes the wheel without running a command."
        )
        .accessibilityIdentifier("command-wheel.center")
    }

    private func offset(for slotIndex: Int) -> CGSize {
        segmentLayout.offset(
            slotIndex: slotIndex,
            startAngleDegrees: model.appearance.startAngleDegrees
        )
    }

    private func keyboardHint(for slotIndex: Int) -> String? {
        guard model.appearance.showsKeyboardHints,
              model.interaction.allowsKeyboardSelection,
              segmentLayout.showsKeyboardHint,
              slotIndex < 9 else {
            return nil
        }
        return String(slotIndex + 1)
    }

    private var selectionAnimation: Animation? {
        switch model.appearance.animationPreference {
        case .disabled:
            return nil
        case .reduced:
            return .easeOut(duration: MotionDuration.fast.rawValue)
        case .system:
            return usesReducedMotion
                ? .easeOut(duration: MotionDuration.fast.rawValue)
                : CommandlyMotion.hover
        }
    }

    private var pageAnimation: Animation? {
        guard usesReducedMotion == false else {
            return .easeOut(duration: MotionDuration.fast.rawValue)
        }
        switch model.appearance.animationPreference {
        case .disabled:
            return nil
        case .reduced:
            return .easeOut(duration: MotionDuration.fast.rawValue)
        case .system:
            return CommandlyMotion.navigation
        }
    }

    private var presentationAnimation: Animation? {
        switch model.appearance.animationPreference {
        case .disabled:
            return nil
        case .reduced:
            return .easeOut(duration: MotionDuration.fast.rawValue)
        case .system:
            return usesReducedMotion
                ? .easeOut(duration: MotionDuration.fast.rawValue)
                : .easeOut(duration: MotionDuration.normal.rawValue)
        }
    }

    private var presentationScale: CGFloat {
        guard model.appearance.animationPreference != .disabled,
              usesReducedMotion == false else {
            return 1
        }
        switch model.visualPhase {
        case .appearing: return 0.94
        case .visible: return 1
        case .dismissing: return 0.97
        }
    }

    private var presentationOpacity: Double {
        guard model.appearance.animationPreference != .disabled else { return 1 }
        return model.visualPhase == .visible ? 1 : 0
    }

    private var accessibilityEnvironmentSummary: String {
        let appearance = colorScheme == .dark ? "dark appearance" : "light appearance"
        let motion = usesReducedMotion ? "reduced motion" : "standard motion"
        let contrast = usesIncreasedContrast ? "increased contrast" : "standard contrast"
        return "\(appearance), \(motion), \(contrast)"
    }

    private var wheelAccessibilityLabel: String {
        let base = "Command Wheel, \(model.profileName), \(model.pageName)"
        #if DEBUG
        if CommandWheelDebugFixture.isWheelPresentationRequested {
            return "\(base), \(accessibilityEnvironmentSummary)"
        }
        #endif
        return base
    }

    private var usesReducedMotion: Bool {
        #if DEBUG
        reduceMotion || CommandWheelDebugFixture.forcesReducedMotion
        #else
        reduceMotion
        #endif
    }

    private var usesReducedTransparency: Bool {
        reduceTransparency
    }

    private var usesIncreasedContrast: Bool {
        #if DEBUG
        contrast == .increased || CommandWheelDebugFixture.forcesIncreasedContrast
        #else
        contrast == .increased
        #endif
    }

    private var segmentLayout: CommandWheelSegmentLayout {
        CommandWheelSegmentLayout(
            wheelRadius: CGFloat(model.appearance.wheelRadius),
            slotCount: model.interaction.visibleSlotCount
        )
    }
}

/// Annular slot with a small angular gutter. It is decorative—the corresponding Button remains
/// the single semantic and interactive element for accessibility and click selection.
private nonisolated struct CommandWheelPetalShape: Shape {
    let slotIndex: Int
    let slotCount: Int
    let startAngleDegrees: Double
    let innerRadius: Double
    let outerRadius: Double
    let angularInsetDegrees: Double

    func path(in rect: CGRect) -> Path {
        guard slotCount > 0, slotIndex >= 0, slotIndex < slotCount else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let halfSlot = 180 / Double(slotCount)
        let centerAngle = startAngleDegrees + Double(slotIndex) * 360 / Double(slotCount)
        let startAngle = centerAngle - halfSlot + angularInsetDegrees
        let endAngle = centerAngle + halfSlot - angularInsetDegrees
        let inner = max(0, innerRadius)
        let outer = max(inner, outerRadius)
        let steps = max(4, Int(ceil((endAngle - startAngle) / 8)))

        var path = Path()
        for step in 0 ... steps {
            let fraction = Double(step) / Double(steps)
            let angle = startAngle + (endAngle - startAngle) * fraction
            let point = Self.point(center: center, radius: outer, angleDegrees: angle)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        for step in (0 ... steps).reversed() {
            let fraction = Double(step) / Double(steps)
            let angle = startAngle + (endAngle - startAngle) * fraction
            path.addLine(to: Self.point(center: center, radius: inner, angleDegrees: angle))
        }
        path.closeSubpath()
        return path
    }

    private static func point(
        center: CGPoint,
        radius: Double,
        angleDegrees: Double
    ) -> CGPoint {
        let radians = angleDegrees * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(sin(radians) * radius),
            y: center.y - CGFloat(cos(radians) * radius)
        )
    }
}

private struct CommandWheelSegmentLabel: View {
    let segment: CommandWheelPresentedSegment
    let selected: Bool
    let pressed: Bool
    let keyboardHint: String?
    let increasedContrast: Bool
    let layout: CommandWheelSegmentLayout

    var body: some View {
        ZStack {
            segmentIcon
        }
        .frame(width: layout.tileSide, height: layout.tileSide)
        .background(
            backgroundColor,
            in: RoundedRectangle(cornerRadius: layout.cornerRadius)
        )
        .overlay(alignment: .topTrailing) {
            if layout.showsAuxiliaryBadges, case .submenu = segment.kind {
                Image(systemName: "chevron.forward.circle.fill")
                    .font(.system(size: layout.badgeSize, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: layout.badgeSize, height: layout.badgeSize)
                    .padding(layout.badgeInset)
            }
        }
        .overlay(alignment: .topLeading) {
            if layout.showsKeyboardHint, let keyboardHint {
                Text(keyboardHint)
                    .font(.system(
                        size: max(6, layout.badgeSize * 0.64),
                        weight: .bold,
                        design: .monospaced
                    ))
                    .foregroundStyle(SemanticColors.color(for: .secondaryText))
                    .frame(width: layout.badgeSize, height: layout.badgeSize)
                    .background(.thinMaterial, in: Circle())
                    .padding(layout.badgeInset)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if layout.showsAuxiliaryBadges, let stateSymbol {
                Image(systemName: stateSymbol)
                    .font(.system(size: layout.badgeSize, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: layout.badgeSize, height: layout.badgeSize)
                    .padding(layout.badgeInset)
            }
        }
        .foregroundStyle(foregroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: layout.cornerRadius)
                .strokeBorder(strokeColor, lineWidth: selected || increasedContrast ? 2 : 1)
        )
    }

    @ViewBuilder
    private var segmentIcon: some View {
        if segment.usesCustomIcon == false, let path = segment.applicationIconPath {
            ApplicationLauncherIcon(path: path, size: layout.primaryIconSize)
        } else if segment.state == .loading {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(max(0.55, layout.primaryIconSize / 16))
                .frame(width: layout.primaryIconSize, height: layout.primaryIconSize)
        } else {
            Image(systemName: segment.systemImage)
                .font(.system(size: layout.primaryIconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var stateSymbol: String? {
        switch segment.state {
        case .available, .empty, .loading: return nil
        case .unavailable: return "slash.circle.fill"
        case .missing: return "questionmark.diamond.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var foregroundColor: Color {
        switch segment.state {
        case .missing, .error:
            return SemanticColors.color(for: .danger)
        case .unavailable, .empty, .loading:
            return SemanticColors.color(for: .secondaryText)
        case .available:
            return SemanticColors.color(for: .primaryText)
        }
    }

    private var backgroundColor: Color {
        if selected {
            return SemanticColors.color(for: .accent).opacity(pressed ? 0.34 : 0.22)
        }
        return SemanticColors.color(for: .secondaryBackground).opacity(0.78)
    }

    private var strokeColor: Color {
        if selected { return SemanticColors.color(for: .accent) }
        if increasedContrast { return SemanticColors.color(for: .primaryText).opacity(0.5) }
        return SemanticColors.color(for: .primaryText).opacity(0.15)
    }
}

#if DEBUG
@MainActor
enum CommandWheelPreviewFactory {
    static func makeModel() -> CommandWheelPresentationModel {
        let profile = CommandWheelDefaults.defaultProfile
        let page = profile.pages[0]
        let titles = ["Files", "Copy", "Notes", "Share", "Settings", "Timers", "Tools", "More"]
        let icons = ["doc.text.magnifyingglass", "doc.on.doc", "note.text", "square.and.arrow.up", "gearshape", "timer", "wrench.and.screwdriver", "ellipsis"]
        let segments = (0 ..< profile.interaction.visibleSlotCount).map { slot in
            CommandWheelPresentedSegment(
                sourceSegmentID: page.segments[slot].id,
                pageID: page.id,
                slotIndex: slot,
                kind: slot == 7 ? .submenu(pageID: UUID()) : .command(
                    CommandReference(commandID: CommandID(rawValue: "preview.\(slot)"))
                ),
                state: slot == 5 ? .unavailable(.temporarilyUnavailable) : .available,
                title: titles[slot],
                subtitle: nil,
                systemImage: icons[slot],
                isDynamic: false
            )
        }
        return CommandWheelPresentationModel(
            profileID: profile.id,
            profileName: profile.name,
            pageID: page.id,
            pageName: page.name,
            appearance: profile.appearance,
            interaction: profile.interaction,
            segments: segments
        )
    }
}

#Preview("Command Wheel") {
    CommandWheelView(
        model: CommandWheelPreviewFactory.makeModel(),
        onActivateSlot: { _ in },
        onActivateCenter: {}
    )
    .frame(width: 500, height: 500)
}
#endif
