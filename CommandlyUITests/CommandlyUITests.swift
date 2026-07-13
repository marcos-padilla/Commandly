import XCTest

final class CommandlyUITests: XCTestCase {
    @MainActor
    func testFileSearchFindsIndexedCSVAndShowsActions() throws {
        let app = launchFileSearch(query: "wpb_hoa")

        let result = app.buttons["file-search-result-wpb_hoa_contacts.csv"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["wpb_hoa_contacts.csv"].exists)
        XCTAssertTrue(app.staticTexts["Palm Beach HOA"].waitForExistence(timeout: 5))

        result.rightClick()

        XCTAssertTrue(app.groups["launcher-action-panel"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["launcher-action-file.open-with"].exists)
        XCTAssertTrue(app.buttons["launcher-action-file.share"].exists)
        XCTAssertTrue(app.buttons["launcher-action-file.trash"].exists)
        let back = app.groups["launcher-action-panel"].buttons["Back"]
        XCTAssertTrue(back.exists)
        back.click()

        let query = app.textFields["file-search-query"]
        XCTAssertTrue(query.exists)
        query.click()
        query.typeKey("a", modifierFlags: .command)
        query.typeText("emergency contacts")

        let contentResult = app.buttons["file-search-result-Board Notes.txt"]
        XCTAssertTrue(contentResult.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["File contents"].waitForExistence(timeout: 3))

        query.click()
        query.typeKey("a", modifierFlags: .command)
        query.typeText("Preview Churn")
        XCTAssertTrue(
            app.buttons["file-search-result-Preview Churn 1.txt"].waitForExistence(timeout: 3)
        )
        for _ in 0 ..< 12 {
            query.typeKey(.downArrow, modifierFlags: [])
            query.typeKey(.upArrow, modifierFlags: [])
        }
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.windows["Commandly"].exists)
    }

    @MainActor
    private func launchFileSearch(query: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--commandly-show-launcher",
            "--commandly-skip-onboarding",
            "--commandly-file-search-fixture",
            "--commandly-file-search-query",
            query
        ]
        app.launch()
        app.activate()
        if app.windows["Commandly"].waitForExistence(timeout: 2) == false {
            app.typeKey(.space, modifierFlags: .option)
        }
        if app.windows["Commandly"].waitForExistence(timeout: 3) == false {
            let statusItem = app.statusItems["Command"]
            XCTAssertTrue(statusItem.waitForExistence(timeout: 3))
            statusItem.click()
            let openCommandly = app.menuItems["Open Commandly"]
            XCTAssertTrue(openCommandly.waitForExistence(timeout: 3))
            openCommandly.click()
        }
        XCTAssertTrue(app.windows["Commandly"].waitForExistence(timeout: 5))
        return app
    }
}
