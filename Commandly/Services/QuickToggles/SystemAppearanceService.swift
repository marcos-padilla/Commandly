import AppKit
import CoreServices
import Foundation

/// Typed failures from reading or changing the system appearance.
nonisolated enum SystemAppearanceError: Error, Equatable, Sendable {
    /// System Events is not running and could not be reached.
    case systemEventsUnavailable
    /// The user has not allowed Commandly to control System Events.
    case notAuthorized
    /// The event was delivered but System Events refused or failed it.
    case changeFailed
}

/// Reads and flips the whole Mac's light/dark appearance.
///
/// Reading is a plain global-preferences lookup. Changing it is the one thing macOS exposes only
/// through System Events, so the change is a single fixed Apple Event with no caller-supplied
/// codes and no script text — the same shape as Commandly's Finder reads.
nonisolated protocol SystemAppearanceControlling: Sendable {
    /// `true` when the Mac is in dark mode, `nil` when the setting could not be read.
    func isDarkModeEnabled() -> Bool?
    /// Switches the whole system. Throws rather than reporting a change it did not make.
    func setDarkModeEnabled(_ enabled: Bool) async throws
}

/// System Events adapter for the system appearance.
nonisolated struct SystemEventsAppearanceService: SystemAppearanceControlling {
    private static let systemEventsBundleIdentifier = "com.apple.systemevents"

    /// Event codes from the installed System Events scripting definition and the public Apple
    /// Event headers. Nothing here is built from caller input.
    private enum Code {
        static let core: UInt32 = 0x636F7265 // core
        static let setData: UInt32 = 0x73657464 // setd
        static let directObject: UInt32 = 0x2D2D2D2D // ----
        static let dataParameter: UInt32 = 0x64617461 // data
        static let errorNumber: UInt32 = 0x6572726E // errn
        static let property: UInt32 = 0x70726F70 // prop
        static let formProperty: UInt32 = 0x70726F70 // prop
        static let wantKey: UInt32 = 0x77616E74 // want
        static let formKey: UInt32 = 0x666F726D // form
        static let seldKey: UInt32 = 0x73656C64 // seld
        static let fromKey: UInt32 = 0x66726F6D // from
        /// System Events' `appearance preferences` object.
        static let appearancePreferences: UInt32 = 0x70416E63 // pAnc
        /// Its `dark mode` property.
        static let darkMode: UInt32 = 0x70416E44 // pAnD
    }

    /// Apple Event error numbers that mean consent, not a broken request.
    private static let notAuthorizedErrors: Set<Int> = [-1_743, -1_744]

    func isDarkModeEnabled() -> Bool? {
        // The global domain is readable from the sandbox; only writing it is refused. macOS omits
        // the key entirely in light mode rather than storing "Light".
        if let style = CFPreferencesCopyAppValue(
            "AppleInterfaceStyle" as CFString,
            kCFPreferencesAnyApplication
        ) as? String {
            return style.caseInsensitiveCompare("dark") == .orderedSame
        }
        // A missing key normally means light mode, but only once we know the read itself worked.
        // `AppleInterfaceStyleSwitchesAutomatically` is present on any Mac that has ever been
        // through the appearance setting, so it tells the two cases apart.
        if CFPreferencesCopyAppValue(
            "AppleInterfaceStyleSwitchesAutomatically" as CFString,
            kCFPreferencesAnyApplication
        ) != nil {
            return false
        }
        // Nothing readable: fall back to what this process is actually drawing with.
        return MainActor.assumeIsolated {
            NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    func setDarkModeEnabled(_ enabled: Bool) async throws {
        let processIdentifier = try systemEventsProcessIdentifier()

        // Sending blocks its thread until System Events replies, so it never runs on the main
        // actor. The first send is also what raises the Automation consent prompt. The event and
        // its reply stay inside the task; only the reply's error number comes back out.
        let errorNumber = try await Task.detached(priority: .userInitiated) {
            let event = Self.setDarkModeEvent(enabled, processIdentifier: processIdentifier)
            let reply = try event.sendEvent(
                options: [.waitForReply, .canSwitchLayer],
                timeout: 10
            )
            return reply.paramDescriptor(forKeyword: Code.errorNumber)?.int32Value ?? 0
        }.value

        guard errorNumber == 0 else {
            throw Self.notAuthorizedErrors.contains(Int(errorNumber))
                ? SystemAppearanceError.notAuthorized
                : SystemAppearanceError.changeFailed
        }
    }

    /// System Events is a background agent macOS launches on demand; it is asked for by bundle
    /// identifier rather than by a path this app could be pointed at.
    private func systemEventsProcessIdentifier() throws -> pid_t {
        if let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.systemEventsBundleIdentifier
        ).first {
            return running.processIdentifier
        }
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.systemEventsBundleIdentifier
        ) else {
            throw SystemAppearanceError.systemEventsUnavailable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        // Launching it is what makes the target addressable; the event below is still the only
        // thing Commandly asks it to do.
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        guard let started = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.systemEventsBundleIdentifier
        ).first else {
            throw SystemAppearanceError.systemEventsUnavailable
        }
        return started.processIdentifier
    }

    /// `set dark mode of appearance preferences to <enabled>`, built from fixed codes.
    private static func setDarkModeEvent(
        _ enabled: Bool,
        processIdentifier: pid_t
    ) -> NSAppleEventDescriptor {
        let container = NSAppleEventDescriptor.record()
        container.setDescriptor(.init(typeCode: Code.appearancePreferences), forKeyword: Code.wantKey)
        container.setDescriptor(.init(enumCode: Code.formProperty), forKeyword: Code.formKey)
        container.setDescriptor(.init(typeCode: Code.appearancePreferences), forKeyword: Code.seldKey)
        container.setDescriptor(.null(), forKeyword: Code.fromKey)
        let preferences = container.coerce(toDescriptorType: Code.property) ?? container

        let target = NSAppleEventDescriptor.record()
        target.setDescriptor(.init(typeCode: Code.property), forKeyword: Code.wantKey)
        target.setDescriptor(.init(enumCode: Code.formProperty), forKeyword: Code.formKey)
        target.setDescriptor(.init(typeCode: Code.darkMode), forKeyword: Code.seldKey)
        target.setDescriptor(preferences, forKeyword: Code.fromKey)
        let darkModeProperty = target.coerce(toDescriptorType: Code.property) ?? target

        let event = NSAppleEventDescriptor(
            eventClass: Code.core,
            eventID: Code.setData,
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: processIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(darkModeProperty, forKeyword: Code.directObject)
        event.setParam(NSAppleEventDescriptor(boolean: enabled), forKeyword: Code.dataParameter)
        return event
    }
}
