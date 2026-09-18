import AppKit
import Infrastructure
import SecurityKit

@MainActor struct NotionWorkspaceApplicationServices {
    let service: any NotionWorkspaceServing
    let copy: @MainActor (String) -> Bool
    let open: @MainActor (URL) -> Void
    init(service: any NotionWorkspaceServing,
         copy: @escaping @MainActor (String) -> Bool = { value in NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(value, forType: .string) },
         open: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.service = service; self.copy = copy; self.open = open
    }
    static func live(store: any SecureStoring) -> Self { .init(service: NotionWorkspaceService(store: store)) }
    static var unavailable: Self { .init(service: UnavailableNotionWorkspaceService()) }
}
nonisolated private struct UnavailableNotionWorkspaceService: NotionWorkspaceServing {
    func connection() async throws -> NotionWorkspaceConnection? { nil }
    func connect(token: String) async throws -> NotionWorkspaceConnection { throw NotionWorkspaceError.setupRequired }
    func disconnect() async throws { throw NotionWorkspaceError.setupRequired }
    func search(_ query: String, cursor: String?, connection: NotionWorkspaceConnection) async throws -> NotionWorkspacePage { throw NotionWorkspaceError.setupRequired }
    func children(of item: NotionWorkspaceItem, cursor: String?, connection: NotionWorkspaceConnection) async throws -> NotionWorkspacePage { throw NotionWorkspaceError.setupRequired }
}
