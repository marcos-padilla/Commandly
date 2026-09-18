import Foundation
import Infrastructure

/// Model-facing image conversion intent contains opaque handles and settings, never filesystem paths.
nonisolated struct FinderAIImageConversionRequest: Sendable, Equatable {
    let source: FinderAIItemID
    let destination: FinderAIDirectoryReference
    let outputName: String
    let options: ImageConversionOptions

    /// Validates settings separately from the workspace's filename/identity/authority checks.
    func validate() throws {
        guard (0...3).contains(options.clockwiseQuarterTurns),
              options.longestEdge.map({ (1...16_384).contains($0) }) ?? true else {
            throw FinderAIWorkspaceError.limitExceeded
        }
        let suffix = (outputName as NSString).pathExtension.lowercased()
        let suffixes: Set<String> = switch options.format {
        case .png: ["png"]
        case .jpeg: ["jpg", "jpeg"]
        case .heic: ["heic"]
        case .tiff: ["tif", "tiff"]
        }
        guard suffixes.contains(suffix) else { throw FinderAIWorkspaceError.invalidName }
    }
}

/// A stable directory object identity, excluding its mutable child count and modification date.
nonisolated struct FinderAIImageDirectoryIdentity: Sendable, Equatable {
    let device: UInt64
    let inode: UInt64
}
