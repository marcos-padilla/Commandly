nonisolated struct MarkdownPreviewApplicationServices: Sendable {
    let loader: any MarkdownPreviewFileLoading
    let renderer: any MarkdownPreviewRendering
    let watcher: any MarkdownPreviewFileWatching
    let scrollStore: any MarkdownPreviewScrollStateStoring

    init(
        loader: any MarkdownPreviewFileLoading,
        renderer: any MarkdownPreviewRendering,
        watcher: any MarkdownPreviewFileWatching,
        scrollStore: any MarkdownPreviewScrollStateStoring
    ) {
        self.loader = loader
        self.renderer = renderer
        self.watcher = watcher
        self.scrollStore = scrollStore
    }

    static var live: MarkdownPreviewApplicationServices {
        MarkdownPreviewApplicationServices(
            loader: BoundedMarkdownPreviewFileLoader(),
            renderer: MarkdownPreviewRendererAdapter(),
            watcher: DispatchSourceMarkdownPreviewFileWatcher(),
            scrollStore: UserDefaultsMarkdownPreviewScrollStore()
        )
    }

    static var inMemory: MarkdownPreviewApplicationServices {
        MarkdownPreviewApplicationServices(
            loader: BoundedMarkdownPreviewFileLoader(),
            renderer: MarkdownPreviewRendererAdapter(),
            watcher: NoopMarkdownPreviewFileWatcher(),
            scrollStore: InMemoryMarkdownPreviewScrollStore()
        )
    }
}
