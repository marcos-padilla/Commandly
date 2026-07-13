#if DEBUG
import Foundation

/// Deterministic, sandbox-local files used only by the macOS UI test launch argument.
enum CommandlyFileSearchDebugFixture {
    struct Fixture {
        let rootURL: URL
        let databaseURL: URL
    }

    static func prepareIfRequested() -> Fixture? {
        guard CommandlyDebugLaunchOptions.usesFileSearchFixture else { return nil }
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent(
            "CommandlyFileSearchUITest",
            isDirectory: true
        )
        let root = base.appendingPathComponent("Indexed Files", isDirectory: true)
        let database = base
            .appendingPathComponent("Database", isDirectory: true)
            .appendingPathComponent("FileIndex.sqlite")
        try? manager.removeItem(at: base)
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            let csv = root.appendingPathComponent("wpb_hoa_contacts.csv")
            try Data(
                "Name,Email,Role\nPalm Beach HOA,board@example.com,Treasurer\n".utf8
            ).write(to: csv, options: .atomic)
            let notes = root.appendingPathComponent("Board Notes.txt")
            try Data(
                "homeowner association emergency contacts and quarterly meeting notes".utf8
            ).write(to: notes, options: .atomic)
            for index in 1 ... 8 {
                let previewFile = root.appendingPathComponent("Preview Churn \(index).txt")
                try Data(
                    "Quick Look cancellation regression fixture \(index)".utf8
                ).write(to: previewFile, options: .atomic)
            }
            return Fixture(rootURL: root, databaseURL: database)
        } catch {
            return nil
        }
    }
}
#endif
