import CoreGraphics
import Foundation
import Testing
@testable import Infrastructure

@Suite("Window switching contracts")
struct WindowSwitchingTests {
    @Test
    func queryOptionsApplyEveryPrivacyAndPresentationFilter() async throws {
        let display = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let expected = snapshot(
            id: "visible",
            processIdentifier: 10,
            bundleIdentifier: "com.example.Editor",
            title: "Draft",
            frame: CGRect(x: 80, y: 90, width: 700, height: 500)
        )
        let service = InMemoryWindowService(windows: [
            expected,
            snapshot(id: "minimized", isMinimized: true),
            snapshot(id: "hidden", isHidden: true),
            snapshot(id: "other-desktop", isOnCurrentDesktop: false),
            snapshot(id: "excluded-app", bundleIdentifier: "com.example.Commandly"),
            snapshot(id: "excluded-title", title: "Private Overlay"),
            snapshot(
                id: "other-display",
                frame: CGRect(x: 2_000, y: 0, width: 600, height: 500)
            ),
            snapshot(
                id: "windowless",
                title: "",
                frame: .zero,
                captureWindowID: nil,
                isWindowless: true
            )
        ])

        let results = try await service.windows(
            options: WindowQueryOptions(
                includeMinimized: false,
                includeHidden: false,
                includeWindowless: false,
                currentDesktopOnly: true,
                currentDisplayFrame: display,
                excludedBundleIdentifiers: ["com.example.Commandly"],
                excludedTitleTerms: ["private"]
            )
        )

        #expect(results == [expected])
    }

    @Test
    func queryCanIncludeMinimizedHiddenWindowlessAndOtherDesktopResults() async throws {
        let windows = [
            snapshot(id: "minimized", isMinimized: true),
            snapshot(id: "hidden", isHidden: true),
            snapshot(id: "other-desktop", isOnCurrentDesktop: false),
            snapshot(
                id: "windowless",
                title: "",
                frame: .zero,
                captureWindowID: nil,
                isWindowless: true
            )
        ]
        let service = InMemoryWindowService(windows: windows)

        let results = try await service.windows(
            options: WindowQueryOptions(
                includeMinimized: true,
                includeHidden: true,
                includeWindowless: true,
                currentDesktopOnly: false
            )
        )

        #expect(results == windows)
        #expect(results.last?.isWindowless == true)
    }

    @Test
    func activateRestoresTargetAndMovesFocus() async throws {
        let first = snapshot(id: "first", processIdentifier: 10, isFocused: true)
        let second = snapshot(
            id: "second",
            processIdentifier: 20,
            isMinimized: true,
            isHidden: true
        )
        let service = InMemoryWindowService(windows: [first, second])

        try await service.perform(.activate, on: second.id)
        let results = try await service.windows(
            options: WindowQueryOptions(
                includeMinimized: true,
                includeHidden: true,
                currentDesktopOnly: false
            )
        )

        #expect(results.first?.isFocused == false)
        #expect(results.last?.isFocused == true)
        #expect(results.last?.isMinimized == false)
        #expect(results.last?.isHidden == false)
        #expect(
            await service.performedActions
                == [WindowActionInvocation(action: .activate, windowID: second.id)]
        )
    }

    @Test
    func minimizeCloseAndQuitMutateOnlyTheirExpectedTargets() async throws {
        let first = snapshot(id: "first", processIdentifier: 10)
        let sibling = snapshot(id: "sibling", processIdentifier: 10)
        let other = snapshot(id: "other", processIdentifier: 20)
        let service = InMemoryWindowService(windows: [first, sibling, other])

        try await service.perform(.toggleMinimized, on: first.id)
        var results = try await allWindows(from: service)
        #expect(results.first(where: { $0.id == first.id })?.isMinimized == true)

        try await service.perform(.close, on: first.id)
        results = try await allWindows(from: service)
        #expect(results.contains(where: { $0.id == first.id }) == false)
        #expect(results.contains(where: { $0.id == sibling.id }))

        try await service.perform(.quit, on: sibling.id)
        results = try await allWindows(from: service)
        #expect(results == [other])
    }

    @Test
    func missingWindowAndConfiguredFailuresRemainTyped() async {
        let missingID = WindowID(rawValue: "missing", processIdentifier: 99)
        let service = InMemoryWindowService()
        let failingQuery = InMemoryWindowService(queryError: .queryUnavailable)

        await #expect(throws: WindowServiceError.windowNotFound(missingID)) {
            try await service.perform(.close, on: missingID)
        }
        await #expect(throws: WindowServiceError.queryUnavailable) {
            try await failingQuery.windows()
        }
        #expect(await service.performedActions.isEmpty)
    }

    private func allWindows(from service: InMemoryWindowService) async throws -> [WindowSnapshot] {
        try await service.windows(
            options: WindowQueryOptions(
                includeMinimized: true,
                includeHidden: true,
                includeWindowless: true,
                currentDesktopOnly: false
            )
        )
    }

    private func snapshot(
        id rawID: String,
        processIdentifier: Int32 = 1,
        bundleIdentifier: String? = "com.example.App",
        title: String = "Window",
        frame: CGRect = CGRect(x: 40, y: 40, width: 500, height: 400),
        isMinimized: Bool = false,
        isHidden: Bool = false,
        isOnCurrentDesktop: Bool = true,
        isFocused: Bool = false,
        captureWindowID: UInt32? = 1,
        isWindowless: Bool = false
    ) -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: rawID, processIdentifier: processIdentifier),
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            applicationName: "Example",
            title: title,
            frame: frame,
            isMinimized: isMinimized,
            isHidden: isHidden,
            isOnCurrentDesktop: isOnCurrentDesktop,
            isFocused: isFocused,
            captureWindowID: captureWindowID,
            isWindowless: isWindowless
        )
    }
}
