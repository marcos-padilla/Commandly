import Foundation
import ImageIO
import Infrastructure
import Testing
import UniformTypeIdentifiers
@testable import Commandly

@Suite("Approved Finder AI image conversion", .timeLimit(.minutes(1)))
struct FinderAIImageConversionTests {
    @Test
    func everyAvailableNativeFormatConvertsOnlyAfterApprovalAndRemovesPrivateMetadata() async throws {
        let converter = NativeImageConversionService()
        let formats = await converter.supportedFormats()
        #expect(formats.contains(.png) && formats.contains(.jpeg))
        for format in formats {
            let files = try FinderAIImageTestFiles(); defer { files.remove() }
            let original = try #require(CGImageSourceCreateWithData(files.sourceData as CFData, nil))
            let originalMetadata = try #require(CGImageSourceCopyPropertiesAtIndex(original, 0, nil) as? [CFString: Any])
            #expect((originalMetadata[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyPNGDescription] as? String == "PRIVATE GENERATED SOURCE DESCRIPTION")
            #expect((originalMetadata[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] as? String == "PRIVATE GENERATED EXIF")
            #expect(originalMetadata[kCGImagePropertyGPSDictionary] != nil)
            let service = await files.service(converter: converter)
            let handles = try await files.handles(service)
            let options = ImageConversionOptions(format: format, longestEdge: 64, clockwiseQuarterTurns: 1)
            let name = "converted.\(format.filenameExtension)"
            let plan = try await service.planMutation(handles.request(name: name, options: options), in: handles.session)
            #expect(plan.operations.first?.imageConversion == options && plan.affectedItemCount == 1 && plan.risk == .createsItems)
            #expect(plan.operations.first?.sourceLocations.first?.rootRelativePath == "source.png")
            #expect(plan.operations.first?.destinations.first?.userVisibleDescription.contains("Output") == true)
            let output = files.destination.appendingPathComponent(name)
            #expect(!FileManager.default.fileExists(atPath: output.path))
            let approval = try await service.approveMutation(planID: plan.id, in: handles.session)
            #expect(!FileManager.default.fileExists(atPath: output.path))
            let report = try await service.executeApprovedMutation(approval)
            #expect(report.completedCount == 1 && report.results.first?.operation == .convertImage)
            #expect(try Data(contentsOf: files.source) == files.sourceData)
            let converted = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(converted, 0, nil) as? [CFString: Any])
            #expect((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 32)
            #expect((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 64)
            #expect(properties[kCGImagePropertyGPSDictionary] == nil)
            #expect((properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] == nil)
            #expect((properties[kCGImagePropertyPNGDictionary] as? [CFString: Any])?[kCGImagePropertyPNGDescription] == nil)
            #expect((try FileManager.default.attributesOfItem(atPath: output.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            #expect(try FileManager.default.contentsOfDirectory(atPath: files.destination.path) == [name])
            await #expect(throws: FinderAIWorkspaceError.invalidApproval) { try await service.executeApprovedMutation(approval) }
        }
    }

    @Test
    func exactSettingsFilenameAndNativeEncoderAreValidatedWithoutReadingImageBytes() async throws {
        let files = try FinderAIImageTestFiles(); defer { files.remove() }
        let converter = try FinderAIImageGatedConverter()
        let service = await files.service(converter: converter)
        let handles = try await files.handles(service)
        for (name, options) in [("../escape.png", ImageConversionOptions()), ("wrong.jpg", .init()),
                                 ("image.png", .init(longestEdge: 16_385)), ("image.png", .init(clockwiseQuarterTurns: 4))] {
            await #expect(throws: FinderAIWorkspaceError.self) { try await service.planMutation(handles.request(name: name, options: options), in: handles.session) }
        }
        await #expect(throws: FinderAIWorkspaceError.unsupportedImageFormat) {
            try await service.planMutation(handles.request(name: "image.heic", options: .init(format: .heic)), in: handles.session)
        }
        #expect(await converter.calls == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.destination.path).isEmpty)
    }

    @Test
    func sourceReplacementAfterCodecBeginsInvalidatesApprovalAndWritesNothing() async throws {
        let files = try FinderAIImageTestFiles(); defer { files.remove() }
        let converter = try FinderAIImageGatedConverter()
        let service = await files.service(converter: converter)
        let handles = try await files.handles(service)
        let plan = try await service.planMutation(handles.request(), in: handles.session)
        let approval = try await service.approveMutation(planID: plan.id, in: handles.session)
        let work = Task { try await service.executeApprovedMutation(approval) }
        defer { work.cancel(); Task { await converter.release() } }
        try await converter.waitForConversion()
        try Data("changed source".utf8).write(to: files.source)
        await converter.release()
        let report = try await work.value
        #expect(report.completedCount == 0 && report.results.first?.status == .failed(.itemChangedSincePreview))
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.destination.path).isEmpty)
        #expect(try Data(contentsOf: files.source) == Data("changed source".utf8))
    }

    @Test
    func sourceAndDestinationSymlinkReplacementCannotRedirectPostCodecWrites() async throws {
        for replaceSource in [true, false] {
            let files = try FinderAIImageTestFiles(); defer { files.remove() }
            let converter = try FinderAIImageGatedConverter()
            let service = await files.service(converter: converter)
            let handles = try await files.handles(service)
            let plan = try await service.planMutation(handles.request(), in: handles.session)
            let approval = try await service.approveMutation(planID: plan.id, in: handles.session)
            let work = Task { try await service.executeApprovedMutation(approval) }
            defer { work.cancel(); Task { await converter.release() } }
            try await converter.waitForConversion()
            let outside = files.base.appendingPathComponent(replaceSource ? "outside.png" : "Outside", isDirectory: !replaceSource)
            let replaced = replaceSource ? files.source : files.destination
            try FileManager.default.moveItem(at: replaced, to: outside)
            try FileManager.default.createSymbolicLink(at: replaced, withDestinationURL: outside)
            await converter.release()
            #expect(try await work.value.completedCount == 0)
            #expect(!FileManager.default.fileExists(atPath: files.destination.appendingPathComponent("converted.png").path))
            if replaceSource { #expect(try Data(contentsOf: outside) == files.sourceData) }
            else { #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty) }
        }
    }

    @Test
    func newDestinationCollisionAfterApprovalNeverOverwritesAnything() async throws {
        let files = try FinderAIImageTestFiles(); defer { files.remove() }
        let converter = try FinderAIImageGatedConverter()
        let service = await files.service(converter: converter)
        let handles = try await files.handles(service)
        let plan = try await service.planMutation(handles.request(), in: handles.session)
        let approval = try await service.approveMutation(planID: plan.id, in: handles.session)
        let work = Task { try await service.executeApprovedMutation(approval) }
        defer { work.cancel(); Task { await converter.release() } }
        try await converter.waitForConversion()
        let output = files.destination.appendingPathComponent("converted.png")
        let existing = Data("USER FILE".utf8)
        try existing.write(to: output)
        await converter.release()
        #expect(try await work.value.completedCount == 0)
        #expect(try Data(contentsOf: output) == existing)
    }

    @Test(arguments: ["cancel", "session", "expiry", "root"])
    func cancellationAndStaleAuthorityWhileCodecRunsSuppressLateResults(reason: String) async throws {
        let files = try FinderAIImageTestFiles(); defer { files.remove() }
        let converter = try FinderAIImageGatedConverter()
        let clock = FinderAIImageClock()
        let service = await files.service(converter: converter, now: { clock.now() })
        let handles = try await files.handles(service)
        let plan = try await service.planMutation(handles.request(), in: handles.session)
        let approval = try await service.approveMutation(planID: plan.id, in: handles.session)
        let work = Task { try await service.executeApprovedMutation(approval) }
        defer { work.cancel(); Task { await converter.release() } }
        try await converter.waitForConversion()
        switch reason {
        case "cancel": work.cancel()
        case "session": await service.endSession(handles.session)
        case "expiry": clock.advance()
        default: try FileManager.default.moveItem(at: files.root, to: files.base.appendingPathComponent("MovedRoot"))
        }
        await converter.release()
        let report = try await work.value
        #expect(report.completedCount == 0)
        if reason == "cancel" { #expect(report.results.first?.status == .cancelled) }
        #expect(!FileManager.default.fileExists(atPath: files.destination.appendingPathComponent("converted.png").path))
        #expect(!FileManager.default.fileExists(atPath: files.base.appendingPathComponent("MovedRoot/Output/converted.png").path))
    }
}
