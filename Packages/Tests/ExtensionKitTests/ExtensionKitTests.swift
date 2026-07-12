import Testing
@testable import ExtensionKit

struct ExtensionKitTests {
    @Test func validManifestPassesValidation() {
        let manifest = ExtensionManifest(
            id: ExtensionID(rawValue: "com.example.demo"),
            name: "Demo",
            version: ExtensionVersion(major: 1, minor: 0, patch: 0),
            permissions: [.notifications],
            minimumAppVersion: "1.0.0"
        )
        #expect(ExtensionManifestValidator.validate(manifest) == .valid)
    }

    @Test func emptyNameFailsValidation() {
        let manifest = ExtensionManifest(
            id: ExtensionID(rawValue: "com.example.demo"),
            name: "   ",
            version: ExtensionVersion(major: 1, minor: 0, patch: 0),
            minimumAppVersion: "1.0.0"
        )
        let result = ExtensionManifestValidator.validate(manifest)
        guard case .invalid(let reasons) = result else {
            Issue.record("Expected invalid result")
            return
        }
        #expect(reasons.contains(where: { $0.contains("name") }))
    }

    @Test func extensionVersionOrdering() {
        let older = ExtensionVersion(major: 1, minor: 0, patch: 0)
        let newer = ExtensionVersion(major: 1, minor: 1, patch: 0)
        #expect(older < newer)
    }
}
