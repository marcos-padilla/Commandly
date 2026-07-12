import Foundation
import Observation
import AppCore

@Observable
@MainActor
final class AppState {
    var route: AppRoute
    let metadata: ApplicationMetadata

    init(metadata: ApplicationMetadata, route: AppRoute = .root) {
        self.metadata = metadata
        self.route = route
    }
}
