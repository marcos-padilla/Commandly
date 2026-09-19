import CommandKit
import Foundation
import Infrastructure
import ModuleKit
import ModuleRuntime
import Testing
@testable import ScreenToolsModule

// MARK: - Doubles

final class FakeBoard: PasteboardAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func readString() async -> String? { lock.withLock { value } }
    func writeString(_ string: String) async { lock.withLock { value = string } }
    func writeFileURLs(_ urls: [URL]) async { _ = urls }
    var current: String? { lock.withLock { value } }
}

@MainActor
final class FakeCapture: ScreenshotCapturing {
    var result: Result<ScreenshotImage, any Error>
    private(set) var captureCount = 0
    init(result: Result<ScreenshotImage, any Error>) { self.result = result }
    func capture(_ request: ScreenshotRequest) async throws -> ScreenshotImage {
        captureCount += 1
        return try result.get()
    }
    func cancel() {}
}

struct FakeRecognizer: ImageRecognizing {
    var result: ImageRecognitionResult = ImageRecognitionResult(text: "hello")
    var error: (any Error)?
    func recognize(
        _ source: ImageConversionSource,
        mode: ImageRecognitionMode
    ) async throws -> ImageRecognitionResult {
        if let error { throw error }
        return result
    }
}

@MainActor
final class FakeSampler: ScreenColorSampling {
    var color: ScreenColor?
    init(color: ScreenColor? = nil) { self.color = color }
    func sampleColor() async -> ScreenColor? { color }
}

@MainActor
enum Fx {
    static func image() throws -> ScreenshotImage {
        // A one-pixel PNG is enough: recognition is faked, so only the plumbing is under test.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==") ?? Data([0x01])
        return try ScreenshotImage(
            pngData: png, previewPNGData: png, kind: .region, pixelWidth: 1, pixelHeight: 1
        )
    }

    static func operations(
        board: FakeBoard,
        capture: FakeCapture,
        recognizer: FakeRecognizer = FakeRecognizer(),
        sampler: FakeSampler = FakeSampler(),
        joinsLines: Bool = false,
        format: ScreenColorFormat = .hex
    ) -> ScreenToolsOperations {
        ScreenToolsOperations(
            capture: { capture },
            recognizer: recognizer,
            sampler: sampler,
            pasteboard: board,
            joinsLines: { joinsLines },
            colorFormat: { format }
        )
    }

    static func invocation(
        _ id: CommandID,
        grants: ModuleCallerGrants = .directUser
    ) -> ModuleCommandInvocation {
        ModuleCommandInvocation(
            commandID: id, arguments: .empty,
            context: CommandInvocationContext(source: .search), grants: grants
        )
    }
}

// MARK: - Colour formatting

struct ScreenColorFormatterTests {
    private let red = ScreenColor(red: 1, green: 0, blue: 0)
    private let grey = ScreenColor(red: 0.5, green: 0.5, blue: 0.5)

    @Test func formatsEveryStyle() {
        #expect(ScreenColorFormatter.string(for: red, format: .hex) == "#FF0000")
        #expect(ScreenColorFormatter.string(for: red, format: .hexWithAlpha) == "#FF0000FF")
        #expect(ScreenColorFormatter.string(for: red, format: .rgb) == "rgb(255, 0, 0)")
        #expect(ScreenColorFormatter.string(for: red, format: .rgba) == "rgba(255, 0, 0, 1.000)")
        #expect(ScreenColorFormatter.string(for: red, format: .hsl) == "hsl(0, 100%, 50%)")
        #expect(
            ScreenColorFormatter.string(for: red, format: .swiftUI)
                == "Color(red: 1.000, green: 0.000, blue: 0.000)"
        )
    }

    @Test func greyHasNoSaturation() {
        #expect(ScreenColorFormatter.string(for: grey, format: .hsl) == "hsl(0, 0%, 50%)")
    }

    @Test func hueIsNeverNegative() {
        // Blue-dominant colours take the branch that can produce a negative hue before wrapping.
        let magenta = ScreenColor(red: 1, green: 0, blue: 1)
        let hsl = ScreenColorFormatter.hslComponents(for: magenta)
        #expect(hsl.hue >= 0 && hsl.hue <= 360)
        #expect(Int(hsl.hue.rounded()) == 300)
    }

    @Test func componentsAreClamped() {
        let wild = ScreenColor(red: 2, green: -1, blue: .nan, alpha: 5)
        #expect(ScreenColorFormatter.string(for: wild, format: .hex) == "#FF0000")
        #expect(wild.alpha == 1)
    }
}

// MARK: - Line joining

struct RecognizedTextJoiningTests {
    @Test func joinsWrappedLinesButKeepsParagraphs() {
        let text = "one\ntwo\n\nthree\nfour"
        #expect(ScreenToolsOperations.joinedLines(of: text) == "one two\n\nthree four")
    }

    @Test func trimsLineWhitespaceWhenJoining() {
        #expect(ScreenToolsOperations.joinedLines(of: "  a  \n  b  ") == "a b")
    }
}

// MARK: - Operations

@MainActor
struct ScreenToolsOperationsTests {
    @Test func copyTextRecognizesAndCopies() async throws {
        let board = FakeBoard()
        let capture = FakeCapture(result: .success(try Fx.image()))
        let operations = Fx.operations(board: board, capture: capture)

        let recognized = try await operations.copyTextFromScreen()

        #expect(board.current == "hello")
        #expect(recognized.characterCount == 5)
        #expect(capture.captureCount == 1)
    }

    @Test func copyTextAppliesTheJoinSetting() async throws {
        let board = FakeBoard()
        let capture = FakeCapture(result: .success(try Fx.image()))
        let recognizer = FakeRecognizer(result: ImageRecognitionResult(text: "one\ntwo"))
        let operations = Fx.operations(
            board: board, capture: capture, recognizer: recognizer, joinsLines: true
        )

        _ = try await operations.copyTextFromScreen()
        #expect(board.current == "one two")
    }

    @Test func emptyRecognitionDoesNotTouchTheClipboard() async throws {
        let board = FakeBoard()
        let capture = FakeCapture(result: .success(try Fx.image()))
        let recognizer = FakeRecognizer(result: ImageRecognitionResult(text: "   \n  "))
        let operations = Fx.operations(board: board, capture: capture, recognizer: recognizer)

        await #expect(throws: ScreenToolsFailure.noTextFound) {
            _ = try await operations.copyTextFromScreen()
        }
        #expect(board.current == nil)
    }

    @Test func aDeniedPermissionIsReportedAsSuch() async {
        let board = FakeBoard()
        let capture = FakeCapture(result: .failure(ScreenshotCaptureError.permissionRequired))
        let operations = Fx.operations(board: board, capture: capture)

        await #expect(throws: ScreenToolsFailure.permissionRequired) {
            _ = try await operations.copyTextFromScreen()
        }
        #expect(board.current == nil)
    }

    @Test func cancellingTheSelectionCopiesNothing() async {
        let board = FakeBoard()
        let capture = FakeCapture(result: .failure(ScreenshotCaptureError.cancelled))
        let operations = Fx.operations(board: board, capture: capture)

        await #expect(throws: ScreenToolsFailure.cancelled) {
            _ = try await operations.copyTextFromScreen()
        }
        #expect(board.current == nil)
    }

    @Test func pickColorCopiesInTheConfiguredFormat() async throws {
        let board = FakeBoard()
        let capture = FakeCapture(result: .success(try Fx.image()))
        let sampler = FakeSampler(color: ScreenColor(red: 0, green: 0, blue: 1))
        let operations = Fx.operations(
            board: board, capture: capture, sampler: sampler, format: .rgb
        )

        let value = try await operations.pickColorFromScreen()
        #expect(value == "rgb(0, 0, 255)")
        #expect(board.current == "rgb(0, 0, 255)")
    }

    @Test func cancellingTheSamplerCopiesNothing() async throws {
        let board = FakeBoard()
        let capture = FakeCapture(result: .success(try Fx.image()))
        let operations = Fx.operations(board: board, capture: capture, sampler: FakeSampler())

        await #expect(throws: ScreenToolsFailure.cancelled) {
            _ = try await operations.pickColorFromScreen()
        }
        #expect(board.current == nil)
    }
}

// MARK: - Handlers and policy

@MainActor
struct ScreenToolsHandlerTests {
    @Test func handlersDenyAnUngrantedCallerWithoutCapturing() async throws {
        let board = FakeBoard()
        let capture = FakeCapture(result: .success(try Fx.image()))
        let operations = Fx.operations(board: board, capture: capture)

        let outcomes = [
            await CopyScreenTextCommandHandler(operations: operations)
                .execute(Fx.invocation(ScreenToolsIdentifiers.copyText, grants: [])),
            await PickScreenColorCommandHandler(operations: operations)
                .execute(Fx.invocation(ScreenToolsIdentifiers.pickColor, grants: []))
        ]
        for outcome in outcomes {
            guard case .denied = outcome else {
                Issue.record("Expected a denial. Got \(outcome).")
                continue
            }
        }
        // Nothing was captured, so no screen content was read for an unauthorized caller.
        #expect(capture.captureCount == 0)
    }

    @Test func aMissingPermissionIsReportedAsUnavailableNotFailure() async throws {
        let board = FakeBoard()
        let capture = FakeCapture(result: .failure(ScreenshotCaptureError.permissionRequired))
        let handler = CopyScreenTextCommandHandler(
            operations: Fx.operations(board: board, capture: capture)
        )
        let outcome = await handler.execute(Fx.invocation(ScreenToolsIdentifiers.copyText))

        guard case .unavailable(let reason, _) = outcome else {
            Issue.record("Expected unavailable. Got \(outcome).")
            return
        }
        #expect(reason == .missingPermission(identifier: ScreenToolsCapability.screenRecording))
    }

    @Test func cancellationIsReportedAsCancelledNotFailure() async {
        let board = FakeBoard()
        let capture = FakeCapture(result: .failure(ScreenshotCaptureError.cancelled))
        let handler = CopyScreenTextCommandHandler(
            operations: Fx.operations(board: board, capture: capture)
        )
        let outcome = await handler.execute(Fx.invocation(ScreenToolsIdentifiers.copyText))
        #expect(outcome == .cancelled)
    }

    @Test func recognizedTextIsNeverReturnedToTheCaller() async throws {
        let board = FakeBoard()
        let capture = FakeCapture(result: .success(try Fx.image()))
        let recognizer = FakeRecognizer(result: ImageRecognitionResult(text: "SECRET TOKEN"))
        let handler = CopyScreenTextCommandHandler(
            operations: Fx.operations(board: board, capture: capture, recognizer: recognizer)
        )
        let outcome = await handler.execute(Fx.invocation(ScreenToolsIdentifiers.copyText))

        guard case .succeeded(let message, let output) = outcome else {
            Issue.record("Expected success. Got \(outcome).")
            return
        }
        // The text goes to the clipboard only. A count is safe; the content is not.
        #expect(message?.contains("SECRET") == false)
        #expect(output[ScreenToolsOutputName.characterCount] == .integer(12))
        #expect(output.values.values.contains(.string("SECRET TOKEN")) == false)
        #expect(board.current == "SECRET TOKEN")
    }
}

struct ScreenToolsPolicyTests {
    @Test func noCommandIsExposedToAI() {
        #expect(ScreenToolsCommands.all.allSatisfy { $0.policy.aiExposure == .hidden })
    }

    @Test func copyTextDeclaresPrivateDisclosureAndThePermission() {
        #expect(ScreenToolsCommands.copyText.policy.disclosure == .localPrivateContent)
        #expect(
            ScreenToolsCommands.copyText.manifest.availabilityRequirements
                == [.permission(identifier: ScreenToolsCapability.screenRecording)]
        )
    }

    @Test func bothToolsNeedNativeSelection() {
        // Each one asks the user to point at something, so neither can run headlessly.
        #expect(ScreenToolsCommands.copyText.policy.executionMode == .requiresUserInterface)
        #expect(ScreenToolsCommands.pickColor.policy.executionMode == .requiresUserInterface)
    }

    @Test func identifiersAreStable() {
        #expect(ScreenToolsIdentifiers.application.rawValue == "screen.tools")
        #expect(ScreenToolsIdentifiers.copyText.rawValue == "screen.tools.copy-text")
        #expect(ScreenToolsIdentifiers.pickColor.rawValue == "screen.tools.pick-color")
    }
}

@MainActor
struct ScreenToolsHostTests {
    private func assembly(
        capture: FakeCapture,
        configuration: StaticScreenToolsConfiguration = StaticScreenToolsConfiguration()
    ) -> ScreenToolsAssembly {
        ScreenToolsAssembly(
            makeCapture: { capture },
            recognizer: FakeRecognizer(),
            sampler: FakeSampler(color: ScreenColor(red: 1, green: 1, blue: 1)),
            pasteboard: FakeBoard(),
            configuration: configuration
        )
    }

    @Test func theModuleRegistersAndValidates() throws {
        let host = ModuleHost()
        #expect(throws: Never.self) {
            try host.register(assembly(capture: FakeCapture(result: .failure(ScreenToolsFailure.cancelled))))
        }
    }

    @Test func metadataDiscoveryCapturesNothing() throws {
        let capture = FakeCapture(result: .failure(ScreenToolsFailure.cancelled))
        let host = ModuleHost()
        try host.register(assembly(capture: capture))

        _ = host.commandDefinitions()
        _ = host.settingsContributions()
        _ = host.documentationContributions()

        #expect(capture.captureCount == 0)
        #expect(host.isActivated(ScreenToolsIdentifiers.module) == false)
    }

    @Test func aMissingPermissionMakesTheModuleUnavailable() throws {
        final class DenyScreenRecording: ModuleCapabilityEvaluating {
            func firstUnmetRequirement(
                among requirements: [ModuleCapabilityRequirement]
            ) -> ModuleCapabilityRequirement? { requirements.first }
        }
        let host = ModuleHost(capabilities: DenyScreenRecording())
        try host.register(assembly(capture: FakeCapture(result: .failure(ScreenToolsFailure.cancelled))))

        #expect(
            host.availability(of: ScreenToolsIdentifiers.module)
                == .permissionRequired(identifier: ScreenToolsCapability.screenRecording)
        )
    }

    @Test func settingsChangeTheCopiedColorFormat() async throws {
        let configuration = StaticScreenToolsConfiguration()
        let board = FakeBoard()
        let assembly = ScreenToolsAssembly(
            makeCapture: { FakeCapture(result: .failure(ScreenToolsFailure.cancelled)) },
            recognizer: FakeRecognizer(),
            sampler: FakeSampler(color: ScreenColor(red: 0, green: 0, blue: 0)),
            pasteboard: board,
            configuration: configuration
        )

        _ = try await assembly.makeOperations().pickColorFromScreen()
        #expect(board.current == "#000000")

        configuration.update([ScreenToolsSettingsVariable.colorFormat: .text(ScreenColorFormat.rgb.rawValue)])
        _ = try await assembly.makeOperations().pickColorFromScreen()
        #expect(board.current == "rgb(0, 0, 0)")
    }

    @Test func anUnknownStoredFormatFallsBackToHex() {
        let format = ScreenToolsSettings.colorFormat(
            from: [ScreenToolsSettingsVariable.colorFormat: .text("not-a-format")]
        )
        #expect(format == .hex)
    }
}
