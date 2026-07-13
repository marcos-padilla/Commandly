import CommandKit
import SearchKit
import SwiftUI

@MainActor
struct FileSearchApplication: LauncherApplication {
    private let services: FileSearchApplicationServices

    private static let manifest = CommandManifest(
        id: BuiltInCommandID.searchFiles,
        title: "Search Files",
        subtitle: "Find files, folders, and indexed contents",
        systemImage: "doc.text.magnifyingglass",
        category: .productivity,
        mode: .view,
        keywords: ["files", "finder", "documents", "folders", "images"],
        badgeTitle: "Command",
        defaultActions: [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openFile,
                title: "Open",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .extension,
        order: 20,
        configurationFields: [
            LauncherConfigurationField(
                id: "default-category",
                variable: "defaultCategory",
                title: "Default category",
                description: "Choose the file category selected when this application opens.",
                kind: .selection,
                defaultValue: .text(FileSearchCategory.all.rawValue),
                options: FileSearchCategory.allCases.map {
                    LauncherConfigurationOption(id: $0.rawValue, title: $0.title)
                }
            ),
            LauncherConfigurationField(
                id: "show-details",
                variable: "showsDetails",
                title: "Show file details",
                description: "Open File Search with its metadata preview visible.",
                kind: .toggle,
                defaultValue: .boolean(true)
            )
        ],
        documentation: RegisteredApplicationDocumentation.fileSearch
    )

    init(services: FileSearchApplicationServices) {
        self.services = services
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let category = context.settings.value(for: "defaultCategory")?.textValue
            .flatMap { FileSearchCategory(rawValue: $0) } ?? .all
        let showsDetails = context.settings.value(for: "showsDetails")?.booleanValue ?? true
        let model = FileSearchViewModel(
            searchService: services.searchService,
            urlOpener: services.urlOpener,
            fileRevealer: services.fileRevealer,
            fileActionService: services.fileActionService,
            finderInfoPresenter: services.finderInfoPresenter,
            pasteboard: services.pasteboard,
            initialCategory: category,
            initiallyShowsDetails: showsDetails,
            onGoBack: context.navigation.goBack,
            onDismiss: context.navigation.dismissLauncher,
            onOpenSettings: context.navigation.openSettings
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                FileSearchView(viewModel: $0)
            }
        )
    }
}

extension FileSearchViewModel: LauncherApplicationModel {}
