import Foundation

/// Microphone authorization, read without starting capture or requesting permission.
public enum DictationMicrophoneAuthorization: Sendable, Equatable { case notDetermined, authorized, denied, restricted }
/// Explicit microphone permission and Settings recovery boundary; never called automatically at launch.
public protocol DictationMicrophoneAuthorizing: Sendable {
    /// Reads the current grant without prompting.
    func authorization() async -> DictationMicrophoneAuthorization
    /// Requests an undetermined grant only after explicit user intent.
    func requestAuthorization() async -> DictationMicrophoneAuthorization
    /// Opens the microphone privacy settings after an explicit action.
    func openSettings() async
}
/// One supported on-device recognition locale. Selecting it does not download assets or open audio.
public struct DictationLanguage: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let name: String
    /// The recognizer selected for this locale; both choices are on-device.
    public let engine: DictationRecognitionEngine
    public init(id: String, name: String, engine: DictationRecognitionEngine) { self.id = id; self.name = name; self.engine = engine }
}
/// Native engine choice based on hardware and locale support, never a server fallback.
public enum DictationRecognitionEngine: String, Equatable, Codable, Sendable { case speechTranscriber, dictationTranscriber }
/// Availability of a chosen locale's system-managed assets.
public enum DictationModelAvailability: Sendable, Equatable { case unsupported, downloadRequired, downloading, installed }
/// Locale support and model downloads. Downloads require an explicit separate user action.
public protocol DictationLanguageProviding: Sendable {
    /// Lists only native on-device locales supported by this hardware and OS.
    func languages() async throws -> [DictationLanguage]
    /// Returns a supported equivalent of the system locale, without detecting spoken audio.
    func preferredLanguageID() async -> String?
    /// Inspects system-managed model state without downloading.
    func availability(for language: DictationLanguage) async throws -> DictationModelAvailability
    /// Downloads chosen system-managed assets after a separate explicit user action.
    func download(language: DictationLanguage) async throws
}
/// A currently connected microphone, never persisted or logged.
public struct DictationMicrophone: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let isDefault: Bool
    public init(id: String, name: String, isDefault: Bool) { self.id = id; self.name = name; self.isDefault = isDefault }
}
/// An explicit recording intent with an identity allocated before asynchronous preparation begins.
public struct DictationCaptureRequest: Sendable, Equatable {
    public let id: UUID
    public let language: DictationLanguage
    public let microphoneID: String?
    public init(id: UUID = UUID(), language: DictationLanguage, microphoneID: String? = nil) {
        self.id = id; self.language = language; self.microphoneID = microphoneID
    }
}
/// A full replacement transcript snapshot, with no audio or native framework objects.
public struct DictationTranscript: Sendable, Equatable {
    public let text: String
    public let containsProvisionalText: Bool
    public init(text: String, containsProvisionalText: Bool) throws {
        guard text.utf8.count <= 64 * 1_024 else { throw DictationError.transcriptLimit }
        self.text = text; self.containsProvisionalText = containsProvisionalText
    }
}
/// Terminal events are emitted only after microphone shutdown. Snapshots replace prior UI text.
public enum DictationCaptureEvent: Sendable, Equatable {
    case transcript(DictationTranscript)
    case finished(DictationTranscript, reachedDurationLimit: Bool)
    case failed(DictationError, transcript: DictationTranscript?)
    case cancelled
}
/// The microphone and bounded event stream belonging to one explicit request.
public struct DictationCaptureSession: Sendable {
    public let id: UUID
    public let microphone: DictationMicrophone
    public let events: AsyncStream<DictationCaptureEvent>
    public init(id: UUID, microphone: DictationMicrophone, events: AsyncStream<DictationCaptureEvent>) {
        self.id = id; self.microphone = microphone; self.events = events
    }
}
/// Audio-only native capture. Initialization and device listing must not create or start an input.
public protocol DictationCapturing: Sendable {
    /// Lists input metadata without creating or starting an audio input.
    func microphones() async throws -> [DictationMicrophone]
    /// Starts one authorized request; terminal events follow input shutdown.
    func start(_ request: DictationCaptureRequest) async throws -> DictationCaptureSession
    /// Stops microphone input immediately, then drains final recognition results for review.
    func finish(requestID: UUID) async throws
    /// Stops/rejects this specific pending or active request and discards remaining native analysis.
    func cancel(requestID: UUID) async
}
/// Sanitized failures that never contain audio, transcripts, device details, or native provider errors.
public enum DictationError: Error, Sendable, Equatable, LocalizedError {
    case permissionRequired, permissionDenied, permissionRestricted, noMicrophone, microphoneUnavailable
    case languageUnsupported, modelDownloadRequired, modelUnavailable, downloadFailed, busy
    case startFailed, interrupted, recognitionFailed, transcriptLimit, historyUnavailable, historyCorrupt, historyFull
    case rewriteUnavailable, rewriteTooLong, invalidRewrite
    public var errorDescription: String? {
        switch self {
        case .permissionRequired: "Start Dictation to allow microphone access."
        case .permissionDenied: "Microphone access is denied. Enable Commandly in System Settings → Privacy & Security → Microphone, then start again."
        case .permissionRestricted: "Microphone access is restricted. Ask the device administrator to change this restriction."
        case .noMicrophone: "No microphone is available. Connect one and refresh microphones."
        case .microphoneUnavailable: "The selected microphone is unavailable. Refresh microphones and choose another input."
        case .languageUnsupported: "This language is not supported by on-device recognition on this Mac. Choose another language."
        case .modelDownloadRequired: "Download this language model before starting dictation."
        case .modelUnavailable: "The speech model is unavailable or its reservation limit was reached. Refresh languages or restart Commandly and try again."
        case .downloadFailed: "The language model could not be downloaded. Check your connection and available storage, then retry."
        case .busy: "The previous recording is still stopping. Wait before starting another."
        case .startFailed: "The microphone could not start. Check its connection and permission, then retry."
        case .interrupted: "The microphone was interrupted or disconnected. Review the available text, then start a new recording."
        case .recognitionFailed: "On-device transcription stopped unexpectedly. Review the available text and retry."
        case .transcriptLimit: "The transcript reached the 64 KiB limit. Review this text and start a new recording."
        case .historyUnavailable: "Saved dictations could not be read or written. Your current text is still available to copy."
        case .historyCorrupt: "Saved dictation history is unreadable. Clear History can reset it; your current draft remains available."
        case .historyFull: "History is full. Delete earlier dictations before saving another."
        case .rewriteUnavailable: "Writing style is unavailable. Check your provider in AI Settings or try another model."
        case .rewriteTooLong: "Writing styles support up to 8 KiB of text. Shorten the text or keep the original."
        case .invalidRewrite: "The model did not return a complete, valid rewrite. Your original text is unchanged."
        }
    }
}
