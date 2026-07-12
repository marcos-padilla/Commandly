/// Describes the runtime environment in which Commandly is executing.
public enum ApplicationEnvironment: String, Sendable, Equatable, CaseIterable {
    case development
    case testing
    case production
}
