#if DEBUG
import SwiftUI

#Preview("Loaded catalog") {
    if let alphaURL = URL(string: "https://svgl.app/library/alpha.svg"),
       let betaLightURL = URL(string: "https://svgl.app/library/beta-light.svg"),
       let betaDarkURL = URL(string: "https://svgl.app/library/beta-dark.svg") {
        let alphaSVG = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 50">
              <rect width="120" height="50" rx="12" fill="#111827"/>
              <text x="60" y="32" text-anchor="middle" fill="white" font-size="20">ALPHA</text>
            </svg>
            """.utf8
        )
        let betaLightSVG = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 50">
              <circle cx="25" cy="25" r="20" fill="#7C3AED"/>
              <text x="52" y="32" fill="#171717" font-size="20">Beta</text>
            </svg>
            """.utf8
        )
        let betaDarkSVG = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 50">
              <circle cx="25" cy="25" r="20" fill="#A78BFA"/>
              <text x="52" y="32" fill="white" font-size="20">Beta</text>
            </svg>
            """.utf8
        )
        let service = InMemorySVGLService(
            assets: [
                LogoAsset(
                    id: 1,
                    title: "Alpha",
                    categories: ["Software"],
                    routes: LogoRoutes(standard: alphaURL, light: nil, dark: nil),
                    websiteURL: nil,
                    brandURL: nil
                ),
                LogoAsset(
                    id: 2,
                    title: "Beta",
                    categories: ["Design", "Software"],
                    routes: LogoRoutes(
                        standard: nil,
                        light: betaLightURL,
                        dark: betaDarkURL
                    ),
                    websiteURL: nil,
                    brandURL: nil
                )
            ],
            svgByURL: [
                alphaURL: alphaSVG,
                betaLightURL: betaLightSVG,
                betaDarkURL: betaDarkSVG
            ]
        )
        let model = LogosViewModel(
            service: service,
            favoritesStore: InMemoryLogoFavoritesStore(values: [2]),
            pasteboard: InMemoryPasteboard(),
            exporter: InMemoryLogoFileExporter()
        )
        LogosView(viewModel: model)
            .frame(width: 760, height: 460)
    } else {
        Text("Preview fixture unavailable")
    }
}
#endif
