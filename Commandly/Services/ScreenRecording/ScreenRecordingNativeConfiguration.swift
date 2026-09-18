import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import Infrastructure
import ScreenCaptureKit

nonisolated enum ScreenRecordingNativeConfiguration {
    static func dimensions(points: CGSize, scale: CGFloat, resolution: ScreenRecordingResolution) throws -> (Int, Int) {
        let width = points.width * scale
        let height = points.height * scale
        guard width.isFinite, height.isFinite, width >= 2, height >= 2,
              width <= 32_768, height <= 32_768 else { throw ScreenRecordingError.selectionInvalid }
        let maximum = resolution == .fullHD ? CGSize(width: 1_920, height: 1_080) : CGSize(width: 1_280, height: 720)
        let ratio = min(1, maximum.width / width, maximum.height / height)
        return (max(2, Int(width * ratio) / 2 * 2), max(2, Int(height * ratio) / 2 * 2))
    }

    static func stream(options: ScreenRecordingOptions, width: Int, height: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.showsCursor = options.showsCursor
        configuration.capturesAudio = options.audio == .systemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = false
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.captureDynamicRange = .SDR
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.includeChildWindows = false
        return configuration
    }

    static func recording(options: ScreenRecordingOptions, outputURL: URL) throws -> SCRecordingOutputConfiguration {
        let configuration = SCRecordingOutputConfiguration()
        let codec: AVVideoCodecType = options.codec == .h264 ? .h264 : .hevc
        let container: AVFileType = options.container == .mp4 ? .mp4 : .mov
        guard configuration.availableVideoCodecTypes.contains(codec),
              configuration.availableOutputFileTypes.contains(container) else {
            throw ScreenRecordingError.unsupportedConfiguration
        }
        configuration.outputURL = outputURL
        configuration.videoCodecType = codec
        configuration.outputFileType = container
        return configuration
    }

    static func limitReason(progress: ScreenRecordingProgress, limits: ScreenRecordingLimits) -> ScreenRecordingStopReason? {
        if progress.fileBytes >= limits.stopFileBytes { return .sizeLimit }
        if progress.duration >= limits.maximumDuration { return .durationLimit }
        return nil
    }

    static func failure(_ error: Error, fallback: ScreenRecordingError) -> ScreenRecordingError {
        let native = error as NSError
        if native.domain == SCStreamErrorDomain,
           native.code == SCStreamError.Code.userDeclined.rawValue { return .permissionRequired }
        return fallback
    }

    static func isUserStop(_ error: Error) -> Bool {
        let native = error as NSError
        return native.domain == SCStreamErrorDomain && native.code == SCStreamError.Code.userStopped.rawValue
    }
}
