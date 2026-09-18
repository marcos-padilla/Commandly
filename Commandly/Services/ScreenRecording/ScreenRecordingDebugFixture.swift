#if DEBUG
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreText
import CoreVideo
import Foundation
import Infrastructure

@MainActor
enum ScreenRecordingDebugFixture {
    static let label = "Generated demo — no screen or audio is captured"
    static func capture() -> any ScreenRecordingCapturing { GeneratedScreenRecordingCapture() }
}

/// UI acceptance uses an original generated one-second movie, never the user's display or audio.
@MainActor
private final class GeneratedScreenRecordingCapture: ScreenRecordingCapturing {
    private let writer = ScreenRecordingDebugMovieWriter()
    private var continuation: AsyncStream<ScreenRecordingEvent>.Continuation?
    private var destination: ScreenRecordingDraft?
    private var work: Task<Void, Never>?
    private var operationID: UUID?

    func begin(options: ScreenRecordingOptions, destination: ScreenRecordingDraft,
               limits: ScreenRecordingLimits) async throws -> AsyncStream<ScreenRecordingEvent> {
        try Task.checkCancellation()
        guard operationID == nil else { throw ScreenRecordingError.busy }
        operationID = UUID()
        self.destination = destination
        let stream = AsyncStream<ScreenRecordingEvent>.makeStream()
        continuation = stream.continuation
        continuation?.yield(.started)
        return stream.stream
    }
    func stop() async {
        guard let id = operationID, let destination, work == nil else { return }
        continuation?.yield(.stopping(.user))
        work = Task { [weak self, writer] in
            do {
                let summary = try await writer.write(to: destination)
                try Task.checkCancellation()
                guard let self, operationID == id else { return }
                continuation?.yield(.finished(summary))
                finish()
            } catch {
                guard let self, operationID == id else { return }
                continuation?.yield(error is CancellationError ? .cancelled : .failed(.recordingFailed))
                finish()
            }
        }
    }
    func cancel() async {
        guard operationID != nil else { return }
        let pending = work
        pending?.cancel()
        await pending?.value
        continuation?.yield(.cancelled)
        finish()
    }
    private func finish() {
        continuation?.finish(); continuation = nil; destination = nil; operationID = nil; work = nil
    }
}

/// AVFoundation's suspending receiver supplies backpressure; no readiness polling or sleeps.
actor ScreenRecordingDebugMovieWriter {
    func write(to draft: ScreenRecordingDraft) async throws -> ScreenRecordingSummary {
        try Task.checkCancellation()
        let writer = try AVAssetWriter(outputURL: draft.url, fileType: draft.container == .mp4 ? .mp4 : .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360
        ])
        guard writer.canAdd(input) else { throw ScreenRecordingError.unsupportedConfiguration }
        let attributes = CVPixelBufferCreationAttributes(pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA),
                                                        size: .init(width: 640, height: 360))
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        do {
            for index in 0..<30 {
                try Task.checkCancellation()
                let frame = try makeFrame(index: index, attributes: attributes)
                try await receiver.append(frame, with: CMTime(value: Int64(index), timescale: 30))
            }
            receiver.finish()
            writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
            await writer.finishWriting()
            try Task.checkCancellation()
            guard writer.status == .completed else { throw ScreenRecordingError.finalizationFailed }
            let values = try draft.url.resourceValues(forKeys: [.fileSizeKey])
            return ScreenRecordingSummary(duration: 1, fileBytes: Int64(values.fileSize ?? 0), pixelWidth: 640, pixelHeight: 360)
        } catch {
            writer.cancelWriting()
            throw error
        }
    }

    private func makeFrame(index: Int, attributes: CVPixelBufferCreationAttributes) throws -> CVReadOnlyPixelBuffer {
        var buffer = try CVMutablePixelBuffer(attributes)
        try buffer.accessUnsafeMutableRawPlaneBytes { planes in
            guard let plane = planes.first, let base = plane.bytes.baseAddress,
                  let context = CGContext(data: base, width: 640, height: 360, bitsPerComponent: 8,
                    bytesPerRow: plane.properties.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
                throw ScreenRecordingError.invalidArtifact
            }
            context.setFillColor(CGColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            context.setFillColor(CGColor(red: 0.46, green: 0.75, blue: 0.94, alpha: 1))
            context.fillEllipse(in: CGRect(x: 70 + index * 13, y: 92, width: 58, height: 58))
            context.setFillColor(CGColor(gray: 0.95, alpha: 1))
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil),
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "GENERATED RECORDING", attributes: attributes))
            context.textPosition = CGPoint(x: 56, y: 244)
            CTLineDraw(line, context)
        }
        return CVReadOnlyPixelBuffer(buffer)
    }
}
#endif
