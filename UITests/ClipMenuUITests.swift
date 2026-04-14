import XCTest

final class ClipMenuUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSelectingClipFromPopupAutoPastesIntoFocusedField() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CLIPMENU_UI_TEST_MODE"] = "1"
        app.launch()

        let field = app.textFields["pasteTargetField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()

        let button = app.buttons["openPopupButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 2))
        button.click()

        let seedLabel = app.staticTexts["menuSeedStatusLabel"]
        XCTAssertTrue(seedLabel.waitForExistence(timeout: 2))
        XCTAssertEqual(elementText(seedLabel), "Seeded menu clip: ClipMenu UI test paste")

        let popupItem = app.menuItems["ClipMenu UI test paste"]
        XCTAssertTrue(popupItem.waitForExistence(timeout: 5))
        popupItem.click()

        let callbackLabel = app.staticTexts["simulatedPasteCountLabel"]
        XCTAssertTrue(callbackLabel.waitForExistence(timeout: 2))
        let callbackExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { evaluated, _ in
                guard let element = evaluated as? XCUIElement else { return false }
                return self.elementText(element) == "Paste callback count: 1"
            },
            object: callbackLabel
        )
        XCTAssertEqual(XCTWaiter.wait(for: [callbackExpectation], timeout: 5), .completed)

        let resultLabel = app.staticTexts["pasteResultLabel"]
        XCTAssertTrue(resultLabel.waitForExistence(timeout: 2))
        let resultExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { evaluated, _ in
                guard let element = evaluated as? XCUIElement else { return false }
                return self.elementText(element) == "Rendered result: ClipMenu UI test paste"
            },
            object: resultLabel
        )
        XCTAssertEqual(XCTWaiter.wait(for: [resultExpectation], timeout: 5), .completed)
    }

    private func elementText(_ element: XCUIElement) -> String {
        if !element.label.isEmpty {
            return element.label
        }

        if let value = element.value as? String {
            return value
        }

        return ""
    }
}
