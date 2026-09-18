import AIKit
import Foundation

@MainActor struct VisualAIApplicationServices {
    let screenshots: ScreenshotApplicationServices
    let imagePreparer: any VisualAIImagePreparing
    let ai: any VisualAIServicing
    static var inMemory: Self { .init(screenshots: .inMemory, imagePreparer: VisualAIImagePreparer(), ai: UnavailableVisualAIService()) }
    static func live(screenshots: ScreenshotApplicationServices, connections: any AIConnectionStoring,
                     credentials: any AIProviderCredentialStoring, registry: AIProviderRegistry,
                     transport: any AIHTTPTransport = URLSessionAIHTTPTransport()) -> Self {
        .init(screenshots: screenshots, imagePreparer: VisualAIImagePreparer(),
              ai: NativeVisualAIService(connections: connections, credentials: credentials, registry: registry, transport: transport))
    }
}
