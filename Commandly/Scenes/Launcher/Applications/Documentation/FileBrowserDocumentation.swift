import Foundation

extension RegisteredApplicationDocumentation {
    static let fileBrowser = LauncherApplicationDocumentation(category: .productivity,
        overview: "Browse the folders you authorize, navigate their immediate children inside Commandly, and explicitly open selected files.",
        sections: [
            DocumentationSection(id: "file-browser.navigate", title: "Browse a Folder", blocks: [
                .steps("file-browser.navigate.steps", [
                    "Open File Browser or Browse Authorized Folders. If needed, choose folders in Settings → Permissions.",
                    "Select an authorized folder with the arrow keys and press Return to enter it. Return enters selected child folders too.",
                    "Type to filter the displayed names. Command-Up goes to the parent folder; at an authorized root it returns to the authorized-folder list.",
                    "Return on a file or package explicitly opens it with macOS. Symbolic links and Finder aliases stay closed.",
                    "Escape clears a filter, goes up a folder, then returns to launcher search. Back returns directly to launcher search."
                ]),
                .shortcuts("file-browser.keys", [
                    DocumentationShortcut(id: "file-browser.return", title: "Enter folder or open file", keys: ["Return"]),
                    DocumentationShortcut(id: "file-browser.up", title: "Parent folder", keys: ["⌘", "↑"]),
                    DocumentationShortcut(id: "file-browser.refresh", title: "Refresh this folder", keys: ["⌘", "R"])
                ])
            ]),
            DocumentationSection(id: "file-browser.scope", title: "Private, Bounded Browsing", blocks: [
                .paragraph("file-browser.scope.bounds", "Each request reads one directory level, scans at most 5,000 directory entries, and displays at most 1,000 non-hidden files and folders. A visible notice identifies truncated folders; filtering applies only to the displayed snapshot. Refresh to see filesystem changes."),
                .paragraph("file-browser.scope.privacy", "Browsing reads names and metadata, never file contents. Authorization is rechecked for each operation. Parent navigation stops at the authorized root. Symbolic-link traversal, aliases, and hidden paths are not supported. Nothing is uploaded or logged, and no new permission is requested automatically.")
            ])
        ], keywords: ["file browser", "browse folders", "parent folder", "authorized folders"])
}
