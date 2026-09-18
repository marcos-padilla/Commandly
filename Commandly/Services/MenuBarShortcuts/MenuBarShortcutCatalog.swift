import CommandKit
import Foundation

@MainActor
enum MenuBarShortcutCatalog {
    static func items(in registry: LauncherApplicationRegistry) -> [MenuBarShortcutItem] {
        registry.allDefinitions().compactMap { definition in
            guard registry.isLaunchableCommand(definition.id) else { return nil }
            let owner = registry.owningApplicationID(for: definition.id).flatMap { registry.definition(for: $0) }
            let subtitle = owner?.id == definition.id ? (definition.subtitle ?? "Application")
                : (owner?.title ?? "Tool")
            return MenuBarShortcutItem(id: definition.id, title: definition.title,
                subtitle: subtitle, systemImage: definition.systemImage,
                isEnabled: registry.isEffectivelyEnabled(definition.id))
        }.sorted {
            let comparison = $0.title.localizedStandardCompare($1.title)
            return comparison == .orderedSame ? $0.id.rawValue < $1.id.rawValue : comparison == .orderedAscending
        }
    }
}
