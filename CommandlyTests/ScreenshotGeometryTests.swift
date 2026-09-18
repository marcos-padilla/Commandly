import AppKit
import CoreGraphics
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct ScreenshotGeometryTests {
    @Test
    func primaryAndSecondaryCoordinatesUseThePrimaryTopRatherThanActiveScreenHeight() throws {
        let primary = try ScreenshotGeometry.captureRect(appKitRect: CGRect(x: 20, y: 100, width: 200, height: 300), primaryDisplayTop: 900)
        #expect(primary == CGRect(x: 20, y: 500, width: 200, height: 300))
        let left = try ScreenshotGeometry.captureRect(appKitRect: CGRect(x: -1_300, y: -100, width: 400, height: 200), primaryDisplayTop: 900)
        #expect(left == CGRect(x: -1_300, y: 800, width: 400, height: 200))
        let above = try ScreenshotGeometry.captureRect(appKitRect: CGRect(x: 200, y: 1_050, width: 300, height: 200), primaryDisplayTop: 900)
        #expect(above == CGRect(x: 200, y: -350, width: 300, height: 200))
    }

    @Test
    func allDragDirectionsCreateTheSamePositiveRectangle() {
        let rect = CGRect(x: -100, y: 20, width: 300, height: 200)
        for (start, end) in [(CGPoint(x: -100, y: 20), CGPoint(x: 200, y: 220)),
                             (CGPoint(x: 200, y: 220), CGPoint(x: -100, y: 20)),
                             (CGPoint(x: 200, y: 20), CGPoint(x: -100, y: 220))] {
            #expect(ScreenshotGeometry.rectangle(from: start, to: end) == rect)
        }
    }

    @Test
    func mixedDensityRegionsUseHighestIntersectingScaleWithoutScalingCoordinates() throws {
        let displays: [(frame: CGRect, scale: CGFloat)] = [(CGRect(x: 0, y: 0, width: 1_000, height: 800), 2),
                                                         (CGRect(x: -800, y: 0, width: 800, height: 600), 1)]
        #expect(try ScreenshotGeometry.scale(for: CGRect(x: -600, y: 20, width: 200, height: 200), displays: displays) == 1)
        let spanning = CGRect(x: -200, y: 20, width: 400, height: 200)
        let scale = try ScreenshotGeometry.scale(for: spanning, displays: displays)
        #expect(scale == 2)
        let output = try ScreenshotGeometry.outputSize(points: spanning.size, scale: scale)
        #expect(output.width == 800 && output.height == 400)
        #expect(throws: ScreenshotCaptureError.selectionInvalid) {
            try ScreenshotGeometry.scale(for: CGRect(x: 5_000, y: 0, width: 10, height: 10), displays: displays)
        }
    }

    @Test
    func retinaAndLargeOutputBoundsPreserveAspectAndNeverExceedFortyMegapixels() throws {
        let retina = try ScreenshotGeometry.outputSize(points: CGSize(width: 1_440, height: 900), scale: 2)
        #expect(retina.width == 2_880 && retina.height == 1_800)
        let square = try ScreenshotGeometry.outputSize(points: CGSize(width: 10_000, height: 10_000), scale: 2)
        #expect(square.width == square.height && square.width * square.height <= 40_000_000)
        let wide = try ScreenshotGeometry.outputSize(points: CGSize(width: 65_536, height: 2_000), scale: 2)
        #expect(wide.width == 8_192 && wide.height == 250)
        for (points, scale) in [(CGSize(width: 0, height: 20), CGFloat(1)), (CGSize(width: CGFloat.infinity, height: 2), 1),
                                (CGSize(width: 10, height: 10), 0), (CGSize(width: 10, height: 10), .nan)] {
            #expect(throws: ScreenshotCaptureError.selectionInvalid) { try ScreenshotGeometry.outputSize(points: points, scale: scale) }
        }
    }

    @Test
    func emptySubminimumAndNonFiniteRegionsAreRejected() {
        for rect in [CGRect.zero, CGRect(x: 0, y: 0, width: 1, height: 10), CGRect(x: CGFloat.infinity, y: 0, width: 5, height: 5)] {
            #expect(throws: ScreenshotCaptureError.selectionInvalid) { try ScreenshotGeometry.captureRect(appKitRect: rect, primaryDisplayTop: 900) }
        }
    }
}

extension ScreenshotGeometryTests {
    @Test
    func topologyComparisonIgnoresListOrderButRejectsGeometryScaleIdentityAndPrimaryChanges() {
        let first = ScreenshotDisplayGeometry(id: 10, frame: CGRect(x: 0, y: 0, width: 1_440, height: 900), scale: 2)
        let second = ScreenshotDisplayGeometry(id: 20, frame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080), scale: 1)
        let selected = ScreenshotDisplayLayout(primaryDisplayID: 10, displays: [first, second])
        #expect(selected == ScreenshotDisplayLayout(primaryDisplayID: 10, displays: [second, first]))
        #expect(selected != ScreenshotDisplayLayout(primaryDisplayID: 20, displays: [first, second]))
        #expect(selected != ScreenshotDisplayLayout(primaryDisplayID: 10, displays: [first]))
        for replacement in [
            ScreenshotDisplayGeometry(id: 20, frame: second.frame.offsetBy(dx: 10, dy: 0), scale: 1),
            ScreenshotDisplayGeometry(id: 20, frame: second.frame, scale: 2),
            ScreenshotDisplayGeometry(id: 30, frame: second.frame, scale: 1)
        ] {
            #expect(selected != ScreenshotDisplayLayout(primaryDisplayID: 10, displays: [first, replacement]))
        }
    }

    @Test
    @MainActor
    func regionUsesEachDeliveredMouseEventThroughTheOriginatingWindowConversion() throws {
        for (type, location) in [(NSEvent.EventType.leftMouseDown, CGPoint(x: 10, y: 20)),
                                 (.leftMouseDragged, CGPoint(x: 150, y: -30)), (.leftMouseUp, CGPoint(x: 220, y: 80))] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 1,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
            var delivered: CGPoint?
            let point = ScreenshotRegionEventPosition.screenPoint(for: event) { value in
                delivered = value
                // Generated originating-window transform for a display to the left/below primary.
                return CGPoint(x: value.x - 1_920, y: value.y - 200)
            }
            #expect(delivered == location)
            #expect(point == CGPoint(x: location.x - 1_920, y: location.y - 200))
        }
    }
}
