import Foundation
import Infrastructure
import Security

nonisolated enum CleanShotCodeSignature {
    // Authoritative evidence: signed official CleanShot X 4.8.10 release, inspected read-only
    // on 2026-09-14. Both bundle ID and team are pinned; a matching name/scheme is insufficient.
    static let requirementText = "anchor apple generic and identifier \"pl.maketheweb.cleanshotx\" and certificate leaf[subject.OU] = \"AFJU4P8ZV4\""

    /// Blocking signature inspection runs only from the bundle-inspector actor after explicit
    /// handoff intent. Network access flags are deliberately absent; no revocation fetch is asked for.
    static func validate(_ application: URL) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(application as CFURL, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let code, let requirement else { throw ScreenshotAnnotationError.unexpectedApplication }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw ScreenshotAnnotationError.unexpectedApplication
        }
    }
}
