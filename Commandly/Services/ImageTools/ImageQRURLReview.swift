import Foundation

/// A web destination prepared for a separate, explicit review before native browser dispatch.
nonisolated struct ImageQRURLReview: Identifiable, Equatable {
    var id: String { payload }
    let payload: String
    let url: URL
    let host: String

    static func make(for payload: String) -> ImageQRURLReview? {
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard payload.count <= ImageRecognitionOutput.maximumQRPayloadCharacters,
              payload.rangeOfCharacter(from: forbidden) == nil,
              payload.contains("\\") == false,
              let decoded = payload.removingPercentEncoding,
              decoded.rangeOfCharacter(from: .controlCharacters) == nil,
              let components = URLComponents(string: payload),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil, components.password == nil,
              components.port.map({ (1...65_535).contains($0) }) ?? true,
              let url = components.url,
              let host = url.host, host.isEmpty == false else { return nil }
        return ImageQRURLReview(payload: payload, url: url, host: host)
    }
}
