import Darwin
import Foundation
import Infrastructure

/// All bookmark resolution and bounded metadata enumeration run on this actor, never the UI actor.
actor AuthorizedFileBrowserService: FileBrowsing {
    private struct Root {
        let id: String
        let bookmark: Data
        let url: URL
    }
    private let folderAccessStore: any FolderAccessStoring
    private let resolver: any FileBrowserRootResolving
    private let maximumEntries: Int
    private let maximumScannedEntries: Int
    private var identifiers: [Data: String] = [:]

    init(folderAccessStore: any FolderAccessStoring,
         resolver: any FileBrowserRootResolving = SecurityScopedFileBrowserRootResolver(),
         maximumEntries: Int = 1_000, maximumScannedEntries: Int = 5_000) {
        self.folderAccessStore = folderAccessStore
        self.resolver = resolver
        self.maximumEntries = min(1_000, max(1, maximumEntries))
        self.maximumScannedEntries = min(5_000, max(1, maximumScannedEntries))
    }

    func roots() async throws -> [FileBrowserRoot] {
        let roots = try await resolvedRoots()
        var available: [FileBrowserRoot] = []
        for root in roots {
            try Task.checkCancellation()
            guard resolver.startAccessing(root.url) else { continue }
            defer { resolver.stopAccessing(root.url) }
            do {
                let descriptor = try openDirectory(root: root, components: [])
                Darwin.close(descriptor)
                available.append(FileBrowserRoot(id: root.id, name: root.url.lastPathComponent))
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        guard available.isEmpty == false else { throw FileBrowserError.authorizationUnavailable }
        return available.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func list(_ location: FileBrowserLocation) async throws -> FileBrowserSnapshot {
        let root = try await currentRoot(location.rootID)
        guard resolver.startAccessing(root.url) else { throw FileBrowserError.accessDenied }
        defer { resolver.stopAccessing(root.url) }
        let descriptor = try openDirectory(root: root, components: location.components)
        guard let directory = Darwin.fdopendir(descriptor) else {
            Darwin.close(descriptor)
            throw FileBrowserError.folderUnavailable
        }
        defer { Darwin.closedir(directory) }
        var entries: [FileBrowserEntry] = []
        var scanned = 0
        var truncated = false
        while true {
            try Task.checkCancellation()
            errno = 0
            guard let raw = Darwin.readdir(directory) else {
                guard errno == 0 else { throw FileBrowserError.folderUnavailable }
                break
            }
            scanned += 1
            if scanned > maximumScannedEntries { truncated = true; break }
            let name = withUnsafePointer(to: &raw.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                    String(validatingCString: $0)
                }
            }
            guard let name, name.hasPrefix(".") == false else { continue }
            if entries.count >= maximumEntries { truncated = true; break }
            var status = stat()
            guard Darwin.fstatat(descriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            let type = status.st_mode & S_IFMT
            guard type == S_IFREG || type == S_IFDIR || type == S_IFLNK else { continue }
            let child = FileBrowserLocation(rootID: location.rootID, components: location.components + [name])
            let url = child.components.reduce(root.url) { $0.appendingPathComponent($1) }
            let kind: FileBrowserEntry.Kind
            if type == S_IFLNK { kind = .symbolicLink }
            else {
                let values = try? url.resourceValues(forKeys: [.isPackageKey, .isAliasFileKey])
                if values?.isAliasFile == true { kind = .alias }
                else if type == S_IFDIR { kind = values?.isPackage == true ? .package : .folder }
                else { kind = .file }
            }
            entries.append(FileBrowserEntry(location: child, name: name, kind: kind,
                identity: identity(status), byteCount: type == S_IFREG ? status.st_size : nil,
                modifiedAt: Date(timeIntervalSince1970: Double(status.st_mtimespec.tv_sec))))
        }
        entries.sort {
            if ($0.kind == .folder) != ($1.kind == .folder) { return $0.kind == .folder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        guard await folderAccessStore.bookmarkData.contains(root.bookmark) else { throw FileBrowserError.accessDenied }
        try Task.checkCancellation()
        return FileBrowserSnapshot(location: location, entries: entries, isTruncated: truncated)
    }

    func open(_ entry: FileBrowserEntry, using opener: any URLOpening) async throws {
        guard entry.kind == .file || entry.kind == .package else { throw FileBrowserError.unsupportedItem }
        let root = try await currentRoot(entry.location.rootID)
        guard resolver.startAccessing(root.url) else { throw FileBrowserError.accessDenied }
        defer { resolver.stopAccessing(root.url) }
        guard let name = entry.location.components.last, let parent = entry.location.parent else {
            throw FileBrowserError.unsafeLocation
        }
        try validateComponents(entry.location.components)
        let directory = try openDirectory(root: root, components: parent.components)
        defer { Darwin.close(directory) }
        let descriptor = Darwin.openat(directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw FileBrowserError.itemChanged }
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0, identity(status) == entry.identity,
              status.st_mode & S_IFMT == (entry.kind == .package ? S_IFDIR : S_IFREG) else {
            throw FileBrowserError.itemChanged
        }
        let url = entry.location.components.reduce(root.url) { $0.appendingPathComponent($1) }
        guard let reference = (url as NSURL).fileReferenceURL() else { throw FileBrowserError.itemChanged }
        // A file-reference URL preserves the selected object if its pathname changes before
        // the system opener consumes it. Compare it to the no-follow descriptor first.
        var referenceStatus = stat()
        guard Darwin.fstatat(AT_FDCWD, reference.path, &referenceStatus, 0) == 0, identity(referenceStatus) == entry.identity else {
            throw FileBrowserError.itemChanged
        }
        guard (try? reference.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == false else {
            throw FileBrowserError.unsupportedItem
        }
        try Task.checkCancellation()
        guard await folderAccessStore.bookmarkData.contains(root.bookmark) else { throw FileBrowserError.accessDenied }
        try Task.checkCancellation()
        do { try await opener.openURL(reference) }
        catch is CancellationError { throw CancellationError() }
        catch { throw FileBrowserError.openFailed }
    }

    private func resolvedRoots() async throws -> [Root] {
        let bookmarks = await folderAccessStore.bookmarkData
        guard bookmarks.isEmpty == false else { throw FileBrowserError.noAuthorizedFolders }
        var result: [Root] = []
        var seen: Set<URL> = []
        for bookmark in bookmarks {
            try Task.checkCancellation()
            guard let url = try? resolver.resolve(bookmark), url.isFileURL,
                  seen.insert(url.standardizedFileURL).inserted else { continue }
            let id = identifiers[bookmark] ?? UUID().uuidString
            identifiers[bookmark] = id
            result.append(Root(id: id, bookmark: bookmark, url: url.standardizedFileURL))
        }
        guard result.isEmpty == false else { throw FileBrowserError.authorizationUnavailable }
        return result
    }

    private func currentRoot(_ id: String) async throws -> Root {
        guard let root = try await resolvedRoots().first(where: { $0.id == id }) else {
            throw FileBrowserError.accessDenied
        }
        return root
    }

    private func openDirectory(root: Root, components: [String]) throws -> Int32 {
        try validateComponents(components)
        var descriptor = Darwin.open(root.url.path, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw FileBrowserError.folderUnavailable }
        do {
            var currentURL = root.url
            for component in components {
                try Task.checkCancellation()
                let next = Darwin.openat(descriptor, component, O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW)
                guard next >= 0 else {
                    throw errno == ENOENT ? FileBrowserError.folderUnavailable : FileBrowserError.unsafeLocation
                }
                Darwin.close(descriptor)
                descriptor = next
                currentURL.appendPathComponent(component)
                guard let values = try? currentURL.resourceValues(forKeys: [.isPackageKey, .isAliasFileKey]),
                      values.isPackage == false, values.isAliasFile == false else {
                    throw FileBrowserError.unsupportedItem
                }
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func validateComponents(_ components: [String]) throws {
        guard components.count <= 64, components.allSatisfy({
            $0.isEmpty == false && $0.hasPrefix(".") == false && $0.contains("/") == false && $0.contains("\0") == false
        }) else { throw FileBrowserError.unsafeLocation }
    }

    private func identity(_ status: stat) -> FileBrowserIdentity {
        FileBrowserIdentity(device: UInt64(UInt32(bitPattern: status.st_dev)), inode: status.st_ino)
    }
}
