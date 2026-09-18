import Foundation

extension RegisteredApplicationDocumentation {
    static let notionWorkspace = LauncherApplicationDocumentation(category: .productivity,
        overview: "Search and browse pages shared with your own Notion integration.", sections: [
            DocumentationSection(id: "notion.setup", title: "Connect your workspace", blocks: [
                .paragraph("notion.setup.1", "Create an internal Notion integration with Read content access and connect it to the pages you want to browse. Choose Connection, paste its token, and Check & Connect. The token is validated directly with Notion and saved in Keychain."),
                .paragraph("notion.setup.2", "Commandly cannot see pages that are not shared with the integration. It does not create accounts, install integrations, request write access or change your workspace.")]),
            DocumentationSection(id: "notion.browse", title: "Search and read", blocks: [
                .paragraph("notion.browse.1", "Submit a title search, or submit an empty search to browse shared pages and databases. Select a result and choose Browse Contents. Return in the result list opens children; Back returns to the previous level. Load More retrieves the next page."),
                .paragraph("notion.browse.2", "Readable text, headings, to-do items, table cells and nested blocks appear inside Commandly. Media, unsupported blocks and full database presentation remain available through Open in Notion. Search matches titles rather than page bodies.")]),
            DocumentationSection(id: "notion.privacy", title: "Data and privacy", blocks: [
                .paragraph("notion.privacy.1", "Explicit searches and page requests reach Notion. Page data stays in the current session; no browsing history or AI context is created. Copy Text uses the clipboard and may be retained by Clipboard History. Remove Local Connection deletes the saved token; revoke the integration separately in Notion.")])
        ])
}
