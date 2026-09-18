import CommandKit
import Infrastructure
import SwiftUI

@MainActor
struct FileBrowserApplication: LauncherApplication {
    static let id = CommandID(rawValue: "files.browser")
    static let openToolID = CommandID(rawValue: "files.browser.open")
    static let manifest = CommandManifest(id: id, title: "File Browser", subtitle: "Browse your authorized folders inside Commandly",
        systemImage: "folder", category: .productivity, mode: .view,
        keywords: ["file browser", "browse files", "folders", "directories", "navigate files"], badgeTitle: "Application")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID, kind: .application, order: 21,
        documentation: RegisteredApplicationDocumentation.fileBrowser)
    private let folderAccessStore: any FolderAccessStoring
    private let urlOpener: any URLOpening
    private let browserOverride: (any FileBrowsing)?

    init(folderAccessStore: any FolderAccessStoring, urlOpener: any URLOpening, browser: (any FileBrowsing)? = nil) {
        self.folderAccessStore = folderAccessStore; self.urlOpener = urlOpener
        self.browserOverride = browser
    }
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.openToolID, parentID: Self.id, title: "Browse Authorized Folders",
               subtitle: "Navigate folders inside Commandly", systemImage: "folder",
               keywords: ["browse", "file browser", "folders", "directories"])]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = FileBrowserViewModel(browser: browserOverride ?? AuthorizedFileBrowserService(folderAccessStore: folderAccessStore),
            opener: urlOpener, onGoBack: context.navigation.goBack, onOpenPermissions: context.navigation.openPermissionsSettings)
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { FileBrowserView(model: $0) })
    }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard toolID == Self.openToolID else { return .message("That File Browser tool is unavailable.") }
        return launch(in: context)
    }
}
