import AppKit
import Foundation
import Infrastructure
import SecurityKit

@MainActor
struct SlackEmojiApplicationServices {
    let service: any SlackEmojiServing
    let decoder: any SlackEmojiImageDecoding
    let exporter: any SlackEmojiExporting
    let openURL: @MainActor (URL) -> Void
    let fixtureLabel: String?
    init(service: any SlackEmojiServing, decoder: any SlackEmojiImageDecoding, exporter: any SlackEmojiExporting,
         openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }, fixtureLabel: String? = nil) {
        self.service = service; self.decoder = decoder; self.exporter = exporter; self.openURL = openURL; self.fixtureLabel = fixtureLabel
    }
    static func live(secureStore: any SecureStoring) -> Self {
        let decoder = SlackEmojiImageDecoder()
        return .init(service: SlackEmojiService(credentials: SlackEmojiCredentialStore(secureStore: secureStore)), decoder: decoder, exporter: NativeSlackEmojiExporter(decoder: decoder))
    }
    static var unavailable: Self { .init(service: UnavailableSlackEmojiService(), decoder: SlackEmojiImageDecoder(), exporter: NativeSlackEmojiExporter()) }
}
nonisolated private struct UnavailableSlackEmojiService: SlackEmojiServing {
    func connections() async throws -> [SlackEmojiWorkspace] { [] }
    func connect(token: String, replacing: SlackEmojiWorkspace?) async throws -> SlackEmojiWorkspace { throw SlackEmojiError.credentialsUnavailable }
    func disconnect(_ workspace: SlackEmojiWorkspace) async throws { throw SlackEmojiError.credentialsUnavailable }
    func refresh(_ workspace: SlackEmojiWorkspace) async throws -> SlackEmojiCatalog { throw SlackEmojiError.setupRequired }
    func search(_ query: String, catalog: SlackEmojiCatalog) async throws -> SlackEmojiMatches { throw SlackEmojiError.setupRequired }
    func media(_ item: SlackCustomEmoji, catalog: SlackEmojiCatalog) async throws -> Data { throw SlackEmojiError.setupRequired }
    func release(_ catalog: SlackEmojiCatalog) async {}
}
