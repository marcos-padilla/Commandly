import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct SystemSettingsRoutingTests {
    @Test func catalogExposesSixDisplayIntentsAndUniqueFixedDestinations() throws {
        let display = SystemSettingsCatalog.items.filter { $0.pane == .displays }
        #expect(display.count == 6)
        #expect(Set(display.map(\.id)).count == 6)
        #expect(display.allSatisfy { $0.subtitle == "Opens Displays in System Settings" })
        #expect(SystemSettingsCatalog.items.count == 27)
        #expect(Set(SystemSettingsCatalog.items.map(\.toolID)).count == 27)
        #expect(Set(SystemSettingsCatalog.items.map(\.pane)) == Set(SystemSettingsPane.allCases))
        for pane in SystemSettingsPane.allCases {
            let route = SystemSettingsPaneRoute.forPane(pane)
            let url = try #require(route.url)
            #expect(url.scheme == "x-apple.systempreferences")
            #expect(url.host == nil && url.query == nil && url.fragment == nil)
            #expect(url.absoluteString == "x-apple.systempreferences:\(route.bundleIdentifier)")
        }
    }

    @Test(arguments: ["", "com.apple.", "com.apple..Displays", "https://example.com", "com.apple.Settings?foo=bar", "com.apple.Settings#anchor", "com.apple.Settings/path", "com.apple.Settings%3Ffoo", "com.apple.Settings\n", "com.apple.設定", String(repeating: "a", count: 161)])
    func malformedDestinationIdentifiersCannotBecomeURLs(_ identifier: String) {
        #expect(SystemSettingsPaneRoute.url(bundleIdentifier: identifier) == nil)
    }

    @Test func searchIsBoundedAndFindsMacEquivalents() {
        #expect(SystemSettingsCatalog.matching("display").count == 6)
        #expect(SystemSettingsCatalog.matching("PROFILE").map(\.id) == ["display-color-profile"])
        #expect(SystemSettingsCatalog.matching("display scale").map(\.id) == ["display-scale"])
        #expect(SystemSettingsCatalog.matching("do not disturb").map(\.id) == ["focus"])
        #expect(SystemSettingsCatalog.matching("privacy").map(\.pane) == [.privacySecurity])
        #expect(SystemSettingsCatalog.matching(String(repeating: "x", count: 257)).isEmpty)
    }
}

struct NativeSystemSettingsResolverTests {
    @Test func resolvesGeneratedMetadataWithEncodedSpacesAndKnownID() async throws {
        try await withSettingsFixture { fixture in
            let resolver = await fixture.resolver()
            let plan = try await resolver.resolve(.dateTime)
            #expect(plan.applicationURL.absoluteString.contains("System%20Settings.app"))
            #expect(plan.paneURL?.absoluteString == "x-apple.systempreferences:com.apple.Date-Time-Settings.extension")
            let rootPlan = try await resolver.resolve(nil)
            #expect(rootPlan.paneURL == nil)
        }
    }

    @Test(arguments: [SettingsMetadataMutation.missingPane, .wrongPaneIdentity, .malformedPane, .oversizedPane, .privateScheme, .missingScheme, .symlinkPane])
    func unavailableDestinationFallsBackWithoutGuessing(_ mutation: SettingsMetadataMutation) async throws {
        try await withSettingsFixture { fixture in
            try await fixture.mutate(mutation)
            let plan = try await fixture.resolver().resolve(.dateTime)
            #expect(plan.paneURL == nil)
            #expect(plan.applicationURL.lastPathComponent == "System Settings.app")
        }
    }

    @Test(arguments: [SettingsMetadataMutation.wrongAppIdentity, .malformedApp, .symlinkApp])
    func rejectsUntrustedOrMalformedApplicationMetadata(_ mutation: SettingsMetadataMutation) async throws {
        try await withSettingsFixture { fixture in
            try await fixture.mutate(mutation)
            await #expect(throws: SystemSettingsNavigationError.unavailable) {
                _ = try await fixture.resolver().resolve(.dateTime)
            }
        }
    }
}

enum SettingsMetadataMutation: Sendable {
    case missingPane, wrongPaneIdentity, malformedPane, oversizedPane, privateScheme, missingScheme, symlinkPane
    case wrongAppIdentity, malformedApp, symlinkApp
}

private actor SettingsMetadataFixture {
    private let root = FileManager.default.temporaryDirectory.appending(component: "Commandly Settings Fixture \(UUID().uuidString)", directoryHint: .isDirectory)
    private var app: URL { root.appending(component: "System Settings.app", directoryHint: .isDirectory) }
    private var extensions: URL { root.appending(component: "Extensions", directoryHint: .isDirectory) }
    private var pane: URL { extensions.appending(component: SystemSettingsPaneRoute.forPane(.dateTime).extensionName, directoryHint: .isDirectory) }
    private var appInfo: URL { app.appending(path: "Contents/Info.plist") }
    private var paneInfo: URL { pane.appending(path: "Contents/Info.plist") }

    func prepare() throws {
        try FileManager.default.createDirectory(at: appInfo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paneInfo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeApp()
        try write(["CFBundleIdentifier": SystemSettingsPaneRoute.forPane(.dateTime).bundleIdentifier], to: paneInfo)
    }
    func resolver() -> NativeSystemSettingsResolver { .init(applicationURL: app, extensionsURL: extensions) }
    func cleanup() throws { try FileManager.default.removeItem(at: root) }
    func mutate(_ mutation: SettingsMetadataMutation) throws {
        switch mutation {
        case .missingPane: try FileManager.default.removeItem(at: pane)
        case .wrongPaneIdentity: try write(["CFBundleIdentifier": "com.example.not-settings"], to: paneInfo)
        case .malformedPane: try Data("not a plist".utf8).write(to: paneInfo)
        case .oversizedPane: try Data(repeating: 0, count: 131_073).write(to: paneInfo)
        case .privateScheme: try writeApp(isPrivate: true)
        case .missingScheme: try writeApp(scheme: "settings-navigation")
        case .wrongAppIdentity: try writeApp(identifier: "com.example.settings")
        case .malformedApp: try Data("not a plist".utf8).write(to: appInfo)
        case .symlinkPane:
            let moved = root.appending(component: "Moved Pane.appex", directoryHint: .isDirectory)
            try FileManager.default.moveItem(at: pane, to: moved)
            try FileManager.default.createSymbolicLink(at: pane, withDestinationURL: moved)
        case .symlinkApp:
            let moved = root.appending(component: "Moved App.app", directoryHint: .isDirectory)
            try FileManager.default.moveItem(at: app, to: moved)
            try FileManager.default.createSymbolicLink(at: app, withDestinationURL: moved)
        }
    }
    private func writeApp(identifier: String = "com.apple.systempreferences", scheme: String = "x-apple.systempreferences", isPrivate: Bool = false) throws {
        try write(["CFBundleIdentifier": identifier, "CFBundleURLTypes": [["CFBundleURLSchemes": [scheme], "CFBundleURLIsPrivate": isPrivate]]], to: appInfo)
    }
    private func write(_ object: [String: Any], to url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0).write(to: url)
    }
}

private func withSettingsFixture(_ body: (SettingsMetadataFixture) async throws -> Void) async throws {
    let fixture = SettingsMetadataFixture()
    try await fixture.prepare()
    do { try await body(fixture); try await fixture.cleanup() }
    catch { try await fixture.cleanup(); throw error }
}
