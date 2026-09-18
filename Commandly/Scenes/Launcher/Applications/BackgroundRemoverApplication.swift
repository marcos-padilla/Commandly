import CommandKit
import Infrastructure
import SwiftUI

/// Removes image backgrounds locally with Apple Vision and exports transparent PNG files.
@MainActor
struct BackgroundRemoverApplication: LauncherApplication {
    static let applicationID = CommandID(rawValue: "images.background-remover")
    static let openToolID = CommandID(rawValue: "images.background-remover.tool.open")
    static let chooseImageToolID = CommandID(rawValue: "background-remover.choose-image")

    static let manifest = CommandManifest(
        id: applicationID,
        title: "Background Remover",
        subtitle: "Create a transparent PNG with on-device AI",
        systemImage: "person.crop.rectangle",
        category: .productivity,
        mode: .view,
        keywords: [
            "background", "remove background", "bg", "bg remover", "remove image", "transparent",
            "image", "photo", "cutout", "subject", "png", "AI"
        ],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: BackgroundRemoverActionID.chooseImage,
                title: "Choose Image",
                isPrimary: true,
                keyHint: .return
            )
        ]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 38,
        documentation: RegisteredApplicationDocumentation.backgroundRemover
    )

    private let remover: any BackgroundRemoving

    init(remover: any BackgroundRemoving) {
        self.remover = remover
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: Self.openToolID,
                parentID: Self.applicationID,
                title: "Open Background Remover",
                subtitle: "Create a transparent PNG with on-device AI",
                systemImage: "person.crop.rectangle",
                keywords: [
                    "open", "background remover", "remove background", "bg", "transparent", "png"
                ]
            ),
            LauncherApplicationDefinition.tool(
                id: Self.chooseImageToolID,
                parentID: Self.applicationID,
                title: "Choose Image",
                subtitle: "Choose an image to remove its background",
                systemImage: "photo.on.rectangle",
                order: 1,
                keywords: [
                    "choose image", "select image", "background", "bg remover", "photo", "cutout"
                ]
            )
        ]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        makeLaunch(opensImageImporter: false, context: context)
    }

    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        _ = arguments
        switch toolID {
        case Self.openToolID:
            return makeLaunch(opensImageImporter: false, context: context)
        case Self.chooseImageToolID:
            return makeLaunch(opensImageImporter: true, context: context)
        default:
            return .message("Background Remover tool is unavailable.")
        }
    }

    private func makeLaunch(
        opensImageImporter: Bool,
        context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        let model = BackgroundRemoverViewModel(
            remover: remover,
            onGoBack: context.navigation.goBack
        )
        if opensImageImporter {
            model.perform(BackgroundRemoverActionID.chooseImage)
        }
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                BackgroundRemoverView(viewModel: $0)
            }
        )
    }
}
