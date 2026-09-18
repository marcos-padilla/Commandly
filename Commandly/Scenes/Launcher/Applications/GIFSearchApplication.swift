import CommandKit
import SwiftUI

@MainActor
struct GIFSearchApplication: LauncherApplication {
    static let id = CommandID(rawValue: "media.gif-search")
    static let openToolID = CommandID(rawValue: "media.gif-search.tool.open")
    static let manifest = CommandManifest(id: id, title: "GIF Search", subtitle: "Find, preview, and copy animated reactions",
        systemImage: "rectangle.on.rectangle", category: .productivity, mode: .view,
        keywords: ["gif", "gifs", "animated", "reaction", "giphy", "meme"], badgeTitle: "Application")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 49, documentation: RegisteredApplicationDocumentation.gifSearch)
    private let services: GIFSearchApplicationServices
    init(services: GIFSearchApplicationServices) { self.services = services }
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.openToolID, parentID: Self.id, title: "Search Animated GIFs", subtitle: "Search GIPHY using your own API key",
               systemImage: "rectangle.on.rectangle", keywords: ["gif", "giphy", "reaction", "animated image"])]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = GIFSearchViewModel(services: services, onGoBack: context.navigation.goBack)
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { GIFSearchView(viewModel: $0) })
    }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = arguments
        guard toolID == Self.openToolID else { return .message("This GIF tool is unavailable.") }
        return launch(in: context)
    }
}
