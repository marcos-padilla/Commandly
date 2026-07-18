import CommandKit
import Foundation

/// Semantic destination for one registration owned by Commandly's single Carbon shortcut monitor.
enum RuntimeGlobalShortcutRoute: Equatable, Sendable {
    case launcher
    case shelf(ShelfGlobalShortcut)
    case application(CommandID)
    case commandWheel(profileID: UUID, allowsContextOverride: Bool)
}

struct RuntimeGlobalShortcutBinding: Equatable, Sendable {
    let registration: GlobalShortcutRegistration
    let route: RuntimeGlobalShortcutRoute
}

/// Builds the deterministic app-lifetime registration order used for conflict ownership.
///
/// Existing fixed Commandly shortcuts are first, registered application shortcuts retain registry
/// order, and user wheel shortcuts follow profile order. A wheel therefore cannot silently steal an
/// existing launcher, Shelf, or application shortcut.
enum RuntimeGlobalShortcutCatalog {
    static let launcherID = GlobalShortcutID(rawValue: "runtime.launcher")

    static func bindings(
        applicationHotKeys: [(CommandID, LauncherHotKey)],
        wheelConfiguration: CommandWheelConfiguration
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

        result.append(contentsOf: ShelfGlobalShortcut.allCases.map { shortcut in
            RuntimeGlobalShortcutBinding(
                registration: GlobalShortcutRegistration(
                    id: GlobalShortcutID(
                        rawValue: "runtime.shelf.\(shortcut.commandID.rawValue)"
                    ),
                    hotKey: shortcut.hotKey
                ),
                route: .shelf(shortcut)
            )
        })

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

        guard wheelConfiguration.isEnabled else { return result }
        result.append(contentsOf: wheelConfiguration.profiles.compactMap { profile in
            guard profile.isEnabled, let hotKey = profile.shortcut else { return nil }
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
        return result
    }
}
