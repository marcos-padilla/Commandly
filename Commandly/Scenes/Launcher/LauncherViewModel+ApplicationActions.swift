import Foundation
import AppKit
import CommandKit
import Infrastructure
import SwiftUI

extension LauncherViewModel {
    func presentApplicationActions(forBundleID bundleIdentifier: String) {
        guard cachedApplications.contains(where: { $0.bundleIdentifier == bundleIdentifier })
            || selectedApplicationBundleID == bundleIdentifier
        else {
            // Allow presentation even if cache is briefly empty by resolving from selection.
            if case .openInstalledApplication(let id) = selectedItem?.action,
               id == bundleIdentifier {
                applicationActionsTargetBundleID = bundleIdentifier
                applicationActionsQuery = ""
                return
            }
            statusMessage = "That application isn’t available."
            return
        }
        applicationActionsTargetBundleID = bundleIdentifier
        applicationActionsQuery = ""
        statusMessage = nil
    }

    func presentApplicationActionsForSelection() {
        if let bundleID = selectedApplicationBundleID {
            presentApplicationActions(forBundleID: bundleID)
        } else if let selectedItem,
                  case .launchApplication = selectedItem.action {
            presentRegisteredCommandActions(for: selectedItem)
        } else {
            statusMessage = "Select a command or application to see actions."
        }
    }

    func dismissApplicationActionsPanel() {
        applicationActionsTargetBundleID = nil
        applicationActionsQuery = ""
    }

    func applicationActions(for bundleIdentifier: String?) -> [LauncherApplicationAction] {
        guard let bundleIdentifier else { return [] }
        let prefs = applicationPreferencesStore.load()
        let favorite = prefs.isFavorite(bundleIdentifier)
        let disabled = prefs.isDisabled(bundleIdentifier)
        let autoQuit = prefs.isAutoQuitEnabled(bundleIdentifier)

        var actions = [
            LauncherApplicationAction(
                id: BuiltInCommandActionID.openApplication,
                title: "Open Application",
                systemImage: "macwindow",
                keyHint: .return,
                isDestructive: false,
                section: .primary
            ),
            LauncherApplicationAction(
                id: BuiltInCommandActionID.showInFinder,
                title: "Show in Finder",
                systemImage: "folder",
                keyHint: CommandKeyHint(symbols: ["⌘", "↩"]),
                isDestructive: false,
                section: .finder
            ),
            LauncherApplicationAction(
                id: BuiltInCommandActionID.showInfoInFinder,
                title: "Show Info in Finder",
                systemImage: "info.circle",
                keyHint: CommandKeyHint(symbols: ["⌘", "I"]),
                isDestructive: false,
                section: .finder
            ),
            LauncherApplicationAction(
                id: BuiltInCommandActionID.showPackageContents,
                title: "Show Package Contents",
                systemImage: "folder.badge.gearshape",
                keyHint: CommandKeyHint(symbols: ["⌥", "⌘", "I"]),
                isDestructive: false,
                section: .finder
            ),
            LauncherApplicationAction(
                id: BuiltInCommandActionID.toggleFavorite,
                title: favorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: favorite ? "star.fill" : "star",
                keyHint: CommandKeyHint(symbols: ["⇧", "⌘", "F"]),
                isDestructive: false,
                section: .finder
            ),
            LauncherApplicationAction(
                id: BuiltInCommandActionID.copyAppName,
                title: "Copy Name",
                systemImage: "doc.on.doc",
                keyHint: CommandKeyHint(symbols: ["⌘", "."]),
                isDestructive: false,
                section: .clipboard
            ),
            LauncherApplicationAction(
                id: BuiltInCommandActionID.copyAppPath,
                title: "Copy Path",
                systemImage: "doc.on.doc",
                keyHint: CommandKeyHint(symbols: ["⇧", "⌘", "."]),
                isDestructive: false,
                section: .clipboard
            ),
            LauncherApplicationAction(
                id: BuiltInCommandActionID.copyBundleIdentifier,
                title: "Copy Bundle Identifier",
                systemImage: "doc.on.doc",
                keyHint: CommandKeyHint(symbols: ["⇧", "⌘", "C"]),
                isDestructive: false,
                section: .clipboard
            ),
            LauncherApplicationAction(
                id: BuiltInCommandActionID.toggleAutoQuit,
                title: autoQuit ? "Disable Auto Quit" : "Enable Auto Quit",
                systemImage: "xmark.circle",
                keyHint: nil,
                isDestructive: false,
                section: .manage
            ),
            LauncherApplicationAction(
                id: BuiltInCommandActionID.toggleDisableApplication,
                title: disabled ? "Enable Application" : "Disable Application",
                systemImage: disabled ? "checkmark.circle" : "nosign",
                keyHint: CommandKeyHint(symbols: ["⌃", "⇧", "⌘", "D"]),
                isDestructive: disabled == false,
                section: .manage
            ),
            LauncherApplicationAction(
                id: BuiltInCommandActionID.uninstallApplication,
                title: "Uninstall Application…",
                systemImage: "trash",
                keyHint: nil,
                isDestructive: true,
                section: .manage
            ),
            LauncherApplicationAction(
                id: BuiltInCommandActionID.resetAppRanking,
                title: "Reset Ranking",
                systemImage: "arrow.counterclockwise",
                keyHint: nil,
                isDestructive: false,
                section: .ranking
            )
        ]
        if commandWheelAssignmentStore != nil {
            actions.insert(
                LauncherApplicationAction(
                    id: LauncherCommandWheelActionID.add,
                    title: "Add to Command Wheel…",
                    systemImage: "circle.grid.cross",
                    keyHint: nil,
                    isDestructive: false,
                    section: .manage
                ),
                at: actions.firstIndex(where: { $0.section == .manage }) ?? actions.endIndex
            )
        }
        return actions
    }

    func performApplicationAction(_ id: CommandActionID) {
        guard let bundleID = applicationActionsTargetBundleID ?? selectedApplicationBundleID else {
            return
        }
        Task { @MainActor [weak self] in
            await self?.performApplicationAction(id, bundleIdentifier: bundleID)
        }
    }

    /// Handles keyboard shortcuts while the application actions panel is open.
    func handleApplicationActionsKeyPress(characters: String, modifiers: EventModifiers) -> Bool {
        guard showsApplicationActionsPanel else { return false }
        let chars = characters.lowercased()
        if modifiers.contains(.command), modifiers.contains(.shift), chars == "f" {
            performApplicationAction(BuiltInCommandActionID.toggleFavorite)
            return true
        }
        if modifiers.contains(.command), modifiers.contains(.shift), chars == "c" {
            performApplicationAction(BuiltInCommandActionID.copyBundleIdentifier)
            return true
        }
        if modifiers.contains(.command), modifiers.contains(.shift), chars == "." {
            performApplicationAction(BuiltInCommandActionID.copyAppPath)
            return true
        }
        if modifiers.contains(.command), chars == "." {
            performApplicationAction(BuiltInCommandActionID.copyAppName)
            return true
        }
        if modifiers.contains(.command), modifiers.contains(.option), chars == "i" {
            performApplicationAction(BuiltInCommandActionID.showPackageContents)
            return true
        }
        if modifiers.contains(.command), chars == "i" {
            performApplicationAction(BuiltInCommandActionID.showInfoInFinder)
            return true
        }
        if modifiers.contains(.command),
           modifiers.contains(.shift),
           modifiers.contains(.control),
           chars == "d" {
            performApplicationAction(BuiltInCommandActionID.toggleDisableApplication)
            return true
        }
        if modifiers.contains(.command), characters == "\r" || characters == "\n" {
            performApplicationAction(BuiltInCommandActionID.showInFinder)
            return true
        }
        if characters == "\r" || characters == "\n" {
            performApplicationAction(BuiltInCommandActionID.openApplication)
            return true
        }
        return false
    }

    func recordApplicationOpen(bundleIdentifier: String) {
        var prefs = applicationPreferencesStore.load()
        var ranking = prefs.ranking(for: bundleIdentifier)
        ranking.openCount += 1
        ranking.lastOpenedAt = Date()
        prefs.ranking[bundleIdentifier] = ranking
        applicationPreferencesStore.save(prefs)
    }

    private func performApplicationAction(
        _ id: CommandActionID,
        bundleIdentifier: String
    ) async {
        if id == LauncherCommandWheelActionID.add {
            dismissApplicationActionsPanel()
            presentCommandWheelAssignmentForInstalledApplication(
                bundleIdentifier: bundleIdentifier
            )
            return
        }
        guard let app = resolveApplication(bundleIdentifier: bundleIdentifier) else {
            statusMessage = "That application isn’t available."
            dismissApplicationActionsPanel()
            return
        }

        switch id {
        case BuiltInCommandActionID.openApplication:
            dismissApplicationActionsPanel()
            await openApplication(bundleIdentifier: bundleIdentifier)

        case BuiltInCommandActionID.showInFinder:
            do {
                try await fileRevealer.revealInFinder(urls: [URL(fileURLWithPath: app.path)])
                dismissApplicationActionsPanel()
                dismiss()
            } catch {
                statusMessage = "Couldn’t show that application in Finder."
            }

        case BuiltInCommandActionID.showInfoInFinder:
            do {
                try await finderInfoPresenter.showGetInfo(atPath: app.path)
                dismissApplicationActionsPanel()
                dismiss()
            } catch {
                statusMessage = "Couldn’t open Get Info. Allow Automation for Finder in System Settings."
            }

        case BuiltInCommandActionID.showPackageContents:
            do {
                try await bundleManager.showPackageContents(atApplicationPath: app.path)
                dismissApplicationActionsPanel()
                dismiss()
            } catch {
                statusMessage = "Couldn’t open package contents."
            }

        case BuiltInCommandActionID.toggleFavorite:
            var prefs = applicationPreferencesStore.load()
            if prefs.favoriteBundleIDs.contains(bundleIdentifier) {
                prefs.favoriteBundleIDs.remove(bundleIdentifier)
                statusMessage = "Removed from Favorites."
            } else {
                prefs.favoriteBundleIDs.insert(bundleIdentifier)
                statusMessage = "Added to Favorites."
            }
            applicationPreferencesStore.save(prefs)
            scheduleSearch()

        case BuiltInCommandActionID.copyAppName:
            await pasteboard.writeString(app.name)
            statusMessage = "Copied name."
            dismissApplicationActionsPanel()

        case BuiltInCommandActionID.copyAppPath:
            await pasteboard.writeString(app.path)
            statusMessage = "Copied path."
            dismissApplicationActionsPanel()

        case BuiltInCommandActionID.copyBundleIdentifier:
            await pasteboard.writeString(app.bundleIdentifier)
            statusMessage = "Copied bundle identifier."
            dismissApplicationActionsPanel()

        case BuiltInCommandActionID.toggleAutoQuit:
            var prefs = applicationPreferencesStore.load()
            if prefs.autoQuitBundleIDs.contains(bundleIdentifier) {
                prefs.autoQuitBundleIDs.remove(bundleIdentifier)
                statusMessage = "Auto Quit disabled."
            } else {
                prefs.autoQuitBundleIDs.insert(bundleIdentifier)
                statusMessage = "Auto Quit enabled."
            }
            applicationPreferencesStore.save(prefs)

        case BuiltInCommandActionID.toggleDisableApplication:
            var prefs = applicationPreferencesStore.load()
            if prefs.disabledBundleIDs.contains(bundleIdentifier) {
                prefs.disabledBundleIDs.remove(bundleIdentifier)
                statusMessage = "Application enabled."
            } else {
                prefs.disabledBundleIDs.insert(bundleIdentifier)
                statusMessage = "Application disabled."
            }
            applicationPreferencesStore.save(prefs)
            dismissApplicationActionsPanel()
            scheduleSearch()

        case BuiltInCommandActionID.uninstallApplication:
            dismissApplicationActionsPanel()
            presentUninstallReview(for: app)

        case BuiltInCommandActionID.resetAppRanking:
            var prefs = applicationPreferencesStore.load()
            prefs.ranking[bundleIdentifier] = nil
            applicationPreferencesStore.save(prefs)
            statusMessage = "Ranking reset."
            scheduleSearch()

        default:
            break
        }
    }

    func presentUninstallReview(for app: InstalledApplicationSnapshot) {
        uninstallViewModel = ApplicationUninstallViewModel(
            applicationName: app.name,
            applicationPath: app.path,
            bundleIdentifier: app.bundleIdentifier,
            discoverer: uninstallDiscoverer,
            bundleManager: bundleManager,
            onFinished: { [weak self] message in
                guard let self else { return }
                self.cachedApplications.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
                var prefs = self.applicationPreferencesStore.load()
                prefs.favoriteBundleIDs.remove(app.bundleIdentifier)
                prefs.disabledBundleIDs.remove(app.bundleIdentifier)
                prefs.autoQuitBundleIDs.remove(app.bundleIdentifier)
                prefs.ranking[app.bundleIdentifier] = nil
                self.applicationPreferencesStore.save(prefs)
                self.statusMessage = message
                self.goBack()
                self.scheduleSearch()
            },
            onCancel: { [weak self] in
                self?.goBack()
            }
        )
        route = .uninstallReview(bundleIdentifier: app.bundleIdentifier)
        statusMessage = nil
    }

    private func resolveApplication(bundleIdentifier: String) -> InstalledApplicationSnapshot? {
        if let cached = cachedApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return cached
        }
        if case .openInstalledApplication(let id) = selectedItem?.action,
           id == bundleIdentifier,
           case .application(let path) = selectedItem?.icon {
            return InstalledApplicationSnapshot(
                bundleIdentifier: bundleIdentifier,
                name: selectedItem?.title ?? bundleIdentifier,
                path: path
            )
        }
        return nil
    }
}
