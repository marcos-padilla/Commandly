import Testing
@testable import Observability

struct ObservabilityTests {
    @Test func logCategoriesAreUnique() {
        let rawValues = LogCategory.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test func loggerFactoryProvidesCategoryLoggers() {
        let logger: AppLogger = Loggers.lifecycle
        logger.info("lifecycle smoke")
        #expect(LogCategory.lifecycle.rawValue == "lifecycle")
    }
}
