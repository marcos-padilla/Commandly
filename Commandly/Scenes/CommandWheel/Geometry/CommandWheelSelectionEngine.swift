import CoreGraphics
import Foundation

/// Stateful pointer-selection logic. Geometry remains immediately usable while presentation
/// animations run; animation progress never participates in selection.
nonisolated struct CommandWheelSelectionEngine: Sendable {
    let geometry: CommandWheelGeometry
    let hysteresisDegrees: Double
    let minimumSelectionMovement: Double

    private(set) var selection: CommandWheelSelection?
    private var lastAcceptedPointerLocation: CGPoint?

    init(
        geometry: CommandWheelGeometry,
        hysteresisDegrees: Double,
        minimumSelectionMovement: Double
    ) {
        self.geometry = geometry
        let maximumUsefulHysteresis = max(0, geometry.degreesPerSlot / 2)
        self.hysteresisDegrees = min(max(0, hysteresisDegrees), maximumUsefulHysteresis)
        self.minimumSelectionMovement = max(0, minimumSelectionMovement)
    }

    init(
        interaction: CommandWheelInteractionConfiguration,
        startAngleDegrees: Double
    ) {
        self.init(
            geometry: CommandWheelGeometry(
                interaction: interaction,
                startAngleDegrees: startAngleDegrees
            ),
            hysteresisDegrees: interaction.selectionHysteresisDegrees,
            minimumSelectionMovement: interaction.minimumSelectionMovement
        )
    }

    /// Updates selection from the latest pointer sample.
    ///
    /// A final key-up sample bypasses movement and angular hysteresis, so a fast flick resolves from
    /// the actual release position even when intermediate motion events were coalesced. Dead,
    /// neutral, and empty-slot hits always clear selection immediately; they can never execute the
    /// previously highlighted slot.
    mutating func update(
        pointerLocation: CGPoint,
        actualCenter: CGPoint,
        selectableSlotIndices: Set<Int>,
        isFinalSample: Bool = false
    ) -> CommandWheelSelectionUpdate {
        let previous = selection
        let hitTest = geometry.hitTest(
            pointerLocation: pointerLocation,
            center: actualCenter,
            selectableSlotIndices: selectableSlotIndices
        )

        guard case .selectableSlot(let candidateSlot) = hitTest.target else {
            selection = nil
            lastAcceptedPointerLocation = pointerLocation
            return CommandWheelSelectionUpdate(
                previousSelection: previous,
                selection: nil,
                hitTest: hitTest,
                change: previous == nil ? .unchanged : .cleared
            )
        }

        let candidate = CommandWheelSelection(slotIndex: candidateSlot, hitTest: hitTest)

        guard let previous else {
            let hasMinimumMovement = hitTest.distance >= minimumSelectionMovement
            guard isFinalSample || hasMinimumMovement else {
                return CommandWheelSelectionUpdate(
                    previousSelection: nil,
                    selection: nil,
                    hitTest: hitTest,
                    change: .unchanged
                )
            }
            selection = candidate
            lastAcceptedPointerLocation = pointerLocation
            return CommandWheelSelectionUpdate(
                previousSelection: nil,
                selection: candidate,
                hitTest: hitTest,
                change: .selected
            )
        }

        if previous.slotIndex == candidateSlot {
            // Update radial/submenu information, but retain the last transition point so many tiny
            // samples cannot defeat the minimum movement required for a neighboring slot.
            selection = candidate
            return CommandWheelSelectionUpdate(
                previousSelection: previous,
                selection: candidate,
                hitTest: hitTest,
                change: .unchanged
            )
        }

        let movement = lastAcceptedPointerLocation.map {
            hypot(
                Double(pointerLocation.x - $0.x),
                Double(pointerLocation.y - $0.y)
            )
        } ?? hitTest.distance
        let enteredCandidate = isInsideCandidateBeyondHysteresis(
            slotIndex: candidateSlot,
            angle: hitTest.clockwiseAngleDegrees
        )

        guard isFinalSample || (movement >= minimumSelectionMovement && enteredCandidate) else {
            return CommandWheelSelectionUpdate(
                previousSelection: previous,
                selection: previous,
                hitTest: hitTest,
                change: .unchanged
            )
        }

        selection = candidate
        lastAcceptedPointerLocation = pointerLocation
        return CommandWheelSelectionUpdate(
            previousSelection: previous,
            selection: candidate,
            hitTest: hitTest,
            change: .changed
        )
    }

    mutating func reset() {
        selection = nil
        lastAcceptedPointerLocation = nil
    }

    private func isInsideCandidateBeyondHysteresis(slotIndex: Int, angle: Double) -> Bool {
        guard let center = geometry.slotCenterAngleDegrees(slotIndex) else { return false }
        let halfSlot = geometry.degreesPerSlot / 2
        let allowedDistanceFromCenter = max(0, halfSlot - hysteresisDegrees)
        return CommandWheelGeometry.shortestAngularDistanceDegrees(angle, center)
            <= allowedDistanceFromCenter
    }
}

nonisolated struct CommandWheelSelectionUpdate: Sendable, Equatable {
    let previousSelection: CommandWheelSelection?
    let selection: CommandWheelSelection?
    let hitTest: CommandWheelHitTest
    let change: CommandWheelSelectionChange
}

nonisolated enum CommandWheelSelectionChange: Sendable, Equatable {
    case unchanged
    case selected
    case changed
    case cleared
}

nonisolated enum CommandWheelKeyboardDirection: Sendable, Equatable {
    case next
    case previous
}

nonisolated enum CommandWheelKeyboardSelection {
    /// Moves clockwise (`next`) or counter-clockwise (`previous`), skipping empty slots and
    /// wrapping exactly once. With no current selection, next starts at zero and previous starts
    /// at the final slot.
    static func movedSelection(
        from currentSlot: Int?,
        direction: CommandWheelKeyboardDirection,
        slotCount: Int,
        selectableSlotIndices: Set<Int>
    ) -> Int? {
        guard slotCount > 0, selectableSlotIndices.isEmpty == false else { return nil }
        let step = direction == .next ? 1 : -1
        let startingSlot: Int
        if let currentSlot, currentSlot >= 0, currentSlot < slotCount {
            startingSlot = currentSlot
        } else {
            startingSlot = direction == .next ? slotCount - 1 : 0
        }

        for offset in 1 ... slotCount {
            let candidate = positiveModulo(startingSlot + step * offset, modulus: slotCount)
            if selectableSlotIndices.contains(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func positiveModulo(_ value: Int, modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }
}
