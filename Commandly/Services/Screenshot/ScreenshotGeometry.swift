import CoreGraphics
import Foundation
import Infrastructure

/// Pure coordinate and pixel sizing rules, independent of NSScreen or capture access.
nonisolated enum ScreenshotGeometry {
    static func outputSize(points: CGSize, scale: CGFloat) throws -> (width: Int, height: Int) {
        guard points.width.isFinite, points.height.isFinite, scale.isFinite,
              points.width > 0, points.height > 0, points.width <= 65_536, points.height <= 65_536,
              scale >= 0.5, scale <= 8 else { throw ScreenshotCaptureError.selectionInvalid }
        let rawWidth = points.width * scale
        let rawHeight = points.height * scale
        let reduction = min(1, 8_192 / max(rawWidth, rawHeight), sqrt(40_000_000 / (rawWidth * rawHeight)))
        return (max(1, Int((rawWidth * reduction).rounded(.down))), max(1, Int((rawHeight * reduction).rounded(.down))))
    }

    static func rectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// AppKit uses bottom-left coordinates; screenshot APIs use a top-left primary display origin.
    static func captureRect(appKitRect: CGRect, primaryDisplayTop: CGFloat) throws -> CGRect {
        guard appKitRect.origin.x.isFinite, appKitRect.origin.y.isFinite, primaryDisplayTop.isFinite,
              appKitRect.width.isFinite, appKitRect.height.isFinite,
              appKitRect.width >= 2, appKitRect.height >= 2 else { throw ScreenshotCaptureError.selectionInvalid }
        return CGRect(x: appKitRect.minX, y: primaryDisplayTop - appKitRect.maxY,
                      width: appKitRect.width, height: appKitRect.height)
    }

    /// A spanning selection uses the highest intersecting display scale; geometry stays in points.
    static func scale(for rect: CGRect, displays: [(frame: CGRect, scale: CGFloat)]) throws -> CGFloat {
        let values = displays.filter { $0.frame.intersection(rect).isEmpty == false }.map(\.scale)
        guard let scale = values.max(), scale.isFinite, scale >= 0.5, scale <= 8 else {
            throw ScreenshotCaptureError.selectionInvalid
        }
        return scale
    }
}


/// Ephemeral display geometry used to reject a region after display rearrangement or scale changes.
nonisolated struct ScreenshotDisplayGeometry: Sendable, Equatable {
    let id: UInt32
    let frame: CGRect
    let scale: CGFloat
}

nonisolated struct ScreenshotDisplayLayout: Sendable, Equatable {
    let primaryDisplayID: UInt32
    let displays: [ScreenshotDisplayGeometry]
    init(primaryDisplayID: UInt32, displays: [ScreenshotDisplayGeometry]) {
        self.primaryDisplayID = primaryDisplayID
        self.displays = displays.sorted { $0.id < $1.id }
    }
}
