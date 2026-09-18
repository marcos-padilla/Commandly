#if DEBUG
import Foundation
import Infrastructure

/// Fictional, memory-only folders for explicit debug UI runs. Even Open performs no system action.
actor FileBrowserDebugFixture: FileBrowsing {
    private(set) var opened: [FileBrowserLocation] = []

    func roots() async throws -> [FileBrowserRoot] {
        try Task.checkCancellation()
        return [FileBrowserRoot(id: "debug-design", name: "Design Workspace"),
                FileBrowserRoot(id: "debug-shared", name: "Shared Samples")]
    }

    func list(_ location: FileBrowserLocation) async throws -> FileBrowserSnapshot {
        try Task.checkCancellation()
        let children: [(String, FileBrowserEntry.Kind, Int64?)]
        switch (location.rootID, location.components) {
        case ("debug-design", []):
            children = [("Notes", .folder, nil), ("Projects", .folder, nil),
                        ("Reference Link", .symbolicLink, nil), ("Welcome.txt", .file, 240)]
        case ("debug-design", ["Projects"]):
            children = [("Archive", .folder, nil), ("Assets", .folder, nil), ("Launch plan.md", .file, 3_200)]
        case ("debug-design", ["Projects", "Assets"]):
            children = [("Screenshot.png", .file, 1_240_000)]
        case ("debug-design", ["Notes"]):
            children = [("Team notes.md", .file, 1_800)]
        case ("debug-design", ["Projects", "Archive"]): children = []
        case ("debug-shared", []): children = [("Read me.txt", .file, 120)]
        default: throw FileBrowserError.unsafeLocation
        }
        let entries = children.enumerated().map { index, child in
            FileBrowserEntry(location: FileBrowserLocation(rootID: location.rootID, components: location.components + [child.0]),
                name: child.0, kind: child.1, identity: FileBrowserIdentity(device: 1, inode: UInt64(index + 1)),
                byteCount: child.2, modifiedAt: Date(timeIntervalSince1970: 1_783_000_000))
        }
        return FileBrowserSnapshot(location: location, entries: entries)
    }

    func open(_ entry: FileBrowserEntry, using opener: any URLOpening) async throws {
        guard let parent = entry.location.parent, entry.kind == .file,
              try await list(parent).entries.contains(entry) else { throw FileBrowserError.unsupportedItem }
        try Task.checkCancellation()
        // Deliberately do not call the injected opener: fixture names have no filesystem URL.
        opened.append(entry.location)
    }
}
#endif
