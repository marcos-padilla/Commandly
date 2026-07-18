import XCTest

final class CommandWheelUITests: XCTestCase {
    private enum Identifier {
        static let wheel = "command-wheel"
        static let center = "command-wheel.center"
        static let rootCommand =
            "command-wheel.segment.58435549-434D-4457-8000-000000000021.0"
        static let rootSubmenu =
            "command-wheel.segment.58435549-434D-4457-8000-000000000022.1"
        static let rootFinder =
            "command-wheel.segment.58435549-434D-4457-8000-000000000025.4"
        static let settingsProfile = "58435549-434D-4457-8000-000000000071"
        static let settingsPage = "58435549-434D-4457-8000-000000000072"

        static func settingsSlot(_ index: Int) -> String {
            "command-wheel.slot.\(settingsProfile).\(settingsPage).\(index)"
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWheelOpensAndCancelsFromCenter() {
        let app = launchWheel()
        let wheel = element(Identifier.wheel, in: app)

        XCTAssertTrue(wheel.label.contains("Command Wheel, XCUI Wheel, Main"))
        let command = element(Identifier.rootCommand, in: app)
        let submenu = element(Identifier.rootSubmenu, in: app)
        let finder = element(Identifier.rootFinder, in: app)
        XCTAssertTrue(waitForLabel(of: command, containing: "Find Files"))
        XCTAssertTrue(waitForLabel(of: submenu, containing: "Utilities"))
        XCTAssertTrue(waitForLabel(of: finder, containing: "Finder"))
        XCTAssertFalse(app.staticTexts["Find Files"].exists)
        XCTAssertFalse(app.staticTexts["Utilities"].exists)
        XCTAssertFalse(app.staticTexts["Finder"].exists)

        let center = element(Identifier.center, in: app)
        XCTAssertTrue(center.waitForExistence(timeout: 2))
        XCTAssertEqual(center.label, "Center, Cancel")

        center.click()
        XCTAssertTrue(wheel.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testWheelKeyboardSelectionSubmenuAndReturnToParent() {
        let app = launchWheel()
        let wheel = element(Identifier.wheel, in: app)
        let command = element(Identifier.rootCommand, in: app)
        let submenu = element(Identifier.rootSubmenu, in: app)

        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(waitForSelection(of: command))

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitForSelection(of: submenu))

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForLabel(of: wheel, containing: "Utilities"))
        XCTAssertEqual(element(Identifier.center, in: app).label, "Center, Back")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForLabel(of: wheel, containing: "Main"))
        XCTAssertEqual(element(Identifier.center, in: app).label, "Center, Cancel")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(wheel.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testWheelClickSelectionDismissesAfterSelectingCommand() {
        let app = launchWheel()
        let wheel = element(Identifier.wheel, in: app)
        let command = element(Identifier.rootCommand, in: app)

        XCTAssertTrue(command.waitForExistence(timeout: 2))
        command.click()

        XCTAssertTrue(wheel.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testWheelLightAppearance() {
        assertWheelEnvironment(
            launchArgument: "--commandly-command-wheel-light",
            expectedValue: "light appearance"
        )
    }

    @MainActor
    func testWheelDarkAppearance() {
        assertWheelEnvironment(
            launchArgument: "--commandly-command-wheel-dark",
            expectedValue: "dark appearance"
        )
    }

    @MainActor
    func testWheelReducedMotion() {
        assertWheelEnvironment(
            launchArgument: "--commandly-command-wheel-reduce-motion",
            expectedValue: "reduced motion"
        )
    }

    @MainActor
    func testWheelIncreasedContrast() {
        assertWheelEnvironment(
            launchArgument: "--commandly-command-wheel-increased-contrast",
            expectedValue: "increased contrast"
        )
    }

    @MainActor
    func testSettingsEditsAssignsAndReordersSlots() {
        let app = launchCommandWheelSettings()
        let nameField = element("command-wheel.profile.name", in: app)

        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("XCUI Edited Wheel")
        nameField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["XCUI Edited Wheel"].waitForExistence(timeout: 3))

        let emptySlot = element(Identifier.settingsSlot(1), in: app)
        scrollToElement(emptySlot, in: app)
        emptySlot.click()

        let slotTwoActions = app.menuButtons["Actions for slot 2"]
        XCTAssertTrue(slotTwoActions.waitForExistence(timeout: 3))
        slotTwoActions.click()
        let chooseCommand = app.menuItems["Choose Command…"]
        XCTAssertTrue(chooseCommand.waitForExistence(timeout: 2))
        chooseCommand.click()

        let calculationHistory = element(
            "command-wheel.command.command:calculator.history",
            in: app
        )
        XCTAssertTrue(calculationHistory.waitForExistence(timeout: 3))
        calculationHistory.click()
        XCTAssertTrue(waitForSemanticText(of: emptySlot, containing: "Calculation History"))

        let firstSlot = element(Identifier.settingsSlot(0), in: app)
        let slotOneActions = selectSettingsSlot(
            firstSlot,
            actionsLabel: "Actions for slot 1",
            in: app
        )
        slotOneActions.click()
        let moveLater = app.menuItems["Move Later"]
        XCTAssertTrue(moveLater.waitForExistence(timeout: 2))
        moveLater.click()

        XCTAssertTrue(waitForSemanticText(of: firstSlot, containing: "Calculation History"))
        XCTAssertTrue(waitForSemanticText(of: emptySlot, containing: "Search Files"))
    }

    @MainActor
    func testSettingsShowsMissingCommandAndPermissionExplanation() {
        let app = launchCommandWheelSettings()
        let permissionDetail = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "The wheel shortcut itself uses Carbon")
        ).firstMatch

        XCTAssertTrue(permissionDetail.waitForExistence(timeout: 5))
        XCTAssertTrue(element("command-wheel.permissions.open", in: app).exists)

        let missingSlot = element(Identifier.settingsSlot(2), in: app)
        scrollToElement(missingSlot, in: app)
        missingSlot.click()

        XCTAssertTrue(waitForSemanticText(of: missingSlot, containing: "Missing command"))
        let missingExplanation = app.staticTexts.matching(
            NSPredicate(
                format: "value BEGINSWITH %@",
                "The saved command or provider is not installed"
            )
        ).firstMatch
        XCTAssertTrue(missingExplanation.waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchWheel(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--commandly-skip-onboarding",
            "--commandly-command-wheel-fixture",
        ] + additionalArguments
        app.launch()
        app.activate()
        addSynchronousTerminationTeardown(for: app)
        XCTAssertTrue(element(Identifier.wheel, in: app).waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func launchCommandWheelSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--commandly-skip-onboarding",
            "--commandly-command-wheel-settings-fixture",
        ]
        app.launch()
        app.activate()
        addSynchronousTerminationTeardown(for: app)
        XCTAssertTrue(app.staticTexts["Command Wheel"].waitForExistence(timeout: 8))
        return app
    }

    @MainActor
    private func addSynchronousTerminationTeardown(for app: XCUIApplication) {
        addTeardownBlock {
            app.terminate()
            XCTAssertTrue(
                app.wait(for: .notRunning, timeout: 5),
                "Commandly did not terminate before the next UI fixture launched."
            )
        }
    }

    @MainActor
    private func selectSettingsSlot(
        _ slot: XCUIElement,
        actionsLabel: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        let actions = app.menuButtons[actionsLabel]
        for _ in 0 ..< 2 where actions.exists == false {
            XCTAssertTrue(slot.isHittable)
            slot.click()
            if actions.waitForExistence(timeout: 2) {
                break
            }
        }
        XCTAssertTrue(
            actions.exists,
            "The Command Wheel slot inspector did not select \(actionsLabel)."
        )
        return actions
    }

    @MainActor
    private func assertWheelEnvironment(
        launchArgument: String,
        expectedValue: String
    ) {
        let app = launchWheel(additionalArguments: [launchArgument])
        XCTAssertTrue(
            waitForLabel(of: element(Identifier.wheel, in: app), containing: expectedValue)
        )
    }

    @MainActor
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) {
        let detailScrollView = app.scrollViews.allElementsBoundByIndex.max {
            $0.frame.width < $1.frame.width
        }
        guard let detailScrollView else {
            XCTFail("The Settings detail scroll view was not available.")
            return
        }
        let scrollCoordinate = detailScrollView.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        for _ in 0 ..< 6 where element.isHittable == false {
            scrollCoordinate.scroll(byDeltaX: 0, deltaY: -420)
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForLabel(
        of element: XCUIElement,
        containing expectedLabel: String,
        timeout: TimeInterval = 3
    ) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", expectedLabel)
        return XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }

    private func waitForSemanticText(
        of element: XCUIElement,
        containing expectedText: String,
        timeout: TimeInterval = 3
    ) -> Bool {
        let predicate = NSPredicate(
            format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
            expectedText,
            expectedText
        )
        return XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }

    private func waitForSelection(
        of element: XCUIElement,
        timeout: TimeInterval = 3
    ) -> Bool {
        let predicate = NSPredicate(format: "selected == YES")
        return XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }
}
