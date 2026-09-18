import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct BackgroundRemoverApplicationTests {
    @Test @MainActor
    func registeredApplicationProcessesAndOffersTransparentPNGExport() async throws {
        let expected = BackgroundRemovalResult(
            sourcePreviewPNGData: Data([1, 2, 3]),
            transparentPreviewPNGData: Data([4, 5, 6]),
            transparentPNGData: Data([137, 80, 78, 71]),
            sourceFilename: "portrait.jpg",
            pixelWidth: 1_200,
            pixelHeight: 800
        )
        let remover = FakeBackgroundRemover(result: .success(expected))
        let registry = LauncherApplicationRegistry.makeBuiltIn(
            backgroundRemovalService: remover
        )

        let definition = try #require(
            registry.definition(for: BackgroundRemoverApplication.applicationID)
        )
        #expect(definition.commandManifest?.title == "Background Remover")
        #expect(definition.parentID == BuiltInLauncherApplicationGroup.catalogID)
        #expect(definition.documentation != nil)

        let application = try #require(
            registry.application(for: BackgroundRemoverApplication.applicationID)
        )
        let launch = application.launch(in: makeContext())
        guard case .present(let session) = launch else {
            Issue.record("Expected Background Remover to present a session")
            return
        }
        let model = try #require(session.model(as: BackgroundRemoverViewModel.self))
        model.process(URL(fileURLWithPath: "/tmp/portrait.jpg"))
        await model.waitForProcessingForTesting()

        #expect(model.result == expected)
        #expect(model.suggestedFilename == "portrait-background-removed.png")
        #expect(model.footerActions.first?.id == BackgroundRemoverActionID.savePNG)
        #expect(model.statusMessage?.contains("ready to save") == true)
        #expect(await remover.requestedFilenames() == ["portrait.jpg"])

        session.stop()
        #expect(model.result == nil)
        #expect(model.statusMessage == nil)
    }

    @Test @MainActor
    func noForegroundFailureIsRecoverable() async {
        let remover = FakeBackgroundRemover(result: .failure(.noForegroundFound))
        let model = BackgroundRemoverViewModel(remover: remover, onGoBack: {})

        model.process(URL(fileURLWithPath: "/tmp/flat-image.png"))
        await model.waitForProcessingForTesting()

        #expect(model.result == nil)
        #expect(model.statusMessage == "No distinct foreground subject was found. Try an image with a clearer subject.")
        #expect(model.footerActions.first?.id == BackgroundRemoverActionID.chooseImage)
    }

    @Test @MainActor
    func backgroundRemoverToolsAreRegisteredAndChooseImageUsesTheExistingImporter() async throws {
        let remover = FakeBackgroundRemover(result: .failure(.noForegroundFound))
        let registry = LauncherApplicationRegistry.makeBuiltIn(
            backgroundRemovalService: remover
        )
        let tools = registry.children(of: BackgroundRemoverApplication.applicationID)

        #expect(tools.map(\.id) == [
            BackgroundRemoverApplication.openToolID,
            BackgroundRemoverApplication.chooseImageToolID
        ])
        #expect(tools.allSatisfy { $0.kind == .tool })
        #expect(tools.allSatisfy {
            $0.parentID == BackgroundRemoverApplication.applicationID
        })
        #expect(
            registry.owningApplicationID(for: BackgroundRemoverApplication.chooseImageToolID)
                == BackgroundRemoverApplication.applicationID
        )
        #expect(registry.allManifests().contains { manifest in
            manifest.id == BackgroundRemoverApplication.chooseImageToolID
                && manifest.keywords.contains("choose image")
        })
        #expect(
            registry.resolvedSettings(for: BackgroundRemoverApplication.chooseImageToolID) != nil
        )

        let application = try #require(
            registry.application(for: BackgroundRemoverApplication.applicationID)
        )
        guard case .present(let openSession) = application.launch(
            toolID: BackgroundRemoverApplication.openToolID,
            arguments: CommandArguments(),
            in: makeContext()
        ) else {
            Issue.record("Expected Open Background Remover to present a session")
            return
        }
        #expect(
            openSession.model(as: BackgroundRemoverViewModel.self)?.showsImageImporter == false
        )

        guard case .present(let chooseSession) = application.launch(
            toolID: BackgroundRemoverApplication.chooseImageToolID,
            arguments: CommandArguments(),
            in: makeContext()
        ) else {
            Issue.record("Expected Choose Image to present Background Remover")
            return
        }
        let model = try #require(
            chooseSession.model(as: BackgroundRemoverViewModel.self)
        )
        #expect(model.showsImageImporter)
        #expect(model.state == .empty)
        #expect(await remover.requestedFilenames().isEmpty)
    }

    @MainActor
    private func makeContext() -> LauncherApplicationContext {
        LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: LauncherApplicationResolvedSettings(
                alias: "",
                hotKey: nil,
                isEnabled: true,
                configuration: [:]
            )
        )
    }
}

private actor FakeBackgroundRemover: BackgroundRemoving {
    private let result: Result<BackgroundRemovalResult, BackgroundRemovalError>
    private var filenames: [String] = []

    init(result: Result<BackgroundRemovalResult, BackgroundRemovalError>) {
        self.result = result
    }

    func removeBackground(from sourceURL: URL) async throws -> BackgroundRemovalResult {
        filenames.append(sourceURL.lastPathComponent)
        return try result.get()
    }

    func requestedFilenames() -> [String] {
        filenames
    }
}
