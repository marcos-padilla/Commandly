import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

struct LogosApplicationTests {
    @Test func catalogDecoderAcceptsFlexibleCategoriesAndAppearanceRoutes() throws {
        let data = try #require(
            """
            [
              {
                "id": 1,
                "title": "Alpha",
                "category": "Software",
                "route": "https://svgl.app/library/alpha.svg",
                "url": "https://alpha.example"
              },
              {
                "id": 2,
                "title": "Beta",
                "category": ["Design", "Software"],
                "route": {
                  "light": "https://svgl.app/library/beta-light.svg",
                  "dark": "https://svgl.app/library/beta-dark.svg"
                },
                "brandUrl": "https://beta.example/brand"
              },
              {
                "id": 3,
                "title": "Untrusted",
                "category": "Software",
                "route": "https://example.com/untrusted.svg"
              }
            ]
            """.data(using: .utf8)
        )

        let assets = try SVGLCatalogDecoder.decode(data)

        #expect(assets.map(\.title) == ["Alpha", "Beta"])
        #expect(assets[0].categories == ["Software"])
        #expect(assets[1].categories == ["Design", "Software"])
        #expect(assets[1].routes.hasAppearanceVariants)
        #expect(assets[1].routes.url(for: .dark)?.lastPathComponent == "beta-dark.svg")
    }

    @Test @MainActor func sessionSearchFilterFavoritesCopyAndDownloadRemainKeyboardUsable() async throws {
        let alphaURL = try #require(URL(string: "https://svgl.app/library/alpha.svg"))
        let betaLightURL = try #require(URL(string: "https://svgl.app/library/beta-light.svg"))
        let betaDarkURL = try #require(URL(string: "https://svgl.app/library/beta-dark.svg"))
        let alpha = LogoAsset(
            id: 1,
            title: "Alpha",
            categories: ["Software"],
            routes: LogoRoutes(standard: alphaURL, light: nil, dark: nil),
            websiteURL: nil,
            brandURL: nil
        )
        let beta = LogoAsset(
            id: 2,
            title: "Beta",
            categories: ["Design", "Software"],
            routes: LogoRoutes(standard: nil, light: betaLightURL, dark: betaDarkURL),
            websiteURL: nil,
            brandURL: nil
        )
        let alphaSVG = Data("<svg id=\"alpha\"></svg>".utf8)
        let betaLightSVG = Data("<svg id=\"beta-light\"></svg>".utf8)
        let betaDarkSVG = Data("<svg id=\"beta-dark\"></svg>".utf8)
        let service = InMemorySVGLService(
            assets: [alpha, beta],
            svgByURL: [
                alphaURL: alphaSVG,
                betaLightURL: betaLightSVG,
                betaDarkURL: betaDarkSVG
            ]
        )
        let favorites = InMemoryLogoFavoritesStore(values: [2])
        let pasteboard = InMemoryPasteboard()
        let exporter = InMemoryLogoFileExporter()
        var didGoBack = false
        let application = LogosApplication(
            services: LogosApplicationServices(
                service: service,
                favoritesStore: favorites,
                pasteboard: pasteboard,
                exporter: exporter
            )
        )
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: { didGoBack = true }
            ),
            settings: LauncherApplicationResolvedSettings(
                alias: "",
                hotKey: nil,
                isEnabled: true,
                configuration: [:]
            )
        )

        guard case .present(let session) = application.launch(in: context) else {
            Issue.record("Expected Logos to present a session")
            return
        }
        let model = try #require(session.model(as: LogosViewModel.self))
        model.load()
        await model.waitForLoadForTesting()

        #expect(application.definition.id == LogosApplication.applicationID)
        #expect(application.definition.commandManifest?.mode == .view)
        #expect(model.loadState == .loaded)
        #expect(model.selectedLogo == alpha)
        #expect(model.filterOptions.first(where: { $0.title == "Software" })?.count == 2)

        model.query = "design"
        #expect(model.filteredLogos == [beta])
        #expect(model.selectedLogo == beta)
        #expect(model.handleEscape())
        #expect(model.query.isEmpty)

        model.filterID = LogoFilterOption.favoritesID
        #expect(model.filteredLogos == [beta])
        model.variant = .dark
        model.perform(LogosActionID.copySVG)
        await model.waitForOperationForTesting()
        #expect(pasteboard.currentValue == String(data: betaDarkSVG, encoding: .utf8))
        #expect(model.statusMessage == "SVG copied.")

        model.perform(LogosActionID.copyURL)
        await model.waitForOperationForTesting()
        #expect(pasteboard.currentValue == betaDarkURL.absoluteString)

        model.perform(LogosActionID.download)
        await model.waitForOperationForTesting()
        let exports = await exporter.exports
        #expect(exports.count == 1)
        #expect(exports.first?.data == betaDarkSVG)
        #expect(exports.first?.fileName == "beta-dark.svg")

        model.perform(LogosActionID.toggleFavorite)
        await model.waitForOperationForTesting()
        let favoritesAfterRemoval = await favorites.favoriteIDs()
        #expect(favoritesAfterRemoval.isEmpty)
        #expect(model.filteredLogos.isEmpty)

        model.filterID = LogoFilterOption.allID
        model.select(alpha.id)
        model.perform(LogosActionID.toggleFavorite)
        await model.waitForOperationForTesting()
        let favoritesAfterAddition = await favorites.favoriteIDs()
        #expect(favoritesAfterAddition == Set([alpha.id]))

        model.perform(BuiltInCommandActionID.goBack)
        #expect(didGoBack)
    }

    @Test @MainActor func catalogFailureSurfacesAContentFreeRetryState() async {
        let model = LogosViewModel(
            service: InMemorySVGLService(catalogError: .catalogUnavailable),
            favoritesStore: InMemoryLogoFavoritesStore(),
            pasteboard: InMemoryPasteboard(),
            exporter: InMemoryLogoFileExporter()
        )

        model.load()
        await model.waitForLoadForTesting()

        #expect(model.loadState == .failed(.catalogUnavailable))
        #expect(model.statusMessage == "The logo catalog is temporarily unavailable.")
        #expect(model.footerActions.first?.id == LogosActionID.refresh)
    }
}
