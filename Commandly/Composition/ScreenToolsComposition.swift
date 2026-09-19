import AppKit
import Infrastructure
import CommandKit
import Foundation
import ModuleKit
import ScreenToolsModule

/// Samples a screen pixel with the system colour sampler.
///
/// `NSColorSampler` is public API and needs no permission: the person points at the pixel
/// themselves, and macOS owns the loupe. Nothing is captured or retained.
@MainActor
final class SystemScreenColorSampler: ScreenColorSampling {
    func sampleColor() async -> ScreenColor? {
        await withCheckedContinuation { continuation in
            NSColorSampler().show { color in
                guard let color,
                      let srgb = color.usingColorSpace(.sRGB) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: ScreenColor(
                        red: Double(srgb.redComponent),
                        green: Double(srgb.greenComponent),
                        blue: Double(srgb.blueComponent),
                        alpha: Double(srgb.alphaComponent)
                    )
                )
            }
        }
    }
}

/// Reads the Screen Tools module's configuration from the launcher's existing preferences.
/// The registry is installed after it is built, because the launcher application this reads
/// settings for is itself registered while the registry is being constructed. Until then the
/// module falls back to its declared defaults rather than guessing.
@MainActor
final class LauncherRegistryScreenToolsConfiguration: ScreenToolsConfigurationProviding {
    private weak var registry: LauncherApplicationRegistry?
    private let applicationID: CommandID

    init(
        registry: LauncherApplicationRegistry? = nil,
        applicationID: CommandID = ScreenToolsIdentifiers.application
    ) {
        self.registry = registry
        self.applicationID = applicationID
    }

    /// Binds the registry once it exists.
    func install(registry: LauncherApplicationRegistry) {
        self.registry = registry
    }

    func currentValues() -> [String: ModuleConfigurationValue] {
        guard let settings = registry?.resolvedSettings(for: applicationID) else { return [:] }
        return settings.configuration.mapValues { $0.moduleValue }
    }
}

/// Capture that always reports the selection is unavailable.
///
/// Used by the registry's preview and test construction so building a registry never creates a
/// real capture session.
@MainActor
final class UnavailableScreenToolsCapture: ScreenshotCapturing {
    func capture(_ request: ScreenshotRequest) async throws -> ScreenshotImage {
        throw ScreenshotCaptureError.selectionUnavailable
    }
    func cancel() {}
}

/// Recognizer that returns nothing, for preview and test construction.
struct InMemoryImageRecognitionService: ImageRecognizing {
    func recognize(
        _ source: ImageConversionSource,
        mode: ImageRecognitionMode
    ) async throws -> ImageRecognitionResult {
        ImageRecognitionResult()
    }
}
