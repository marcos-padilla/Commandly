import Foundation
import AppCore
import CommandKit
import Persistence
import SecurityKit
import Observability
import Infrastructure

/// Assembled runtime dependencies for Commandly.
struct AppDependencies: Sendable {
    let metadata: ApplicationMetadata
    let dateProvider: any DateProviding
    let uuidProvider: any UUIDProviding
    let commandRegistry: CommandRegistry
    let persistenceStore: any PersistenceStore
    let secureStore: any SecureStoring
    let aiConnectionStore: any AIConnectionStoring
    let permissionService: any PermissionServicing
    let privacySettingsOpener: any PrivacySettingsOpening
    let onboardingStatusStore: any OnboardingStatusStoring
    let appSettingsStore: any AppSettingsStoring
    let launcherApplicationPreferencesStore: any LauncherApplicationPreferencesStoring
    let applicationPreferencesStore: any ApplicationPreferencesStoring
    let folderAccessStore: any FolderAccessStoring
    let loginItemManager: any LoginItemManaging
    let logger: AppLogger
}
