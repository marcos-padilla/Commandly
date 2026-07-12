import Foundation
import AppCore
import CommandKit
import Persistence
import SecurityKit
import Observability

/// Assembled runtime dependencies for Commandly.
struct AppDependencies: Sendable {
    let metadata: ApplicationMetadata
    let dateProvider: any DateProviding
    let uuidProvider: any UUIDProviding
    let commandRegistry: CommandRegistry
    let persistenceStore: any PersistenceStore
    let permissionChecker: any PermissionChecking
    let logger: AppLogger
}
