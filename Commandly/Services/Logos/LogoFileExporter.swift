import AppKit
import Foundation
import UniformTypeIdentifiers

nonisolated protocol LogoFileExporting: Sendable {
    func export(svg: Data, suggestedFileName: String) async throws -> Bool
}

nonisolated enum LogoFileExportError: LocalizedError, Sendable {
    case writeFailed

    var errorDescription: String? { "The logo could not be saved." }
}

actor NativeLogoFileExporter: LogoFileExporting {
    func export(svg: Data, suggestedFileName: String) async throws -> Bool {
        let destination = await MainActor.run { () -> URL? in
            let panel = NSSavePanel()
            panel.title = "Download Logo"
            panel.nameFieldStringValue = suggestedFileName
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [.svg]
            guard panel.runModal() == .OK else { return nil }
            return panel.url
        }
        guard let destination else { return false }

        let isAccessing = destination.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { destination.stopAccessingSecurityScopedResource() }
        }
        do {
            try svg.write(to: destination, options: .atomic)
            return true
        } catch {
            throw LogoFileExportError.writeFailed
        }
    }
}

actor InMemoryLogoFileExporter: LogoFileExporting {
    private(set) var exports: [(data: Data, fileName: String)] = []

    func export(svg: Data, suggestedFileName: String) -> Bool {
        exports.append((svg, suggestedFileName))
        return true
    }
}
