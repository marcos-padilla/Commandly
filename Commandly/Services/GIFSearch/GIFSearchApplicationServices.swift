import AppKit
import Foundation
import Infrastructure
import SecurityKit

@MainActor
struct GIFSearchApplicationServices {
    let catalog: any GIFCatalogServing
    let decoder: any GIFAnimationDecoding
    let exporter: any GIFExporting
    let openURL: @MainActor (URL) -> Void
    let fixtureLabel: String?
    init(catalog: any GIFCatalogServing, decoder: any GIFAnimationDecoding, exporter: any GIFExporting,
         openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }, fixtureLabel: String? = nil) {
        self.catalog = catalog; self.decoder = decoder; self.exporter = exporter; self.openURL = openURL; self.fixtureLabel = fixtureLabel
    }
    static var unavailable: Self {
        .init(catalog: UnavailableGIFCatalog(), decoder: GIFAnimationDecoder(), exporter: NativeGIFExporter())
    }
    static func live(secureStore: any SecureStoring) -> Self {
        let decoder = GIFAnimationDecoder()
        return .init(catalog: GIPHYCatalogService(credentials: GIPHYCredentialStore(secureStore: secureStore)),
                     decoder: decoder, exporter: NativeGIFExporter(decoder: decoder))
    }
}

/// Inert composition fallback. It never pretends a key was saved or silently uses a generated catalog.
nonisolated private struct UnavailableGIFCatalog: GIFCatalogServing {
    private let state = GIFConnectionState(revision: UUID(), isConfigured: false)
    func connection() async throws -> GIFConnectionState { state }
    func configure(key: String) async throws -> GIFConnectionState { throw GIFSearchError.credentialsUnavailable }
    func disconnect() async throws -> GIFConnectionState { throw GIFSearchError.credentialsUnavailable }
    func search(_ query: GIFCatalogQuery, rating: GIFContentRating, offset: Int, connection: UUID) async throws -> GIFCatalogPage { throw GIFSearchError.setupRequired }
    func media(_ item: GIFCatalogItem, original: Bool, connection: UUID) async throws -> Data { throw GIFSearchError.setupRequired }
}
