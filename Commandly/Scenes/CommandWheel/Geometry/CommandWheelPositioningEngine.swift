import CoreGraphics
import Foundation

/// Immutable display geometry captured for one Command Wheel invocation.
///
/// `identifier` only needs to remain stable for the current process/session. Persisted placements
/// may prefer it, but positioning always has deterministic fallbacks when that display is absent.
nonisolated struct CommandWheelDisplaySnapshot: Sendable, Equatable {
    let identifier: String
    let frame: CGRect
    let visibleFrame: CGRect
    let scale: Double

    init(identifier: String, frame: CGRect, visibleFrame: CGRect, scale: Double) {
        self.identifier = identifier
        self.frame = frame.standardized
        self.visibleFrame = visibleFrame.standardized
        self.scale = scale
    }

    var usableFrame: CGRect {
        visibleFrame.isEmpty ? frame : visibleFrame
    }

    var isUsable: Bool {
        identifier.isEmpty == false
            && frame.isNull == false
            && frame.isInfinite == false
            && frame.width > 0
            && frame.height > 0
            && scale.isFinite
            && scale > 0
    }

    static func == (lhs: CommandWheelDisplaySnapshot, rhs: CommandWheelDisplaySnapshot) -> Bool {
        lhs.identifier == rhs.identifier
            && equal(lhs.frame, rhs.frame)
            && equal(lhs.visibleFrame, rhs.visibleFrame)
            && lhs.scale == rhs.scale
    }

    private static func equal(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        lhs.origin.x == rhs.origin.x
            && lhs.origin.y == rhs.origin.y
            && lhs.size.width == rhs.size.width
            && lhs.size.height == rhs.size.height
    }
}

nonisolated struct CommandWheelPosition: Sendable, Equatable {
    let display: CommandWheelDisplaySnapshot
    let requestedCenter: CGPoint
    let actualCenter: CGPoint
    let contentFrame: CGRect
    let wasClamped: Bool

    static func == (lhs: CommandWheelPosition, rhs: CommandWheelPosition) -> Bool {
        lhs.display == rhs.display
            && equal(lhs.requestedCenter, rhs.requestedCenter)
            && equal(lhs.actualCenter, rhs.actualCenter)
            && equal(lhs.contentFrame, rhs.contentFrame)
            && lhs.wasClamped == rhs.wasClamped
    }

    private static func equal(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y
    }

    private static func equal(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        lhs.origin.x == rhs.origin.x
            && lhs.origin.y == rhs.origin.y
            && lhs.size.width == rhs.size.width
            && lhs.size.height == rhs.size.height
    }
}

nonisolated enum CommandWheelPositioningEngine {
    /// Resolves a point to a display without consulting `NSScreen`.
    ///
    /// Display frames use inclusive edges for candidate discovery. If a point lies on a shared
    /// boundary, the display with the closest center wins, followed by lexical identifier order.
    /// Points in a display gap use the closest frame with the same deterministic tie-break.
    static func display(
        containing point: CGPoint,
        in displays: [CommandWheelDisplaySnapshot],
        preferredIdentifier: String? = nil
    ) -> CommandWheelDisplaySnapshot? {
        let usableDisplays = displays.filter(\.isUsable)
        guard usableDisplays.isEmpty == false else { return nil }

        let boundaryCandidates = usableDisplays.filter { containsInclusively($0.frame, point: point) }
        if let preferredIdentifier,
           let preferred = boundaryCandidates.first(where: { $0.identifier == preferredIdentifier }) {
            return preferred
        }
        if boundaryCandidates.isEmpty == false {
            return boundaryCandidates.sorted { compare($0, $1, relativeTo: point) }.first
        }
        if let preferredIdentifier,
           let preferred = usableDisplays.first(where: { $0.identifier == preferredIdentifier }) {
            return preferred
        }
        return usableDisplays.sorted { compareByFrameDistance($0, $1, relativeTo: point) }.first
    }

    static func position(
        placement: CommandWheelPlacement,
        pointerLocation: CGPoint,
        displays: [CommandWheelDisplaySnapshot],
        activeDisplayIdentifier: String?,
        contentSize: CGSize
    ) -> CommandWheelPosition? {
        let usableDisplays = displays.filter(\.isUsable)
        guard usableDisplays.isEmpty == false else { return nil }

        let pointerDisplay = display(containing: pointerLocation, in: usableDisplays)
        let activeDisplay = activeDisplayIdentifier.flatMap { identifier in
            usableDisplays.first { $0.identifier == identifier }
        }
        let deterministicFallback = usableDisplays.sorted(by: stableDisplayOrder).first

        let targetDisplay: CommandWheelDisplaySnapshot?
        let requestedCenter: CGPoint
        switch placement {
        case .cursor:
            targetDisplay = pointerDisplay ?? activeDisplay ?? deterministicFallback
            requestedCenter = pointerLocation

        case .activeScreenCenter:
            targetDisplay = activeDisplay ?? pointerDisplay ?? deterministicFallback
            requestedCenter = targetDisplay.map { center(of: $0.usableFrame) } ?? pointerLocation

        case .fixedNormalizedPoint(let screenIdentifier, let x, let y):
            targetDisplay = screenIdentifier.flatMap { identifier in
                usableDisplays.first { $0.identifier == identifier }
            } ?? activeDisplay ?? pointerDisplay ?? deterministicFallback
            if let targetDisplay {
                let frame = targetDisplay.usableFrame
                requestedCenter = CGPoint(
                    x: frame.minX + normalizedCoordinate(x) * frame.width,
                    y: frame.minY + normalizedCoordinate(y) * frame.height
                )
            } else {
                requestedCenter = pointerLocation
            }
        }

        guard let targetDisplay else { return nil }
        let size = sanitized(contentSize)
        let actualCenter = clampedCenter(
            requestedCenter,
            contentSize: size,
            visibleFrame: targetDisplay.usableFrame
        )
        let contentFrame = CGRect(
            x: actualCenter.x - size.width / 2,
            y: actualCenter.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        return CommandWheelPosition(
            display: targetDisplay,
            requestedCenter: requestedCenter,
            actualCenter: actualCenter,
            contentFrame: contentFrame,
            wasClamped: actualCenter != requestedCenter
        )
    }

    static func clampedCenter(
        _ requestedCenter: CGPoint,
        contentSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let frame = visibleFrame.standardized
        let size = sanitized(contentSize)
        return CGPoint(
            x: clampedAxis(
                requestedCenter.x,
                minimum: frame.minX,
                maximum: frame.maxX,
                contentLength: size.width
            ),
            y: clampedAxis(
                requestedCenter.y,
                minimum: frame.minY,
                maximum: frame.maxY,
                contentLength: size.height
            )
        )
    }

    private static func clampedAxis(
        _ requested: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat,
        contentLength: CGFloat
    ) -> CGFloat {
        let half = contentLength / 2
        let lower = minimum + half
        let upper = maximum - half
        guard lower <= upper else {
            // Preserve segment/content size on an undersized display and center the overflow.
            return minimum + (maximum - minimum) / 2
        }
        return min(max(requested, lower), upper)
    }

    private static func sanitized(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width.isFinite ? max(0, size.width) : 0,
            height: size.height.isFinite ? max(0, size.height) : 0
        )
    }

    private static func normalizedCoordinate(_ value: Double) -> CGFloat {
        guard value.isFinite else { return 0.5 }
        return CGFloat(min(max(value, 0), 1))
    }

    private static func center(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    private static func containsInclusively(_ frame: CGRect, point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }

    private static func compare(
        _ lhs: CommandWheelDisplaySnapshot,
        _ rhs: CommandWheelDisplaySnapshot,
        relativeTo point: CGPoint
    ) -> Bool {
        let lhsDistance = squaredDistance(point, center(of: lhs.frame))
        let rhsDistance = squaredDistance(point, center(of: rhs.frame))
        if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
        return stableDisplayOrder(lhs, rhs)
    }

    private static func compareByFrameDistance(
        _ lhs: CommandWheelDisplaySnapshot,
        _ rhs: CommandWheelDisplaySnapshot,
        relativeTo point: CGPoint
    ) -> Bool {
        let lhsDistance = squaredDistanceToFrame(point, frame: lhs.frame)
        let rhsDistance = squaredDistanceToFrame(point, frame: rhs.frame)
        if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
        return compare(lhs, rhs, relativeTo: point)
    }

    private static func stableDisplayOrder(
        _ lhs: CommandWheelDisplaySnapshot,
        _ rhs: CommandWheelDisplaySnapshot
    ) -> Bool {
        if lhs.identifier != rhs.identifier { return lhs.identifier < rhs.identifier }
        if lhs.frame.minX != rhs.frame.minX { return lhs.frame.minX < rhs.frame.minX }
        if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
        if lhs.frame.width != rhs.frame.width { return lhs.frame.width < rhs.frame.width }
        return lhs.frame.height < rhs.frame.height
    }

    private static func squaredDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        let x = Double(lhs.x - rhs.x)
        let y = Double(lhs.y - rhs.y)
        return x * x + y * y
    }

    private static func squaredDistanceToFrame(_ point: CGPoint, frame: CGRect) -> Double {
        let xDistance: CGFloat
        if point.x < frame.minX {
            xDistance = frame.minX - point.x
        } else if point.x > frame.maxX {
            xDistance = point.x - frame.maxX
        } else {
            xDistance = 0
        }

        let yDistance: CGFloat
        if point.y < frame.minY {
            yDistance = frame.minY - point.y
        } else if point.y > frame.maxY {
            yDistance = point.y - frame.maxY
        } else {
            yDistance = 0
        }
        return Double(xDistance * xDistance + yDistance * yDistance)
    }
}
