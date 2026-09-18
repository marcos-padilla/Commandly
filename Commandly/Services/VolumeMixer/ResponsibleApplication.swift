import AppKit
import Darwin

/// Maps helper processes to the application responsible for them and gives processes a readable
/// name, so a browser's audio helper rolls up into one row with the browser's own icon.
nonisolated enum ResponsibleApplication {
    /// `responsibility_get_pid_responsible_for_pid`, exported by libsystem and used by the
    /// system for the same grouping. Resolved at runtime so a missing symbol degrades to
    /// per-process rows instead of breaking the mixer.
    private static let resolveResponsible: (@convention(c) (pid_t) -> pid_t)? = {
        // RTLD_DEFAULT searches every image already loaded into the process.
        guard let symbol = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2),
            "responsibility_get_pid_responsible_for_pid"
        ) else {
            return nil
        }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    static func owner(of processID: pid_t) -> pid_t {
        guard let resolveResponsible else { return processID }
        let owner = resolveResponsible(processID)
        return owner > 0 ? owner : processID
    }

    /// The regular application to bill a process to.
    ///
    /// Normally that is its responsible process, but some browsers detach their audio helpers
    /// from the responsibility chain and each one answers for itself. The parent chain still
    /// leads to the app that spawned the helper. `nil` when no ancestor is a regular app, so
    /// daemons and login items stay unlisted.
    static func regularApplicationOwner(of processID: pid_t) -> NSRunningApplication? {
        let responsible = owner(of: processID)
        let isRegular: (pid_t) -> Bool = {
            NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular
        }

        let resolved = MixerRoutingRules.owningRegularApplicationID(
            responsibleProcessID: responsible,
            isRegularApplication: isRegular,
            parentProcessID: parent(of:)
        ) ?? (responsible != processID
            ? MixerRoutingRules.owningRegularApplicationID(
                responsibleProcessID: processID,
                isRegularApplication: isRegular,
                parentProcessID: parent(of:)
            )
            : nil)

        return resolved.flatMap(NSRunningApplication.init(processIdentifier:))
    }

    /// Prefers the app's localized name; system processes fall back to their kernel-reported
    /// name, then to the caller's hint.
    static func displayName(processID: pid_t, fallback: String) -> String {
        if let application = NSRunningApplication(processIdentifier: processID),
           let name = application.localizedName, name.isEmpty == false {
            return name
        }
        var buffer = [CChar](repeating: 0, count: 256)
        if proc_name(processID, &buffer, UInt32(buffer.count)) > 0 {
            let name = String(cString: buffer)
            if name.isEmpty == false { return name }
        }
        return fallback.trimmingCharacters(in: .whitespaces)
    }

    private static func parent(of processID: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(processID, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return pid_t(info.pbi_ppid)
    }
}
