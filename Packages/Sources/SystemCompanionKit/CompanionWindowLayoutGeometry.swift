import Foundation
import Infrastructure

/// Helper-local display topology in AX top-left coordinates, collected on the main actor.
public struct CompanionLayoutDisplay: Equatable, Sendable {
    public let identifier: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect
    public init(identifier: UInt32, frame: CGRect, visibleFrame: CGRect) {
        self.identifier = identifier; self.frame = frame; self.visibleFrame = visibleFrame
    }
}

public enum CompanionWindowLayoutGeometry {
    public static func validFrame(_ frame: CGRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0 && frame.width <= 100_000 && frame.height <= 100_000
            && abs(frame.origin.x) <= 1_000_000 && abs(frame.origin.y) <= 1_000_000
    }
    public static func target(_ rect: CompanionNormalizedWindowRect, in display: CompanionLayoutDisplay) throws -> CGRect {
        guard rect.isValid, validFrame(display.frame), validFrame(display.visibleFrame),
              display.frame.contains(display.visibleFrame) else { throw CompanionWindowLayoutError.invalidGeometry }
        let visible = display.visibleFrame
        // Clamp floating-point thirds at the right/bottom edge. No integral expansion can cross that boundary.
        let minX = visible.minX + rect.x * visible.width
        let minY = visible.minY + rect.y * visible.height
        let maxX = min(visible.maxX, visible.minX + (rect.x + rect.width) * visible.width)
        let maxY = min(visible.maxY, visible.minY + (rect.y + rect.height) * visible.height)
        let target = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard validFrame(target), target.width >= 1, target.height >= 1 else { throw CompanionWindowLayoutError.invalidGeometry }
        return target
    }
    public static func display(for frame: CGRect, among displays: [CompanionLayoutDisplay]) throws -> CompanionLayoutDisplay {
        guard validFrame(frame), displays.isEmpty == false, displays.count <= 32 else { throw CompanionWindowLayoutError.displayChanged }
        var best: CompanionLayoutDisplay?
        var bestArea: CGFloat = 0
        for display in displays {
            let intersection = frame.intersection(display.frame)
            let area: CGFloat = intersection.isNull ? CGFloat.zero : intersection.width * intersection.height
            if area > bestArea || (area == bestArea && display.identifier < (best?.identifier ?? UInt32.max)) {
                best = display; bestArea = area
            }
        }
        guard let best, bestArea > 0 else { throw CompanionWindowLayoutError.displayChanged }
        return best
    }
    public static func matches(_ actual: CGRect, _ target: CGRect) -> Bool {
        validFrame(actual) && abs(actual.minX - target.minX) <= 1 && abs(actual.minY - target.minY) <= 1
            && abs(actual.width - target.width) <= 1 && abs(actual.height - target.height) <= 1
    }
}
