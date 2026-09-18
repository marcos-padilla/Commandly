#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import SecurityKit
import UniformTypeIdentifiers

@MainActor enum SlackEmojiDebugFixture {
    static func services(exporter: any SlackEmojiExporting = NativeSlackEmojiExporter()) -> SlackEmojiApplicationServices {
        .init(service: GeneratedSlackEmojiService(), decoder: SlackEmojiImageDecoder(), exporter: exporter,
              openURL: { _ in }, fixtureLabel: "Generated Slack Emoji UI Fixture — no network or Keychain")
    }
}
actor GeneratedSlackEmojiMedia {
    func make(animated: Bool, frameCount: Int? = nil, dimension: Int = 64) throws -> Data {
        let count = frameCount ?? (animated ? 4 : 1)
        guard (1...1_001).contains(count), (1...2_048).contains(dimension), animated || count == 1 else { throw SlackEmojiError.invalidImage }
        let output = NSMutableData(); let type = animated ? UTType.gif.identifier : UTType.png.identifier
        guard let destination = CGImageDestinationCreateWithData(output, type as CFString, count, nil) else { throw SlackEmojiError.invalidImage }
        if animated { CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary) }
        for index in 0..<count {
            try Task.checkCancellation()
            guard let context = CGContext(data: nil, width: dimension, height: dimension, bitsPerComponent: 8, bytesPerRow: dimension * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw SlackEmojiError.invalidImage }
            context.setFillColor(CGColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))
            context.setFillColor(CGColor(red: 0.22, green: 0.83, blue: 0.68, alpha: 1))
            context.fillEllipse(in: CGRect(x: dimension / 8 + index % 4 * dimension / 10, y: dimension / 4, width: dimension / 3, height: dimension / 3))
            guard let image = context.makeImage() else { throw SlackEmojiError.invalidImage }
            let properties: [CFString: Any] = animated ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.15]] : [:]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw SlackEmojiError.invalidImage }
        return output as Data
    }
}
private actor GeneratedSlackEmojiService {
    private let credentials = SlackEmojiCredentialStore(secureStore: InMemorySecureStore())
    private var service: SlackEmojiService?
    private var initializing: Task<SlackEmojiService, Error>?
    private func initialized() async throws -> SlackEmojiService {
        if let service { return service }
        let task: Task<SlackEmojiService, Error>
        if let initializing { task = initializing }
        else {
            task = Task { [credentials] in
                let service = SlackEmojiService(credentials: credentials, transport: GeneratedSlackEmojiTransport())
                _ = try await service.connect(token: "xoxb-generated-one", replacing: nil)
                _ = try await service.connect(token: "xoxb-generated-two", replacing: nil)
                return service
            }; initializing = task
        }
        let result = try await task.value; service = result; initializing = nil; return result
    }
    func connections() async throws -> [SlackEmojiWorkspace] { try await initialized().connections() }
    func connect(token: String, replacing: SlackEmojiWorkspace?) async throws -> SlackEmojiWorkspace { try await initialized().connect(token: token, replacing: replacing) }
    func disconnect(_ workspace: SlackEmojiWorkspace) async throws { try await initialized().disconnect(workspace) }
    func refresh(_ workspace: SlackEmojiWorkspace) async throws -> SlackEmojiCatalog { try await initialized().refresh(workspace) }
    func search(_ query: String, catalog: SlackEmojiCatalog) async throws -> SlackEmojiMatches { try await initialized().search(query, catalog: catalog) }
    func media(_ item: SlackCustomEmoji, catalog: SlackEmojiCatalog) async throws -> Data { try await initialized().media(item, catalog: catalog) }
    func release(_ catalog: SlackEmojiCatalog) async { if let service { await service.release(catalog) } }
}
extension GeneratedSlackEmojiService: SlackEmojiServing {}
private actor GeneratedSlackEmojiTransport {
    private let media = GeneratedSlackEmojiMedia()
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> SlackEmojiHTTPResponse {
        guard let url = request.url else { throw SlackEmojiError.invalidResponse }
        if url.host == "emoji.slack-edge.com" {
            let data = try await media.make(animated: url.pathExtension == "gif")
            return .init(data: data, status: 200, contentType: url.pathExtension == "gif" ? "image/gif" : "image/png", scopes: nil, retryAfter: nil, location: nil)
        }
        let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let suffix = token.contains("-two") ? "TWO" : token.contains("-one") ? "ONE" : "NEW"
        let team = "TGENERATED" + suffix
        let value: [String: Any]
        if url.lastPathComponent == "auth.test" {
            value = ["ok": true, "team_id": team, "team": "Generated Workspace " + suffix.capitalized,
                     "url": "https://generated-" + suffix.lowercased() + ".slack.com/", "bot_id": "BGENERATED" + suffix]
        } else if url.lastPathComponent == "emoji.list" {
            value = ["ok": true, "emoji": ["celebrate": "https://emoji.slack-edge.com/" + team + "/celebrate/generated.gif",
                                                   "circle": "https://emoji.slack-edge.com/" + team + "/circle/generated.png",
                                                   "hello": "alias:celebrate", "wave": "alias:hello", "missing_alias": "alias:unreturned_standard"]]
        } else { throw SlackEmojiError.invalidResponse }
        return .init(data: try JSONSerialization.data(withJSONObject: value), status: 200, contentType: "application/json", scopes: "emoji:read", retryAfter: nil, location: nil)
    }
}
extension GeneratedSlackEmojiTransport: SlackEmojiHTTPTransporting {}
#endif
