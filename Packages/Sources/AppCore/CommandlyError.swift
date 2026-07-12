/// Domain-neutral typed errors used across Commandly modules.
public enum CommandlyError: Error, Sendable, Equatable {
    /// A requested resource could not be found.
    case notFound(String)
    /// Input failed validation.
    case invalidInput(String)
    /// An operation is not supported in the current state.
    case unsupported(String)
    /// Persistence failed for a described reason.
    case persistence(String)
    /// A security or permission boundary blocked the operation.
    case security(String)
    /// An unexpected internal failure.
    case internalFailure(String)
}
