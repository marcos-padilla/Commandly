import CommandKit
import Foundation
import ModuleKit

/// Stable identifiers owned by the Clipboard Tools module.
///
/// These are persisted in Command Wheel profiles, menu-bar pins, shortcut overrides and usage
/// history, so they must not change once shipped.
public enum ClipboardToolsIdentifiers {
    /// The module itself.
    public static let module = ModuleID(rawValue: "clipboard-tools")
    /// The Clipboard Tools launcher application.
    public static let application = CommandID(rawValue: "clipboard.tools")
    /// Replaces the clipboard's contents with its plain text.
    public static let plainText = CommandID(rawValue: "clipboard.tools.plain-text")
    /// Removes tracking parameters from a copied link.
    public static let cleanURL = CommandID(rawValue: "clipboard.tools.clean-url")
    /// Clears the system clipboard immediately.
    public static let clearNow = CommandID(rawValue: "clipboard.tools.clear")
}

/// Configuration variables owned by the module.
public enum ClipboardToolsSettingsVariable {
    /// Extra query parameter names the user wants stripped.
    public static let additionalTrackingParameters = "additionalTrackingParameters"
    /// Whether a copied link is cleaned automatically.
    public static let cleanLinksAutomatically = "cleanLinksAutomatically"
    /// Seconds of inactivity before the clipboard clears. Zero disables it.
    public static let autoClearIdleSeconds = "autoClearIdleSeconds"
    /// Clear when the Mac sleeps.
    public static let autoClearOnSystemSleep = "autoClearOnSystemSleep"
    /// Clear when the display sleeps.
    public static let autoClearOnDisplaySleep = "autoClearOnDisplaySleep"
    /// Clear when the screen locks.
    public static let autoClearOnScreenLock = "autoClearOnScreenLock"
}

/// Canonical command definitions for the Clipboard Tools module.
public enum ClipboardToolsCommands {
    /// Opens the Clipboard Tools surface.
    public static let application = ModuleCommandDefinition(
        manifest: CommandManifest(
            id: ClipboardToolsIdentifiers.application,
            title: "Clipboard Tools",
            subtitle: "Flatten formatting, clean links, and clear the clipboard",
            systemImage: "doc.on.clipboard",
            category: .productivity,
            mode: .view,
            keywords: ["clipboard", "paste", "plain text", "clean", "clear"],
            badgeTitle: "Application"
        ),
        summary: "Opens the Clipboard Tools application surface.",
        policy: ModuleCommandPolicy(
            executionMode: .requiresUserInterface,
            effect: .readOnly,
            aiExposure: .hidden,
            isIdempotent: true
        )
    )

    /// Strips formatting from the clipboard so the next ordinary paste arrives as plain text.
    ///
    /// Commandly is sandboxed and does not synthesise keystrokes into other applications, so this
    /// deliberately flattens the clipboard rather than performing the paste itself. The user then
    /// pastes normally. This is stated plainly in the module's documentation so nobody expects a
    /// keystroke that is not sent.
    public static let plainText = ModuleCommandDefinition(
        manifest: CommandManifest(
            id: ClipboardToolsIdentifiers.plainText,
            title: "Clipboard to Plain Text",
            subtitle: "Drop fonts, colors, and links from what you copied",
            systemImage: "textformat",
            category: .productivity,
            mode: .action,
            keywords: ["plain text", "paste", "formatting", "strip", "unformatted"],
            badgeTitle: "Tool"
        ),
        summary: "Replaces the clipboard's rich text with its plain text so the next paste is unformatted.",
        policy: ModuleCommandPolicy(
            executionMode: .direct,
            effect: .localMutation,
            // The command rewrites private clipboard content in place. It never returns that
            // content to its caller, so nothing is disclosed.
            disclosure: .none,
            aiExposure: .hidden,
            isIdempotent: true
        )
    )

    /// Removes tracking parameters from a copied link.
    public static let cleanURL = ModuleCommandDefinition(
        manifest: CommandManifest(
            id: ClipboardToolsIdentifiers.cleanURL,
            title: "Clean Copied Link",
            subtitle: "Remove tracking parameters from the copied URL",
            systemImage: "link",
            category: .productivity,
            mode: .action,
            keywords: ["clean url", "link", "tracking", "utm", "share"],
            badgeTitle: "Tool"
        ),
        summary: "Removes known tracking parameters from the copied link, leaving its destination unchanged.",
        policy: ModuleCommandPolicy(
            executionMode: .direct,
            effect: .localMutation,
            disclosure: .none,
            aiExposure: .hidden,
            isIdempotent: true
        )
    )

    /// Clears the system clipboard immediately.
    public static let clearNow = ModuleCommandDefinition(
        manifest: CommandManifest(
            id: ClipboardToolsIdentifiers.clearNow,
            title: "Clear Clipboard",
            subtitle: "Empty the system clipboard now",
            systemImage: "xmark.bin",
            category: .productivity,
            mode: .action,
            keywords: ["clear clipboard", "empty", "wipe", "privacy"],
            badgeTitle: "Tool"
        ),
        summary: "Empties the system clipboard. Saved Clipboard History entries are not deleted.",
        policy: ModuleCommandPolicy(
            executionMode: .direct,
            effect: .localMutation,
            disclosure: .none,
            aiExposure: .hidden,
            isIdempotent: true
        )
    )

    /// Every command the module owns, in stable order.
    public static let all: [ModuleCommandDefinition] = [
        application, plainText, cleanURL, clearNow
    ]
}

/// Static manifest for the Clipboard Tools module.
public enum ClipboardToolsManifest {
    /// Module metadata. Reading it constructs nothing.
    public static let value = ModuleManifest(
        id: ClipboardToolsIdentifiers.module,
        title: "Clipboard Tools",
        summary: "Flatten copied formatting, strip tracking from links, and clear the clipboard on your terms.",
        status: .shipping,
        ownedApplicationIDs: [ClipboardToolsIdentifiers.application],
        ownedCommandIDs: ClipboardToolsCommands.all.map(\.id),
        capabilities: [],
        // Auto-clear is background behavior: it has to be running before the user copies
        // something, not after they first open a launcher surface.
        activationPolicy: .atLaunchWhenEnabled,
        configurationVersion: 1,
        documentationArticleIDs: [ClipboardToolsDocumentation.overviewArticleID]
    )
}
