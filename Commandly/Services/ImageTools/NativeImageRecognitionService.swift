import Foundation
import Infrastructure
import Vision

/// Uses Apple's asynchronous Vision requests on bounded, orientation-corrected pixels.
actor NativeImageRecognitionService: ImageRecognizing {
    func recognize(_ source: ImageConversionSource, mode: ImageRecognitionMode) async throws -> ImageRecognitionResult {
        try Task.checkCancellation()
        let imageSource = try ImageToolsImageDecoder.validatedSource(source.data)
        let dimensions = try ImageToolsImageDecoder.dimensions(imageSource)
        let image = try ImageToolsImageDecoder.thumbnail(
            imageSource,
            longestEdge: min(4_096, max(dimensions.width, dimensions.height))
        )
        try Task.checkCancellation()
        do {
            let result: ImageRecognitionResult
            switch mode {
            case .text:
                var request = RecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                request.usesLanguageCorrection = false
                let observations = try await request.perform(on: image)
                result = ImageRecognitionOutput.text(observations.compactMap { $0.topCandidates(1).first?.string })
            case .qr:
                var request = DetectBarcodesRequest()
                request.symbologies = [.qr]
                let observations = try await request.perform(on: image)
                result = ImageRecognitionOutput.qr(observations.map(\.payloadString))
            }
            try Task.checkCancellation()
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw ImageRecognitionError.recognitionFailed
        }
    }
}

/// Pure output bounds shared with deterministic tests; never changes the meaning of a QR payload.
nonisolated enum ImageRecognitionOutput {
    static let maximumCharacters = 64_000
    static let maximumQRPayloadCharacters = 4_096
    static let maximumQRCodes = 32

    static func text(_ lines: [String]) -> ImageRecognitionResult {
        var text = ""
        var remaining = maximumCharacters
        var truncated = false
        for line in lines where line.isEmpty == false {
            let separator = text.isEmpty ? "" : "\n"
            guard remaining > separator.count else { truncated = true; break }
            text += separator
            remaining -= separator.count
            let clipped = String(line.prefix(remaining))
            text += clipped
            remaining -= clipped.count
            if clipped.count < line.count { truncated = true; break }
        }
        return ImageRecognitionResult(text: text, isTruncated: truncated)
    }

    static func qr(_ payloads: [String?]) -> ImageRecognitionResult {
        var seen = Set<String>()
        var result: [String] = []
        var totalCharacters = 0
        var nonTextCount = 0
        var truncated = false
        for payload in payloads {
            guard let payload, payload.isEmpty == false else { nonTextCount += 1; continue }
            guard seen.contains(payload) == false else { continue }
            let count = payload.count
            guard result.count < maximumQRCodes, count <= maximumQRPayloadCharacters,
                  count <= maximumCharacters - totalCharacters else {
                truncated = true
                continue
            }
            seen.insert(payload)
            result.append(payload)
            totalCharacters += count
        }
        return ImageRecognitionResult(qrPayloads: result, isTruncated: truncated, nonTextQRCodeCount: nonTextCount)
    }
}
