import Foundation

/// Non-secret volume mixer preferences.
nonisolated struct VolumeMixerSettings: Equatable, Sendable {
    /// Keeps idle apps off the list. Rows with a custom volume or output stay visible anyway.
    var hidesInactiveApplications: Bool
    /// The Finder keeps its own visibility switch, from when it was the only hideable row.
    var showsFinder: Bool
    /// Turns the speakers down when headphones go away, so sound never bursts out of them.
    var lowersVolumeOnHeadphonesDisconnect: Bool
    /// The level, as a percentage, the speakers are set to on a headphone disconnect.
    var headphonesDisconnectVolumePercent: Int
    /// Turns the volume keys into macOS' fine volume step.
    var usesFinerVolumeSteps: Bool
    /// Cycles the system output through `switcherDeviceUIDs` on a shortcut.
    var switchesOutputsWithShortcut: Bool
    /// The outputs the shortcut cycles through, in order.
    var switcherDeviceUIDs: [String]

    static let `default` = VolumeMixerSettings(
        hidesInactiveApplications: false,
        showsFinder: true,
        lowersVolumeOnHeadphonesDisconnect: false,
        headphonesDisconnectVolumePercent: 30,
        usesFinerVolumeSteps: false,
        switchesOutputsWithShortcut: false,
        switcherDeviceUIDs: []
    )

    /// Percentages offered by the headphone-disconnect picker.
    static let allowedDisconnectVolumePercents = [0, 10, 20, 30, 40, 50]

    static func sanitizedDisconnectVolumePercent(_ percent: Int) -> Int {
        allowedDisconnectVolumePercents.contains(percent) ? percent : `default`.headphonesDisconnectVolumePercent
    }
}

/// Persists volume mixer preferences and the per-application volumes and routes.
///
/// Per-application values are kept apart from `VolumeMixerSettings`: they are maps keyed by
/// bundle identifier that change on every slider drag, so they are read and written on their own
/// rather than round-tripping the whole settings value.
protocol VolumeMixerSettingsStoring: AnyObject, Sendable {
    func load() -> VolumeMixerSettings
    func save(_ settings: VolumeMixerSettings)

    /// Volume per persistence id, `0...2`. A row at unity is absent rather than stored as `1`.
    func applicationVolumes() -> [String: Double]
    func saveApplicationVolumes(_ volumes: [String: Double])

    /// Output device uid per persistence id. A row following the default output is absent.
    func applicationRoutes() -> [String: String]
    func saveApplicationRoutes(_ routes: [String: String])

    /// Persistence id to display name for the apps taken off the list.
    func hiddenApplications() -> [String: String]
    func saveHiddenApplications(_ hidden: [String: String])
}

/// UserDefaults-backed mixer preference store.
///
/// `@unchecked Sendable`: `UserDefaults` is safe for concurrent simple get/set; this type only
/// reads and writes scalar preferences and small property-list maps.
final class UserDefaultsVolumeMixerSettingsStore: VolumeMixerSettingsStoring, @unchecked Sendable {
    private enum Key {
        static let hidesInactiveApplications = "mixer.hidesInactiveApplications"
        static let showsFinder = "mixer.showsFinder"
        static let lowersVolumeOnHeadphonesDisconnect = "mixer.lowersVolumeOnHeadphonesDisconnect"
        static let headphonesDisconnectVolumePercent = "mixer.headphonesDisconnectVolumePercent"
        static let usesFinerVolumeSteps = "mixer.usesFinerVolumeSteps"
        static let switchesOutputsWithShortcut = "mixer.switchesOutputsWithShortcut"
        static let switcherDeviceUIDs = "mixer.switcherDeviceUIDs"
        static let applicationVolumes = "mixer.applicationVolumes"
        static let applicationRoutes = "mixer.applicationRoutes"
        static let hiddenApplications = "mixer.hiddenApplications"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> VolumeMixerSettings {
        let fallback = VolumeMixerSettings.default
        let storedShowsFinder = defaults.object(forKey: Key.showsFinder) as? Bool
        let storedPercent = defaults.object(forKey: Key.headphonesDisconnectVolumePercent) as? Int

        return VolumeMixerSettings(
            hidesInactiveApplications: defaults.bool(forKey: Key.hidesInactiveApplications),
            showsFinder: storedShowsFinder ?? fallback.showsFinder,
            lowersVolumeOnHeadphonesDisconnect: defaults.bool(
                forKey: Key.lowersVolumeOnHeadphonesDisconnect
            ),
            headphonesDisconnectVolumePercent: VolumeMixerSettings.sanitizedDisconnectVolumePercent(
                storedPercent ?? fallback.headphonesDisconnectVolumePercent
            ),
            usesFinerVolumeSteps: defaults.bool(forKey: Key.usesFinerVolumeSteps),
            switchesOutputsWithShortcut: defaults.bool(forKey: Key.switchesOutputsWithShortcut),
            switcherDeviceUIDs: MixerRoutingRules.sanitizedDeviceUIDList(
                defaults.array(forKey: Key.switcherDeviceUIDs) ?? []
            )
        )
    }

    func save(_ settings: VolumeMixerSettings) {
        defaults.set(settings.hidesInactiveApplications, forKey: Key.hidesInactiveApplications)
        defaults.set(settings.showsFinder, forKey: Key.showsFinder)
        defaults.set(
            settings.lowersVolumeOnHeadphonesDisconnect,
            forKey: Key.lowersVolumeOnHeadphonesDisconnect
        )
        defaults.set(
            VolumeMixerSettings.sanitizedDisconnectVolumePercent(
                settings.headphonesDisconnectVolumePercent
            ),
            forKey: Key.headphonesDisconnectVolumePercent
        )
        defaults.set(settings.usesFinerVolumeSteps, forKey: Key.usesFinerVolumeSteps)
        defaults.set(settings.switchesOutputsWithShortcut, forKey: Key.switchesOutputsWithShortcut)
        let uids = MixerRoutingRules.sanitizedDeviceUIDList(settings.switcherDeviceUIDs)
        if uids.isEmpty {
            defaults.removeObject(forKey: Key.switcherDeviceUIDs)
        } else {
            defaults.set(uids, forKey: Key.switcherDeviceUIDs)
        }
    }

    func applicationVolumes() -> [String: Double] {
        MixerRoutingRules.sanitizedVolumeMap(defaults.dictionary(forKey: Key.applicationVolumes) ?? [:])
    }

    func saveApplicationVolumes(_ volumes: [String: Double]) {
        if volumes.isEmpty {
            defaults.removeObject(forKey: Key.applicationVolumes)
        } else {
            defaults.set(volumes, forKey: Key.applicationVolumes)
        }
    }

    func applicationRoutes() -> [String: String] {
        MixerRoutingRules.sanitizedRouteMap(defaults.dictionary(forKey: Key.applicationRoutes) ?? [:])
    }

    func saveApplicationRoutes(_ routes: [String: String]) {
        if routes.isEmpty {
            defaults.removeObject(forKey: Key.applicationRoutes)
        } else {
            defaults.set(routes, forKey: Key.applicationRoutes)
        }
    }

    func hiddenApplications() -> [String: String] {
        MixerRoutingRules.sanitizedHiddenApplications(
            defaults.dictionary(forKey: Key.hiddenApplications) ?? [:]
        )
    }

    func saveHiddenApplications(_ hidden: [String: String]) {
        if hidden.isEmpty {
            defaults.removeObject(forKey: Key.hiddenApplications)
        } else {
            defaults.set(hidden, forKey: Key.hiddenApplications)
        }
    }
}

/// In-memory mixer store for previews and tests.
///
/// `@unchecked Sendable`: every stored value is guarded by `lock`.
final class InMemoryVolumeMixerSettingsStore: VolumeMixerSettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: VolumeMixerSettings
    private var volumes: [String: Double] = [:]
    private var routes: [String: String] = [:]
    private var hidden: [String: String] = [:]

    init(settings: VolumeMixerSettings = .default) {
        self.settings = settings
    }

    func load() -> VolumeMixerSettings { lock.withLock { settings } }
    func save(_ settings: VolumeMixerSettings) { lock.withLock { self.settings = settings } }
    func applicationVolumes() -> [String: Double] { lock.withLock { volumes } }
    func saveApplicationVolumes(_ volumes: [String: Double]) { lock.withLock { self.volumes = volumes } }
    func applicationRoutes() -> [String: String] { lock.withLock { routes } }
    func saveApplicationRoutes(_ routes: [String: String]) { lock.withLock { self.routes = routes } }
    func hiddenApplications() -> [String: String] { lock.withLock { hidden } }
    func saveHiddenApplications(_ hidden: [String: String]) { lock.withLock { self.hidden = hidden } }
}
