import Foundation

extension RegisteredApplicationDocumentation {
    static let logos = LauncherApplicationDocumentation(
        category: .productivity,
        overview: "Browse the community-maintained SVGL catalog inside Commandly, search or filter its SVG brand assets, keep local favorites, and explicitly copy or download a selected logo.",
        sections: [
            DocumentationSection(
                id: "logos.browse",
                title: "Find a Logo",
                blocks: [
                    .bullets("logos.browse.options", [
                        "Search matches logo titles and categories in the loaded catalog.",
                        "The filter menu includes All Logos, Favorites, and every category returned by SVGL.",
                        "Appearance-aware assets provide Light and Dark variants in the detail pane."
                    ]),
                    .shortcuts("logos.browse.shortcuts", [
                        DocumentationShortcut(id: "logos.browse.arrows", title: "Move selection", keys: ["↑", "↓"]),
                        DocumentationShortcut(id: "logos.browse.copy", title: "Copy the selected SVG", keys: ["Return"]),
                        DocumentationShortcut(id: "logos.browse.actions", title: "Open actions", keys: ["⌘", "K"]),
                        DocumentationShortcut(id: "logos.browse.escape", title: "Clear search or filter, then go back", keys: ["Esc"])
                    ])
                ]
            ),
            DocumentationSection(
                id: "logos.actions",
                title: "Copy, Favorite, and Download",
                blocks: [
                    .bullets("logos.actions.items", [
                        "Copy SVG fetches the selected variant and places its SVG source on the pasteboard.",
                        "Copy SVG URL places the validated svgl.app asset URL on the pasteboard.",
                        "Download opens a native save panel and writes the selected SVG only after you choose a destination.",
                        "Favorites persist locally on this Mac and can be used as a filter."
                    ]),
                    .callout(
                        "logos.actions.usage",
                        DocumentationCallout(
                            kind: .important,
                            title: "Check brand usage rights",
                            text: "SVGL provides community-maintained assets, not a blanket trademark license. Review the brand owner's guidance before publishing or redistributing a logo."
                        )
                    )
                ]
            ),
            DocumentationSection(
                id: "logos.network",
                title: "Network and Privacy",
                blocks: [
                    .callout(
                        "logos.network.cache",
                        DocumentationCallout(
                            kind: .privacy,
                            title: "Cached, query-local browsing",
                            text: "Opening Logos contacts api.svgl.app to load the public catalog. Commandly caches that response for ten minutes and searches it locally, so typed queries and favorites are not sent to SVGL. Visible previews, copy, and download may fetch selected SVG files from svgl.app."
                        )
                    ),
                    .callout(
                        "logos.network.limits",
                        DocumentationCallout(
                            kind: .limitation,
                            title: "Community service dependency",
                            text: "Catalog and asset availability depend on SVGL and the network. Commandly does not upload logos, create an SVGL account, submit assets, or guarantee that a remote logo remains available."
                        )
                    )
                ]
            )
        ],
        keywords: ["brand assets", "vector", "SVG", "SVGL", "favorites", "download", "categories"]
    )
}
