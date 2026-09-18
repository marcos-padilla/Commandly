import Foundation
import Infrastructure
import Security

/// Validates the current signed app and its embedded helper off the UI actor, before registration or IPC.
public actor NativeCompanionInstallationValidator: CompanionInstallationValidating {
    private let applicationURL: URL
    public init(applicationURL: URL) { self.applicationURL = applicationURL }
    public func validate() throws -> String {
        let policy = try CompanionSigningPolicy()
        try policy.validateCurrentProcess(as: .application)
        try policy.validateBundle(at: applicationURL, as: .application)
        let helperURL = applicationURL.appendingPathComponent(CompanionIdentity.helperRelativePath, isDirectory: true)
        try policy.validateBundle(at: helperURL, as: .helper)
        try validateEntitlements(applicationURL: applicationURL, helperURL: helperURL)
        // Profile presence is a preflight prerequisite, not a claim of Apple authorization or live IPC success.
        let profile = applicationURL.appendingPathComponent("Contents/embedded.provisionprofile")
        guard FileManager.default.fileExists(atPath: profile.path) else { throw CompanionError.missingProvisioningProfile }
        guard let app = Bundle(url: applicationURL), let helper = Bundle(url: helperURL),
              let appBuild = app.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let helperBuild = helper.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              CompanionWireCodec.validBuild(appBuild), appBuild == helperBuild else { throw CompanionError.versionMismatch }
        return appBuild
    }
    private func validateEntitlements(applicationURL: URL, helperURL: URL) throws {
        let app = try entitlements(at: applicationURL)
        let helper = try entitlements(at: helperURL)
        guard app["com.apple.security.app-sandbox"] as? Bool == true,
              (app["com.apple.security.application-groups"] as? [String])?.contains(CompanionIdentity.appGroup) == true,
              helper["com.apple.security.app-sandbox"] as? Bool != true else { throw CompanionError.invalidConfiguration }
    }
    private func entitlements(at url: URL) throws -> [String: Any] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { throw CompanionError.invalidSignature }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { throw CompanionError.invalidSignature }
        return info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
    }
}
