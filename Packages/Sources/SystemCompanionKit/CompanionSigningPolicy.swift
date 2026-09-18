import Darwin
import Foundation
import Infrastructure
import Security

/// Release identities are compiled, not accepted from IPC, environment variables, or caller-supplied paths.
public enum CompanionIdentity {
    public static let team = "RLF9X72HRT"
    public static let app = "com.businessmate360.Commandly"
    public static let helper = "com.businessmate360.Commandly.SystemCompanion"
    public static let appGroup = "group.com.businessmate360.Commandly"
    public static let machService = "group.com.businessmate360.Commandly.SystemCompanion"
    public static let agentPlist = "com.businessmate360.Commandly.SystemCompanion.plist"
    public static let helperRelativePath = "Contents/Library/Helpers/CommandlySystemCompanion.app"
}
/// Expected side of the authenticated channel.
public enum CompanionPeerRole: Sendable { case application, helper }
/// Kernel-reported user and login audit session, not client assertions or PID-based signature checks.
public struct CompanionUserSession: Equatable, Sendable {
    public let effectiveUser: UInt32
    public let auditSession: Int32
    public init(effectiveUser: UInt32, auditSession: Int32) { self.effectiveUser = effectiveUser; self.auditSession = auditSession }
    public func permits(_ peer: CompanionUserSession) -> Bool { effectiveUser != 0 && auditSession != -1 && self == peer }
    public static func current() throws -> Self {
        var audit = auditinfo_addr()
        guard geteuid() != 0, getaudit_addr(&audit, Int32(MemoryLayout<auditinfo_addr>.size)) == 0 else { throw CompanionError.wrongUserSession }
        let value = Self(effectiveUser: geteuid(), auditSession: audit.ai_asid)
        guard value.permits(value) else { throw CompanionError.wrongUserSession }
        return value
    }
}
/// Validates syntax once before Foundation's setter, which raises an exception for malformed requirements.
public struct CompanionSigningPolicy: Sendable {
    public let applicationRequirement: String
    public let helperRequirement: String
    public init() throws {
        applicationRequirement = try Self.requirement(team: CompanionIdentity.team, bundle: CompanionIdentity.app)
        helperRequirement = try Self.requirement(team: CompanionIdentity.team, bundle: CompanionIdentity.helper)
    }
    public func requirement(for role: CompanionPeerRole) -> String { role == .application ? applicationRequirement : helperRequirement }
    public static func requirement(team: String, bundle: String) throws -> String {
        guard team.utf8.count == 10, team.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }),
              bundle.isEmpty == false, bundle.utf8.count <= 200,
              bundle.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 46 || $0 == 45 }) else {
            throw CompanionError.invalidConfiguration
        }
        let source = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(bundle)\""
        _ = try validatedRequirement(source)
        return source
    }
    public func validateCurrentProcess(as role: CompanionPeerRole) throws {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, [], try Self.validatedRequirement(requirement(for: role))) == errSecSuccess else {
            throw CompanionError.invalidSignature
        }
    }
    public func validateBundle(at url: URL, as role: CompanionPeerRole) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
                try Self.validatedRequirement(requirement(for: role))) == errSecSuccess else { throw CompanionError.invalidSignature }
    }
    private static func validatedRequirement(_ source: String) throws -> SecRequirement {
        var value: SecRequirement?
        guard SecRequirementCreateWithString(source as CFString, [], &value) == errSecSuccess, let value else {
            throw CompanionError.invalidConfiguration
        }
        return value
    }
}
