import Foundation

protocol WindowSwitcherConfigurationChoice: RawRepresentable where RawValue == String {
    var title: String { get }
}

enum WindowSwitcherShortcutMode: String, CaseIterable, Codable, Sendable, WindowSwitcherConfigurationChoice {
    case toggleOverlay
    case holdToCycle

    var title: String {
        switch self {
        case .toggleOverlay: return "Toggle Overlay"
        case .holdToCycle: return "Hold and Cycle"
        }
    }
}

enum WindowSwitcherFilterMode: String, CaseIterable, Codable, Sendable, WindowSwitcherConfigurationChoice {
    case allWindows
    case activeApplication
    case applications

    var title: String {
        switch self {
        case .allWindows: return "All Windows"
        case .activeApplication: return "Active Application"
        case .applications: return "Group by Application"
        }
    }
}

enum WindowSwitcherSortOrder: String, CaseIterable, Codable, Sendable, WindowSwitcherConfigurationChoice {
    case recentlyUsed
    case applicationName
    case windowTitle

    var title: String {
        switch self {
        case .recentlyUsed: return "Current Window Order"
        case .applicationName: return "Application Name"
        case .windowTitle: return "Window Title"
        }
    }
}

enum WindowSwitcherLayoutStyle: String, CaseIterable, Codable, Sendable, WindowSwitcherConfigurationChoice {
    case grid
    case list
    case strip

    var title: String { rawValue.capitalized }
}

enum WindowSwitcherItemSize: String, CaseIterable, Codable, Sendable, WindowSwitcherConfigurationChoice {
    case compact
    case regular
    case large

    var title: String { rawValue.capitalized }
}

enum WindowSwitcherThumbnailQuality: String, CaseIterable, Codable, Sendable, WindowSwitcherConfigurationChoice {
    case efficient
    case balanced
    case detailed

    var title: String { rawValue.capitalized }
}

enum WindowSwitcherPlacement: String, CaseIterable, Codable, Sendable, WindowSwitcherConfigurationChoice {
    case activeDisplay
    case pointerDisplay
    case mainDisplay

    var title: String {
        switch self {
        case .activeDisplay: return "Active Display"
        case .pointerDisplay: return "Pointer Display"
        case .mainDisplay: return "Main Display"
        }
    }
}

/// Non-secret behavior and appearance values resolved for one Window Switcher presentation.
struct WindowSwitcherConfiguration: Equatable, Sendable {
    var shortcutMode: WindowSwitcherShortcutMode = .holdToCycle
    var filterMode: WindowSwitcherFilterMode = .allWindows
    var sortOrder: WindowSwitcherSortOrder = .recentlyUsed
    var limitsToCurrentDesktop = true
    var limitsToCurrentDisplay = false
    var includesHiddenApplications = false
    var includesMinimizedWindows = true
    var includesWindowlessApplications = false
    var allowsSearch = true
    var allowsMouseSelection = true
    var allowsVimNavigation = false
    var layoutStyle: WindowSwitcherLayoutStyle = .grid
    var itemSize: WindowSwitcherItemSize = .regular
    var gridColumnCount = 4
    var showsWindowTitles = true
    var showsApplicationNames = true
    var showsWindowActions = true
    var showsThumbnails = true
    var usesLivePreviews = true
    var thumbnailCacheLimit = 48
    var thumbnailQuality: WindowSwitcherThumbnailQuality = .balanced
    var placement: WindowSwitcherPlacement = .activeDisplay
    var horizontalOffset = 0
    var verticalOffset = 0
    var showsDockPreviews = false
    var dockPreviewDelay = 0.35
    var replacesCommandTab = false
    var exclusionTerms: [String] = []

    static let `default` = WindowSwitcherConfiguration()

    init() {}

    init(settings: LauncherApplicationResolvedSettings) {
        self.init()
        applyInvocation(settings)
        applyWindowSet(settings)
        applyInteraction(settings)
        applyAppearance(settings)
        applyPreviews(settings)
        applyPlacementAndIntegrations(settings)
    }

    private static func selection<T: RawRepresentable>(
        _ type: T.Type,
        variable: String,
        settings: LauncherApplicationResolvedSettings,
        fallback: T
    ) -> T where T.RawValue == String {
        _ = type
        guard let rawValue = settings.value(for: variable)?.textValue else { return fallback }
        return T(rawValue: rawValue) ?? fallback
    }

    private static func boolean(
        _ variable: String,
        settings: LauncherApplicationResolvedSettings,
        fallback: Bool
    ) -> Bool {
        settings.value(for: variable)?.booleanValue ?? fallback
    }

    private static func integer(
        _ variable: String,
        settings: LauncherApplicationResolvedSettings,
        fallback: Int
    ) -> Int {
        settings.value(for: variable)?.integerValue ?? fallback
    }

    private static func decimal(
        _ variable: String,
        settings: LauncherApplicationResolvedSettings,
        fallback: Double
    ) -> Double {
        let value = settings.value(for: variable)?.decimalValue ?? fallback
        return value.isFinite ? value : fallback
    }

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func exclusionTerms(from value: String) -> [String] {
        let components = value.components(
            separatedBy: CharacterSet(charactersIn: ",\n\r")
        )
        var seen: Set<String> = []
        return components.compactMap { component in
            let term = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard term.isEmpty == false else { return nil }
            let comparisonKey = term.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(comparisonKey).inserted else { return nil }
            return term
        }
    }

    private typealias Variable = WindowSwitcherConfigurationVariable
}

private extension WindowSwitcherConfiguration {
    mutating func applyInvocation(_ settings: LauncherApplicationResolvedSettings) {
        shortcutMode = Self.selection(
            WindowSwitcherShortcutMode.self,
            variable: Variable.shortcutMode,
            settings: settings,
            fallback: shortcutMode
        )
        replacesCommandTab = Self.boolean(
            Variable.replaceCommandTab,
            settings: settings,
            fallback: replacesCommandTab
        )
    }

    mutating func applyWindowSet(_ settings: LauncherApplicationResolvedSettings) {
        filterMode = Self.selection(
            WindowSwitcherFilterMode.self,
            variable: Variable.filterMode,
            settings: settings,
            fallback: filterMode
        )
        sortOrder = Self.selection(
            WindowSwitcherSortOrder.self,
            variable: Variable.sortOrder,
            settings: settings,
            fallback: sortOrder
        )
        limitsToCurrentDesktop = Self.boolean(
            Variable.currentDesktopOnly,
            settings: settings,
            fallback: limitsToCurrentDesktop
        )
        limitsToCurrentDisplay = Self.boolean(
            Variable.currentDisplayOnly,
            settings: settings,
            fallback: limitsToCurrentDisplay
        )
        includesHiddenApplications = Self.boolean(
            Variable.includeHiddenApplications,
            settings: settings,
            fallback: includesHiddenApplications
        )
        includesMinimizedWindows = Self.boolean(
            Variable.includeMinimizedWindows,
            settings: settings,
            fallback: includesMinimizedWindows
        )
        includesWindowlessApplications = Self.boolean(
            Variable.includeWindowlessApplications,
            settings: settings,
            fallback: includesWindowlessApplications
        )
    }

    mutating func applyInteraction(_ settings: LauncherApplicationResolvedSettings) {
        allowsSearch = Self.boolean(
            Variable.searchEnabled,
            settings: settings,
            fallback: allowsSearch
        )
        allowsMouseSelection = Self.boolean(
            Variable.mouseSelectionEnabled,
            settings: settings,
            fallback: allowsMouseSelection
        )
        allowsVimNavigation = Self.boolean(
            Variable.vimNavigationEnabled,
            settings: settings,
            fallback: allowsVimNavigation
        )
    }

    mutating func applyAppearance(_ settings: LauncherApplicationResolvedSettings) {
        layoutStyle = Self.selection(
            WindowSwitcherLayoutStyle.self,
            variable: Variable.layoutStyle,
            settings: settings,
            fallback: layoutStyle
        )
        itemSize = Self.selection(
            WindowSwitcherItemSize.self,
            variable: Variable.itemSize,
            settings: settings,
            fallback: itemSize
        )
        gridColumnCount = Self.clamp(
            Self.integer(Variable.gridColumnCount, settings: settings, fallback: gridColumnCount),
            to: 2...8
        )
        showsWindowTitles = Self.boolean(
            Variable.showWindowTitles,
            settings: settings,
            fallback: showsWindowTitles
        )
        showsApplicationNames = Self.boolean(
            Variable.showApplicationNames,
            settings: settings,
            fallback: showsApplicationNames
        )
        showsWindowActions = Self.boolean(
            Variable.showWindowActions,
            settings: settings,
            fallback: showsWindowActions
        )
    }

    mutating func applyPreviews(_ settings: LauncherApplicationResolvedSettings) {
        showsThumbnails = Self.boolean(
            Variable.showThumbnails,
            settings: settings,
            fallback: showsThumbnails
        )
        usesLivePreviews = Self.boolean(
            Variable.livePreviewsEnabled,
            settings: settings,
            fallback: usesLivePreviews
        )
        thumbnailCacheLimit = Self.clamp(
            Self.integer(
                Variable.thumbnailCacheLimit,
                settings: settings,
                fallback: thumbnailCacheLimit
            ),
            to: 0...200
        )
        thumbnailQuality = Self.selection(
            WindowSwitcherThumbnailQuality.self,
            variable: Variable.thumbnailQuality,
            settings: settings,
            fallback: thumbnailQuality
        )
    }

    mutating func applyPlacementAndIntegrations(
        _ settings: LauncherApplicationResolvedSettings
    ) {
        placement = Self.selection(
            WindowSwitcherPlacement.self,
            variable: Variable.placement,
            settings: settings,
            fallback: placement
        )
        horizontalOffset = Self.clamp(
            Self.integer(
                Variable.horizontalOffset,
                settings: settings,
                fallback: horizontalOffset
            ),
            to: -600...600
        )
        verticalOffset = Self.clamp(
            Self.integer(
                Variable.verticalOffset,
                settings: settings,
                fallback: verticalOffset
            ),
            to: -600...600
        )
        showsDockPreviews = Self.boolean(
            Variable.dockPreviewsEnabled,
            settings: settings,
            fallback: showsDockPreviews
        )
        dockPreviewDelay = Self.clamp(
            Self.decimal(
                Variable.dockPreviewDelay,
                settings: settings,
                fallback: dockPreviewDelay
            ),
            to: 0...3
        )
        exclusionTerms = Self.exclusionTerms(
            from: settings.value(for: Variable.exclusionTerms)?.textValue ?? ""
        )
    }
}
