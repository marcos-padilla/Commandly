import Foundation
import Observation
import AppCore

@Observable
@MainActor
final class RootViewModel {
    let title: String
    let status: String
    let message: String
    let metadata: ApplicationMetadata

    init(metadata: ApplicationMetadata) {
        self.metadata = metadata
        self.title = metadata.name
        self.status = "Foundation ready"
        self.message = "Feature development has not started yet."
    }
}
