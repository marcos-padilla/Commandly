import Foundation

extension WindowSwitcherConfiguration {
    static let schema: [LauncherConfigurationField] =
        invocationFields
        + windowSetFields
        + interactionFields
        + appearanceFields
        + labelAndActionFields
        + previewFields
        + placementFields
        + dockFields
        + exclusionFields
}

private extension WindowSwitcherConfiguration {
    typealias Field = WindowSwitcherConfigurationFieldFactory
    typealias Section = WindowSwitcherConfigurationSection
    typealias Variable = WindowSwitcherConfigurationVariable

    static let invocationFields = [
        Field.selection(
            "shortcut-mode", Variable.shortcutMode, "Shortcut behavior",
            section: Section.invocation, defaultValue: WindowSwitcherShortcutMode.holdToCycle,
            values: WindowSwitcherShortcutMode.allCases,
            description: "Choose whether a shortcut toggles the switcher or cycles while held."
        ),
        Field.toggle(
            "replace-command-tab", Variable.replaceCommandTab, "Replace Command-Tab",
            section: Section.invocation, defaultValue: false,
            description: "Use the Window Switcher for the standard macOS application shortcut."
        ),
    ]

    static let windowSetFields = [
        Field.selection(
            "filter-mode", Variable.filterMode, "Window scope",
            section: Section.windowSet, defaultValue: WindowSwitcherFilterMode.allWindows,
            values: WindowSwitcherFilterMode.allCases,
            description: "Show individual windows, the active application, or application groups."
        ),
        Field.selection(
            "sort-order", Variable.sortOrder, "Sort order",
            section: Section.windowSet, defaultValue: WindowSwitcherSortOrder.recentlyUsed,
            values: WindowSwitcherSortOrder.allCases,
            description: "Keep the focused window first and preserve the system adapter's order, "
                + "or sort by application or title."
        ),
        Field.toggle(
            "current-desktop-only", Variable.currentDesktopOnly, "Current desktop only",
            section: Section.windowSet, defaultValue: true,
            description: "Best-effort filter using public current-desktop window information."
        ),
        Field.toggle(
            "current-display-only", Variable.currentDisplayOnly, "Current display only",
            section: Section.windowSet, defaultValue: false,
            description: "Exclude windows that do not intersect the selected display."
        ),
        Field.toggle(
            "include-hidden-applications", Variable.includeHiddenApplications,
            "Include hidden applications", section: Section.windowSet, defaultValue: false
        ),
        Field.toggle(
            "include-minimized-windows", Variable.includeMinimizedWindows,
            "Include minimized windows", section: Section.windowSet, defaultValue: true
        ),
        Field.toggle(
            "include-windowless-applications", Variable.includeWindowlessApplications,
            "Include applications without windows", section: Section.windowSet,
            defaultValue: false,
            description: "Offer running applications that currently have no selectable window."
        ),
    ]

    static let interactionFields = [
        Field.toggle(
            "search-enabled", Variable.searchEnabled, "Type to search",
            section: Section.interaction, defaultValue: true
        ),
        Field.toggle(
            "mouse-selection-enabled", Variable.mouseSelectionEnabled,
            "Select on pointer hover", section: Section.interaction, defaultValue: true,
            description: "Move selection as the pointer crosses items; clicking remains available."
        ),
        Field.toggle(
            "vim-navigation-enabled", Variable.vimNavigationEnabled, "Vim navigation",
            section: Section.interaction, defaultValue: false,
            description: "Navigate with H, J, K, and L while search is not accepting text."
        ),
    ]

    static let appearanceFields = [
        Field.selection(
            "layout-style", Variable.layoutStyle, "Layout",
            section: Section.appearance, defaultValue: WindowSwitcherLayoutStyle.grid,
            values: WindowSwitcherLayoutStyle.allCases
        ),
        Field.selection(
            "item-size", Variable.itemSize, "Item size",
            section: Section.appearance, defaultValue: WindowSwitcherItemSize.regular,
            values: WindowSwitcherItemSize.allCases
        ),
        Field.integer(
            "grid-column-count", Variable.gridColumnCount, "Grid columns",
            section: Section.appearance, defaultValue: 4, range: 2...8, step: 1
        ),
    ]

    static let labelAndActionFields = [
        Field.toggle(
            "show-window-titles", Variable.showWindowTitles, "Window titles",
            section: Section.labelsAndActions, defaultValue: true
        ),
        Field.toggle(
            "show-application-names", Variable.showApplicationNames, "Application names",
            section: Section.labelsAndActions, defaultValue: true
        ),
        Field.toggle(
            "show-window-actions", Variable.showWindowActions, "Window action controls",
            section: Section.labelsAndActions, defaultValue: true,
            description: "Show explicit window and application actions when available."
        ),
    ]

    static let previewFields = [
        Field.toggle(
            "show-thumbnails", Variable.showThumbnails, "Window thumbnails",
            section: Section.previews, defaultValue: true,
            description: "Use metadata-only cards when Screen Recording access is unavailable."
        ),
        Field.toggle(
            "live-previews-enabled", Variable.livePreviewsEnabled, "Live previews",
            section: Section.previews, defaultValue: true,
            description: "Refresh visible thumbnails while the switcher is open."
        ),
        Field.integer(
            "thumbnail-cache-limit", Variable.thumbnailCacheLimit, "Thumbnail cache limit",
            section: Section.previews, defaultValue: 48, range: 0...200, step: 8,
            description: "Maximum in-memory previews. Set to zero to disable reuse."
        ),
        Field.selection(
            "thumbnail-quality", Variable.thumbnailQuality, "Thumbnail quality",
            section: Section.previews,
            defaultValue: WindowSwitcherThumbnailQuality.balanced,
            values: WindowSwitcherThumbnailQuality.allCases
        ),
    ]

    static let placementFields = [
        Field.selection(
            "placement", Variable.placement, "Display placement",
            section: Section.placement, defaultValue: WindowSwitcherPlacement.activeDisplay,
            values: WindowSwitcherPlacement.allCases
        ),
        Field.integer(
            "horizontal-offset", Variable.horizontalOffset, "Horizontal offset",
            section: Section.placement, defaultValue: 0, range: -600...600, step: 10,
            description: "Move the panel left or right from its selected display anchor."
        ),
        Field.integer(
            "vertical-offset", Variable.verticalOffset, "Vertical offset",
            section: Section.placement, defaultValue: 0, range: -600...600, step: 10,
            description: "Move the panel down or up from its selected display anchor."
        ),
    ]

    static let dockFields = [
        Field.toggle(
            "dock-previews-enabled", Variable.dockPreviewsEnabled, "Dock window previews",
            section: Section.dockIntegration, defaultValue: false,
            description: "Show an application's windows after resting on its Dock icon."
        ),
        Field.decimal(
            "dock-preview-delay", Variable.dockPreviewDelay, "Dock preview delay",
            section: Section.dockIntegration, defaultValue: 0.35, range: 0...3, step: 0.05,
            description: "Seconds before a Dock preview appears."
        ),
    ]

    static let exclusionFields = [
        LauncherConfigurationField(
            id: "exclusion-terms",
            variable: Variable.exclusionTerms,
            title: "Exclusion terms",
            description: "Application names, exact bundle identifiers, and window-title terms.",
            placeholder: "Example App, com.example.utility",
            section: Section.exclusions,
            kind: .text,
            defaultValue: .text("")
        ),
    ]
}

private enum WindowSwitcherConfigurationSection {
    static let invocation = "Invocation"
    static let windowSet = "Window Set"
    static let interaction = "Interaction"
    static let appearance = "Grid, List & Strip"
    static let labelsAndActions = "Labels & Actions"
    static let previews = "Thumbnails & Live Preview"
    static let placement = "Placement"
    static let dockIntegration = "Dock Previews"
    static let exclusions = "Exclusions"
}

enum WindowSwitcherConfigurationVariable {
    static let shortcutMode = "shortcutMode"
    static let filterMode = "filterMode"
    static let sortOrder = "sortOrder"
    static let currentDesktopOnly = "currentDesktopOnly"
    static let currentDisplayOnly = "currentDisplayOnly"
    static let includeHiddenApplications = "includeHiddenApplications"
    static let includeMinimizedWindows = "includeMinimizedWindows"
    static let includeWindowlessApplications = "includeWindowlessApplications"
    static let searchEnabled = "searchEnabled"
    static let mouseSelectionEnabled = "mouseSelectionEnabled"
    static let vimNavigationEnabled = "vimNavigationEnabled"
    static let layoutStyle = "layoutStyle"
    static let itemSize = "itemSize"
    static let gridColumnCount = "gridColumnCount"
    static let showWindowTitles = "showWindowTitles"
    static let showApplicationNames = "showApplicationNames"
    static let showWindowActions = "showWindowActions"
    static let showThumbnails = "showThumbnails"
    static let livePreviewsEnabled = "livePreviewsEnabled"
    static let thumbnailCacheLimit = "thumbnailCacheLimit"
    static let thumbnailQuality = "thumbnailQuality"
    static let placement = "placement"
    static let horizontalOffset = "horizontalOffset"
    static let verticalOffset = "verticalOffset"
    static let dockPreviewsEnabled = "dockPreviewsEnabled"
    static let dockPreviewDelay = "dockPreviewDelay"
    static let replaceCommandTab = "replaceCommandTab"
    static let exclusionTerms = "exclusionTerms"
}

private enum WindowSwitcherConfigurationFieldFactory {
    static func toggle(
        _ id: String,
        _ variable: String,
        _ title: String,
        section: String,
        defaultValue: Bool,
        description: String? = nil
    ) -> LauncherConfigurationField {
        LauncherConfigurationField(
            id: id,
            variable: variable,
            title: title,
            description: description,
            section: section,
            kind: .toggle,
            defaultValue: .boolean(defaultValue)
        )
    }

    static func integer(
        _ id: String,
        _ variable: String,
        _ title: String,
        section: String,
        defaultValue: Int,
        range: ClosedRange<Int>,
        step: Int,
        description: String? = nil
    ) -> LauncherConfigurationField {
        LauncherConfigurationField(
            id: id,
            variable: variable,
            title: title,
            description: description,
            section: section,
            kind: .integer,
            defaultValue: .integer(defaultValue),
            minimumValue: Double(range.lowerBound),
            maximumValue: Double(range.upperBound),
            step: Double(step)
        )
    }

    static func decimal(
        _ id: String,
        _ variable: String,
        _ title: String,
        section: String,
        defaultValue: Double,
        range: ClosedRange<Double>,
        step: Double,
        description: String? = nil
    ) -> LauncherConfigurationField {
        LauncherConfigurationField(
            id: id,
            variable: variable,
            title: title,
            description: description,
            section: section,
            kind: .decimal,
            defaultValue: .decimal(defaultValue),
            minimumValue: range.lowerBound,
            maximumValue: range.upperBound,
            step: step
        )
    }

    static func selection<T: WindowSwitcherConfigurationChoice>(
        _ id: String,
        _ variable: String,
        _ title: String,
        section: String,
        defaultValue: T,
        values: [T],
        description: String? = nil
    ) -> LauncherConfigurationField {
        LauncherConfigurationField(
            id: id,
            variable: variable,
            title: title,
            description: description,
            section: section,
            kind: .selection,
            defaultValue: .text(defaultValue.rawValue),
            options: values.map {
                LauncherConfigurationOption(id: $0.rawValue, title: $0.title)
            }
        )
    }
}
