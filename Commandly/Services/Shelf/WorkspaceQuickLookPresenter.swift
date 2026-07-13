import Foundation
import Infrastructure
import QuickLookUI

/// Presents ordered Shelf resources in the system Quick Look panel.
@MainActor
final class WorkspaceQuickLookPresenter: FilePreviewPresenting {
    // QLPreviewPanel does not retain its data source, so the adapter owns it for the panel lifetime.
    private var retainedDataSource: ShelfQuickLookDataSource?

    func preview(urls: [URL], selectedIndex: Int) {
        guard urls.isEmpty == false,
              urls.allSatisfy(\.isFileURL),
              let panel = QLPreviewPanel.shared() else { return }

        let dataSource = ShelfQuickLookDataSource(urls: urls)
        retainedDataSource = dataSource
        panel.dataSource = dataSource
        panel.reloadData()
        panel.currentPreviewItemIndex = min(max(0, selectedIndex), urls.count - 1)
        panel.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class ShelfQuickLookDataSource: NSObject, QLPreviewPanelDataSource {
    private let items: [NSURL]

    init(urls: [URL]) {
        self.items = urls.map { $0 as NSURL }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        _ = panel
        return items.count
    }

    func previewPanel(
        _ panel: QLPreviewPanel,
        previewItemAt index: Int
    ) -> any QLPreviewItem {
        _ = panel
        guard items.indices.contains(index) else {
            return NSURL(fileURLWithPath: "/")
        }
        return items[index]
    }
}
