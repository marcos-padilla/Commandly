import CoreAudio
import Foundation

/// Decides which engine build may be installed when it lands.
///
/// Building a tap takes tens of milliseconds off the main actor, and the mixer can throw every
/// engine away in the meantime. Each build carries the token it started with and is installed
/// only while that token is still the row's current one, so a late build is discarded instead of
/// leaving a second live tap rendering the same app twice.
nonisolated struct MixerEngineBuilds: Sendable {
    private var tokens: [String: Int] = [:]
    private var nextToken = 1

    var isEmpty: Bool { tokens.isEmpty }

    /// Claims the row for a build, or `nil` when one is already in flight — so a slider being
    /// dragged cannot queue a build per tick.
    mutating func begin(_ id: String) -> Int? {
        guard tokens[id] == nil else { return nil }
        let token = nextToken
        nextToken += 1
        tokens[id] = token
        return token
    }

    func isCurrent(_ id: String, token: Int) -> Bool { tokens[id] == token }

    /// Frees the row for the next build. A late build that no longer owns the row leaves the
    /// current one untouched.
    mutating func finish(_ id: String, token: Int) {
        guard tokens[id] == token else { return }
        tokens.removeValue(forKey: id)
    }

    /// Marks everything in flight as stale. Tokens are never reused, so queued builds can no
    /// longer be installed while a fresh build for the same row can start right away.
    mutating func invalidateAll() { tokens.removeAll() }
}

/// Gives one dead audio path a single replacement, then leaves that exact path untapped so a
/// persistent HAL failure cannot keep an app muted.
nonisolated struct MixerEngineRecovery: Sendable {
    struct Configuration: Equatable, Sendable {
        let objects: [AudioObjectID]
        let outputDeviceUID: String
    }

    private struct Failure {
        let configuration: Configuration
        var count: Int
    }

    private var failures: [String: Failure] = [:]

    func allowsBuild(_ id: String, configuration: Configuration) -> Bool {
        guard let failure = failures[id], failure.configuration == configuration else { return true }
        return failure.count < 2
    }

    mutating func recordFailure(_ id: String, configuration: Configuration) -> Bool {
        let count = failures[id]?.configuration == configuration
            ? (failures[id]?.count ?? 0) + 1
            : 1
        failures[id] = Failure(configuration: configuration, count: count)
        return count < 2
    }

    mutating func clear(_ id: String) { failures.removeValue(forKey: id) }

    mutating func clearAll() { failures.removeAll() }
}

/// Arbitrates the refresh passes that read the audio HAL.
///
/// Reading device and process properties happens off the main actor, because a device being
/// reconfigured can hold a single read for as long as the audio daemon holds that device. Only
/// one pass reads at a time, a request that arrives mid-pass is remembered and runs once that
/// pass lands, and a pass whose generation is no longer current is dropped rather than
/// publishing state that is already out of date.
nonisolated struct MixerRefreshCoordinator: Sendable {
    private(set) var generation = 0
    private(set) var isReading = false
    private var requestedAgain = false

    /// Claims the slot for a pass, or `nil` when one is already reading. The request is
    /// remembered either way, so nothing is silently lost.
    mutating func begin() -> Int? {
        guard isReading == false else {
            requestedAgain = true
            return nil
        }
        isReading = true
        generation += 1
        return generation
    }

    /// Frees the slot and reports whether this pass may still publish.
    mutating func finish(_ generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        isReading = false
        return true
    }

    /// Whether a refresh was asked for while the pass was reading; clears the request so it runs
    /// exactly once.
    mutating func takeRepeatRequest() -> Bool {
        defer { requestedAgain = false }
        return requestedAgain
    }

    /// Drops whatever is in flight: what it read is already out of date.
    mutating func discardInFlight() {
        generation += 1
        isReading = false
        requestedAgain = false
    }
}
