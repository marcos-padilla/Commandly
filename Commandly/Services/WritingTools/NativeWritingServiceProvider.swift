import AppKit
import Infrastructure

/// Explicit Services invocation is the only authority to read and replace this requestor's selection.
/// The caller registers this object only after all dependencies and app lifecycle handlers are ready.
@MainActor
final class NativeWritingServiceProvider: NSObject {
    static let serviceName = "Quick Fix Selection Locally"
    static let operationTimeout: TimeInterval = 8
    static let advertisedTimeoutMilliseconds = "15000"
    private let checker: any WritingChecking
    private let progress: any WritingInlineProgressPresenting
    private let now: () -> TimeInterval
    private let captureOrigin: () -> WritingServiceOrigin
    private var isRunning = false

    init(checker: any WritingChecking, progress: any WritingInlineProgressPresenting = NativeWritingInlineProgress(),
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         captureOrigin: @escaping () -> WritingServiceOrigin = { .captureNative() }) {
        self.checker = checker; self.progress = progress; self.now = now; self.captureOrigin = captureOrigin
    }

    @objc(quickFixSelection:userData:error:)
    func quickFixSelection(_ pasteboard: NSPasteboard, userData: String?, error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>) {
        do { try perform(on: NativeWritingServicePasteboard(pasteboard)) }
        catch { errorPointer.pointee = Self.message(for: error) as NSString }
    }

    /// Test seam accepts only an explicit service pasteboard; never falls back to NSPasteboard.general.
    func perform(on pasteboard: any WritingServicePasteboard) throws {
        guard isRunning == false else { throw WritingServiceError.busy }
        isRunning = true
        let origin = captureOrigin()
        defer { isRunning = false; origin.restoreIfAppropriate() }
        let deadline = now() + Self.operationTimeout
        let transaction = try WritingServiceTransaction(pasteboard: pasteboard, deadline: deadline, now: now)
        let result = progress.run(text: transaction.original, checker: checker, deadline: deadline,
            originName: origin.name)
        switch result {
        case .success(let report):
            guard report.source == transaction.original else { transaction.cancel(); throw WritingServiceError.changedSelection }
            try transaction.commit(WritingCorrectionPolicy.automaticResult(report))
        case .failure(let error):
            transaction.cancel()
            throw error
        }
    }

    private static func message(for error: any Error) -> String {
        if let error = error as? WritingCheckError {
            switch error {
            case .cancelled: return "Quick Fix was canceled. The selected text was not changed."
            case .timedOut: return "Quick Fix timed out. The selected text was not changed."
            case .malformedResult: return "These suggestions need review. Use Spelling & Grammar in Commandly."
            default: return "Quick Fix could not check this selection. Use Spelling & Grammar in Commandly."
            }
        }
        switch error as? WritingServiceError {
        case .invalidSelection: return "Select plain text of at most 16 KiB in an editable field."
        case .changedSelection: return "The selection request changed. Select the text again before using Quick Fix."
        case .timedOut: return "Quick Fix timed out. The selected text was not changed."
        case .busy: return "Another Quick Fix is running. Wait for it or cancel it first."
        default: return "Quick Fix could not replace this selection. Use the checker and copy the result."
        }
    }
}

@MainActor
private final class NativeWritingServicePasteboard: WritingServicePasteboard {
    private let pasteboard: NSPasteboard
    init(_ pasteboard: NSPasteboard) { self.pasteboard = pasteboard }
    var identity: String { pasteboard.name.rawValue }
    var changeCount: Int { pasteboard.changeCount }
    func readText() -> String? { pasteboard.string(forType: .string) }
    func writeText(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

/// Metadata/focus anchor captured before progress appears. It grants no AX or text authority.
@MainActor
struct WritingServiceOrigin {
    let name: String?
    let restoreIfAppropriate: () -> Void
    static var none: Self { .init(name: nil, restoreIfAppropriate: {}) }
    static func captureNative() -> Self {
        guard let origin = NSWorkspace.shared.frontmostApplication,
              origin.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return .none }
        return .init(name: origin.localizedName) {
            guard origin.isTerminated == false,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
            _ = origin.activate(options: [])
        }
    }
}
