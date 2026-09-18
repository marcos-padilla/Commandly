import Foundation
import Infrastructure
import Testing
@testable import Commandly

@Suite("Accessibility window service")
struct AccessibilityWindowServiceTests {
    @Test func windowlessPlaceholderRequiresNoConcreteWindowAndNoDesktopRestriction() {
        let eligibleOptions = WindowQueryOptions(
            includeWindowless: true,
            currentDesktopOnly: false
        )

        #expect(AccessibilityWindowService.shouldIncludeWindowlessPlaceholder(
            hasConcreteWindows: false,
            options: eligibleOptions
        ))
        #expect(AccessibilityWindowService.shouldIncludeWindowlessPlaceholder(
            hasConcreteWindows: true,
            options: eligibleOptions
        ) == false)
        #expect(AccessibilityWindowService.shouldIncludeWindowlessPlaceholder(
            hasConcreteWindows: false,
            options: .default
        ) == false)
        #expect(AccessibilityWindowService.shouldIncludeWindowlessPlaceholder(
            hasConcreteWindows: false,
            options: WindowQueryOptions(
                includeWindowless: true,
                currentDesktopOnly: true
            )
        ) == false)
    }

    @Test func processIdentityRequiresLaunchEvidenceAndChangesAcrossRelaunch() {
        let firstLaunch = AccessibilityWindowService.ApplicationIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            launchDate: Date(timeIntervalSinceReferenceDate: 100)
        )
        let secondLaunch = AccessibilityWindowService.ApplicationIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            launchDate: Date(timeIntervalSinceReferenceDate: 200)
        )
        let unverifiable = AccessibilityWindowService.ApplicationIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.example.editor",
            launchDate: nil
        )

        #expect(firstLaunch.canVerifyProcessLifetime)
        #expect(firstLaunch != secondLaunch)
        #expect(unverifiable.canVerifyProcessLifetime == false)
    }
}
