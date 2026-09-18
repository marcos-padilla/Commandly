import Foundation
import Infrastructure

/// Closed, signed LaunchAgent layout owned by the companion app, not by its sandboxed container.
public enum CompanionSetupManifest {
    public static let program = "Contents/MacOS/CommandlySystemCompanion"
    public static let arguments = ["CommandlySystemCompanion", "--service"]
    public static func validate(_ data: Data) throws {
        guard data.count <= 16_384 else { throw CompanionError.oversizedMessage }
        let decoded: Any
        do { decoded = try PropertyListSerialization.propertyList(from: data, format: nil) }
        catch { throw CompanionError.invalidConfiguration }
        guard let value = decoded as? [String: Any],
              Set(value.keys) == Set(["Label", "BundleProgram", "ProgramArguments", "MachServices", "LimitLoadToSessionType", "ProcessType"]),
              value["Label"] as? String == CompanionIdentity.helper,
              value["BundleProgram"] as? String == program,
              value["ProgramArguments"] as? [String] == arguments,
              value["MachServices"] as? [String: Bool] == [CompanionIdentity.machService: true],
              value["LimitLoadToSessionType"] as? String == "Aqua",
              value["ProcessType"] as? String == "Interactive" else { throw CompanionError.invalidConfiguration }
    }
}
/// A normal macOS application launch opens setup. Only the signed LaunchAgent passes --service.
public enum CompanionLaunchMode: Equatable, Sendable {
    case setup, service
    public static func resolve(arguments: [String]) throws -> Self {
        if arguments.isEmpty || arguments == ["--setup"] { return .setup }
        if arguments == ["--service"] { return .service }
        throw CompanionError.invalidConfiguration
    }
}
