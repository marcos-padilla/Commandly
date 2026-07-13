import Foundation

/// Immutable metadata for one regular file at the top level of Downloads.
nonisolated struct RecentDownloadItem: Identifiable, Sendable, Equatable, Hashable {
    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent }
    var recencyDate: Date { addedToDirectoryAt ?? createdAt ?? modifiedAt }

    let url: URL
    let addedToDirectoryAt: Date?
    let createdAt: Date?
    let modifiedAt: Date
    let byteCount: Int64

    init(
        url: URL,
        addedToDirectoryAt: Date? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date,
        byteCount: Int64
    ) {
        self.url = url.standardizedFileURL
        self.addedToDirectoryAt = addedToDirectoryAt
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.byteCount = max(0, byteCount)
    }
}

/// Content-free failures safe to surface without disclosing filenames or paths.
nonisolated enum RecentDownloadsError: LocalizedError, Sendable, Equatable {
    case downloadsDirectoryUnavailable
    case directoryUnavailable
    case scanFailed
    case openFailed
    case revealFailed

    var errorDescription: String? {
        switch self {
        case .downloadsDirectoryUnavailable:
            return "The Downloads folder could not be located."
        case .directoryUnavailable:
            return "The Downloads folder is unavailable."
        case .scanFailed:
            return "Recent downloads could not be read."
        case .openFailed:
            return "The download could not be opened."
        case .revealFailed:
            return "The download could not be shown in Finder."
        }
    }
}

/// Asynchronous boundary for reading recent Downloads metadata.
nonisolated protocol RecentDownloadsProviding: Sendable {
    func recentDownloads(limit: Int) async throws -> [RecentDownloadItem]
}

/// Native, actor-confined scanner for the user's Downloads directory.
///
/// Enumeration and metadata reads execute on this actor rather than the main actor. Only top-level,
/// non-hidden regular files are returned, and cancellation is checked throughout enumeration.
actor NativeRecentDownloadsService: RecentDownloadsProviding {
    static let defaultLimit = 50
    static let maximumLimit = 500

    private let directoryURL: URL?
    private let fileManager: FileManager

    init(fileManager: FileManager = FileManager()) {
        self.fileManager = fileManager
        self.directoryURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    init(directoryURL: URL, fileManager: FileManager = FileManager()) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    func recentDownloads(limit: Int = NativeRecentDownloadsService.defaultLimit) async throws
        -> [RecentDownloadItem]
    {
        do {
            try Task.checkCancellation()
            guard let directoryURL else {
                throw RecentDownloadsError.downloadsDirectoryUnavailable
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw RecentDownloadsError.directoryUnavailable
            }

            let resourceKeys: Set<URLResourceKey> = [
                .isRegularFileKey,
                .isHiddenKey,
                .addedToDirectoryDateKey,
                .creationDateKey,
                .contentModificationDateKey,
                .fileSizeKey
            ]
            let urls = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
            )

            var downloads: [RecentDownloadItem] = []
            downloads.reserveCapacity(min(urls.count, max(0, limit)))
            for url in urls {
                try Task.checkCancellation()
                let values = try url.resourceValues(forKeys: resourceKeys)
                guard values.isRegularFile == true,
                      values.isHidden != true,
                      url.lastPathComponent.hasPrefix(".") == false else {
                    continue
                }
                downloads.append(
                    RecentDownloadItem(
                        url: url,
                        addedToDirectoryAt: values.addedToDirectoryDate,
                        createdAt: values.creationDate,
                        modifiedAt: values.contentModificationDate ?? .distantPast,
                        byteCount: Int64(values.fileSize ?? 0)
                    )
                )
            }

            try Task.checkCancellation()
            downloads.sort(by: Self.isOrderedBefore)
            return Array(downloads.prefix(min(max(0, limit), Self.maximumLimit)))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RecentDownloadsError {
            throw error
        } catch {
            throw RecentDownloadsError.scanFailed
        }
    }

    private nonisolated static func isOrderedBefore(
        _ lhs: RecentDownloadItem,
        _ rhs: RecentDownloadItem
    ) -> Bool {
        if lhs.recencyDate != rhs.recencyDate {
            return lhs.recencyDate > rhs.recencyDate
        }
        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}
