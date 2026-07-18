import CoreGraphics
import Foundation
import Testing
@testable import Commandly

struct CommandWheelGeometryTests {
    @Test func angleNormalizationUsesHalfOpenTurn() {
        #expect(CommandWheelGeometry.normalizedDegrees(0) == 0)
        #expect(CommandWheelGeometry.normalizedDegrees(360) == 0)
        #expect(CommandWheelGeometry.normalizedDegrees(725) == 5)
        #expect(CommandWheelGeometry.normalizedDegrees(-10) == 350)
        #expect(CommandWheelGeometry.normalizedDegrees(.infinity) == 0)
        #expect(CommandWheelGeometry.normalizedRadians(2 * .pi) == 0)
        #expect(CommandWheelGeometry.normalizedRadians(-.pi / 2) == 3 * .pi / 2)
    }

    @Test func globalAppKitCardinalDirectionsIncreaseClockwiseFromTop() {
        let geometry = makeGeometry(slotCount: 8)
        let center = CGPoint(x: -300, y: 200)

        #expect(geometry.slotIndex(from: center, to: CGPoint(x: -300, y: 300)) == 0)
        #expect(geometry.slotIndex(from: center, to: CGPoint(x: -200, y: 300)) == 1)
        #expect(geometry.slotIndex(from: center, to: CGPoint(x: -200, y: 200)) == 2)
        #expect(geometry.slotIndex(from: center, to: CGPoint(x: -200, y: 100)) == 3)
        #expect(geometry.slotIndex(from: center, to: CGPoint(x: -300, y: 100)) == 4)
        #expect(geometry.slotIndex(from: center, to: CGPoint(x: -400, y: 100)) == 5)
        #expect(geometry.slotIndex(from: center, to: CGPoint(x: -400, y: 200)) == 6)
        #expect(geometry.slotIndex(from: center, to: CGPoint(x: -400, y: 300)) == 7)
    }

    @Test(arguments: [4, 6, 8, 12])
    func centeredSamplesResolveEverySupportedSlot(slotCount: Int) {
        let geometry = makeGeometry(slotCount: slotCount)
        let center = CGPoint(x: 50, y: -75)

        for slotIndex in 0 ..< slotCount {
            let angle = Double(slotIndex) * geometry.degreesPerSlot
            let point = point(clockwiseDegrees: angle, radius: 140, center: center)
            #expect(geometry.slotIndex(from: center, to: point) == slotIndex)
        }
    }

    @Test func configurableStartAngleOffsetsSlotZeroCenter() {
        let geometry = CommandWheelGeometry(
            slotCount: 4,
            startAngleDegrees: 30,
            deadZoneRadius: 20,
            selectionRadius: 40,
            submenuActivationRadius: 120
        )
        let center = CGPoint.zero

        #expect(geometry.slotIndex(from: center, to: point(clockwiseDegrees: 30, radius: 80)) == 0)
        #expect(geometry.slotIndex(from: center, to: point(clockwiseDegrees: 120, radius: 80)) == 1)
    }

    @Test func exactClockwiseBoundaryBelongsToFollowingSlot() {
        let geometry = makeGeometry(slotCount: 8)

        #expect(geometry.slotIndex(forClockwiseAngleDegrees: 22.499) == 0)
        #expect(geometry.slotIndex(forClockwiseAngleDegrees: 22.5) == 1)
        #expect(geometry.slotIndex(forClockwiseAngleDegrees: 337.499) == 7)
        #expect(geometry.slotIndex(forClockwiseAngleDegrees: 337.5) == 0)
    }

    @Test func radialThresholdsHaveDeterministicInclusiveOuterEdges() {
        let geometry = makeGeometry(slotCount: 8)

        #expect(geometry.radialRegion(distance: 19.999) == .deadZone)
        #expect(geometry.radialRegion(distance: 20) == .neutral)
        #expect(geometry.radialRegion(distance: 39.999) == .neutral)
        #expect(geometry.radialRegion(distance: 40) == .selection)
        #expect(geometry.radialRegion(distance: 119.999) == .selection)
        #expect(geometry.radialRegion(distance: 120) == .submenuActivation)
    }

    @Test func hitTestReportsDeadNeutralSelectableEmptyAndSubmenuRegions() {
        let geometry = makeGeometry(slotCount: 4)
        let slots: Set<Int> = [0, 2]

        #expect(
            geometry.hitTest(
                pointerLocation: point(clockwiseDegrees: 0, radius: 10),
                center: .zero,
                selectableSlotIndices: slots
            ).target == .none
        )
        #expect(
            geometry.hitTest(
                pointerLocation: point(clockwiseDegrees: 0, radius: 30),
                center: .zero,
                selectableSlotIndices: slots
            ).region == .neutral
        )
        #expect(
            geometry.hitTest(
                pointerLocation: point(clockwiseDegrees: 0, radius: 80),
                center: .zero,
                selectableSlotIndices: slots
            ).target == .selectableSlot(0)
        )
        #expect(
            geometry.hitTest(
                pointerLocation: point(clockwiseDegrees: 90, radius: 80),
                center: .zero,
                selectableSlotIndices: slots
            ).target == .emptySlot(1)
        )
        #expect(
            geometry.hitTest(
                pointerLocation: point(clockwiseDegrees: 180, radius: 130),
                center: .zero,
                selectableSlotIndices: slots
            ).region == .submenuActivation
        )
    }

    @Test func selectionUsesActualClampedCenter() {
        let geometry = makeGeometry(slotCount: 4)
        let requestedCursor = CGPoint(x: 0, y: 0)
        let actualCenter = CGPoint(x: 100, y: 50)
        let pointer = CGPoint(x: 100, y: 100)

        #expect(geometry.slotIndex(from: actualCenter, to: pointer) == 0)
        #expect(geometry.slotIndex(from: requestedCursor, to: pointer) == 1)
    }

    @Test func emptySlotImmediatelyClearsPriorSelection() {
        var engine = makeSelectionEngine(slotCount: 4)
        let slots: Set<Int> = [0, 2, 3]

        let selected = engine.update(
            pointerLocation: point(clockwiseDegrees: 0, radius: 80),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )
        #expect(selected.selection?.slotIndex == 0)

        let empty = engine.update(
            pointerLocation: point(clockwiseDegrees: 90, radius: 80),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )
        #expect(empty.hitTest.target == .emptySlot(1))
        #expect(empty.selection == nil)
        #expect(empty.change == .cleared)
    }

    @Test func returningToNeutralOrDeadZoneClearsSelection() {
        var engine = makeSelectionEngine(slotCount: 8)
        let slots = Set(0 ..< 8)
        _ = engine.update(
            pointerLocation: point(clockwiseDegrees: 0, radius: 80),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )

        let neutral = engine.update(
            pointerLocation: point(clockwiseDegrees: 0, radius: 30),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )
        #expect(neutral.selection == nil)
        #expect(neutral.change == .cleared)

        _ = engine.update(
            pointerLocation: point(clockwiseDegrees: 0, radius: 80),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )
        let dead = engine.update(
            pointerLocation: point(clockwiseDegrees: 0, radius: 10),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )
        #expect(dead.selection == nil)
        #expect(dead.hitTest.region == .deadZone)
    }

    @Test func submenuThresholdIsCarriedBySelection() {
        var engine = makeSelectionEngine(slotCount: 8)
        let slots = Set(0 ..< 8)

        let inner = engine.update(
            pointerLocation: point(clockwiseDegrees: 0, radius: 80),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )
        #expect(inner.selection?.reachedSubmenuActivationRadius == false)

        let outer = engine.update(
            pointerLocation: point(clockwiseDegrees: 0, radius: 130),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )
        #expect(outer.selection?.reachedSubmenuActivationRadius == true)
    }

    @Test func angularHysteresisStabilizesBoundaryThenAllowsIntentionalChange() {
        var engine = makeSelectionEngine(
            slotCount: 8,
            hysteresisDegrees: 8,
            minimumMovement: 4
        )
        let slots = Set(0 ..< 8)
        _ = engine.update(
            pointerLocation: point(clockwiseDegrees: 0, radius: 100),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )

        let boundary = engine.update(
            pointerLocation: point(clockwiseDegrees: 24, radius: 100),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )
        #expect(boundary.hitTest.target == .selectableSlot(1))
        #expect(boundary.selection?.slotIndex == 0)
        #expect(boundary.change == .unchanged)

        let intentional = engine.update(
            pointerLocation: point(clockwiseDegrees: 40, radius: 100),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )
        #expect(intentional.selection?.slotIndex == 1)
        #expect(intentional.change == .changed)
    }

    @Test func minimumMovementRejectsTinyBoundaryJitter() {
        let geometry = CommandWheelGeometry(
            slotCount: 12,
            deadZoneRadius: 0,
            selectionRadius: 0,
            submenuActivationRadius: 200
        )
        var engine = CommandWheelSelectionEngine(
            geometry: geometry,
            hysteresisDegrees: 0,
            minimumSelectionMovement: 10
        )
        let slots = Set(0 ..< 12)
        _ = engine.update(
            pointerLocation: point(clockwiseDegrees: 14, radius: 100),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )

        let jitter = engine.update(
            pointerLocation: point(clockwiseDegrees: 16, radius: 100),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )
        #expect(jitter.hitTest.target == .selectableSlot(1))
        #expect(jitter.selection?.slotIndex == 0)

        let deliberate = engine.update(
            pointerLocation: point(clockwiseDegrees: 30, radius: 100),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )
        #expect(deliberate.selection?.slotIndex == 1)
    }

    @Test func finalFastSampleBypassesHysteresisAndMinimumMovement() {
        var engine = makeSelectionEngine(
            slotCount: 8,
            hysteresisDegrees: 10,
            minimumMovement: 200
        )
        let slots = Set(0 ..< 8)

        let ordinary = engine.update(
            pointerLocation: point(clockwiseDegrees: 45, radius: 80),
            actualCenter: .zero,
            selectableSlotIndices: slots
        )
        #expect(ordinary.selection == nil)

        let released = engine.update(
            pointerLocation: point(clockwiseDegrees: 45, radius: 80),
            actualCenter: .zero,
            selectableSlotIndices: slots,
            isFinalSample: true
        )
        #expect(released.selection?.slotIndex == 1)
        #expect(released.change == .selected)
    }

    @Test func finalFastSampleStillClearsAnEmptySlot() {
        var engine = makeSelectionEngine(slotCount: 8)
        _ = engine.update(
            pointerLocation: point(clockwiseDegrees: 0, radius: 80),
            actualCenter: .zero,
            selectableSlotIndices: [0]
        )

        let released = engine.update(
            pointerLocation: point(clockwiseDegrees: 45, radius: 80),
            actualCenter: .zero,
            selectableSlotIndices: [0],
            isFinalSample: true
        )
        #expect(released.hitTest.target == .emptySlot(1))
        #expect(released.selection == nil)
    }

    @Test func keyboardSelectionSkipsEmptySlotsAndWrapsDeterministically() {
        let slots: Set<Int> = [0, 3, 6]

        #expect(
            CommandWheelKeyboardSelection.movedSelection(
                from: nil,
                direction: .next,
                slotCount: 8,
                selectableSlotIndices: slots
            ) == 0
        )
        #expect(
            CommandWheelKeyboardSelection.movedSelection(
                from: nil,
                direction: .previous,
                slotCount: 8,
                selectableSlotIndices: slots
            ) == 6
        )
        #expect(
            CommandWheelKeyboardSelection.movedSelection(
                from: 0,
                direction: .next,
                slotCount: 8,
                selectableSlotIndices: slots
            ) == 3
        )
        #expect(
            CommandWheelKeyboardSelection.movedSelection(
                from: 6,
                direction: .next,
                slotCount: 8,
                selectableSlotIndices: slots
            ) == 0
        )
        #expect(
            CommandWheelKeyboardSelection.movedSelection(
                from: 0,
                direction: .previous,
                slotCount: 8,
                selectableSlotIndices: slots
            ) == 6
        )
        #expect(
            CommandWheelKeyboardSelection.movedSelection(
                from: 3,
                direction: .previous,
                slotCount: 8,
                selectableSlotIndices: slots
            ) == 0
        )
    }

    @Test func keyboardSelectionReturnsNilForNoUsableSlots() {
        #expect(
            CommandWheelKeyboardSelection.movedSelection(
                from: nil,
                direction: .next,
                slotCount: 8,
                selectableSlotIndices: []
            ) == nil
        )
        #expect(
            CommandWheelKeyboardSelection.movedSelection(
                from: nil,
                direction: .next,
                slotCount: 0,
                selectableSlotIndices: [0]
            ) == nil
        )
    }

    @Test func iconOnlyTileLayoutMaintainsGapsAtValidatedBoundaries() {
        let tolerance: CGFloat = 0.001

        for wheelRadius: CGFloat in [80, 150, 320] {
            for slotCount in [4, 6, 8, 12] {
                let layout = CommandWheelSegmentLayout(
                    wheelRadius: wheelRadius,
                    slotCount: slotCount
                )
                #expect(layout.tileSide > 0)
                #expect(layout.tileSide <= CommandWheelSegmentLayout.maximumTileSide)

                for startAngle in [0.0, 7.5, 22.5, 71.0, 359.0] {
                    let frames = (0 ..< slotCount).map {
                        layout.tileFrame(
                            slotIndex: $0,
                            startAngleDegrees: startAngle
                        )
                    }

                    for firstIndex in frames.indices {
                        let first = frames[firstIndex]
                        let nearestX = max(0, abs(first.midX) - first.width / 2)
                        let nearestY = max(0, abs(first.midY) - first.height / 2)
                        let centerClearance = hypot(nearestX, nearestY)
                            - layout.centerDiameter / 2
                        #expect(
                            centerClearance
                                >= CommandWheelSegmentLayout.visualGap - tolerance
                        )

                        for secondIndex in frames.indices where secondIndex > firstIndex {
                            let second = frames[secondIndex]
                            let axisGap = max(
                                abs(first.midX - second.midX) - layout.tileSide,
                                abs(first.midY - second.midY) - layout.tileSide
                            )
                            #expect(
                                axisGap >= CommandWheelSegmentLayout.visualGap - tolerance
                            )
                        }

                        for corner in [
                            CGPoint(x: first.minX, y: first.minY),
                            CGPoint(x: first.minX, y: first.maxY),
                            CGPoint(x: first.maxX, y: first.minY),
                            CGPoint(x: first.maxX, y: first.maxY),
                        ] {
                            #expect(
                                hypot(corner.x, corner.y)
                                    <= wheelRadius
                                        - CommandWheelSegmentLayout.visualGap
                                        + tolerance
                            )
                        }
                    }
                }
            }
        }
    }

    @Test func compactIconLayoutDegradesBadgesWithoutOverlappingPrimaryIcon() {
        let compact = CommandWheelSegmentLayout(wheelRadius: 80, slotCount: 12)
        #expect(compact.showsAuxiliaryBadges == false)
        #expect(compact.showsKeyboardHint == false)

        for wheelRadius: CGFloat in [80, 150, 320] {
            for slotCount in [4, 6, 8, 12] {
                let layout = CommandWheelSegmentLayout(
                    wheelRadius: wheelRadius,
                    slotCount: slotCount
                )
                guard layout.showsAuxiliaryBadges else { continue }
                let primaryMargin = (layout.tileSide - layout.primaryIconSize) / 2
                let badgeInnerEdge = layout.badgeInset + layout.badgeSize
                #expect(primaryMargin - badgeInnerEdge >= 0.999)
                if layout.showsKeyboardHint {
                    #expect(layout.tileSide >= 48)
                }
            }
        }
    }
}

private func makeGeometry(slotCount: Int) -> CommandWheelGeometry {
    CommandWheelGeometry(
        slotCount: slotCount,
        deadZoneRadius: 20,
        selectionRadius: 40,
        submenuActivationRadius: 120
    )
}

private func makeSelectionEngine(
    slotCount: Int,
    hysteresisDegrees: Double = 6,
    minimumMovement: Double = 4
) -> CommandWheelSelectionEngine {
    CommandWheelSelectionEngine(
        geometry: makeGeometry(slotCount: slotCount),
        hysteresisDegrees: hysteresisDegrees,
        minimumSelectionMovement: minimumMovement
    )
}

private func point(
    clockwiseDegrees: Double,
    radius: Double,
    center: CGPoint = .zero
) -> CGPoint {
    let radians = clockwiseDegrees * .pi / 180
    return CGPoint(
        x: center.x + CGFloat(sin(radians) * radius),
        y: center.y + CGFloat(cos(radians) * radius)
    )
}
