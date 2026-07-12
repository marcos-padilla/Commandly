import Foundation
import Observation
import Infrastructure
import CommandKit

enum ApplicationUninstallSort: String, CaseIterable, Identifiable, Sendable {
    case path
    case name
    case size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .path: return "Sort by Path"
        case .name: return "Sort by Name"
        case .size: return "Sort by Size"
        }
    }
}

@Observable
@MainActor
final class ApplicationUninstallViewModel {
    let applicationName: String
    let applicationPath: String
    let bundleIdentifier: String

    private(set) var items: [ApplicationRelatedItem] = []
    private(set) var isLoading = true
    private(set) var isUninstalling = false
    private(set) var statusMessage: String?

    var filterQuery: String = ""
    var sort: ApplicationUninstallSort = .path
    var selectedPaths: Set<String> = []

    @ObservationIgnored
    private let discoverer: any ApplicationUninstallDiscovering
    @ObservationIgnored
    private let bundleManager: any ApplicationBundleManaging
    @ObservationIgnored
    private let onFinished: (String) -> Void
    @ObservationIgnored
    private let onCancel: () -> Void
    @ObservationIgnored
    private var loadTask: Task<Void, Never>?

    init(
        applicationName: String,
        applicationPath: String,
        bundleIdentifier: String,
        discoverer: any ApplicationUninstallDiscovering,
        bundleManager: any ApplicationBundleManaging,
        onFinished: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.applicationName = applicationName
        self.applicationPath = applicationPath
        self.bundleIdentifier = bundleIdentifier
        self.discoverer = discoverer
        self.bundleManager = bundleManager
        self.onFinished = onFinished
        self.onCancel = onCancel
    }

    var filteredItems: [ApplicationRelatedItem] {
        let trimmed = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [ApplicationRelatedItem]
        if trimmed.isEmpty {
            filtered = items
        } else {
            filtered = items.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                    || $0.containerPath.localizedCaseInsensitiveContains(trimmed)
                    || $0.path.localizedCaseInsensitiveContains(trimmed)
            }
        }
        switch sort {
        case .path:
            return filtered.sorted {
                $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
        case .name:
            return filtered.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .size:
            return filtered.sorted { $0.byteCount > $1.byteCount }
        }
    }

    var selectedItems: [ApplicationRelatedItem] {
        items.filter { selectedPaths.contains($0.path) }
    }

    var selectedByteCount: Int64 {
        selectedItems.reduce(0) { $0 + $1.byteCount }
    }

    var selectedCountLabel: String {
        let count = selectedPaths.count
        return count == 1 ? "1 File" : "\(count) Files"
    }

    var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: selectedByteCount, countStyle: .file)
    }

    var canUninstall: Bool {
        selectedPaths.isEmpty == false && isUninstalling == false && isLoading == false
    }

    func load() {
        loadTask?.cancel()
        isLoading = true
        statusMessage = nil
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let application = InstalledApplication(
                bundleIdentifier: bundleIdentifier,
                name: applicationName,
                path: applicationPath
            )
            let discovered = await discoverer.relatedItems(for: application)
            guard Task.isCancelled == false else { return }
            items = discovered
            selectedPaths = Set(discovered.map(\.path))
            isLoading = false
        }
    }

    func goBack() {
        loadTask?.cancel()
        onCancel()
    }

    func toggleSelection(_ path: String) {
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
        } else {
            selectedPaths.insert(path)
        }
    }

    func selectAllVisible() {
        for item in filteredItems {
            selectedPaths.insert(item.path)
        }
    }

    func deselectAllVisible() {
        for item in filteredItems {
            selectedPaths.remove(item.path)
        }
    }

    func confirmUninstall() {
        guard canUninstall else { return }
        isUninstalling = true
        statusMessage = nil
        let paths = selectedItems
            .sorted { lhs, rhs in
                // Trash nested paths before parents when both selected.
                lhs.path.count > rhs.path.count
            }
            .map(\.path)

        Task { @MainActor [weak self] in
            guard let self else { return }
            var failures = 0
            var trashedApp = false
            for path in paths {
                do {
                    try await bundleManager.moveItemToTrash(atPath: path)
                    if path == applicationPath {
                        trashedApp = true
                    }
                    selectedPaths.remove(path)
                    items.removeAll { $0.path == path }
                } catch {
                    failures += 1
                }
            }
            isUninstalling = false
            if trashedApp && failures == 0 {
                onFinished("Moved \(applicationName) and related files to the Trash.")
            } else if trashedApp {
                onFinished("Moved \(applicationName) to the Trash. Some related files couldn’t be removed.")
            } else if failures == paths.count {
                statusMessage = "Couldn’t uninstall. Check permissions or try revealing the app in Finder."
            } else if failures > 0 {
                statusMessage = "Removed some items. \(failures) couldn’t be moved to the Trash."
            } else {
                onFinished("Moved selected files to the Trash.")
            }
        }
    }
}
