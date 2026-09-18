import CommandKit
import Infrastructure
import SwiftUI

@MainActor struct FinderPathApplication: LauncherApplication {
    static let id = CommandID(rawValue: "files.finder-path")
    static let copyToolID = CommandID(rawValue: "files.finder-path.copy")
    static let manifest = CommandManifest(id: id, title: "Finder Path", subtitle: "Copy the selected item or current folder path",
        systemImage: "folder", category: .productivity, mode: .view,
        keywords: ["finder", "path", "current directory", "copy path", "folder path"], badgeTitle: "Application")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 52, documentation: RegisteredApplicationDocumentation.finderPath)
    private let services: FinderPathApplicationServices
    init(services: FinderPathApplicationServices) { self.services = services }
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.copyToolID, parentID: Self.id, title: "Copy Current Finder Path",
               subtitle: "One selected item, or the current folder when nothing is selected", systemImage: "doc.on.doc",
               category: .productivity, keywords: ["finder", "copy path", "current directory", "folder path"])]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch { makeLaunch(context, copyImmediately: false) }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        guard toolID == Self.copyToolID, arguments.values.isEmpty else { return .message(FinderPathError.invalidRequest.message) }
        return makeLaunch(context, copyImmediately: true)
    }
    private func makeLaunch(_ context: LauncherApplicationContext, copyImmediately: Bool) -> LauncherApplicationLaunch {
        guard context.settings.isEnabled else { return .message(FinderPathError.disabled.message) }
        let model = FinderPathViewModel(services: services, onGoBack: context.navigation.goBack)
        // The tool's explicit activation attempts a no-prompt copy; undetermined permission leaves
        // this explanation visible until the person chooses Allow Finder Access and Copy.
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) {
            FinderPathView(viewModel: $0, copyImmediately: copyImmediately)
        })
    }
}
