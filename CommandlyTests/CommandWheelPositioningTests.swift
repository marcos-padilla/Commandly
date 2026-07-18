import CoreGraphics
import Foundation
import Testing
@testable import Commandly

struct CommandWheelPositioningTests {
    @Test func cursorPlacementAtScreenCenterNeedsNoClamp() throws {
        let display = makeDisplay(
            id: "main",
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: 0, y: 25, width: 1_000, height: 775)
        )
        let position = try #require(
            CommandWheelPositioningEngine.position(
                placement: .cursor,
                pointerLocation: CGPoint(x: 500, y: 400),
                displays: [display],
                activeDisplayIdentifier: "main",
                contentSize: CGSize(width: 240, height: 240)
            )
        )

        expectPoint(position.requestedCenter, x: 500, y: 400)
        expectPoint(position.actualCenter, x: 500, y: 400)
        #expect(position.wasClamped == false)
        #expect(position.display.identifier == "main")
    }

    @Test func cursorPlacementClampsEveryVisibleFrameCorner() throws {
        let display = makeDisplay(
            id: "main",
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            visibleFrame: CGRect(x: 0, y: 20, width: 1_000, height: 760)
        )
        let cases: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 0, y: 20), CGPoint(x: 100, y: 70)),
            (CGPoint(x: 1_000, y: 20), CGPoint(x: 900, y: 70)),
            (CGPoint(x: 0, y: 780), CGPoint(x: 100, y: 730)),
            (CGPoint(x: 1_000, y: 780), CGPoint(x: 900, y: 730)),
        ]

        for (pointer, expected) in cases {
            let position = try #require(
                CommandWheelPositioningEngine.position(
                    placement: .cursor,
                    pointerLocation: pointer,
                    displays: [display],
                    activeDisplayIdentifier: nil,
                    contentSize: CGSize(width: 200, height: 100)
                )
            )
            expectPoint(position.actualCenter, x: expected.x, y: expected.y)
            #expect(position.wasClamped)
            #expect(position.contentFrame.minX >= display.visibleFrame.minX)
            #expect(position.contentFrame.maxX <= display.visibleFrame.maxX)
            #expect(position.contentFrame.minY >= display.visibleFrame.minY)
            #expect(position.contentFrame.maxY <= display.visibleFrame.maxY)
        }
    }

    @Test func negativeOriginDisplayIsResolvedAndClampedInGlobalCoordinates() throws {
        let left = makeDisplay(
            id: "left",
            frame: CGRect(x: -2_000, y: -200, width: 1_200, height: 1_000),
            visibleFrame: CGRect(x: -2_000, y: -160, width: 1_200, height: 960),
            scale: 2
        )
        let main = makeDisplay(
            id: "main",
            frame: CGRect(x: 0, y: 0, width: 1_400, height: 900)
        )
        let position = try #require(
            CommandWheelPositioningEngine.position(
                placement: .cursor,
                pointerLocation: CGPoint(x: -1_990, y: -150),
                displays: [main, left],
                activeDisplayIdentifier: "main",
                contentSize: CGSize(width: 300, height: 300)
            )
        )

        #expect(position.display.identifier == "left")
        #expect(position.display.scale == 2)
        expectPoint(position.actualCenter, x: -1_850, y: -10)
    }

    @Test func activeScreenCenterIgnoresPointerDisplayWhenActiveIDExists() throws {
        let left = makeDisplay(
            id: "left",
            frame: CGRect(x: -1_000, y: 0, width: 1_000, height: 800)
        )
        let right = makeDisplay(
            id: "right",
            frame: CGRect(x: 0, y: 50, width: 1_200, height: 900),
            visibleFrame: CGRect(x: 0, y: 75, width: 1_200, height: 875)
        )
        let position = try #require(
            CommandWheelPositioningEngine.position(
                placement: .activeScreenCenter,
                pointerLocation: CGPoint(x: -500, y: 400),
                displays: [left, right],
                activeDisplayIdentifier: "right",
                contentSize: CGSize(width: 200, height: 200)
            )
        )

        #expect(position.display.identifier == "right")
        expectPoint(position.actualCenter, x: 600, y: 512.5)
        #expect(position.wasClamped == false)
    }

    @Test func fixedNormalizedPlacementUsesSelectedVisibleFrame() throws {
        let display = makeDisplay(
            id: "external",
            frame: CGRect(x: -1_600, y: 0, width: 1_600, height: 1_000),
            visibleFrame: CGRect(x: -1_550, y: 40, width: 1_500, height: 900)
        )
        let position = try #require(
            CommandWheelPositioningEngine.position(
                placement: .fixedNormalizedPoint(
                    screenIdentifier: "external",
                    x: 0.25,
                    y: 0.75
                ),
                pointerLocation: .zero,
                displays: [display],
                activeDisplayIdentifier: nil,
                contentSize: CGSize(width: 100, height: 100)
            )
        )

        expectPoint(position.requestedCenter, x: -1_175, y: 715)
        expectPoint(position.actualCenter, x: -1_175, y: 715)
    }

    @Test func fixedNormalizedCoordinatesClampAndNonfiniteCoordinatesCenter() throws {
        let display = makeDisplay(
            id: "main",
            frame: CGRect(x: 100, y: 200, width: 800, height: 600)
        )
        let clamped = try #require(
            CommandWheelPositioningEngine.position(
                placement: .fixedNormalizedPoint(screenIdentifier: "main", x: -1, y: 2),
                pointerLocation: .zero,
                displays: [display],
                activeDisplayIdentifier: nil,
                contentSize: .zero
            )
        )
        expectPoint(clamped.actualCenter, x: 100, y: 800)

        let centered = try #require(
            CommandWheelPositioningEngine.position(
                placement: .fixedNormalizedPoint(
                    screenIdentifier: "main",
                    x: .nan,
                    y: .infinity
                ),
                pointerLocation: .zero,
                displays: [display],
                activeDisplayIdentifier: nil,
                contentSize: .zero
            )
        )
        expectPoint(centered.actualCenter, x: 500, y: 500)
    }

    @Test func missingFixedDisplayFallsBackToActiveThenPointer() throws {
        let left = makeDisplay(
            id: "left",
            frame: CGRect(x: -1_000, y: 0, width: 1_000, height: 800)
        )
        let right = makeDisplay(
            id: "right",
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )
        let activeFallback = try #require(
            CommandWheelPositioningEngine.position(
                placement: .fixedNormalizedPoint(screenIdentifier: "gone", x: 0.5, y: 0.5),
                pointerLocation: CGPoint(x: -500, y: 400),
                displays: [left, right],
                activeDisplayIdentifier: "right",
                contentSize: CGSize(width: 100, height: 100)
            )
        )
        #expect(activeFallback.display.identifier == "right")

        let pointerFallback = try #require(
            CommandWheelPositioningEngine.position(
                placement: .fixedNormalizedPoint(screenIdentifier: "gone", x: 0.5, y: 0.5),
                pointerLocation: CGPoint(x: -500, y: 400),
                displays: [left, right],
                activeDisplayIdentifier: "also-gone",
                contentSize: CGSize(width: 100, height: 100)
            )
        )
        #expect(pointerFallback.display.identifier == "left")
    }

    @Test func sharedBoundaryTieBreakUsesCenterDistanceThenIdentifier() throws {
        let left = makeDisplay(
            id: "a-left",
            frame: CGRect(x: -1_000, y: 0, width: 1_000, height: 1_000)
        )
        let right = makeDisplay(
            id: "b-right",
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        )
        let point = CGPoint(x: 0, y: 500)

        let resolved = try #require(
            CommandWheelPositioningEngine.display(containing: point, in: [right, left])
        )
        #expect(resolved.identifier == "a-left")

        let preferred = try #require(
            CommandWheelPositioningEngine.display(
                containing: point,
                in: [left, right],
                preferredIdentifier: "b-right"
            )
        )
        #expect(preferred.identifier == "b-right")
    }

    @Test func displayGapUsesNearestFrameWithStableTieBreak() throws {
        let left = makeDisplay(
            id: "left",
            frame: CGRect(x: -1_000, y: 0, width: 800, height: 800)
        )
        let right = makeDisplay(
            id: "right",
            frame: CGRect(x: 200, y: 0, width: 800, height: 800)
        )

        #expect(
            CommandWheelPositioningEngine.display(
                containing: CGPoint(x: -150, y: 400),
                in: [right, left]
            )?.identifier == "left"
        )
        #expect(
            CommandWheelPositioningEngine.display(
                containing: CGPoint(x: 150, y: 400),
                in: [left, right]
            )?.identifier == "right"
        )
    }

    @Test func oversizedWheelKeepsSizeAndCentersOverflow() throws {
        let display = makeDisplay(
            id: "tiny",
            frame: CGRect(x: -200, y: 100, width: 300, height: 200),
            visibleFrame: CGRect(x: -180, y: 120, width: 260, height: 160)
        )
        let position = try #require(
            CommandWheelPositioningEngine.position(
                placement: .cursor,
                pointerLocation: CGPoint(x: -175, y: 125),
                displays: [display],
                activeDisplayIdentifier: nil,
                contentSize: CGSize(width: 500, height: 400)
            )
        )

        expectPoint(position.actualCenter, x: -50, y: 200)
        #expect(position.contentFrame.width == 500)
        #expect(position.contentFrame.height == 400)
        #expect(position.contentFrame.minX < display.visibleFrame.minX)
        #expect(position.contentFrame.maxY > display.visibleFrame.maxY)
    }

    @Test func invalidOrAbsentDisplaysReturnNil() {
        let invalid = makeDisplay(
            id: "invalid",
            frame: CGRect(x: 0, y: 0, width: 0, height: 100),
            scale: 0
        )
        #expect(
            CommandWheelPositioningEngine.position(
                placement: .cursor,
                pointerLocation: .zero,
                displays: [],
                activeDisplayIdentifier: nil,
                contentSize: CGSize(width: 100, height: 100)
            ) == nil
        )
        #expect(
            CommandWheelPositioningEngine.display(containing: .zero, in: [invalid]) == nil
        )
    }
}

private func makeDisplay(
    id: String,
    frame: CGRect,
    visibleFrame: CGRect? = nil,
    scale: Double = 1
) -> CommandWheelDisplaySnapshot {
    CommandWheelDisplaySnapshot(
        identifier: id,
        frame: frame,
        visibleFrame: visibleFrame ?? frame,
        scale: scale
    )
}

private func expectPoint(_ point: CGPoint, x: CGFloat, y: CGFloat) {
    #expect(abs(point.x - x) < 0.000_1)
    #expect(abs(point.y - y) < 0.000_1)
}
