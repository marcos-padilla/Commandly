import Infrastructure

/// Native start/stop/output callbacks can arrive in either order. Review and deletion require both
/// capture shutdown and output finalization; a failed stop never masquerades as capture shutdown.
nonisolated struct ScreenRecordingLifecycle {
    var captureStarted = false
    var outputStarted = false
    var sentStarted = false
    var captureStopped = false
    var outputFinished = false
    var stopIssued = false
    var stopFailed = false
    var stopReason: ScreenRecordingStopReason?
    var sentStopping = false
    var cancelled = false
    var ended = false
    var failure: ScreenRecordingError?

    mutating func requestStop(_ reason: ScreenRecordingStopReason, retry: Bool = false) {
        if stopReason == nil { stopReason = reason }
        if retry, stopFailed { stopFailed = false; stopIssued = false }
    }

    mutating func claimStarted() -> Bool {
        guard !ended, captureStarted, outputStarted, !sentStarted, stopReason == nil, !cancelled else { return false }
        sentStarted = true
        return true
    }

    mutating func claimStopping() -> ScreenRecordingStopReason? {
        guard !ended, !sentStopping, let stopReason else { return nil }
        sentStopping = true
        return stopReason
    }

    mutating func captureStopCompleted(_ error: ScreenRecordingError?) -> Bool {
        guard !ended else { return false }
        if error != nil {
            // Keep the native stream and visible controls alive. The user can retry Stop or use
            // macOS's recording indicator. Do not delete or export while capture might continue.
            stopFailed = true
            return !captureStopped
        }
        captureStopped = true
        return false
    }

    mutating func claimCompletion(summary: ScreenRecordingSummary) -> ScreenRecordingEvent? {
        guard !ended, captureStopped, outputFinished else { return nil }
        ended = true
        if cancelled { return .cancelled }
        if let failure { return .failed(failure) }
        return .finished(summary)
    }
}
