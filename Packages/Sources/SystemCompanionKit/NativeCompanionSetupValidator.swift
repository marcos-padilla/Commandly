import Darwin
import Foundation
import Infrastructure
import Security

/// Validates the independent owner and its sealed, narrowly configured LaunchAgent off the UI actor.
/// It requires the approved embedded relationship, exact code signatures/builds, and a nonsandboxed owner.
public actor NativeCompanionSetupValidator: CompanionInstallationValidating {
    private let helperURL: URL
    public init(helperURL: URL = Bundle.main.bundleURL) { self.helperURL = helperURL }
    public func validate() throws -> String {
        let policy = try CompanionSigningPolicy()
        try policy.validateCurrentProcess(as: .helper)
        _ = try CompanionUserSession.current()
        try policy.validateBundle(at: helperURL, as: .helper)
        var parent = helperURL
        for _ in 0..<4 { parent.deleteLastPathComponent() }
        guard parent.appendingPathComponent(CompanionIdentity.helperRelativePath, isDirectory: true).standardizedFileURL == helperURL.standardizedFileURL else {
            throw CompanionError.invalidConfiguration
        }
        try policy.validateBundle(at: parent, as: .application)
        guard try sandboxEntitlement(at: parent), try sandboxEntitlement(at: helperURL) == false else {
            throw CompanionError.invalidConfiguration
        }
        guard let helper = Bundle(url: helperURL), let main = Bundle(url: parent),
              let build = helper.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let parentBuild = main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              build == parentBuild, CompanionWireCodec.validBuild(build) else { throw CompanionError.versionMismatch }
        let plist = helperURL.appendingPathComponent("Contents/Library/LaunchAgents/" + CompanionIdentity.agentPlist)
        try CompanionSetupManifest.validate(CompanionSetupManifestReader.read(at: plist))
        return build
    }
    private func sandboxEntitlement(at url: URL) throws -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { throw CompanionError.invalidSignature }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { throw CompanionError.invalidSignature }
        let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        return entitlements["com.apple.security.app-sandbox"] as? Bool == true
    }
}

/// Open and inspect one actual file descriptor; a swapped symlink/FIFO must not redirect or block setup.
/// The read limit also applies after the size check, including a concurrent file growth race.
enum CompanionSetupManifestReader {
    static func read(at url: URL) throws -> Data {
        guard url.isFileURL else { throw CompanionError.invalidConfiguration }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw CompanionError.invalidConfiguration }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let result: Result<Data, any Error>
        do {
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  info.st_size > 0, info.st_size <= 16_384 else { throw CompanionError.invalidConfiguration }
            let data = try handle.read(upToCount: 16_385) ?? Data()
            guard data.count <= 16_384 else { throw CompanionError.oversizedMessage }
            result = .success(data)
        } catch { result = .failure(error) }
        do { try handle.close() } catch { throw CompanionError.invalidConfiguration }
        do { return try result.get() }
        catch let error as CompanionError { throw error }
        catch { throw CompanionError.invalidConfiguration }
    }
}
