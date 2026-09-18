import CoreImage
import Foundation
import Infrastructure
import Vision

/// Performs foreground segmentation locally with Apple Vision.
nonisolated struct NativeBackgroundRemovalService: BackgroundRemoving {
    func removeBackground(from sourceURL: URL) async throws -> BackgroundRemovalResult {
        // Vision's public foreground-mask request is synchronous. Running the bounded operation in
        // a background task keeps decoding and segmentation off Commandly's main actor; the
        // cancellation handler forwards cancellation to that task.
        let processingTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try Self.process(sourceURL: sourceURL)
        }
        return try await withTaskCancellationHandler {
            try await processingTask.value
        } onCancel: {
            processingTask.cancel()
        }
    }

    private static func process(sourceURL: URL) throws -> BackgroundRemovalResult {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let sourceData: Data
        do {
            sourceData = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        } catch {
            throw BackgroundRemovalError.fileReadFailed
        }

        try Task.checkCancellation()
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let sourceImage = CIImage(
            data: sourceData,
            options: [.applyOrientationProperty: true]
        ) else {
            throw BackgroundRemovalError.invalidImage
        }
        let extent = sourceImage.extent.integral
        guard extent.isEmpty == false,
              extent.isInfinite == false,
              let sourceCGImage = context.createCGImage(sourceImage, from: extent) else {
            throw BackgroundRemovalError.invalidImage
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: sourceCGImage)
        do {
            try handler.perform([request])
        } catch {
            throw BackgroundRemovalError.segmentationFailed
        }
        try Task.checkCancellation()

        guard let observation = request.results?.first,
              observation.allInstances.isEmpty == false else {
            throw BackgroundRemovalError.noForegroundFound
        }

        let maskedBuffer: CVPixelBuffer
        do {
            maskedBuffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
        } catch {
            throw BackgroundRemovalError.segmentationFailed
        }

        try Task.checkCancellation()
        let maskedImage = CIImage(cvPixelBuffer: maskedBuffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let pngData = context.pngRepresentation(
            of: maskedImage,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            throw BackgroundRemovalError.encodingFailed
        }
        let sourcePreviewData = try previewPNGData(
            for: CIImage(cgImage: sourceCGImage),
            context: context,
            colorSpace: colorSpace
        )
        let transparentPreviewData = try previewPNGData(
            for: maskedImage,
            context: context,
            colorSpace: colorSpace
        )
        try Task.checkCancellation()

        return BackgroundRemovalResult(
            sourcePreviewPNGData: sourcePreviewData,
            transparentPreviewPNGData: transparentPreviewData,
            transparentPNGData: pngData,
            sourceFilename: sourceURL.lastPathComponent,
            pixelWidth: sourceCGImage.width,
            pixelHeight: sourceCGImage.height
        )
    }

    private static func previewPNGData(
        for image: CIImage,
        context: CIContext,
        colorSpace: CGColorSpace
    ) throws -> Data {
        let maximumDimension: CGFloat = 960
        let largestDimension = max(image.extent.width, image.extent.height)
        let scale = largestDimension > maximumDimension ? maximumDimension / largestDimension : 1
        let preview = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let data = context.pngRepresentation(
            of: preview,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            throw BackgroundRemovalError.encodingFailed
        }
        return data
    }
}
