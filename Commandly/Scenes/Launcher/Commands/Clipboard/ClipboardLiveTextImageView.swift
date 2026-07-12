import AppKit
import SwiftUI
import VisionKit

/// AppKit Live Text / Visual Look Up overlay for clipboard image previews.
///
/// Analysis runs once per image identity change — not while the user types in search.
/// Intrinsic size is intentionally unset so SwiftUI `.frame` / `.clipped` own the layout
/// (large screenshots must not expand the detail pane over the sidebar).
struct ClipboardLiveTextImageView: NSViewRepresentable {
    let image: NSImage
    let analysisKey: String

    func makeNSView(context: Context) -> ClipboardLiveTextHostView {
        let view = ClipboardLiveTextHostView()
        view.update(image: image, analysisKey: analysisKey)
        return view
    }

    func updateNSView(_ nsView: ClipboardLiveTextHostView, context: Context) {
        nsView.update(image: image, analysisKey: analysisKey)
    }
}

@MainActor
final class ClipboardLiveTextHostView: NSView {
    private let imageView = NSImageView()
    private let overlayView = ImageAnalysisOverlayView()
    private let analyzer = ImageAnalyzer()
    private var analysisTask: Task<Void, Never>?
    private var currentKey: String?

    /// Let SwiftUI supply the frame; do not size to the full pixel dimensions of the image.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true

        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        addSubview(imageView)

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.trackingImageView = imageView
        overlayView.preferredInteractionTypes = [.textSelection, .dataDetectors, .visualLookUp]
        addSubview(overlayView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: imageView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(image: NSImage, analysisKey: String) {
        imageView.image = image
        guard currentKey != analysisKey else { return }
        currentKey = analysisKey
        overlayView.analysis = nil
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            await self?.analyze(image: image, key: analysisKey)
        }
    }

    private func analyze(image: NSImage, key: String) async {
        do {
            let configuration = ImageAnalyzer.Configuration([.text, .visualLookUp])
            let analysis = try await analyzer.analyze(
                image,
                orientation: .up,
                configuration: configuration
            )
            guard Task.isCancelled == false, currentKey == key else { return }
            overlayView.analysis = analysis
        } catch {
            // Live Text is best-effort; search still uses capture-time OCR.
        }
    }
}
