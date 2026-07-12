import Testing
@testable import SecurityKit

struct SecurityKitTests {
    @Test func permissionCheckerDefaultsToNotDetermined() async {
        let checker = InMemoryPermissionChecker()
        let state = await checker.state(for: .accessibility)
        #expect(state == .notDetermined)
    }

    @Test func permissionCheckerReturnsConfiguredState() async {
        let checker = InMemoryPermissionChecker(states: [.notifications: .authorized])
        let state = await checker.state(for: .notifications)
        #expect(state == .authorized)
    }

    @Test func sensitiveValueIsRedactedInDescription() {
        let value = SensitiveValue("super-secret")
        #expect(value.description == "<redacted>")
        #expect(value.debugDescription == "<redacted>")
        #expect(value.reveal() == "super-secret")
    }
}
