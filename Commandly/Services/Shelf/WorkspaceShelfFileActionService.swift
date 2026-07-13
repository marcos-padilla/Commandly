import AppCore
import AppKit
import Foundation
import Infrastructure

/// Native, collection-aware Shelf actions backed by AppKit and actor-confined file operations.
@MainActor
final class WorkspaceShelfFileActionService: FileCollectionActionServicing {
    private var applicationsByID: [String: URL] = [:]
    private var sharingServicesByID: [String: NSSharingService] = [:]
    private let fileOperations: ShelfFileOperationCoordinator

    init() {
        self.fileOperations = ShelfFileOperationCoordinator()
    }

    func applications(toOpen urls: [URL]) async -> [FileActionOption] {
        guard let firstURL = urls.first else {
            applicationsByID = [:]
            return []
        }

        var seen: Set<String> = []
        var applications = NSWorkspace.shared.urlsForApplications(toOpen: firstURL).filter {
            seen.insert($0.standardizedFileURL.path).inserted
        }
        for url in urls.dropFirst() {
            let supportedPaths = Set(
                NSWorkspace.shared.urlsForApplications(toOpen: url).map {
                    $0.standardizedFileURL.path
                }
            )
            applications.removeAll { supportedPaths.contains($0.standardizedFileURL.path) == false }
        }

        applicationsByID = Dictionary(
            uniqueKeysWithValues: applications.map { ($0.standardizedFileURL.path, $0) }
        )
        return applications.map { applicationURL in
            FileActionOption(
                id: applicationURL.standardizedFileURL.path,
                title: applicationURL.deletingPathExtension().lastPathComponent
            )
        }
    }

    func open(_ urls: [URL], withApplication optionID: String) async throws {
        try Self.validate(urls)
        guard let applicationURL = applicationsByID[optionID] else {
            throw CommandlyError.notFound("Application")
        }

        do {
            let configuration = NSWorkspace.OpenConfiguration()
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.open(
                    urls,
                    withApplicationAt: applicationURL,
                    configuration: configuration
                ) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        } catch {
            throw CommandlyError.internalFailure("Couldn’t open the Shelf items.")
        }
    }

    func canShare(_ urls: [URL], to destination: NativeShareDestination) -> Bool {
        guard Self.areValid(urls), let service = sharingService(for: destination) else {
            return false
        }
        return service.canPerform(withItems: urls)
    }

    func share(_ urls: [URL], to destination: NativeShareDestination) throws {
        try Self.validate(urls)
        guard let service = sharingService(for: destination),
              service.canPerform(withItems: urls) else {
            throw CommandlyError.unsupported("That sharing destination is unavailable.")
        }
        service.perform(withItems: urls)
    }

    func share(_ urls: [URL], withService optionID: String) throws {
        try Self.validate(urls)
        guard let service = sharingServicesByID[optionID],
              service.canPerform(withItems: urls) else {
            throw CommandlyError.notFound("Sharing service")
        }
        service.perform(withItems: urls)
    }

    func chooseDestination(title: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    func duplicate(_ urls: [URL]) async throws -> [URL] {
        try await fileOperations.duplicate(urls)
    }

    func copy(_ urls: [URL], to directory: URL) async throws -> [URL] {
        try await fileOperations.copy(urls, to: directory)
    }

    func move(_ urls: [URL], to directory: URL) async throws -> [URL] {
        try await fileOperations.move(urls, to: directory)
    }

    func rename(_ url: URL, to newName: String) async throws -> URL {
        try await fileOperations.rename(url, to: newName)
    }

    func moveToTrash(_ urls: [URL]) async throws {
        try await fileOperations.moveToTrash(urls)
    }

    private func sharingService(for destination: NativeShareDestination) -> NSSharingService? {
        NSSharingService(named: destination.appKitSharingServiceName)
    }

    private static func validate(_ urls: [URL]) throws {
        guard areValid(urls) else {
            throw CommandlyError.invalidInput("Choose one or more file URLs.")
        }
    }

    private static func areValid(_ urls: [URL]) -> Bool {
        urls.isEmpty == false && urls.allSatisfy(\.isFileURL)
    }
}

/// `sharingServices(forItems:)` is the only public API that supplies rows for Commandly's custom
/// sharing menu. AppKit deprecates custom share lists in favor of its standard menu item, which
/// cannot populate the Shelf's accessible action list.
@available(macOS, deprecated: 13)
extension WorkspaceShelfFileActionService {
    func sharingServices(for urls: [URL]) async -> [FileActionOption] {
        guard Self.areValid(urls) else {
            sharingServicesByID = [:]
            return []
        }

        let records = NSSharingService.sharingServices(forItems: urls).enumerated().map {
            index, service in
            let id = "system-share.\(index).\(service.title)"
            return (id: id, service: service)
        }
        sharingServicesByID = Dictionary(
            uniqueKeysWithValues: records.map { ($0.id, $0.service) }
        )
        return records.map { FileActionOption(id: $0.id, title: $0.service.title) }
            .sorted {
                let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
                return titleOrder == .orderedSame ? $0.id < $1.id : titleOrder == .orderedAscending
            }
    }
}

/// Serializes blocking `FileManager` operations away from the main actor.
private actor ShelfFileOperationCoordinator {
    private let fileManager: FileManager

    init() {
        self.fileManager = FileManager()
    }

    func duplicate(_ suppliedURLs: [URL]) throws -> [URL] {
        try perform(failureMessage: "Couldn’t duplicate the Shelf items.") {
            let urls = try validatedSources(suppliedURLs)
            var destinations: [URL] = []
            destinations.reserveCapacity(urls.count)
            for url in urls {
                try Task.checkCancellation()
                let destination = uniqueDestination(
                    in: url.deletingLastPathComponent(),
                    source: url,
                    suffix: " copy"
                )
                try fileManager.copyItem(at: url, to: destination)
                destinations.append(destination)
            }
            return destinations
        }
    }

    func copy(_ suppliedURLs: [URL], to suppliedDirectory: URL) throws -> [URL] {
        try perform(failureMessage: "Couldn’t copy the Shelf items.") {
            let urls = try validatedSources(suppliedURLs)
            let directory = try validatedDirectory(suppliedDirectory)
            var destinations: [URL] = []
            destinations.reserveCapacity(urls.count)
            for url in urls {
                try Task.checkCancellation()
                let destination = uniqueDestination(in: directory, source: url)
                try fileManager.copyItem(at: url, to: destination)
                destinations.append(destination)
            }
            return destinations
        }
    }

    func move(_ suppliedURLs: [URL], to suppliedDirectory: URL) throws -> [URL] {
        try perform(failureMessage: "Couldn’t move the Shelf items.") {
            let urls = try validatedSources(suppliedURLs)
            let directory = try validatedDirectory(suppliedDirectory)
            var destinations: [URL] = []
            destinations.reserveCapacity(urls.count)
            for url in urls {
                try Task.checkCancellation()
                let destination = uniqueDestination(in: directory, source: url)
                try fileManager.moveItem(at: url, to: destination)
                destinations.append(destination)
            }
            return destinations
        }
    }

    func rename(_ suppliedURL: URL, to suppliedName: String) throws -> URL {
        try perform(failureMessage: "Couldn’t rename the Shelf item.") {
            guard let source = try validatedSources([suppliedURL]).first else {
                throw CommandlyError.notFound("Shelf item")
            }
            let name = suppliedName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false,
                  name != ".",
                  name != "..",
                  name.contains("/") == false,
                  name.utf8.contains(0) == false else {
                throw CommandlyError.invalidInput("Enter a valid file name.")
            }

            let directory = source.deletingLastPathComponent()
            let requestedDestination = directory.appendingPathComponent(name)
            if requestedDestination.standardizedFileURL == source {
                return source
            }
            let destination: URL
            if fileManager.fileExists(atPath: requestedDestination.path) {
                destination = uniqueDestination(in: directory, source: requestedDestination)
            } else {
                destination = requestedDestination
            }
            try fileManager.moveItem(at: source, to: destination)
            return destination
        }
    }

    func moveToTrash(_ suppliedURLs: [URL]) throws {
        _ = try perform(failureMessage: "Couldn’t move the Shelf items to the Trash.") {
            let urls = try validatedSources(suppliedURLs)
            for url in urls {
                try Task.checkCancellation()
                var resultingURL: NSURL?
                try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
            }
            return urls
        }
    }

    private func validatedSources(_ suppliedURLs: [URL]) throws -> [URL] {
        guard suppliedURLs.isEmpty == false else {
            throw CommandlyError.invalidInput("Choose one or more file URLs.")
        }
        return try suppliedURLs.map { suppliedURL in
            guard suppliedURL.isFileURL else {
                throw CommandlyError.invalidInput("Shelf items must be file URLs.")
            }
            let url = suppliedURL.standardizedFileURL
            guard fileManager.fileExists(atPath: url.path) else {
                throw CommandlyError.notFound("Shelf item")
            }
            return url
        }
    }

    private func validatedDirectory(_ suppliedURL: URL) throws -> URL {
        guard suppliedURL.isFileURL else {
            throw CommandlyError.invalidInput("Choose a destination folder.")
        }
        let url = suppliedURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw CommandlyError.notFound("Destination folder")
        }
        return url
    }

    private func uniqueDestination(
        in directory: URL,
        source: URL,
        suffix: String = ""
    ) -> URL {
        let extensionName = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent + suffix
        var destination = directory.appendingPathComponent(stem)
        if extensionName.isEmpty == false {
            destination.appendPathExtension(extensionName)
        }
        var index = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(stem) \(index)")
            if extensionName.isEmpty == false {
                destination.appendPathExtension(extensionName)
            }
            index += 1
        }
        return destination
    }

    private func perform<Value: Sendable>(
        failureMessage: String,
        operation: () throws -> Value
    ) throws -> Value {
        do {
            return try operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CommandlyError {
            throw error
        } catch {
            let nsError = error as NSError
            let permissionCodes = [
                CocoaError.Code.fileReadNoPermission.rawValue,
                CocoaError.Code.fileWriteNoPermission.rawValue
            ]
            if nsError.domain == NSCocoaErrorDomain, permissionCodes.contains(nsError.code) {
                throw CommandlyError.security("The selected location is not accessible.")
            }
            throw CommandlyError.internalFailure(failureMessage)
        }
    }
}
