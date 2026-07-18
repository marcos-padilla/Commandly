import CommandKit

/// Late-bound bridge from the wheel coordinator to Commandly's existing launcher status surface.
///
/// The coordinator can be assembled before `AppRuntime` finishes initialization, while the
/// installed handler remains owned by the runtime. Messages are already sanitized by the shared
/// command pipeline; the relay never inspects command arguments or underlying infrastructure errors.
@MainActor
final class CommandWheelResultFeedbackRelay: CommandWheelResultFeedbackHandling {
    typealias CompletionHandler = (CommandResult, CommandInvocationContext) -> Void
    typealias FailureHandler = (any Error, CommandInvocationContext) -> Void

    private var completionHandler: CompletionHandler?
    private var failureHandler: FailureHandler?

    func install(
        onCompletion: @escaping CompletionHandler,
        onFailure: @escaping FailureHandler
    ) {
        completionHandler = onCompletion
        failureHandler = onFailure
    }

    func commandWheelDidComplete(
        result: CommandResult,
        context: CommandInvocationContext
    ) {
        completionHandler?(result, context)
    }

    func commandWheelDidFail(
        error: any Error,
        context: CommandInvocationContext
    ) {
        failureHandler?(error, context)
    }

    func tearDown() {
        completionHandler = nil
        failureHandler = nil
    }
}
