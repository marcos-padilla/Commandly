import CommandKit
import Foundation
import Infrastructure
import ModuleKit

/// Samples a single pixel's colour after the user points at it.
///
/// Behind a protocol so the operation is testable without a real screen. A live implementation
/// uses the system colour sampler, which needs no permission because the person picks the pixel.
@MainActor
public protocol ScreenColorSampling: Sendable {
    /// Presents the sampler and returns the chosen colour, or `nil` when the user cancelled.
    func sampleColor() async -> ScreenColor?
}

/// Sampler that always cancels, for tests and unsupported hosts.
@MainActor
public final class UnavailableScreenColorSampler: ScreenColorSampling {
    public init() {}
    public func sampleColor() async -> ScreenColor? { nil }
}

/// Why a screen operation could not complete.
public enum ScreenToolsFailure: Error, Equatable, Sendable {
    /// The user dismissed the selection or the sampler.
    case cancelled
    /// Screen capture is not permitted.
    case permissionRequired
    /// Capture or recognition failed.
    case unavailable
    /// The selection contained no readable text.
    case noTextFound
}

/// Output names produced by the module's commands.
public enum ScreenToolsOutputName {
    /// Number of characters recognised. The text itself is never returned to a caller.
    public static let characterCount = "characterCount"
    /// Whether the recognised text was truncated to stay within limits.
    public static let isTruncated = "isTruncated"
    /// The copied colour string.
    public static let color = "color"
}

/// The module's screen operations.
///
/// Both operations are composed from contracts the application already owns — screenshot capture,
/// on-device recognition, and the pasteboard — rather than reaching for the screen directly.
@MainActor
public struct ScreenToolsOperations {
    private let capture: @MainActor () -> any ScreenshotCapturing
    private let recognizer: any ImageRecognizing
    private let sampler: any ScreenColorSampling
    private let pasteboard: any PasteboardAccessing
    private let joinsLines: @MainActor () -> Bool
    private let colorFormat: @MainActor () -> ScreenColorFormat

    /// Creates the operations.
    public init(
        capture: @escaping @MainActor () -> any ScreenshotCapturing,
        recognizer: any ImageRecognizing,
        sampler: any ScreenColorSampling,
        pasteboard: any PasteboardAccessing,
        joinsLines: @escaping @MainActor () -> Bool = { false },
        colorFormat: @escaping @MainActor () -> ScreenColorFormat = { .hex }
    ) {
        self.capture = capture
        self.recognizer = recognizer
        self.sampler = sampler
        self.pasteboard = pasteboard
        self.joinsLines = joinsLines
        self.colorFormat = colorFormat
    }

    /// Recognised-text result, described without carrying the text to the caller.
    public struct RecognizedText: Sendable, Equatable {
        public let characterCount: Int
        public let isTruncated: Bool
    }

    /// Captures a user-selected region, recognises its text, and copies it.
    ///
    /// The recognised text goes to the clipboard and nowhere else: it is deliberately not part of
    /// the returned value, so a caller cannot read private screen content out of the result.
    public func copyTextFromScreen() async throws -> RecognizedText {
        let image: ScreenshotImage
        do {
            image = try await capture().capture(ScreenshotRequest(kind: .region))
        } catch let error as ScreenshotCaptureError {
            throw Self.failure(for: error)
        } catch is CancellationError {
            throw ScreenToolsFailure.cancelled
        } catch {
            throw ScreenToolsFailure.unavailable
        }

        let source = ImageConversionSource(
            data: image.pngData,
            previewPNGData: image.previewPNGData,
            filename: "screen-selection.png",
            pixelWidth: image.pixelWidth,
            pixelHeight: image.pixelHeight
        )

        let result: ImageRecognitionResult
        do {
            result = try await recognizer.recognize(source, mode: .text)
        } catch is CancellationError {
            throw ScreenToolsFailure.cancelled
        } catch {
            throw ScreenToolsFailure.unavailable
        }

        let text = joinsLines() ? Self.joinedLines(of: result.text) : result.text
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ScreenToolsFailure.noTextFound
        }
        await pasteboard.writeString(text)
        return RecognizedText(characterCount: text.count, isTruncated: result.isTruncated)
    }

    /// Samples a pixel and copies its colour in the configured format.
    ///
    /// Returns the copied string, which describes a colour and no private content.
    public func pickColorFromScreen() async throws -> String {
        guard let color = await sampler.sampleColor() else {
            throw ScreenToolsFailure.cancelled
        }
        let text = ScreenColorFormatter.string(for: color, format: colorFormat())
        await pasteboard.writeString(text)
        return text
    }

    /// Collapses hard-wrapped lines into one paragraph while keeping blank-line breaks.
    nonisolated static func joinedLines(of text: String) -> String {
        text
            .components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: " ")
            }
            .joined(separator: "\n\n")
    }

    private static func failure(for error: ScreenshotCaptureError) -> ScreenToolsFailure {
        switch error {
        case .permissionRequired:
            return .permissionRequired
        case .cancelled:
            return .cancelled
        default:
            return .unavailable
        }
    }
}

/// Handler for ``ScreenToolsIdentifiers/copyText``.
@MainActor
public struct CopyScreenTextCommandHandler: ModuleCommandHandling {
    private let operations: ScreenToolsOperations

    /// Creates the handler.
    public init(operations: ScreenToolsOperations) {
        self.operations = operations
    }

    public func execute(_ invocation: ModuleCommandInvocation) async -> ModuleCommandOutcome {
        guard invocation.grants.satisfy(ScreenToolsCommands.copyText.policy) else {
            return .denied(
                reason: .missingCallerGrant,
                message: "This caller isn’t allowed to read the screen."
            )
        }
        do {
            let recognized = try await operations.copyTextFromScreen()
            let suffix = recognized.isTruncated ? " Some text was left out." : ""
            return .succeeded(
                message: "Copied \(recognized.characterCount) characters.\(suffix)",
                output: ModuleCommandOutput([
                    ScreenToolsOutputName.characterCount: .integer(recognized.characterCount),
                    ScreenToolsOutputName.isTruncated: .boolean(recognized.isTruncated)
                ])
            )
        } catch {
            return ScreenToolsOutcome.outcome(for: error)
        }
    }
}

/// Handler for ``ScreenToolsIdentifiers/pickColor``.
@MainActor
public struct PickScreenColorCommandHandler: ModuleCommandHandling {
    private let operations: ScreenToolsOperations

    /// Creates the handler.
    public init(operations: ScreenToolsOperations) {
        self.operations = operations
    }

    public func execute(_ invocation: ModuleCommandInvocation) async -> ModuleCommandOutcome {
        guard invocation.grants.satisfy(ScreenToolsCommands.pickColor.policy) else {
            return .denied(
                reason: .missingCallerGrant,
                message: "This caller isn’t allowed to change the clipboard."
            )
        }
        do {
            let value = try await operations.pickColorFromScreen()
            return .succeeded(
                message: "Copied \(value).",
                output: ModuleCommandOutput([ScreenToolsOutputName.color: .string(value)])
            )
        } catch {
            return ScreenToolsOutcome.outcome(for: error)
        }
    }
}

/// Handler for the module's presentation command.
@MainActor
public struct ScreenToolsPresentationHandler: ModuleCommandHandling {
    /// Creates the handler.
    public init() {}

    public func execute(_ invocation: ModuleCommandInvocation) async -> ModuleCommandOutcome {
        _ = invocation
        return .interactionRequired(message: "Opening Screen Tools needs Commandly’s window.")
    }
}

/// Maps screen failures onto truthful command outcomes.
enum ScreenToolsOutcome {
    static func outcome(for error: any Error) -> ModuleCommandOutcome {
        guard let failure = error as? ScreenToolsFailure else {
            return .failed(message: "That screen action couldn’t be completed.")
        }
        switch failure {
        case .cancelled:
            return .cancelled
        case .permissionRequired:
            return .unavailable(
                reason: .missingPermission(identifier: ScreenToolsCapability.screenRecording),
                message: "Screen Recording permission is needed to read the screen."
            )
        case .noTextFound:
            return .failed(message: "No readable text was found in that selection.")
        case .unavailable:
            return .failed(message: "That screen action couldn’t be completed.")
        }
    }
}
