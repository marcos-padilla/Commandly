import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Displays a static Quick Look representation without embedding `QLPreviewView`.
///
/// A live `QLPreviewView` owns private KVO observers and mutable scrolling state. Reassigning its
/// preview item during rapid launcher selection changes can trigger an AppKit consistency exception.
/// This view requests an immutable system-generated representation instead and cancels stale work.
struct QuickLookSnapshotPreview: View {
    private struct PreviewIdentity: Hashable {
        let url: URL
        let modificationDate: Date?
    }

    let url: URL
    let modificationDate: Date?
    @State private var snapshot: CGImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let snapshot {
                Image(snapshot, scale: 2, label: Text(url.lastPathComponent))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                VStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: 96, maxHeight: 96)
                    if didFail {
                        Text("Preview unavailable")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: PreviewIdentity(url: url, modificationDate: modificationDate)) {
            snapshot = nil
            didFail = false
            do {
                snapshot = try await QuickLookSnapshotLoader.load(url: url)
            } catch is CancellationError {
                return
            } catch {
                didFail = true
            }
        }
    }
}

enum QuickLookSnapshotLoader {
    @MainActor
    private final class RequestController {
        let request: QLThumbnailGenerator.Request

        init(url: URL) {
            request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 1_024, height: 1_024),
                scale: 2,
                representationTypes: [.lowQualityThumbnail, .thumbnail]
            )
        }

        func cancel() {
            QLThumbnailGenerator.shared.cancel(request)
        }
    }

    static func load(url: URL) async throws -> CGImage {
        let controller = RequestController(url: url)
        return try await withTaskCancellationHandler(
            operation: {
                let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(
                    for: controller.request
                )
                guard Task.isCancelled == false else { throw CancellationError() }
                return representation.cgImage
            },
            onCancel: {
                Task { @MainActor in
                    controller.cancel()
                }
            },
            isolation: MainActor.shared
        )
    }
}
