import CommandKit
import Foundation

/// Conservative defaults built only from command identifiers registered by Commandly today.
nonisolated enum CommandWheelDefaults {
    static let appearance = CommandWheelAppearanceConfiguration(
        wheelRadius: 150,
        startAngleDegrees: 0,
        showsLabels: false,
        showsKeyboardHints: true,
        animationPreference: .system
    )

    static let interaction = CommandWheelInteractionConfiguration(
        visibleSlotCount: 8,
        deadZoneRadius: 34,
        selectionRadius: 42,
        submenuActivationRadius: 128,
        submenuDwellDurationSeconds: 0.35,
        selectionHysteresisDegrees: 6,
        minimumSelectionMovement: 4,
        allowsClickSelection: true,
        allowsKeyboardSelection: true,
        submenuActivationBehavior: .directionalContinuation
    )

    static var configuration: CommandWheelConfiguration {
        let profile = defaultProfile
        return CommandWheelConfiguration(
            isEnabled: false,
            contextAwareProfileSelectionEnabled: false,
            defaultProfileID: profile.id,
            profiles: [profile]
        )
    }

    static var defaultProfile: CommandWheelProfile {
        let pageID = stableID(finalByte: 2)
        let content: [CommandWheelSegmentContent] = [
            .command(
                CommandReference(
                    commandID: BuiltInCommandID.searchFiles,
                    arguments: .empty
                )
            ),
            .empty,
            .command(
                CommandReference(
                    commandID: BuiltInCommandID.clipboardHistory,
                    arguments: .empty
                )
            ),
            .empty,
            .command(
                CommandReference(
                    commandID: BuiltInCommandID.openSettings,
                    arguments: .empty
                )
            ),
            .empty,
            .empty,
            .empty,
        ]
        let segments = content.enumerated().map { index, content in
            CommandWheelSegment(
                id: stableID(finalByte: UInt8(16 + index)),
                slotIndex: index,
                content: content,
                customLabel: nil,
                customIcon: nil
            )
        }
        return CommandWheelProfile(
            id: stableID(finalByte: 1),
            name: "Default",
            isEnabled: true,
            shortcut: nil,
            activationBehavior: .holdAndRelease,
            placement: .cursor,
            rootPageID: pageID,
            pages: [
                CommandWheelPage(
                    id: pageID,
                    name: "Main",
                    segments: segments
                )
            ],
            contextRules: [],
            appearance: appearance,
            interaction: interaction,
            hidesUnavailableSegments: false
        )
    }

    private static func stableID(finalByte: UInt8) -> UUID {
        UUID(uuid: (
            0xC0, 0x4D, 0x4D, 0x41,
            0x4E, 0x44,
            0x57, 0x48,
            0x80, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, finalByte
        ))
    }
}
