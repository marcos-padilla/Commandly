import Foundation

extension RegisteredApplicationDocumentation {
    static let finderPath = LauncherApplicationDocumentation(category: .productivity,
        overview: "Copy one selected Finder item's POSIX path. With no selection, copy the current Finder folder instead. Reads happen only for an explicit Copy command.",
        sections: [
            DocumentationSection(id: "finder-path.use", title: "Copy a Finder Path", blocks: [
                .steps("finder-path.steps", [
                    "Open a regular folder window in Finder. Select one file or folder, or deselect everything to copy the current folder.",
                    "Run Copy Current Finder Path. If Automation is undetermined, read the explanation and choose Allow Finder Access and Copy. macOS owns the permission dialog.",
                    "Paste the plain POSIX path. It is not a shell-escaped command or a file-access grant. Multiple selections are refused; Commandly does not choose an arbitrary item."
                ]),
                .paragraph("finder-path.limits", "The front Finder folder window is used even while Commandly is foreground. Desktop-only selection, virtual locations without a concrete local file URL, closed windows and oversized replies produce recovery guidance. Alias and symbolic-link targets are not resolved or opened.")
            ]),
            DocumentationSection(id: "finder-path.privacy", title: "Access and Recovery", blocks: [
                .paragraph("finder-path.permission", "If Finder access is denied, open System Settings → Privacy & Security → Automation and enable Finder for Commandly. Return and retry. Escape cancels the pending copy; it cannot dismiss macOS's consent dialog or recall an already-written clipboard value."),
                .paragraph("finder-path.local", "Commandly sends only fixed read Apple events to the running system Finder and rechecks its process, window, selection and path before copying. No file contents, shell, AI service, network, history database or background monitor is involved. Copied text can enter Clipboard History if enabled. Finder may still change after its final reply; macOS provides no atomic Finder-to-clipboard transaction.")
            ])
        ], keywords: ["finder", "path", "current directory", "folder", "automation", "copy"])
}
