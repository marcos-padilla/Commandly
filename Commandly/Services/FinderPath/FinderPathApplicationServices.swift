import AppKit
import Infrastructure

@MainActor struct FinderPathApplicationServices {
    let reader: any FinderPathReading
    let copier: any FinderPathCopying
    let openSettings: @MainActor @Sendable () async throws -> Void
    var fixtureLabel: String?
    static var live: Self {
        .init(reader: FinderPathReader(probe: NativeFinderPathProbe(processes: NativeFinderProcessProvider())),
              copier: NativeFinderPathCopier(), openSettings: {
                  _ = try await SystemSettingsApplicationServices.live.opener.open(.privacySecurity)
              })
    }
    static var unavailable: Self {
        .init(reader: UnavailableFinderPathReader(), copier: NativeFinderPathCopier(), openSettings: { throw FinderPathError.unavailable })
    }
}
@MainActor struct NativeFinderPathCopier: FinderPathCopying {
    func copy(_ path: String) throws {
        try Task.checkCancellation()
        guard path.hasPrefix("/"), path.utf8.count <= FinderPathValidation.maximumURLBytes else { throw FinderPathError.copyFailed }
        let pasteboard = NSPasteboard.general
        let item = NSPasteboardItem()
        guard item.setString(path, forType: .string) else { throw FinderPathError.copyFailed }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw FinderPathError.copyFailed }
    }
}
private actor UnavailableFinderPathReader: FinderPathReading {
    func authorization(allowPrompt: Bool) throws -> FinderPathAuthorization { throw FinderPathError.unavailable }
    func capture() throws -> FinderPathSnapshot { throw FinderPathError.unavailable }
    func validate(_ snapshot: FinderPathSnapshot) throws { throw FinderPathError.unavailable }
}
