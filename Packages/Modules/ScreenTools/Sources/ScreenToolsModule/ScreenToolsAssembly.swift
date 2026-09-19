import CommandKit
import Foundation
import Infrastructure
import ModuleKit

/// Supplies the Screen Tools module's current configuration.
@MainActor
public protocol ScreenToolsConfigurationProviding: AnyObject, Sendable {
    /// Current values for the module's declared configuration variables.
    func currentValues() -> [String: ModuleConfigurationValue]
}

/// Configuration provider backed by a fixed dictionary, for tests and previews.
@MainActor
public final class StaticScreenToolsConfiguration: ScreenToolsConfigurationProviding {
    private var values: [String: ModuleConfigurationValue]

    /// Creates a provider.
    public init(values: [String: ModuleConfigurationValue] = [:]) {
        self.values = values
    }

    /// Replaces the configuration, as a settings change would.
    public func update(_ values: [String: ModuleConfigurationValue]) {
        self.values = values
    }

    public func currentValues() -> [String: ModuleConfigurationValue] { values }
}

/// Narrow assembly for the Screen Tools module.
///
/// It receives capture, recognition, sampling, and pasteboard interfaces, and nothing else. Reading
/// its metadata constructs no capture session and requests no permission; a capture session is
/// created only when an operation actually runs.
@MainActor
public struct ScreenToolsAssembly: ModuleAssembly {
    private let makeCapture: @MainActor () -> any ScreenshotCapturing
    private let recognizer: any ImageRecognizing
    private let sampler: any ScreenColorSampling
    private let pasteboard: any PasteboardAccessing
    private let configuration: any ScreenToolsConfigurationProviding

    /// Creates the assembly.
    public init(
        makeCapture: @escaping @MainActor () -> any ScreenshotCapturing,
        recognizer: any ImageRecognizing,
        sampler: any ScreenColorSampling,
        pasteboard: any PasteboardAccessing,
        configuration: any ScreenToolsConfigurationProviding
    ) {
        self.makeCapture = makeCapture
        self.recognizer = recognizer
        self.sampler = sampler
        self.pasteboard = pasteboard
        self.configuration = configuration
    }

    public var manifest: ModuleManifest { ScreenToolsManifest.value }

    public var commandDefinitions: [ModuleCommandDefinition] { ScreenToolsCommands.all }

    public var settings: ModuleSettingsContribution? { ScreenToolsSettings.contribution }

    public var documentation: ModuleDocumentationContribution? {
        ScreenToolsDocumentation.contribution
    }

    /// Builds the module's operations from the injected interfaces.
    ///
    /// Exposed so the shell can bind its surface to the same operations the commands run, rather
    /// than constructing a second copy.
    public func makeOperations() -> ScreenToolsOperations {
        let configuration = self.configuration
        return ScreenToolsOperations(
            capture: makeCapture,
            recognizer: recognizer,
            sampler: sampler,
            pasteboard: pasteboard,
            joinsLines: {
                ScreenToolsSettings.joinsRecognizedLines(from: configuration.currentValues())
            },
            colorFormat: {
                ScreenToolsSettings.colorFormat(from: configuration.currentValues())
            }
        )
    }

    public func activate() async throws -> ModuleActivation {
        let operations = makeOperations()
        return ModuleActivation(
            handlers: [
                ScreenToolsIdentifiers.copyText: CopyScreenTextCommandHandler(operations: operations),
                ScreenToolsIdentifiers.pickColor: PickScreenColorCommandHandler(operations: operations),
                ScreenToolsIdentifiers.application: ScreenToolsPresentationHandler()
            ]
        )
    }
}
