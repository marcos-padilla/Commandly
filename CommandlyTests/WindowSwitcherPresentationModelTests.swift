import CoreGraphics
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Window Switcher presentation model")
@MainActor
struct WindowSwitcherPresentationModelTests {
    @Test func applicationModeGroupsEveryWindowWithoutChangingKeyboardTraversal() async throws {
        var configuration = WindowSwitcherConfiguration.default
        configuration.filterMode = .applications
        configuration.showsThumbnails = false
        configuration.usesLivePreviews = false

        let editorPrimary = snapshot(
            rawID: "editor-primary",
            processIdentifier: 101,
            bundleIdentifier: "com.example.Editor",
            applicationName: "Editor",
            title: "Draft",
            isFocused: true
        )
        let browser = snapshot(
            rawID: "browser",
            processIdentifier: 202,
            bundleIdentifier: "com.example.Browser",
            applicationName: "Browser",
            title: "Reference"
        )
        let editorSecondary = snapshot(
            rawID: "editor-secondary",
            processIdentifier: 101,
            bundleIdentifier: "com.example.Editor",
            applicationName: "Editor",
            title: "Notes"
        )
        let model = makeModel(
            configuration: configuration,
            windows: [editorPrimary, browser, editorSecondary]
        )

        model.load()
        #expect(await eventually { model.phase == .ready })

        #expect(model.visibleWindows.map(\.id) == [
            editorPrimary.id,
            browser.id,
            editorSecondary.id,
        ])
        #expect(model.applicationGroups.map(\.applicationName) == ["Editor", "Browser"])
        #expect(model.applicationGroups.map { $0.windows.map(\.id) } == [
            [editorPrimary.id, editorSecondary.id],
            [browser.id],
        ])
        #expect(model.applicationGroups.flatMap(\.windows).count == model.visibleWindows.count)

        model.moveSelection(offset: 1)
        #expect(model.selectedID == browser.id)

        model.setQuery("notes")
        #expect(model.applicationGroups.count == 1)
        #expect(model.applicationGroups.first?.windows.map(\.id) == [editorSecondary.id])
    }

    @Test func successfulActionMessageSurvivesItsCatalogRefresh() async throws {
        var configuration = WindowSwitcherConfiguration.default
        configuration.showsThumbnails = false
        configuration.usesLivePreviews = false
        let window = snapshot(
            rawID: "focused",
            processIdentifier: 303,
            bundleIdentifier: "com.example.Writer",
            applicationName: "Writer",
            title: "Chapter",
            isFocused: true
        )
        let service = InMemoryWindowService(windows: [window])
        let model = makeModel(
            configuration: configuration,
            service: service
        )

        model.load()
        #expect(await eventually { model.phase == .ready })
        model.perform(.zoom)

        #expect(await eventually {
            model.phase == .ready && model.statusMessage == "Window zoomed."
        })
        #expect(await service.performedActions == [
            WindowActionInvocation(action: .zoom, windowID: window.id),
        ])

        model.refresh()
        #expect(await eventually { model.phase == .ready })
        #expect(model.statusMessage == "Window zoomed.")
    }

    @Test func deferredActiveDisplayFrameRefreshesTheCurrentDisplayFilter() async {
        var configuration = WindowSwitcherConfiguration.default
        configuration.limitsToCurrentDisplay = true
        configuration.showsThumbnails = false
        let left = snapshot(
            rawID: "left",
            processIdentifier: 101,
            bundleIdentifier: "com.example.Left",
            applicationName: "Left",
            title: "Left Window",
            frame: CGRect(x: 20, y: 20, width: 500, height: 500)
        )
        let right = snapshot(
            rawID: "right",
            processIdentifier: 202,
            bundleIdentifier: "com.example.Right",
            applicationName: "Right",
            title: "Right Window",
            frame: CGRect(x: 1_220, y: 20, width: 500, height: 500)
        )
        let model = makeModel(configuration: configuration, windows: [left, right])

        model.load()
        #expect(await eventually { model.phase == .ready })
        #expect(model.visibleWindows.map(\.id) == [left.id, right.id])

        model.updateDisplayFrame(
            CGRect(x: 1_200, y: 0, width: 1_200, height: 900),
            refreshesWindowSet: true
        )
        #expect(await eventually {
            model.phase == .ready && model.visibleWindows.map(\.id) == [right.id]
        })
    }

    @Test func printableVimKeysRemainSearchTextWhenSearchIsEnabled() {
        var configuration = WindowSwitcherConfiguration.default
        configuration.allowsSearch = true
        configuration.allowsVimNavigation = true

        let inputs: [(keyCode: UInt16, lowercase: String, uppercase: String)] = [
            (4, "h", "H"),
            (38, "j", "J"),
            (40, "k", "K"),
            (37, "l", "L"),
        ]
        for input in inputs {
            #expect(WindowSwitcherEventMonitor.textOrVimCommand(
                keyCode: input.keyCode,
                flags: [],
                printableText: input.lowercase,
                configuration: configuration
            ) == .appendText(input.lowercase))
            #expect(WindowSwitcherEventMonitor.textOrVimCommand(
                keyCode: input.keyCode,
                flags: [.maskShift],
                printableText: input.uppercase,
                configuration: configuration
            ) == .appendText(input.uppercase))
        }

        configuration.allowsSearch = false
        #expect(WindowSwitcherEventMonitor.textOrVimCommand(
            keyCode: 4,
            flags: [],
            printableText: "h",
            configuration: configuration
        ) == .move(offset: -1))
        #expect(WindowSwitcherEventMonitor.textOrVimCommand(
            keyCode: 38,
            flags: [],
            printableText: "j",
            configuration: configuration
        ) == .move(offset: 1))
    }

    private func makeModel(
        configuration: WindowSwitcherConfiguration,
        windows: [WindowSnapshot]
    ) -> WindowSwitcherPresentationModel {
        makeModel(
            configuration: configuration,
            service: InMemoryWindowService(windows: windows)
        )
    }

    private func makeModel(
        configuration: WindowSwitcherConfiguration,
        service: InMemoryWindowService
    ) -> WindowSwitcherPresentationModel {
        WindowSwitcherPresentationModel(
            configuration: configuration,
            context: .allWindows(frontmostProcessIdentifier: nil),
            queryService: service,
            controlService: service,
            thumbnailService: InMemoryWindowThumbnailService(),
            displayFrame: nil,
            initialSelectionOffset: 0,
            onRequestDismiss: { _ in }
        )
    }

    private func snapshot(
        rawID: String,
        processIdentifier: Int32,
        bundleIdentifier: String?,
        applicationName: String,
        title: String,
        isFocused: Bool = false,
        frame: CGRect = CGRect(x: 20, y: 20, width: 800, height: 600)
    ) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: rawID, processIdentifier: processIdentifier),
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            title: title,
            frame: frame,
            isMinimized: false,
            isHidden: false,
            isOnCurrentDesktop: true,
            isFocused: isFocused,
            captureWindowID: nil
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0 ..< 200 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }
}
