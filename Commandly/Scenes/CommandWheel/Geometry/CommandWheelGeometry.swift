import CoreGraphics
import Foundation

/// Pure presentation geometry for icon-only segment tiles.
///
/// The tile side is bounded by three independent constraints: separation from adjacent
/// axis-aligned tiles, separation from the center action, and containment inside the wheel. The
/// adjacent-tile bound uses the conservative `chord / sqrt(2)` projection so the configured
/// gutter remains positive for every start angle, not only cardinal layouts.
nonisolated struct CommandWheelSegmentLayout: Sendable, Equatable {
    static let visualGap: CGFloat = 3
    static let maximumTileSide: CGFloat = 56

    let wheelRadius: CGFloat
    let slotCount: Int
    let ringRadius: CGFloat
    let tileSide: CGFloat
    let centerDiameter: CGFloat

    init(wheelRadius: CGFloat, slotCount: Int) {
        let radius = max(CGFloat(CommandWheelLimits.minimumWheelRadius), wheelRadius)
        let count = max(1, min(CommandWheelLimits.maximumVisibleSlots, slotCount))
        let centerDiameter = min(72, max(36, radius * 0.4))
        let centerRadius = centerDiameter / 2
        let gap = Self.visualGap
        let squareRootOfTwo = CGFloat(2).squareRoot()

        let innerOuterBalance = (radius + centerRadius) / 2
        let angularCoefficient: CGFloat = count > 1
            ? squareRootOfTwo * sin(.pi / CGFloat(count))
            : .infinity
        let angularOuterBalance: CGFloat
        if angularCoefficient.isFinite {
            angularOuterBalance = (
                squareRootOfTwo * (radius - gap) + gap
            ) / (angularCoefficient + squareRootOfTwo)
        } else {
            angularOuterBalance = innerOuterBalance
        }

        let preferredRingRadius = radius * 0.66
        let preferredLimit = Self.tileLimit(
            ringRadius: preferredRingRadius,
            wheelRadius: radius,
            centerRadius: centerRadius,
            angularCoefficient: angularCoefficient
        )
        let optimizedRingRadius = max(innerOuterBalance, angularOuterBalance)
        let resolvedRingRadius = preferredLimit >= Self.maximumTileSide
            ? preferredRingRadius : optimizedRingRadius
        let tileSide = min(
            Self.maximumTileSide,
            Self.tileLimit(
                ringRadius: resolvedRingRadius,
                wheelRadius: radius,
                centerRadius: centerRadius,
                angularCoefficient: angularCoefficient
            )
        )

        self.wheelRadius = radius
        self.slotCount = count
        self.ringRadius = resolvedRingRadius
        self.tileSide = max(1, tileSide)
        self.centerDiameter = centerDiameter
    }

    var primaryIconSize: CGFloat {
        guard showsAuxiliaryBadges else { return max(9, tileSide * 0.54) }
        return min(28, tileSide - 2 * (badgeSize + badgeInset + 1))
    }

    var badgeSize: CGFloat {
        showsAuxiliaryBadges ? min(14, tileSide * 0.23) : 0
    }

    var badgeInset: CGFloat {
        showsAuxiliaryBadges ? max(1.5, tileSide * 0.045) : 0
    }

    var showsAuxiliaryBadges: Bool {
        tileSide >= 36
    }

    var showsKeyboardHint: Bool {
        tileSide >= 48
    }

    var cornerRadius: CGFloat {
        min(12, tileSide * 0.24)
    }

    func offset(slotIndex: Int, startAngleDegrees: Double) -> CGSize {
        guard (0 ..< slotCount).contains(slotIndex) else { return .zero }
        let angle = CommandWheelGeometry.normalizedDegrees(
            startAngleDegrees + Double(slotIndex) * 360 / Double(slotCount)
        )
        let radians = angle * .pi / 180
        return CGSize(
            width: CGFloat(sin(radians)) * ringRadius,
            height: -CGFloat(cos(radians)) * ringRadius
        )
    }

    func tileFrame(slotIndex: Int, startAngleDegrees: Double) -> CGRect {
        let offset = offset(slotIndex: slotIndex, startAngleDegrees: startAngleDegrees)
        return CGRect(
            x: offset.width - tileSide / 2,
            y: offset.height - tileSide / 2,
            width: tileSide,
            height: tileSide
        )
    }

    private static func tileLimit(
        ringRadius: CGFloat,
        wheelRadius: CGFloat,
        centerRadius: CGFloat,
        angularCoefficient: CGFloat
    ) -> CGFloat {
        let squareRootOfTwo = CGFloat(2).squareRoot()
        let angularLimit = angularCoefficient.isFinite
            ? angularCoefficient * ringRadius - visualGap
            : .infinity
        let centerLimit = squareRootOfTwo * (
            ringRadius - centerRadius - visualGap
        )
        let outerLimit = squareRootOfTwo * (
            wheelRadius - ringRadius - visualGap
        )
        return max(1, min(angularLimit, centerLimit, outerLimit))
    }
}

/// Pure radial geometry for Command Wheel.
///
/// All points use AppKit's global display convention: the origin is in the lower-left of the
/// primary display coordinate space, positive x points right, and positive y points up. Slot zero
/// is centered at the top of the wheel. Slot indices then increase clockwise. Callers must pass the
/// wheel's *actual, edge-clamped* center rather than its originally requested cursor position.
nonisolated struct CommandWheelGeometry: Sendable, Equatable {
    let slotCount: Int
    let startAngleDegrees: Double
    let deadZoneRadius: Double
    let selectionRadius: Double
    let submenuActivationRadius: Double

    init(
        slotCount: Int,
        startAngleDegrees: Double = 0,
        deadZoneRadius: Double,
        selectionRadius: Double,
        submenuActivationRadius: Double
    ) {
        self.slotCount = max(0, slotCount)
        self.startAngleDegrees = Self.normalizedDegrees(startAngleDegrees)
        self.deadZoneRadius = max(0, deadZoneRadius)
        self.selectionRadius = max(self.deadZoneRadius, selectionRadius)
        self.submenuActivationRadius = max(self.selectionRadius, submenuActivationRadius)
    }

    init(
        interaction: CommandWheelInteractionConfiguration,
        startAngleDegrees: Double
    ) {
        self.init(
            slotCount: interaction.visibleSlotCount,
            startAngleDegrees: startAngleDegrees,
            deadZoneRadius: interaction.deadZoneRadius,
            selectionRadius: interaction.selectionRadius,
            submenuActivationRadius: interaction.submenuActivationRadius
        )
    }

    var degreesPerSlot: Double {
        guard slotCount > 0 else { return 0 }
        return 360 / Double(slotCount)
    }

    /// Normalizes an angle into the half-open range `0 ..< 360`.
    static func normalizedDegrees(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    /// Normalizes an angle into the half-open range `0 ..< 2π`.
    static func normalizedRadians(_ radians: Double) -> Double {
        guard radians.isFinite else { return 0 }
        let fullTurn = 2 * Double.pi
        let remainder = radians.truncatingRemainder(dividingBy: fullTurn)
        return remainder >= 0 ? remainder : remainder + fullTurn
    }

    /// Returns the clockwise angle from the configured slot-zero center.
    func clockwiseAngleDegrees(from center: CGPoint, to point: CGPoint) -> Double {
        let deltaX = Double(point.x - center.x)
        let deltaY = Double(point.y - center.y)
        // atan2(x, y) intentionally swaps the conventional arguments: zero is up and positive
        // angles advance clockwise in AppKit's y-up global coordinate space.
        let clockwiseFromTop = atan2(deltaX, deltaY) * 180 / Double.pi
        return Self.normalizedDegrees(clockwiseFromTop - startAngleDegrees)
    }

    func distance(from center: CGPoint, to point: CGPoint) -> Double {
        hypot(Double(point.x - center.x), Double(point.y - center.y))
    }

    /// Returns the nearest slot. An exact clockwise boundary belongs to the following slot.
    func slotIndex(forClockwiseAngleDegrees angle: Double) -> Int? {
        guard slotCount > 0 else { return nil }
        let shifted = Self.normalizedDegrees(angle) + degreesPerSlot / 2
        return Int(floor(shifted / degreesPerSlot)) % slotCount
    }

    func slotIndex(from center: CGPoint, to point: CGPoint) -> Int? {
        slotIndex(forClockwiseAngleDegrees: clockwiseAngleDegrees(from: center, to: point))
    }

    func slotCenterAngleDegrees(_ slotIndex: Int) -> Double? {
        guard slotCount > 0, slotIndex >= 0, slotIndex < slotCount else { return nil }
        return Self.normalizedDegrees(Double(slotIndex) * degreesPerSlot)
    }

    func radialRegion(distance: Double) -> CommandWheelRadialRegion {
        if distance < deadZoneRadius {
            return .deadZone
        }
        if distance < selectionRadius {
            return .neutral
        }
        if distance < submenuActivationRadius {
            return .selection
        }
        return .submenuActivation
    }

    func hitTest(
        pointerLocation: CGPoint,
        center: CGPoint,
        selectableSlotIndices: Set<Int>
    ) -> CommandWheelHitTest {
        let distance = distance(from: center, to: pointerLocation)
        let angle = clockwiseAngleDegrees(from: center, to: pointerLocation)
        let region = radialRegion(distance: distance)

        guard region == .selection || region == .submenuActivation,
              let slotIndex = slotIndex(forClockwiseAngleDegrees: angle) else {
            return CommandWheelHitTest(
                pointerLocation: pointerLocation,
                distance: distance,
                clockwiseAngleDegrees: angle,
                region: region,
                target: .none
            )
        }

        let target: CommandWheelHitTarget = selectableSlotIndices.contains(slotIndex)
            ? .selectableSlot(slotIndex)
            : .emptySlot(slotIndex)
        return CommandWheelHitTest(
            pointerLocation: pointerLocation,
            distance: distance,
            clockwiseAngleDegrees: angle,
            region: region,
            target: target
        )
    }

    static func shortestAngularDistanceDegrees(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(normalizedDegrees(lhs) - normalizedDegrees(rhs))
        return min(difference, 360 - difference)
    }
}

nonisolated enum CommandWheelRadialRegion: Sendable, Equatable {
    case deadZone
    case neutral
    case selection
    case submenuActivation
}

nonisolated enum CommandWheelHitTarget: Sendable, Equatable {
    case none
    case selectableSlot(Int)
    case emptySlot(Int)
}

nonisolated struct CommandWheelHitTest: Sendable, Equatable {
    let pointerLocation: CGPoint
    let distance: Double
    let clockwiseAngleDegrees: Double
    let region: CommandWheelRadialRegion
    let target: CommandWheelHitTarget

    static func == (lhs: CommandWheelHitTest, rhs: CommandWheelHitTest) -> Bool {
        lhs.pointerLocation.x == rhs.pointerLocation.x
            && lhs.pointerLocation.y == rhs.pointerLocation.y
            && lhs.distance == rhs.distance
            && lhs.clockwiseAngleDegrees == rhs.clockwiseAngleDegrees
            && lhs.region == rhs.region
            && lhs.target == rhs.target
    }
}

nonisolated struct CommandWheelSelection: Sendable, Equatable {
    let slotIndex: Int
    let pointerLocation: CGPoint
    let distance: Double
    let clockwiseAngleDegrees: Double
    let reachedSubmenuActivationRadius: Bool

    init(slotIndex: Int, hitTest: CommandWheelHitTest) {
        self.slotIndex = slotIndex
        self.pointerLocation = hitTest.pointerLocation
        self.distance = hitTest.distance
        self.clockwiseAngleDegrees = hitTest.clockwiseAngleDegrees
        self.reachedSubmenuActivationRadius = hitTest.region == .submenuActivation
    }

    static func == (lhs: CommandWheelSelection, rhs: CommandWheelSelection) -> Bool {
        lhs.slotIndex == rhs.slotIndex
            && lhs.pointerLocation.x == rhs.pointerLocation.x
            && lhs.pointerLocation.y == rhs.pointerLocation.y
            && lhs.distance == rhs.distance
            && lhs.clockwiseAngleDegrees == rhs.clockwiseAngleDegrees
            && lhs.reachedSubmenuActivationRadius == rhs.reachedSubmenuActivationRadius
    }
}
