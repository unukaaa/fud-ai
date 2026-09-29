import XCTest

final class FoodStoreRejectedMutationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--foodstore-rejection-ui-test",
            "-AppleLanguages", "(en)",
            "-hasCompletedOnboarding", "NO"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["foodStoreAcceptance.openEdit"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["foodStoreAcceptance.memoryFood"].label, "Accepted old diary")
        XCTAssertEqual(app.staticTexts["foodStoreAcceptance.persistedFood"].label, "Accepted old diary")
        return app
    }

    @MainActor
    private func assertFixtureUnchanged(_ app: XCUIApplication) {
        XCTAssertEqual(app.staticTexts["foodStoreAcceptance.memoryFood"].label, "Accepted old diary")
        XCTAssertEqual(app.staticTexts["foodStoreAcceptance.persistedFood"].label, "Accepted old diary")
        XCTAssertEqual(app.staticTexts["foodStoreAcceptance.waterCount"].label, "1")
        XCTAssertEqual(app.staticTexts["foodStoreAcceptance.persistedWaterCount"].label, "1")
        XCTAssertEqual(app.staticTexts["foodStoreAcceptance.changeCallbacks"].label, "0")
        XCTAssertEqual(app.staticTexts["foodStoreAcceptance.successCallbacks"].label, "0")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testRejectedEditStaysOpenAndShowsErrorWithoutChangingDiary() {
        let app = launchFixture()
        app.buttons["foodStoreAcceptance.openEdit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Food"].waitForExistence(timeout: 10))

        let name = app.textFields["Food name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" changed")
        XCTAssertNotEqual(name.value as? String, "Accepted old diary")
        app.buttons["Save"].tap()

        let error = app.alerts["Couldn’t Save Food"]
        XCTAssertTrue(error.waitForExistence(timeout: 5), "Rejected edit did not show a save error")
        XCTAssertTrue(error.staticTexts["Your changes weren’t saved. Please try again."].exists)
        attach(app, name: "Rejected Edit Food save alert")
        error.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Edit Food"].exists, "Rejected edit falsely dismissed Edit Food")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["foodStoreAcceptance.openEdit"].waitForExistence(timeout: 5))
        assertFixtureUnchanged(app)
    }

    @MainActor
    func testRejectedImportKeepsPreviewAndDoesNotApplyWaterOrSuccessCallbacks() {
        let app = launchFixture()
        app.buttons["foodStoreAcceptance.openImport"].tap()
        XCTAssertTrue(app.navigationBars["Import Food Diary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add as New Entries"].waitForExistence(timeout: 5))
        app.buttons["Add as New Entries"].tap()

        let error = app.alerts["Unable to Import"]
        XCTAssertTrue(error.waitForExistence(timeout: 5), "Rejected import did not show an error")
        XCTAssertTrue(error.staticTexts["The food diary couldn’t be saved. Your existing entries are unchanged."].exists)
        XCTAssertFalse(app.alerts["Import Complete"].exists)
        attach(app, name: "Rejected Import Diary error alert")
        error.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Import Food Diary"].exists)
        XCTAssertTrue(app.buttons["Add as New Entries"].exists, "Rejected import lost the preview")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["foodStoreAcceptance.openImport"].waitForExistence(timeout: 5))
        assertFixtureUnchanged(app)
    }
}
