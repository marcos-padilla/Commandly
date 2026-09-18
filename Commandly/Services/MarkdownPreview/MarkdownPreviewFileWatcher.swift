import Darwin
import Dispatch
import Foundation

nonisolated enum MarkdownPreviewFileChange: Equatable, Sendable {
    case contentsChanged
    case replacedOrRemoved
}

nonisolated enum MarkdownPreviewFileWatcherError: LocalizedError, Equatable, Sendable {
    case unableToObserve

    var errorDescription: String? {
        "Automatic reload could not watch this document."
    }
}

nonisolated protocol MarkdownPreviewFileWatching: Sendable {
    func changes(for sourceURL: URL) async throws -> AsyncStream<MarkdownPreviewFileChange>
}

/// Observes both the selected file and its directory so editor-style atomic replacements do not
/// strand automatic reload on an unlinked file descriptor.
actor DispatchSourceMarkdownPreviewFileWatcher: MarkdownPreviewFileWatching {
    private struct FileIdentity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
    }

    private struct FileSignature: Equatable, Sendable {
        let identity: FileIdentity
        let byteCount: Int64
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
    }

    private struct Observation {
        let sourceURL: URL
        let continuation: AsyncStream<MarkdownPreviewFileChange>.Continuation
        let directorySource: any DispatchSourceFileSystemObject
        var fileSource: (any DispatchSourceFileSystemObject)?
        var signature: FileSignature?
        var debounceTimer: (any DispatchSourceTimer)?
        var debounceGeneration = 0
        var sawFileEvent = false
    }

    private static let coalescingDelay = DispatchTimeInterval.milliseconds(75)
    private static let coalescingLeeway = DispatchTimeInterval.milliseconds(15)

    private let eventQueue = DispatchQueue(
        label: "com.commandly.markdown-preview.file-watcher",
        qos: .utility
    )
    private var observations: [UUID: Observation] = [:]

    func changes(for sourceURL: URL) throws -> AsyncStream<MarkdownPreviewFileChange> {
        let observedURL = sourceURL.standardizedFileURL
        let directoryURL = observedURL.deletingLastPathComponent()
        let directoryDescriptor = open(directoryURL.path, O_EVTONLY | O_CLOEXEC)
        guard directoryDescriptor >= 0,
              let initialSignature = Self.fileSignature(for: observedURL) else {
            if directoryDescriptor >= 0 {
                Darwin.close(directoryDescriptor)
            }
            throw MarkdownPreviewFileWatcherError.unableToObserve
        }

        let identifier = UUID()
        guard let fileSource = makeFileSource(for: observedURL, identifier: identifier) else {
            Darwin.close(directoryDescriptor)
            throw MarkdownPreviewFileWatcherError.unableToObserve
        }
        let directorySource = makeDirectorySource(
            descriptor: directoryDescriptor,
            identifier: identifier
        )

        let streamPair = AsyncStream<MarkdownPreviewFileChange>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let continuation = streamPair.continuation
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.cancelObservation(identifier)
            }
        }

        observations[identifier] = Observation(
            sourceURL: observedURL,
            continuation: continuation,
            directorySource: directorySource,
            fileSource: fileSource,
            signature: initialSignature
        )
        directorySource.resume()
        fileSource.resume()
        return streamPair.stream
    }

    private func makeDirectorySource(
        descriptor: Int32,
        identifier: UUID
    ) -> any DispatchSourceFileSystemObject {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: eventQueue
        )
        source.setEventHandler { [weak self] in
            Task {
                await self?.recordEvent(identifier, originatedFromFile: false)
            }
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        return source
    }

    private func makeFileSource(
        for sourceURL: URL,
        identifier: UUID
    ) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(sourceURL.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: eventQueue
        )
        source.setEventHandler { [weak self] in
            Task {
                await self?.recordEvent(identifier, originatedFromFile: true)
            }
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        return source
    }

    private func recordEvent(_ identifier: UUID, originatedFromFile: Bool) {
        guard var observation = observations[identifier] else { return }
        observation.sawFileEvent = observation.sawFileEvent || originatedFromFile

        guard observation.debounceTimer == nil else {
            observations[identifier] = observation
            return
        }

        observation.debounceGeneration += 1
        let generation = observation.debounceGeneration
        let timer = DispatchSource.makeTimerSource(queue: eventQueue)
        timer.schedule(
            deadline: .now() + Self.coalescingDelay,
            leeway: Self.coalescingLeeway
        )
        timer.setEventHandler { [weak self] in
            Task {
                await self?.finishCoalescing(identifier, generation: generation)
            }
        }
        timer.resume()
        observation.debounceTimer = timer
        observations[identifier] = observation
    }

    private func finishCoalescing(_ identifier: UUID, generation: Int) {
        guard var observation = observations[identifier],
              observation.debounceGeneration == generation,
              let timer = observation.debounceTimer else {
            return
        }

        timer.cancel()
        observation.debounceTimer = nil
        let previousSignature = observation.signature
        let currentSignature = Self.fileSignature(for: observation.sourceURL)
        let sawFileEvent = observation.sawFileEvent
        observation.sawFileEvent = false

        let identityChanged = previousSignature?.identity != currentSignature?.identity
        if currentSignature == nil {
            observation.fileSource?.cancel()
            observation.fileSource = nil
        } else if sawFileEvent || identityChanged || observation.fileSource == nil {
            // A vnode source stays attached to the old inode after an atomic rename. Reopening it
            // here keeps subsequent ordinary writes observable on the replacement document.
            observation.fileSource?.cancel()
            observation.fileSource = makeFileSource(
                for: observation.sourceURL,
                identifier: identifier
            )
            observation.fileSource?.resume()
        }

        observation.signature = currentSignature
        observations[identifier] = observation

        if currentSignature == nil, previousSignature != nil {
            observation.continuation.yield(.replacedOrRemoved)
        } else if currentSignature != previousSignature
            || (sawFileEvent && currentSignature != nil) {
            observation.continuation.yield(.contentsChanged)
        }
    }

    private func cancelObservation(_ identifier: UUID) {
        guard let observation = observations.removeValue(forKey: identifier) else { return }
        observation.debounceTimer?.cancel()
        observation.fileSource?.cancel()
        observation.directorySource.cancel()
    }

    private nonisolated static func fileSignature(for sourceURL: URL) -> FileSignature? {
        var metadata = stat()
        let result = sourceURL.path.withCString { path in
            Darwin.lstat(path, &metadata)
        }
        guard result == 0 else { return nil }

        return FileSignature(
            identity: FileIdentity(
                device: UInt64(metadata.st_dev),
                inode: UInt64(metadata.st_ino)
            ),
            byteCount: Int64(metadata.st_size),
            modificationSeconds: Int64(metadata.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(metadata.st_mtimespec.tv_nsec)
        )
    }

    deinit {
        for observation in observations.values {
            observation.debounceTimer?.cancel()
            observation.fileSource?.cancel()
            observation.directorySource.cancel()
            observation.continuation.finish()
        }
    }
}

actor NoopMarkdownPreviewFileWatcher: MarkdownPreviewFileWatching {
    func changes(for sourceURL: URL) -> AsyncStream<MarkdownPreviewFileChange> {
        _ = sourceURL
        let streamPair = AsyncStream<MarkdownPreviewFileChange>.makeStream()
        streamPair.continuation.finish()
        return streamPair.stream
    }
}
