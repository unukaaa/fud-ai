import XCTest

final class SearchFoodAcceptanceUITests: XCTestCase {
    private var launchedApp: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let launchedApp {
            let attachment = XCTAttachment(screenshot: launchedApp.screenshot())
            attachment.name = "Search Food acceptance failure"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func openSearch(typing query: String) -> XCUIApplication {
        let app = XCUIApplication()
        launchedApp = app
        // Launch-argument defaults affect only this test process. Bypass onboarding
        // and previously introduced announcement sheets without fabricating food data.
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-hasCompletedOnboarding", "YES",
            "-hasSeenHostedUpsellPrompt", "YES",
            "-hasCompletedMeetDeveloperPrompt", "YES",
            "-hasSeenProductHuntLaunchPrompt.2026-09-27", "YES"
        ]
        app.launch()

        let add = app.buttons["home.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 15), "Home Add Meal button did not appear")
        add.tap()

        let searchEntry = app.buttons["addMeal.text"]
        XCTAssertTrue(searchEntry.waitForExistence(timeout: 5), "Search Food entry is missing")
        searchEntry.tap()

        let field = app.descendants(matching: .any)["searchFood.query"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Search Food field is missing")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Search Food did not focus its query field")
        app.typeText(query)
        return app
    }

    @MainActor
    private func assertReviewFood(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Review Food"].waitForExistence(timeout: 15),
                      "Selection did not reach Review Food")
    }

    @MainActor
    func testKFCBrandDiscoveryIsInformational() {
        let app = openSearch(typing: "KFC")
        let brand = app.descendants(matching: .any)["searchFood.brand.kfc_au"]
        XCTAssertTrue(brand.waitForExistence(timeout: 5), "KFC brand row is missing")
        XCTAssertFalse(app.buttons["searchFood.brand.kfc_au"].exists,
                       "A brand must not be tappable as a consumed food")
        XCTAssertTrue(app.buttons["searchFood.item:kfc-au-zinger-burger"].exists,
                      "Expected a verified KFC product suggestion")
        XCTAssertFalse(app.buttons["searchFood.analyse"].exists,
                       "Brand-only intent should lead to product choice, not Analyse")
    }

    @MainActor
    func testMaccasAliasShowsMcDonaldsBrand() {
        let app = openSearch(typing: "Maccas")
        XCTAssertTrue(app.descendants(matching: .any)["searchFood.brand.mcdonalds_au"]
            .waitForExistence(timeout: 5), "Maccas alias did not show McDonald's brand")
    }

    @MainActor
    func testBigMacSuggestionUsesVerifiedHandoff() {
        let app = openSearch(typing: "Big mac")
        let product = app.buttons["searchFood.item:mcd-au-big-mac"]
        XCTAssertTrue(product.waitForExistence(timeout: 5), "Big Mac suggestion is missing")
        product.tap()
        assertReviewFood(in: app)
        XCTAssertTrue(app.staticTexts["reviewFood.name"].label.contains("Big Mac"),
                      "Verified handoff did not retain Big Mac identity")
        XCTAssertEqual(app.staticTexts["reviewFood.source"].label, "Verified restaurant nutrition")
    }

    @MainActor
    func testSixNuggetsKeepsVariantAndQuantity() {
        let app = openSearch(typing: "6 nug")
        let product = app.buttons["searchFood.variant:mcd-au-mcnuggets-6"]
        XCTAssertTrue(product.waitForExistence(timeout: 5), "Six-piece variant suggestion is missing")
        product.tap()
        assertReviewFood(in: app)
        XCTAssertEqual(app.staticTexts["reviewFood.summary.calories"].label, "216 cals")
        let quantity = app.textFields["serving.quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5), "Serving quantity field is missing")
        XCTAssertEqual(quantity.value as? String, "6", "Six pieces must not become six packs")
    }

    @MainActor
    func testWondermelonSelectionSurvivesQuickCheck() {
        let app = openSearch(typing: "Wondermelon")
        let product = app.buttons["searchFood.item:boost-au-wondermelon"]
        XCTAssertTrue(product.waitForExistence(timeout: 5), "Wondermelon parent suggestion is missing")
        product.staticTexts["Wondermelon"].tap()
        XCTAssertTrue(app.navigationBars["Quick check"].waitForExistence(timeout: 15),
                      "Wondermelon did not ask for size")
        let medium = app.buttons["quickCheck.option.size.0"]
        XCTAssertTrue(medium.waitForExistence(timeout: 5), "Medium size choice is missing")
        medium.tap()
        app.buttons["quickCheck.continue"].tap()
        assertReviewFood(in: app)
        XCTAssertEqual(app.staticTexts["reviewFood.summary.calories"].label, "156 cals")
        XCTAssertTrue(app.staticTexts["reviewFood.name"].label.contains("Medium"),
                      "Selected Medium size did not survive clarification")
    }

    @MainActor
    func testUnsupportedOrdinaryFoodKeepsAnalyseFallback() {
        let app = openSearch(typing: "chicken avocado sandwich")
        XCTAssertTrue(app.buttons["searchFood.analyse"].waitForExistence(timeout: 5),
                      "Ordinary-food Analyse fallback is missing")
        let verifiedProduct = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "searchFood.item:")
        ).firstMatch
        XCTAssertFalse(verifiedProduct.exists, "Unsupported ordinary food must not appear verified")
    }
}
