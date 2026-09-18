import CommandKit
import Foundation

/// Semantic destination for one registration owned by Commandly's single Carbon shortcut monitor.
enum RuntimeGlobalShortcutRoute: Equatable, Sendable {
    case launcher
    case application(CommandID)
    case installedApplication(bundleIdentifier: String)
    case commandWheel(profileID: UUID, allowsContextOverride: Bool)
    /// Moves the system audio output to the next device in the mixer's chosen cycle.
    case soundOutputCycle
}

struct RuntimeGlobalShortcutBinding: Equatable, Sendable {
    let registration: GlobalShortcutRegistration
    let route: RuntimeGlobalShortcutRoute
}

/// Builds the deterministic app-lifetime registration order used for conflict ownership.
///
/// The launcher shortcut is first, registered application and tool shortcuts retain registry
/// order, and user wheel shortcuts follow profile order. A wheel therefore cannot silently steal an
/// existing launcher, application, or tool shortcut. Installed-app shortcuts follow all existing
/// categories, retaining the caller’s successful-owner order to prevent silent reassignment.
enum RuntimeGlobalShortcutCatalog {
    static let launcherID = GlobalShortcutID(rawValue: "runtime.launcher")
    static let soundOutputCycleID = GlobalShortcutID(rawValue: "runtime.sound-output-cycle")

    /// Default shortcut for cycling the system output. Registered only while the mixer
    /// preference asks for it, so it never holds a key combination the user did not opt into.
    static let soundOutputCycleHotKey = LauncherHotKey(keyCode: 1, modifiers: [.control, .option])

    static func bindings(
        applicationHotKeys: [(CommandID, LauncherHotKey)],
        wheelConfiguration: CommandWheelConfiguration,
        installedApplicationHotKeys: [(String, LauncherHotKey)] = [],
        cyclesSoundOutput: Bool = false
    ) -> [RuntimeGlobalShortcutBinding] {
        var result = [
            RuntimeGlobalShortcutBinding(
                registration: GlobalShortcutRegistration(
                    id: launcherID,
                    hotKey: LauncherHotKey(keyCode: 49, modifiers: .option)
                ),
                route: .launcher
            ),
        ]

        result.append(contentsOf: applicationHotKeys.map { commandID, hotKey in
            RuntimeGlobalShortcutBinding(
                registration: GlobalShortcutRegistration(
                    id: GlobalShortcutID(
                        rawValue: "runtime.application.\(commandID.rawValue)"
                    ),
                    hotKey: hotKey
                ),
                route: .application(commandID)
            )
        })

        result.append(contentsOf: wheelConfiguration.profiles.compactMap { profile in
            guard wheelConfiguration.isEnabled, profile.isEnabled, let hotKey = profile.shortcut else { return nil }
            return RuntimeGlobalShortcutBinding(
                registration: GlobalShortcutRegistration(
                    id: GlobalShortcutID(
                        rawValue: "runtime.command-wheel.\(profile.id.uuidString.lowercased())"
                    ),
                    hotKey: hotKey
                ),
                route: .commandWheel(
                    profileID: profile.id,
                    allowsContextOverride:
                        wheelConfiguration.contextAwareProfileSelectionEnabled
                            && profile.id == wheelConfiguration.defaultProfileID
                )
            )
        })
        result.append(contentsOf: installedApplicationHotKeys.map { bundleID, hotKey in
            RuntimeGlobalShortcutBinding(
                registration: GlobalShortcutRegistration(
                    id: installedApplicationID(bundleID), hotKey: hotKey
                ),
                route: .installedApplication(bundleIdentifier: bundleID)
            )
        })
        if cyclesSoundOutput {
            result.append(
                RuntimeGlobalShortcutBinding(
                    registration: GlobalShortcutRegistration(
                        id: soundOutputCycleID,
                        hotKey: soundOutputCycleHotKey
                    ),
                    route: .soundOutputCycle
                )
            )
        }
        return result
    }

    static func installedApplicationID(_ bundleID: String) -> GlobalShortcutID {
        GlobalShortcutID(rawValue: "runtime.installed-application.\(bundleID)")
    }
}
