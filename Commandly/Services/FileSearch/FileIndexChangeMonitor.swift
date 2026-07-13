import CoreServices
import Foundation

/// Recursive, low-latency filesystem monitoring for authorized index roots.
@MainActor
final class FileIndexChangeMonitor {
    private var stream: FSEventStreamRef?
    private var callbackBox: CallbackBox?
    private let queue = DispatchQueue(label: "com.commandly.file-index.events", qos: .utility)

    func start(paths: [String], onChange: @escaping @Sendable ([String]) -> Void) {
        stop()
        guard paths.isEmpty == false else { return }
        let box = CallbackBox(handler: onChange)
        callbackBox = box
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.eventCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.35,
            flags
        ) else {
            callbackBox = nil
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        if FSEventStreamStart(stream) == false {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            callbackBox = nil
        }
    }

    private nonisolated static let eventCallback: FSEventStreamCallback = {
        _, info, count, eventPaths, _, _ in
        guard let info else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
        let values = unsafeBitCast(eventPaths, to: NSArray.self)
        let paths = values.compactMap { $0 as? String }
        if paths.isEmpty == false, count > 0 {
            box.handler(Array(Set(paths)))
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        callbackBox = nil
    }

    /// FSEvents invokes this private box on its dispatch queue. Its immutable Sendable
    /// closure is the only state that crosses executors.
    private final class CallbackBox: @unchecked Sendable {
        nonisolated let handler: @Sendable ([String]) -> Void

        init(handler: @escaping @Sendable ([String]) -> Void) {
            self.handler = handler
        }
    }
}
