import Foundation
import Testing
@testable import AIKit

@Suite("AIKit domain")
struct AIKitDomainTests {
    @Test("Credentials redact textual representations")
    func credentialRedaction() {
        let credential = AICredential("secret-value")

        #expect(String(describing: credential) == "<redacted>")
        #expect(String(reflecting: credential) == "<redacted>")
        let mirroredValue = String(describing: credential.customMirror.children.first?.value)
        #expect(!mirroredValue.contains("secret-value"))

        let configuration = AIProviderConfiguration(
            providerID: .openAI,
            credential: credential,
            values: [.organizationID: "sensitive-metadata"]
        )
        #expect(!String(reflecting: configuration).contains("secret-value"))
        #expect(!String(reflecting: configuration).contains("sensitive-metadata"))
    }

    @Test("Provider continuation state redacts opaque payload representations")
    func providerStateRedaction() {
        let state = AIProviderState(
            providerID: .googleGemini,
            payload: Data("thought-signature-secret".utf8)
        )

        let expected = "AIProviderState(providerID: google-gemini, payload: <redacted>)"
        #expect(String(describing: state) == expected)
        #expect(String(reflecting: state) == expected)
        #expect(!String(describing: state).contains("thought-signature-secret"))
        let mirroredValues = state.customMirror.children.map { String(describing: $0.value) }
        #expect(mirroredValues == ["google-gemini", "<redacted>"])
    }
}
