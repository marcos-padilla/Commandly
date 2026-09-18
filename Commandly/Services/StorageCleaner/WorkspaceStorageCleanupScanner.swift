import CryptoKit
import Darwin
import Foundation
import Infrastructure

enum StorageCleanupScanError: LocalizedError, Sendable, Equatable {
    case unavailableDirectory

    var errorDescription: String? {
        switch self {
        case .unavailableDirectory:
            return "That folder is no longer available. Choose it again and retry."
        }
    }
}

/// Performs bounded, on-device discovery for Storage Cleaner.
///
/// Library scanning is limited to direct children of reviewed user-Library locations. Duplicate
/// scanning reads only regular files beneath a directory the user explicitly selected.
actor WorkspaceStorageCleanupScanner: StorageCleanupScanning {
    private struct ScanBudget {
        var inspectedFiles = 0
        var isPartial = false
    }

    private struct DuplicateFile {
        let url: URL
        let byteCount: Int64
        let modifiedAt: Date
    }

    private struct DuplicateEnumeration {
        let filesBySize: [Int64: [DuplicateFile]]
        let inspectedFileCount: Int
        let isPartial: Bool
    }

    private static let maximumLibraryCandidates = 600
    private static let maximumLibraryFiles = 100_000
    private static let maximumDuplicateFiles = 25_000
    private static let maximumDuplicateHashBytes: Int64 = 10 * 1_024 * 1_024 * 1_024
    private static let hashChunkByteCount = 1_048_576

    private let fileManager: FileManager
    private let installedApplicationQuery: any InstalledApplicationQuerying
    private let homeDirectory: URL

    init(
        installedApplicationQuery: any InstalledApplicationQuerying,
        fileManager: FileManager = FileManager(),
        homeDirectory: URL? = nil
    ) {
        self.installedApplicationQuery = installedApplicationQuery
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? Self.realUserHomeDirectory(fileManager: fileManager)
    }

    func scanLibrary() async throws -> StorageCleanupScanResult {
        let installedApplications = await installedApplicationQuery.installedApplications()
        try Task.checkCancellation()

        let installedBundleIdentifiers = Set(
            installedApplications.map { $0.bundleIdentifier.lowercased() }
        )
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        var budget = ScanBudget()
        var itemsByPath: [String: StorageCleanupItem] = [:]

        let leftoverDirectories = [
            "Application Support",
            "Preferences",
            "HTTPStorages",
            "Cookies",
            "WebKit",
            "Containers",
            "Saved Application State",
            "LaunchAgents",
            "Logs",
            "Application Scripts"
        ]

        for directoryName in leftoverDirectories {
            try Task.checkCancellation()
            guard itemsByPath.count < Self.maximumLibraryCandidates else {
                budget.isPartial = true
                break
            }
            let root = library.appendingPathComponent(directoryName, isDirectory: true)
            let children = directoryChildren(at: root, budget: &budget)
            for child in children {
                try Task.checkCancellation()
                guard itemsByPath.count < Self.maximumLibraryCandidates else {
                    budget.isPartial = true
                    break
                }
                guard let bundleIdentifier = Self.inferredBundleIdentifier(
                    from: child.lastPathComponent
                ), Self.isProtectedIdentifier(bundleIdentifier) == false,
                Self.isRepresented(
                    bundleIdentifier,
                    byInstalledBundleIdentifiers: installedBundleIdentifiers
                ) == false else {
                    continue
                }
                if let item = makeItem(
                    at: child,
                    category: .applicationLeftover,
                    bundleIdentifier: bundleIdentifier,
                    suggested: true,
                    budget: &budget
                ) {
                    itemsByPath[item.path] = item
                }
            }
        }

        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        for child in directoryChildren(at: caches, budget: &budget) {
            try Task.checkCancellation()
            guard itemsByPath.count < Self.maximumLibraryCandidates else {
                budget.isPartial = true
                break
            }
            guard Self.isProtectedCacheName(child.lastPathComponent) == false else { continue }
            if let item = makeItem(
                at: child,
                category: .cache,
                bundleIdentifier: Self.inferredBundleIdentifier(from: child.lastPathComponent),
                suggested: false,
                budget: &budget
            ) {
                itemsByPath[item.path] = item
            }
        }

        return StorageCleanupScanResult(
            items: itemsByPath.values.sorted(by: Self.sortCleanupItems),
            inspectedFileCount: budget.inspectedFiles,
            isPartial: budget.isPartial
        )
    }

    func scanDuplicates(in directory: URL) async throws -> StorageCleanupScanResult {
        let root = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw StorageCleanupScanError.unavailableDirectory
        }

        let didStartAccess = root.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                root.stopAccessingSecurityScopedResource()
            }
        }

        let enumeration = try enumerateDuplicateFiles(in: root)

        var hashedByteCount: Int64 = 0
        var hashingWasPartial = false
        var filesByDigest: [String: [DuplicateFile]] = [:]
        for files in enumeration.filesBySize.values where files.count > 1 {
            for file in files {
                try Task.checkCancellation()
                guard hashedByteCount <= Self.maximumDuplicateHashBytes - file.byteCount else {
                    hashingWasPartial = true
                    break
                }
                do {
                    let digest = try sha256Digest(of: file.url)
                    hashedByteCount += file.byteCount
                    filesByDigest["\(file.byteCount):\(digest)", default: []].append(file)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    hashingWasPartial = true
                }
            }
        }

        var items: [StorageCleanupItem] = []
        for (groupID, files) in filesByDigest where files.count > 1 {
            let sorted = files.sorted {
                if $0.modifiedAt != $1.modifiedAt {
                    return $0.modifiedAt > $1.modifiedAt
                }
                return $0.url.path.localizedCaseInsensitiveCompare($1.url.path)
                    == .orderedAscending
            }
            for (index, file) in sorted.enumerated() {
                items.append(
                    StorageCleanupItem(
                        name: file.url.lastPathComponent,
                        containerPath: displayPath(for: file.url.deletingLastPathComponent()),
                        path: file.url.path,
                        byteCount: file.byteCount,
                        category: .duplicate,
                        duplicateGroupID: groupID,
                        isSuggestedForRemoval: index > 0
                    )
                )
            }
        }

        return StorageCleanupScanResult(
            items: items.sorted(by: Self.sortCleanupItems),
            inspectedFileCount: enumeration.inspectedFileCount,
            isPartial: enumeration.isPartial || hashingWasPartial
        )
    }

    private func enumerateDuplicateFiles(in root: URL) throws -> DuplicateEnumeration {
        var encounteredEnumerationError = false
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in
                encounteredEnumerationError = true
                return true
            }
        ) else {
            throw StorageCleanupScanError.unavailableDirectory
        }

        var filesBySize: [Int64: [DuplicateFile]] = [:]
        var inspectedFileCount = 0
        var reachedFileLimit = false
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard inspectedFileCount < Self.maximumDuplicateFiles else {
                reachedFileLimit = true
                break
            }
            guard let values = try? url.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ]
            ), values.isRegularFile == true, values.isSymbolicLink != true else {
                continue
            }
            let byteCount = Int64(values.fileSize ?? 0)
            guard byteCount > 0 else { continue }
            inspectedFileCount += 1
            filesBySize[byteCount, default: []].append(
                DuplicateFile(
                    url: url,
                    byteCount: byteCount,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            )
        }
        return DuplicateEnumeration(
            filesBySize: filesBySize,
            inspectedFileCount: inspectedFileCount,
            isPartial: encounteredEnumerationError || reachedFileLimit
        )
    }

    private func directoryChildren(at directory: URL, budget: inout ScanBudget) -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        do {
            return try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            .filter {
                let values = try? $0.resourceValues(forKeys: [.isSymbolicLinkKey])
                return values?.isSymbolicLink != true
            }
            .sorted {
                $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
        } catch {
            budget.isPartial = true
            return []
        }
    }

    private func makeItem(
        at url: URL,
        category: StorageCleanupCategory,
        bundleIdentifier: String?,
        suggested: Bool,
        budget: inout ScanBudget
    ) -> StorageCleanupItem? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            budget.isPartial = true
            return nil
        }
        let byteCount = measuredByteCount(
            at: url,
            isDirectory: isDirectory.boolValue,
            budget: &budget
        )
        return StorageCleanupItem(
            name: url.lastPathComponent,
            containerPath: displayPath(for: url.deletingLastPathComponent()),
            path: url.path,
            byteCount: byteCount,
            category: category,
            associatedBundleIdentifier: bundleIdentifier,
            isSuggestedForRemoval: suggested
        )
    }

    private func measuredByteCount(
        at url: URL,
        isDirectory: Bool,
        budget: inout ScanBudget
    ) -> Int64 {
        if isDirectory == false {
            guard budget.inspectedFiles < Self.maximumLibraryFiles else {
                budget.isPartial = true
                return 0
            }
            budget.inspectedFiles += 1
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values?.fileSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            budget.isPartial = true
            return 0
        }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            if Task.isCancelled { break }
            guard budget.inspectedFiles < Self.maximumLibraryFiles else {
                budget.isPartial = true
                break
            }
            guard let values = try? child.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            ), values.isRegularFile == true, values.isSymbolicLink != true else {
                continue
            }
            budget.inspectedFiles += 1
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func sha256Digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: Self.hashChunkByteCount) ?? Data()
            guard data.isEmpty == false else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func displayPath(for url: URL) -> String {
        let homePath = homeDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath + "/") {
            return "~" + String(path.dropFirst(homePath.count))
        }
        return path
    }

    nonisolated static func inferredBundleIdentifier(from name: String) -> String? {
        var candidate = name
        let suffixes = [".binarycookies", ".savedstate", ".plist"]
        for suffix in suffixes where candidate.lowercased().hasSuffix(suffix) {
            candidate.removeLast(suffix.count)
            break
        }
        let components = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 3,
              components.allSatisfy({ component in
                  component.isEmpty == false
                      && component.unicodeScalars.allSatisfy {
                          CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
                      }
              }) else {
            return nil
        }
        return candidate
    }

    nonisolated static func isRepresented(
        _ candidate: String,
        byInstalledBundleIdentifiers installed: Set<String>
    ) -> Bool {
        let candidate = candidate.lowercased()
        return installed.contains { installedIdentifier in
            candidate == installedIdentifier
                || candidate.hasPrefix(installedIdentifier + ".")
                || installedIdentifier.hasPrefix(candidate + ".")
        }
    }

    nonisolated private static func isProtectedIdentifier(_ identifier: String) -> Bool {
        let identifier = identifier.lowercased()
        return identifier == "com.apple"
            || identifier.hasPrefix("com.apple.")
            || identifier == "com.businessmate360.commandly"
            || identifier.hasPrefix("com.businessmate360.commandly.")
    }

    nonisolated private static func isProtectedCacheName(_ name: String) -> Bool {
        let name = name.lowercased()
        return name == "com.apple"
            || name.hasPrefix("com.apple.")
            || name.contains("commandly")
    }

    nonisolated private static func sortCleanupItems(
        _ lhs: StorageCleanupItem,
        _ rhs: StorageCleanupItem
    ) -> Bool {
        if lhs.category != rhs.category {
            return lhs.category.rawValue < rhs.category.rawValue
        }
        if lhs.byteCount != rhs.byteCount {
            return lhs.byteCount > rhs.byteCount
        }
        return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }

    nonisolated private static func realUserHomeDirectory(fileManager: FileManager) -> URL {
        if let pw = getpwuid(getuid()), let directory = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
    }
}
