import Darwin
import Foundation

/// Synchronous descriptor operations called only by the workspace actor. Relative components are
/// walked with O_NOFOLLOW; an external rename cannot redirect an opened source or output directory.
nonisolated enum FinderAIImageFileIO {
    static func read(root: URL, rootIdentity: FinderAIImageDirectoryIdentity, components: [String],
                     maximumBytes: Int, validate: (Int32) throws -> Void) throws -> Data {
        guard let name = components.last else { throw FinderAIWorkspaceError.unsupportedItemKind }
        return try withDirectory(root: root, rootIdentity: rootIdentity, components: Array(components.dropLast())) { directory, validatePath in
            try Task.checkCancellation()
            let descriptor = Darwin.openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw FinderAIWorkspaceError.itemChangedSincePreview }
            defer { _ = Darwin.close(descriptor) }
            try validate(descriptor)
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
            guard !data.isEmpty, data.count <= maximumBytes else { throw FinderAIWorkspaceError.limitExceeded }
            try validate(descriptor)
            try validatePath()
            try Task.checkCancellation()
            return data
        }
    }

    /// Stage privately, sync, then use the kernel's exclusive rename. A competing final name is
    /// never replaced, including a symlink. The exact approved output appears only after completion.
    static func write(_ data: Data, root: URL, rootIdentity: FinderAIImageDirectoryIdentity,
                      directoryComponents: [String], name: String,
                      validateDirectory: (Int32) throws -> Void) throws {
        guard !data.isEmpty, data.count <= 192 * 1_024 * 1_024 else { throw FinderAIWorkspaceError.limitExceeded }
        try validateComponent(name)
        try withDirectory(root: root, rootIdentity: rootIdentity, components: directoryComponents) { directory, validatePath in
            try validateDirectory(directory)
            try Task.checkCancellation()
            let temporaryName = ".commandly-image-\(UUID().uuidString).tmp"
            let descriptor = Darwin.openat(directory, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw FinderAIWorkspaceError.imageConversionFailed }
            defer { _ = Darwin.close(descriptor) }
            var opened = stat()
            guard Darwin.fstat(descriptor, &opened) == 0 else {
                // Without an inode identity, do not unlink a name another process could replace.
                throw FinderAIWorkspaceError.imageTemporaryCleanupFailed
            }
            do {
                try data.withUnsafeBytes { bytes in
                    guard let base = bytes.baseAddress else { throw FinderAIWorkspaceError.invalidImage }
                    var offset = 0
                    while offset < bytes.count {
                        try Task.checkCancellation()
                        let count = Darwin.write(descriptor, base.advanced(by: offset), min(1_024 * 1_024, bytes.count - offset))
                        if count < 0, errno == EINTR { continue }
                        guard count > 0 else { throw FinderAIWorkspaceError.imageConversionFailed }
                        offset += count
                    }
                }
                guard Darwin.fsync(descriptor) == 0 else { throw FinderAIWorkspaceError.imageConversionFailed }
                try Task.checkCancellation()
                try validateDirectory(directory)
                try validatePath()
                var named = stat()
                guard Darwin.fstatat(directory, temporaryName, &named, AT_SYMLINK_NOFOLLOW) == 0,
                      named.st_dev == opened.st_dev, named.st_ino == opened.st_ino,
                      named.st_mode & S_IFMT == S_IFREG else { throw FinderAIWorkspaceError.itemChangedSincePreview }
                guard Darwin.renameatx_np(directory, temporaryName, directory, name, UInt32(RENAME_EXCL)) == 0 else {
                    throw errno == EEXIST ? FinderAIWorkspaceError.collision : FinderAIWorkspaceError.imageConversionFailed
                }
                // No cancellation check after the atomic commit: a completed output is reported as completed.
            } catch {
                var remaining = stat()
                let lookup = Darwin.fstatat(directory, temporaryName, &remaining, AT_SYMLINK_NOFOLLOW)
                if lookup == 0, remaining.st_dev == opened.st_dev, remaining.st_ino == opened.st_ino {
                    guard Darwin.unlinkat(directory, temporaryName, 0) == 0 else {
                        throw FinderAIWorkspaceError.imageTemporaryCleanupFailed
                    }
                } else if lookup != 0, errno != ENOENT {
                    throw FinderAIWorkspaceError.imageTemporaryCleanupFailed
                }
                throw error
            }
        }
    }

    static func identity(ofDirectory descriptor: Int32) throws -> FinderAIImageDirectoryIdentity {
        var value = stat()
        guard Darwin.fstat(descriptor, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else {
            throw FinderAIWorkspaceError.itemChangedSincePreview
        }
        return FinderAIImageDirectoryIdentity(device: UInt64(value.st_dev), inode: UInt64(value.st_ino))
    }

    private static func withDirectory<Value>(root: URL, rootIdentity: FinderAIImageDirectoryIdentity,
                                             components: [String], operation: (Int32, () throws -> Void) throws -> Value) throws -> Value {
        guard root.isFileURL else { throw FinderAIWorkspaceError.unauthorized }
        for component in components { try validateComponent(component) }
        let rootDescriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootDescriptor >= 0 else { throw FinderAIWorkspaceError.unauthorized }
        var descriptors = [rootDescriptor]
        defer { for descriptor in descriptors.reversed() { _ = Darwin.close(descriptor) } }
        guard try identity(ofDirectory: rootDescriptor) == rootIdentity else { throw FinderAIWorkspaceError.itemChangedSincePreview }
        // F_GETPATH supplies the physical spelling; Foundation may deliberately preserve /var
        // while the descriptor reports /private/var. Pin this value for the operation lifetime.
        let canonicalRoot = try descriptorPath(rootDescriptor)
        var directory = rootDescriptor
        var expectedPath = canonicalRoot
        for component in components {
            let next = Darwin.openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw FinderAIWorkspaceError.itemChangedSincePreview }
            descriptors.append(next)
            directory = next
            expectedPath = (expectedPath as NSString).appendingPathComponent(component)
        }
        let finalDirectory = directory
        let finalPath = expectedPath
        let validatePath = {
            guard try descriptorPath(rootDescriptor) == canonicalRoot,
                  try descriptorPath(finalDirectory) == finalPath else { throw FinderAIWorkspaceError.itemChangedSincePreview }
        }
        try validatePath()
        return try operation(directory, validatePath)
    }

    private static func descriptorPath(_ descriptor: Int32) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard Darwin.fcntl(descriptor, F_GETPATH, &buffer) == 0,
              let terminator = buffer.firstIndex(of: 0),
              let path = String(validating: buffer[..<terminator].map { UInt8(bitPattern: $0) }, as: UTF8.self) else {
            throw FinderAIWorkspaceError.itemChangedSincePreview
        }
        return path
    }

    private static func validateComponent(_ value: String) throws {
        guard !value.isEmpty, value != ".", value != "..", !value.contains("/"), !value.utf8.contains(0),
              value.utf8.count <= 255 else { throw FinderAIWorkspaceError.invalidName }
    }
}
