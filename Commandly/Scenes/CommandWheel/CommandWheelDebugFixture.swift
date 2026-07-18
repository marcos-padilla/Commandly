#if DEBUG
import AppKit
import CommandKit
import Observation

/// Deterministic, process-local fixture used only by the opt-in macOS UI-validation scheme.
///
/// The fixture presents the production `CommandWheelPanel` and `CommandWheelView`; it replaces
/// only global-shortcut input and command execution so GUI automation can exercise the native
/// radial interaction without registering a developer's shortcuts or launching applications.
@MainActor
@Observable
final class CommandWheelDebugFixturePresenter {
    private let windowController = CommandWheelWindowController()
    private var model: CommandWheelPresentationModel?

    func presentIfRequested() {
        guard CommandWheelDebugFixture.isWheelPresentationRequested else { return }
        CommandWheelDebugFixture.applyRequestedAppearance()

        let model = CommandWheelDebugFixture.makeRootPresentationModel()
        self.model = model
        windowController.present(
            model: model,
            position: position(for: model),
            activationBehavior: .toggle,
            frontmostProcessIdentifier: nil,
            onActivateSlot: { [weak self] slotIndex in
                self?.activate(slotIndex: slotIndex)
            },
            onActivateCenter: { [weak self] in
                self?.activateCenter()
            },
            onKeyboardCommand: { [weak self] command in
                self?.handleKeyboardCommand(command) ?? false
            }
        )
    }

    func tearDown() {
        model = nil
        windowController.tearDown()
    }

    private func activate(slotIndex: Int) {
        guard let model,
              let segment = model.segment(at: slotIndex),
              segment.isSelectable else {
            return
        }
        model.selectedSlotIndex = slotIndex
        switch segment.kind {
        case .command:
            dismiss()
        case .submenu:
            model.replacePage(
                pageID: CommandWheelDebugFixture.childPageID,
                pageName: "Utilities",
                pageDepth: 1,
                segments: CommandWheelDebugFixture.makeChildSegments()
            )
        case .empty:
            break
        }
    }

    private func activateCenter() {
        guard let model else { return }
        if model.pageDepth > 0 {
            model.replacePage(
                pageID: CommandWheelDebugFixture.rootPageID,
                pageName: "Main",
                pageDepth: 0,
                segments: CommandWheelDebugFixture.makeRootSegments()
            )
        } else {
            dismiss()
        }
    }

    private func handleKeyboardCommand(_ command: CommandWheelKeyboardCommand) -> Bool {
        guard let model else { return false }
        switch command {
        case .cancel:
            activateCenter()
        case .activate:
            guard let selectedSlotIndex = model.selectedSlotIndex else { return true }
            activate(slotIndex: selectedSlotIndex)
        case .next, .previous:
            let direction: CommandWheelKeyboardDirection = command == .next ? .next : .previous
            model.selectedSlotIndex = CommandWheelKeyboardSelection.movedSelection(
                from: model.selectedSlotIndex,
                direction: direction,
                slotCount: model.interaction.visibleSlotCount,
                selectableSlotIndices: model.selectableSlotIndices
            )
        case .selectVisibleSlot(let slotIndex):
            if model.selectableSlotIndices.contains(slotIndex) {
                model.selectedSlotIndex = slotIndex
            }
        }
        return true
    }

    private func dismiss() {
        windowController.dismiss()
        model = nil
    }

    private func position(for model: CommandWheelPresentationModel) -> CommandWheelPosition {
        let fallbackFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? fallbackFrame
        let visibleFrame = screen?.visibleFrame ?? fallbackFrame
        let display = CommandWheelDisplaySnapshot(
            identifier: "command-wheel-xcui-display",
            frame: screenFrame,
            visibleFrame: visibleFrame,
            scale: Double(screen?.backingScaleFactor ?? 1)
        )
        let center = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        let frame = CGRect(
            x: center.x - model.contentSize.width / 2,
            y: center.y - model.contentSize.height / 2,
            width: model.contentSize.width,
            height: model.contentSize.height
        )
        return CommandWheelPosition(
            display: display,
            requestedCenter: center,
            actualCenter: center,
            contentFrame: frame,
            wasClamped: false
        )
    }
}

/// Stable fixture content and launch-environment overrides shared by the DEBUG app entry and view.
nonisolated enum CommandWheelDebugFixture {
    static let wheelArgument = "--commandly-command-wheel-fixture"
    static let settingsArgument = "--commandly-command-wheel-settings-fixture"
    static let lightAppearanceArgument = "--commandly-command-wheel-light"
    static let darkAppearanceArgument = "--commandly-command-wheel-dark"
    static let reduceMotionArgument = "--commandly-command-wheel-reduce-motion"
    static let increasedContrastArgument = "--commandly-command-wheel-increased-contrast"

    static let profileID = fixedID(finalByte: 0x61)
    static let rootPageID = fixedID(finalByte: 0x62)
    static let childPageID = fixedID(finalByte: 0x63)

    static var isWheelPresentationRequested: Bool {
        arguments.contains(wheelArgument)
    }

    static var isSettingsPresentationRequested: Bool {
        arguments.contains(settingsArgument)
    }

    static var forcesReducedMotion: Bool {
        arguments.contains(reduceMotionArgument)
    }

    static var forcesIncreasedContrast: Bool {
        arguments.contains(increasedContrastArgument)
    }

    static var settingsConfiguration: CommandWheelConfiguration {
        let pageID = fixedID(finalByte: 0x72)
        let content: [CommandWheelSegmentContent] = [
            .command(CommandReference(commandID: BuiltInCommandID.searchFiles)),
            .empty,
            .command(CommandReference(commandID: CommandID(rawValue: "fixture.removed-command"))),
            .command(CommandReference(commandID: CommandID(rawValue: "windows.layouts"))),
            .command(CommandReference(commandID: BuiltInCommandID.clipboardHistory)),
            .command(CommandReference(commandID: BuiltInCommandID.openSettings)),
            .empty,
            .empty,
        ]
        let segments = content.enumerated().map { slotIndex, content in
            CommandWheelSegment(
                id: fixedID(finalByte: UInt8(0x80 + slotIndex)),
                slotIndex: slotIndex,
                content: content,
                customLabel: nil,
                customIcon: nil
            )
        }
        let profile = CommandWheelProfile(
            id: fixedID(finalByte: 0x71),
            name: "XCUI Wheel",
            isEnabled: true,
            shortcut: nil,
            activationBehavior: .toggle,
            placement: .activeScreenCenter,
            rootPageID: pageID,
            pages: [CommandWheelPage(id: pageID, name: "Main", segments: segments)],
            contextRules: [],
            appearance: CommandWheelDefaults.appearance,
            interaction: CommandWheelDefaults.interaction,
            hidesUnavailableSegments: false
        )
        return CommandWheelConfiguration(
            isEnabled: true,
            contextAwareProfileSelectionEnabled: false,
            defaultProfileID: profile.id,
            profiles: [profile]
        )
    }

    @MainActor
    static func makeRootPresentationModel() -> CommandWheelPresentationModel {
        var appearance = CommandWheelDefaults.appearance
        if forcesReducedMotion {
            appearance.animationPreference = .reduced
        }
        return CommandWheelPresentationModel(
            profileID: profileID,
            profileName: "XCUI Wheel",
            pageID: rootPageID,
            pageName: "Main",
            appearance: appearance,
            interaction: CommandWheelDefaults.interaction,
            segments: makeRootSegments()
        )
    }

    static func makeRootSegments() -> [CommandWheelPresentedSegment] {
        [
            presentedSegment(
                finalByte: 0x21,
                slotIndex: 0,
                kind: .command(CommandReference(commandID: BuiltInCommandID.searchFiles)),
                state: .available,
                title: "Find Files",
                systemImage: "doc.text.magnifyingglass"
            ),
            presentedSegment(
                finalByte: 0x22,
                slotIndex: 1,
                kind: .submenu(pageID: childPageID),
                state: .available,
                title: "Utilities",
                systemImage: "circle.grid.2x2"
            ),
            presentedSegment(
                finalByte: 0x23,
                slotIndex: 2,
                kind: .command(CommandReference(commandID: CommandID(rawValue: "windows.layouts"))),
                state: .unavailable(.missingPermission(identifier: "accessibility")),
                title: "Arrange Windows",
                systemImage: "rectangle.3.group"
            ),
            presentedSegment(
                finalByte: 0x24,
                slotIndex: 3,
                kind: .command(CommandReference(commandID: CommandID(rawValue: "fixture.removed-command"))),
                state: .missing,
                title: "Removed Command",
                systemImage: "questionmark.diamond"
            ),
            presentedSegment(
                finalByte: 0x25,
                slotIndex: 4,
                kind: .command(
                    BuiltInCommandReference.openInstalledApplication(
                        bundleIdentifier: "com.apple.finder"
                    )
                ),
                state: .available,
                title: "Finder",
                systemImage: "folder"
            ),
            presentedSegment(
                finalByte: 0x26,
                slotIndex: 5,
                kind: .command(CommandReference(commandID: BuiltInCommandID.openSettings)),
                state: .available,
                title: "Settings",
                systemImage: "gearshape"
            ),
            presentedSegment(
                finalByte: 0x27,
                slotIndex: 6,
                kind: .empty,
                state: .empty,
                title: "Empty",
                systemImage: "plus"
            ),
            presentedSegment(
                finalByte: 0x28,
                slotIndex: 7,
                kind: .command(CommandReference(commandID: CommandID(rawValue: "fixture.unavailable"))),
                state: .unavailable(.temporarilyUnavailable),
                title: "Offline Tool",
                systemImage: "bolt.slash"
            ),
        ]
    }

    static func makeChildSegments() -> [CommandWheelPresentedSegment] {
        [
            presentedSegment(
                finalByte: 0x31,
                slotIndex: 0,
                pageID: childPageID,
                kind: .command(CommandReference(commandID: BuiltInCommandID.openSettings)),
                state: .available,
                title: "Open Settings",
                systemImage: "gearshape"
            ),
            presentedSegment(
                finalByte: 0x32,
                slotIndex: 4,
                pageID: childPageID,
                kind: .command(CommandReference(commandID: BuiltInCommandID.clipboardHistory)),
                state: .available,
                title: "Clipboard",
                systemImage: "clipboard"
            ),
        ]
    }

    @MainActor
    static func applyRequestedAppearance() {
        if arguments.contains(darkAppearanceArgument) {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else if arguments.contains(lightAppearanceArgument) {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
    }

    private static var arguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    private static func presentedSegment(
        finalByte: UInt8,
        slotIndex: Int,
        pageID: UUID = rootPageID,
        kind: CommandWheelPresentedSegmentKind,
        state: CommandWheelPresentedSegmentState,
        title: String,
        systemImage: String
    ) -> CommandWheelPresentedSegment {
        CommandWheelPresentedSegment(
            sourceSegmentID: fixedID(finalByte: finalByte),
            pageID: pageID,
            slotIndex: slotIndex,
            kind: kind,
            state: state,
            title: title,
            subtitle: nil,
            systemImage: systemImage,
            isDynamic: false
        )
    }

    private static func fixedID(finalByte: UInt8) -> UUID {
        UUID(uuid: (
            0x58, 0x43, 0x55, 0x49,
            0x43, 0x4D,
            0x44, 0x57,
            0x80, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, finalByte
        ))
    }
}
#endif
