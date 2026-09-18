import AppKit
import Foundation
import Infrastructure

/// This port represents only the pasteboard handed to one macOS Services invocation.
@MainActor
protocol WritingServicePasteboard: AnyObject {
    var identity: String { get }
    var changeCount: Int { get }
    func readText() -> String?
    func writeText(_ text: String) -> Bool
}

nonisolated enum WritingServiceError: Error, Equatable, Sendable {
    case invalidSelection, changedSelection, cancelled, timedOut, busy, unavailable, writeFailed
}

/// Services callers may choose their pasteboard. Shared system boards never grant selection authority.
nonisolated enum WritingServicePasteboardIdentity {
    static func isRequestSpecific(_ identity: String) -> Bool {
        let reserved: [NSPasteboard.Name] = [.general, .find, .font, .ruler, .drag]
        return identity.isEmpty == false && reserved.contains { $0.rawValue == identity } == false
    }
}

/// Named pasteboard identity and original text are held for one request, never in history or logs.
@MainActor
final class WritingServiceTransaction {
    let original: String
    private let pasteboard: any WritingServicePasteboard
    private let identity: String
    private let initialChangeCount: Int
    private let deadline: TimeInterval
    private let now: () -> TimeInterval
    private var finished = false

    init(pasteboard: any WritingServicePasteboard, deadline: TimeInterval, now: @escaping () -> TimeInterval) throws {
        guard WritingServicePasteboardIdentity.isRequestSpecific(pasteboard.identity) else {
            throw WritingServiceError.invalidSelection
        }
        guard let text = pasteboard.readText() else { throw WritingServiceError.invalidSelection }
        do { try WritingCorrectionPolicy.validateInput(text) }
        catch { throw WritingServiceError.invalidSelection }
        original = text; self.pasteboard = pasteboard; identity = pasteboard.identity
        initialChangeCount = pasteboard.changeCount; self.deadline = deadline; self.now = now
    }

    func cancel() { finished = true }

    func commit(_ corrected: String) throws {
        guard finished == false else { throw WritingServiceError.cancelled }
        finished = true
        guard now() < deadline else { throw WritingServiceError.timedOut }
        guard corrected.utf8.count <= WritingCorrectionPolicy.maximumOutputBytes else { throw WritingServiceError.invalidSelection }
        guard pasteboard.identity == identity, pasteboard.changeCount == initialChangeCount,
              pasteboard.readText() == original else { throw WritingServiceError.changedSelection }
        // No changes is a successful no-op; the service requestor already owns its original data.
        guard corrected != original else { return }
        guard pasteboard.writeText(corrected) else { throw WritingServiceError.writeFailed }
    }
}

/// One result/deadline winner; useful to both native modal progress and deterministic tests.
@MainActor
final class WritingInlineOperation {
    private let deadline: TimeInterval
    private let now: () -> TimeInterval
    private let onFinish: () -> Void
    private(set) var outcome: Result<WritingCheckReport, WritingCheckError>?
    init(deadline: TimeInterval, now: @escaping () -> TimeInterval, onFinish: @escaping () -> Void) {
        self.deadline = deadline; self.now = now; self.onFinish = onFinish
    }
    func receive(_ result: Result<WritingCheckReport, WritingCheckError>) {
        guard outcome == nil else { return }
        outcome = now() < deadline ? result : .failure(.timedOut)
        onFinish()
    }
    func cancel() { receive(.failure(.cancelled)) }
    func timeOut() {
        guard outcome == nil else { return }
        outcome = .failure(.timedOut)
        onFinish()
    }
}
