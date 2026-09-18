import DesignSystem
import SwiftUI
import WebKit

struct LogoSVGArtwork: View {
    let url: URL?
    let title: String
    let service: any SVGLServicing
    @State private var data: Data?
    @State private var didFail = false

    var body: some View {
        ZStack {
            if let data {
                EmbeddedSVGView(data: data)
                    .accessibilityHidden(true)
            } else {
                Text(initials)
                    .commandlyFont(size: 17, weight: .bold)
                    .foregroundStyle(.tertiary)
                if didFail == false {
                    ProgressView()
                        .controlSize(.mini)
                        .opacity(0.65)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            data = nil
            didFail = false
            guard let url else {
                didFail = true
                return
            }
            do {
                data = try await service.svgData(from: url)
            } catch is CancellationError {
                return
            } catch {
                didFail = true
            }
        }
        .accessibilityLabel("\(title) logo preview")
    }

    private var initials: String {
        let words = title.split(separator: " ")
        let characters = words.prefix(2).compactMap(\.first)
        return String(characters).uppercased()
    }
}

private struct EmbeddedSVGView: NSViewRepresentable {
    let data: Data

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = NonInteractiveWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityElement(false)
        load(data, into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedData != data else { return }
        load(data, into: webView, coordinator: context.coordinator)
    }

    private func load(_ data: Data, into webView: WKWebView, coordinator: Coordinator) {
        coordinator.loadedData = data
        let encoded = data.base64EncodedString()
        let html = """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; }
              body { display: flex; align-items: center; justify-content: center; }
              img { display: block; width: 100%; height: 100%; object-fit: contain; }
            </style>
          </head>
          <body><img alt="" src="data:image/svg+xml;base64,\(encoded)"></body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator {
        var loadedData: Data?
    }
}

private final class NonInteractiveWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
