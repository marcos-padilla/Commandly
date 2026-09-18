import CoreGraphics
import Foundation
import ImageIO
import Infrastructure
import UniformTypeIdentifiers

/// ImageIO work is actor-isolated so file reads and synchronous codecs never run on the main actor.
actor NativeImageConversionService: ImageConverting, ImageDataConverting {
    private let maximumInputBytes = ImageToolsImageDecoder.maximumInputBytes
    private let maximumPixels = ImageToolsImageDecoder.maximumPixels
    private let maximumOutputBytes = 192 * 1_024 * 1_024

    func supportedFormats() -> [ImageConversionFormat] {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return ImageConversionFormat.allCases.filter { identifiers.contains(Self.type(for: $0).identifier) }
    }

    func loadImage(from url: URL) async throws -> ImageConversionSource {
        try Task.checkCancellation()
        guard url.isFileURL else { throw ImageConversionError.fileReadFailed }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { throw ImageConversionError.invalidImage }
            guard let size = values.fileSize, size <= maximumInputBytes else {
                throw ImageConversionError.inputTooLarge
            }
            let handle = try FileHandle(forReadingFrom: url)
            let read = Result { try handle.read(upToCount: maximumInputBytes + 1) ?? Data() }
            try handle.close()
            data = try read.get()
        } catch let error as ImageConversionError {
            throw error
        } catch {
            throw ImageConversionError.fileReadFailed
        }
        guard data.count <= maximumInputBytes else { throw ImageConversionError.inputTooLarge }
        try Task.checkCancellation()
        let imageSource = try ImageToolsImageDecoder.validatedSource(data)
        let dimensions = try ImageToolsImageDecoder.dimensions(imageSource)
        let preview = try ImageToolsImageDecoder.thumbnail(imageSource, longestEdge: min(960, max(dimensions.width, dimensions.height)))
        let previewData = try encode(preview, format: .png)
        try Task.checkCancellation()
        return ImageConversionSource(
            data: data, previewPNGData: previewData, filename: url.lastPathComponent,
            pixelWidth: dimensions.width, pixelHeight: dimensions.height
        )
    }

    func convert(_ source: ImageConversionSource, options: ImageConversionOptions) async throws -> ImageConversionResult {
        try await convertImageData(source.data, options: options)
    }

    func convertImageData(_ data: Data, options: ImageConversionOptions) async throws -> ImageConversionResult {
        try Task.checkCancellation()
        guard supportedFormats().contains(options.format) else { throw ImageConversionError.unsupportedFormat }
        guard (0...3).contains(options.clockwiseQuarterTurns) else { throw ImageConversionError.invalidDimensions }
        let imageSource = try ImageToolsImageDecoder.validatedSource(data)
        let original = try ImageToolsImageDecoder.dimensions(imageSource)
        let target = options.longestEdge ?? max(original.width, original.height)
        guard (1...16_384).contains(target) else { throw ImageConversionError.invalidDimensions }
        let scale = Double(target) / Double(max(original.width, original.height))
        let width = max(1, Int((Double(original.width) * scale).rounded()))
        let height = max(1, Int((Double(original.height) * scale).rounded()))
        guard width * height <= maximumPixels else { throw ImageConversionError.outputTooLarge }
        let input = try ImageToolsImageDecoder.thumbnail(imageSource, longestEdge: min(target, max(original.width, original.height)))
        try Task.checkCancellation()
        let output = try render(
            input, width: width, height: height, turns: options.clockwiseQuarterTurns,
            transparent: options.format.preservesTransparency
        )
        let outputData = try encode(output, format: options.format)
        try Task.checkCancellation()
        let previewScale = min(1, 960 / Double(max(output.width, output.height)))
        let preview = try render(
            output,
            width: max(1, Int((Double(output.width) * previewScale).rounded())),
            height: max(1, Int((Double(output.height) * previewScale).rounded())),
            turns: 0, transparent: options.format.preservesTransparency
        )
        let previewData = try encode(preview, format: .png)
        try Task.checkCancellation()
        return ImageConversionResult(
            data: outputData, previewPNGData: previewData, format: options.format,
            pixelWidth: output.width, pixelHeight: output.height
        )
    }

    private func render(_ image: CGImage, width: Int, height: Int, turns: Int, transparent: Bool) throws -> CGImage {
        let swapsAxes = turns.isMultiple(of: 2) == false
        let outputWidth = swapsAxes ? height : width
        let outputHeight = swapsAxes ? width : height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: outputWidth, height: outputHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ImageConversionError.outputTooLarge }
        if transparent == false {
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        }
        context.translateBy(x: CGFloat(outputWidth) / 2, y: CGFloat(outputHeight) / 2)
        context.rotate(by: -CGFloat(turns) * .pi / 2)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2, width: CGFloat(width), height: CGFloat(height)))
        guard let result = context.makeImage() else { throw ImageConversionError.encodingFailed }
        return result
    }

    private func encode(_ image: CGImage, format: ImageConversionFormat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, Self.type(for: format).identifier as CFString, 1, nil) else {
            throw ImageConversionError.unsupportedFormat
        }
        // Rendered pixels have no source EXIF, GPS, comments, or embedded thumbnail metadata.
        // A fresh sRGB color profile may be written by ImageIO for consistent display.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageConversionError.encodingFailed }
        guard data.length <= maximumOutputBytes else { throw ImageConversionError.outputTooLarge }
        return data as Data
    }

    private static func type(for format: ImageConversionFormat) -> UTType {
        switch format {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        }
    }
}
