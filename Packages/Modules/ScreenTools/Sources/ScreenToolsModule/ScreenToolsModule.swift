import CommandKit
import Foundation
import ModuleKit

/// Stable identifiers owned by the Screen Tools module.
public enum ScreenToolsIdentifiers {
    /// The module itself.
    public static let module = ModuleID(rawValue: "screen-tools")
    /// The Screen Tools launcher application.
    public static let application = CommandID(rawValue: "screen.tools")
    /// Selects an area of the screen and copies the text recognised in it.
    public static let copyText = CommandID(rawValue: "screen.tools.copy-text")
    /// Samples a pixel's colour and copies it in the chosen format.
    public static let pickColor = CommandID(rawValue: "screen.tools.pick-color")
}

/// Configuration variables owned by the module.
public enum ScreenToolsSettingsVariable {
    /// Format used when a sampled colour is copied.
    public static let colorFormat = "screenColorFormat"
    /// Whether recognised line breaks are joined into one paragraph.
    public static let joinRecognizedLines = "joinRecognizedLines"
}

/// Canonical command definitions for the Screen Tools module.
public enum ScreenToolsCommands {
    /// Opens the Screen Tools surface.
    public static let application = ModuleCommandDefinition(
        manifest: CommandManifest(
            id: ScreenToolsIdentifiers.application,
            title: "Screen Tools",
            subtitle: "Copy text from the screen and pick colors",
            systemImage: "viewfinder",
            category: .productivity,
            mode: .view,
            keywords: ["screen", "ocr", "text", "color", "picker"],
            badgeTitle: "Application"
        ),
        summary: "Opens the Screen Tools application surface.",
        policy: ModuleCommandPolicy(
            executionMode: .requiresUserInterface,
            effect: .readOnly,
            aiExposure: .hidden,
            isIdempotent: true
        )
    )

    /// Recognises text inside a screen selection and copies it.
    ///
    /// Requires the Screen Recording permission, which the host evaluates from cached state. The
    /// user draws the selection themselves, so nothing is captured without an explicit gesture.
    public static let copyText = ModuleCommandDefinition(
        manifest: CommandManifest(
            id: ScreenToolsIdentifiers.copyText,
            title: "Copy Text From Screen",
            subtitle: "Select an area and copy the text recognized in it",
            systemImage: "text.viewfinder",
            category: .productivity,
            mode: .action,
            keywords: ["ocr", "copy text", "screen", "recognize", "scan"],
            availabilityRequirements: [.permission(identifier: ScreenToolsCapability.screenRecording)],
            badgeTitle: "Tool"
        ),
        summary: "Recognizes text in a screen area you select and copies it to the clipboard.",
        policy: ModuleCommandPolicy(
            executionMode: .requiresUserInterface,
            effect: .localMutation,
            // Recognised text is private screen content. It is written to the clipboard and never
            // returned to the caller.
            disclosure: .localPrivateContent,
            aiExposure: .hidden,
            isIdempotent: false
        )
    )

    /// Samples a screen pixel's colour and copies it.
    public static let pickColor = ModuleCommandDefinition(
        manifest: CommandManifest(
            id: ScreenToolsIdentifiers.pickColor,
            title: "Pick Color From Screen",
            subtitle: "Sample any pixel and copy it in your format",
            systemImage: "eyedropper",
            category: .productivity,
            mode: .action,
            keywords: ["color picker", "eyedropper", "hex", "rgb", "sample"],
            badgeTitle: "Tool"
        ),
        summary: "Samples a pixel's color from the screen and copies it in the configured format.",
        policy: ModuleCommandPolicy(
            executionMode: .requiresUserInterface,
            effect: .localMutation,
            disclosure: .none,
            aiExposure: .hidden,
            isIdempotent: false
        )
    )

    /// Every command the module owns, in stable order.
    public static let all: [ModuleCommandDefinition] = [application, copyText, pickColor]
}

/// Capability identifiers the module declares.
public enum ScreenToolsCapability {
    /// Matches the permission identifier the host's permission service uses for screen capture.
    public static let screenRecording = "screen-recording"
}

/// Static manifest for the Screen Tools module.
public enum ScreenToolsManifest {
    /// Module metadata. Reading it constructs nothing and prompts for nothing.
    public static let value = ModuleManifest(
        id: ScreenToolsIdentifiers.module,
        title: "Screen Tools",
        summary: "Copy text out of anything on screen, and sample colors from any pixel.",
        status: .shipping,
        ownedApplicationIDs: [ScreenToolsIdentifiers.application],
        ownedCommandIDs: ScreenToolsCommands.all.map(\.id),
        capabilities: [.permission(identifier: ScreenToolsCapability.screenRecording)],
        activationPolicy: .onDemand,
        configurationVersion: 1,
        documentationArticleIDs: [ScreenToolsDocumentation.overviewArticleID]
    )
}
