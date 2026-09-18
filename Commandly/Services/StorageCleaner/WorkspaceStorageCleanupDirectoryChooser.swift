import AppKit
import Infrastructure

/// Presents an ephemeral, user-selected duplicate-scan scope.
@MainActor
struct WorkspaceStorageCleanupDirectoryChooser: StorageCleanupDirectoryChoosing {
    func chooseDuplicateScanDirectory() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder to Find Exact Duplicates"
        panel.message = "Commandly scans this folder on device for byte-for-byte identical files."
        panel.prompt = "Scan Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
