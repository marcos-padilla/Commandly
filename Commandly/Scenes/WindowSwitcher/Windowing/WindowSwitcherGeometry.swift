import AppKit
import Foundation

enum WindowSwitcherGeometry {
    static func panelFrame(
        configuration: WindowSwitcherConfiguration,
        windowCount: Int,
        screenFrame: CGRect,
        dockAnchor: CGRect? = nil
    ) -> CGRect {
        let contentSize = contentSize(
            configuration: configuration,
            windowCount: windowCount,
            screenFrame: screenFrame
        )
        let origin: CGPoint
        if let dockAnchor {
            origin = dockOrigin(
                size: contentSize,
                anchor: dockAnchor,
                screenFrame: screenFrame
            )
        } else {
            origin = CGPoint(
                x: screenFrame.midX - contentSize.width / 2
                    + CGFloat(configuration.horizontalOffset),
                y: screenFrame.midY - contentSize.height / 2
                    + CGFloat(configuration.verticalOffset)
            )
        }
        let proposed = CGRect(origin: origin, size: contentSize)
        return clamp(proposed, to: screenFrame.insetBy(dx: 12, dy: 12)).integral
    }

    static func contentSize(
        configuration: WindowSwitcherConfiguration,
        windowCount: Int,
        screenFrame: CGRect
    ) -> CGSize {
        let count = max(1, windowCount)
        let headerAndFooter: CGFloat = 87
        switch configuration.layoutStyle {
        case .grid:
            let cardWidth = itemWidth(configuration.itemSize)
            let cardHeight = cardWidth * 0.78
            let columns = min(max(1, configuration.gridColumnCount), count)
            let rows = Int(ceil(Double(count) / Double(columns)))
            return CGSize(
                width: min(
                    CGFloat(columns) * cardWidth + CGFloat(max(0, columns - 1)) * 10 + 24,
                    screenFrame.width - 24
                ),
                height: min(
                    CGFloat(rows) * cardHeight + CGFloat(max(0, rows - 1)) * 10
                        + headerAndFooter + 24,
                    screenFrame.height * 0.78
                )
            )
        case .list:
            let rowHeight = listHeight(configuration.itemSize)
            return CGSize(
                width: min(570, screenFrame.width - 24),
                height: min(
                    CGFloat(count) * (rowHeight + 4) + headerAndFooter + 20,
                    screenFrame.height * 0.72
                )
            )
        case .strip:
            let cardWidth = itemWidth(configuration.itemSize)
            return CGSize(
                width: min(
                    CGFloat(count) * cardWidth + CGFloat(max(0, count - 1)) * 10 + 24,
                    screenFrame.width * 0.88
                ),
                height: min(cardWidth * 0.78 + headerAndFooter + 24, screenFrame.height * 0.65)
            )
        }
    }

    private static func itemWidth(_ size: WindowSwitcherItemSize) -> CGFloat {
        switch size {
        case .compact: 192
        case .regular: 240
        case .large: 302
        }
    }

    private static func listHeight(_ size: WindowSwitcherItemSize) -> CGFloat {
        switch size {
        case .compact: 42
        case .regular: 50
        case .large: 60
        }
    }

    private static func dockOrigin(
        size: CGSize,
        anchor: CGRect,
        screenFrame: CGRect
    ) -> CGPoint {
        let gap: CGFloat = 10
        let distances = [
            (edge: NSRectEdge.minY, value: abs(anchor.minY - screenFrame.minY)),
            (edge: NSRectEdge.maxY, value: abs(screenFrame.maxY - anchor.maxY)),
            (edge: NSRectEdge.minX, value: abs(anchor.minX - screenFrame.minX)),
            (edge: NSRectEdge.maxX, value: abs(screenFrame.maxX - anchor.maxX)),
        ]
        let closest = distances.min(by: { $0.value < $1.value })?.edge ?? .minY
        switch closest {
        case .minY:
            return CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        case .maxY:
            return CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - gap)
        case .minX:
            return CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        case .maxX:
            return CGPoint(x: anchor.minX - size.width - gap, y: anchor.midY - size.height / 2)
        @unknown default:
            return CGPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2)
        }
    }

    private static func clamp(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        var result = frame
        if result.width > bounds.width { result.size.width = bounds.width }
        if result.height > bounds.height { result.size.height = bounds.height }
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }
}
