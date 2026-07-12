import XCTest

final class CommandlyUITests: XCTestCase {
    @MainActor
    func testPlaceholderScreenShowsFoundationReady() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Commandly"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Foundation ready"].exists)
        XCTAssertTrue(app.staticTexts["Feature development has not started yet."].exists)
    }
}
