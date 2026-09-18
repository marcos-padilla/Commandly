import AIKit
import Foundation

@MainActor
struct QuickAIApplicationServices {
    let chat: any QuickAIServicing
    init(chat: any QuickAIServicing) { self.chat = chat }

    static var inMemory: Self { Self(chat: InMemoryQuickAIService()) }

    static func live(
        connectionStore: any AIConnectionStoring,
        credentialStore: any AIProviderCredentialStoring,
        registry: AIProviderRegistry,
        streamTransport: any AIHTTPStreamingTransport = URLSessionAIHTTPStreamingTransport(),
        discoveryTransport: any AIHTTPTransport = URLSessionAIHTTPTransport()
    ) -> Self {
        Self(chat: NativeQuickAIService(connectionStore: connectionStore,
            credentialStore: credentialStore, registry: registry, streamTransport: streamTransport,
            modelDiscovery: AIKitConnectionService(registry: registry, transport: discoveryTransport)))
    }
}
