import XCTest

final class AppShellUITests: XCTestCase {
    private enum Scenario: String {
        case seeded
        case emptyOnce = "empty-once"
        case errorOnce = "error-once"
        case loading
        case fatalConfiguration = "fatal-configuration"
    }

    private enum Appearance: String {
        case light
        case dark
    }

    private struct TabContract {
        let name: String
        let title: String

        var tabIdentifier: String { "tab.\(name)" }
        var rootIdentifier: String { "root.\(name)" }
        var contentIdentifier: String { "root.\(name).content" }
    }

    private let tabs = [
        TabContract(name: "today", title: "Bugün"),
        TabContract(name: "training", title: "Antrenman"),
        TabContract(name: "nutrition", title: "Beslenme"),
        TabContract(name: "progress", title: "İlerleme"),
        TabContract(name: "settings", title: "Ayarlar"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFiveTabsExposeDistinctLoadedRootsInLightAppearance() {
        assertLoadedRootMatrix(appearance: .light)
    }

    func testFiveTabsExposeDistinctLoadedRootsInDarkAppearance() {
        assertLoadedRootMatrix(appearance: .dark)
    }

    func testSeededTrainingContentIsOrderedAndDeterministicAcrossFreshProcesses() {
        let firstApp = launchApp(scenario: .seeded, appearance: .light)
        select(tabNamed: "training", in: firstApp)
        assertSeededTrainingContent(in: firstApp)
        firstApp.terminate()

        let secondApp = launchApp(scenario: .seeded, appearance: .light)
        select(tabNamed: "training", in: secondApp)
        assertSeededTrainingContent(in: secondApp)
    }

    func testEmptyOnceReloadShowsLoadingBeforeSeededContent() {
        let app = launchApp(scenario: .emptyOnce, appearance: .light)
        select(tabNamed: "training", in: app)

        let reload = requireElement(
            app.buttons["foundation.state.empty"],
            "The empty-once scenario must expose one deterministic accessible reload button."
        )
        XCTAssertEqual(
            app.buttons.matching(identifier: "foundation.state.empty").count,
            1,
            "The empty state must expose exactly one accessible reload button."
        )
        XCTAssertEqual(reload.label, "Programı yeniden yükle", "The reload button must use its exact localized label.")
        XCTAssertTrue(reload.isHittable, "The foundation reload button must be hittable.")
        attachScreenshot(named: "shell-empty")
        reload.tap()

        requireElement(
            app.descendants(matching: .any)["foundation.state.loading"],
            "Reload must expose an observable loading state before seeded content appears.",
            timeout: 2
        )
        assertSeededTrainingContent(in: app)
    }

    func testErrorOnceRetryShowsLoadingBeforeSeededContent() {
        let app = launchApp(scenario: .errorOnce, appearance: .light)
        select(tabNamed: "training", in: app)

        let retry = requireElement(
            app.buttons["foundation.state.error"],
            "The error-once scenario must expose one deterministic accessible retry button."
        )
        XCTAssertEqual(
            app.buttons.matching(identifier: "foundation.state.error").count,
            1,
            "The error state must expose exactly one accessible retry button."
        )
        XCTAssertEqual(retry.label, "Yeniden dene", "The retry button must use DesignSystem’s exact localized label.")
        XCTAssertTrue(retry.isHittable, "The foundation retry button must be hittable.")
        attachScreenshot(named: "shell-error")
        retry.tap()

        requireElement(
            app.descendants(matching: .any)["foundation.state.loading"],
            "Retry must expose an observable loading state before seeded content appears.",
            timeout: 2
        )
        assertSeededTrainingContent(in: app)
    }

    func testStaticLoadingScenarioProvidesDeterministicEvidence() {
        let app = launchApp(scenario: .loading, appearance: .light)
        select(tabNamed: "training", in: app)
        requireElement(
            app.descendants(matching: .any)["foundation.state.loading"],
            "The loading scenario is the deterministic statically held foundation state."
        )
        attachScreenshot(named: "shell-loading")
    }

    func testStaticFatalConfigurationScenarioProvidesDeterministicEvidence() {
        let app = launchApp(scenario: .fatalConfiguration, appearance: .light)
        requireElement(
            app.descendants(matching: .any)["app.state.fatal-configuration"],
            "The fatal-configuration scenario must render the app-local fatal state outside the tab shell."
        )
        attachScreenshot(named: "shell-fatal")
    }

    func testSettingsGalleryPathRemainsPushedWithoutLeakingAcrossTabs() {
        let app = launchApp(scenario: .seeded, appearance: .light)
        select(tabNamed: "settings", in: app)

        let galleryLinks = app.buttons.matching(identifier: "settings.gallery-link")
        let galleryLink = requireElement(
            galleryLinks.firstMatch,
            "Settings must expose exactly one real DesignSystem gallery route."
        )
        XCTAssertEqual(galleryLinks.count, 1, "Settings must expose exactly one DesignSystem gallery route.")
        XCTAssertTrue(galleryLink.isHittable, "The DesignSystem gallery route must be hittable.")
        galleryLink.tap()

        let gallery = requireElement(
            app.descendants(matching: .any)["designSystem.gallery"],
            "The Settings route must push the existing public DesignSystem gallery."
        )
        attachScreenshot(named: "shell-settings-gallery")

        select(tabNamed: "today", in: app)
        XCTAssertFalse(
            gallery.exists,
            "The Settings gallery must not leak into the Today navigation stack."
        )

        select(tabNamed: "settings", in: app)
        requireElement(
            app.descendants(matching: .any)["designSystem.gallery"],
            "Returning to Settings must restore its independently owned pushed gallery path."
        )
        attachScreenshot(named: "shell-settings-path-isolation")
    }

    private func assertLoadedRootMatrix(appearance: Appearance) {
        let app = launchApp(scenario: .seeded, appearance: appearance)

        for tab in tabs {
            let tabElement = requireElement(
                app.descendants(matching: .any)[tab.tabIdentifier],
                "Expected visible tab \(tab.tabIdentifier) for deterministic seeded scenario."
            )
            XCTAssertTrue(tabElement.isHittable, "Tab \(tab.tabIdentifier) must be visible and hittable.")
        }

        for tab in tabs {
            select(tabNamed: tab.name, in: app)
            requireElement(
                app.descendants(matching: .any)[tab.contentIdentifier],
                "The loaded \(tab.rootIdentifier) must expose \(tab.contentIdentifier) before evidence capture."
            )

            for otherTab in tabs where otherTab.name != tab.name {
                XCTAssertFalse(
                    app.descendants(matching: .any)[otherTab.rootIdentifier].exists,
                    "Selecting \(tab.tabIdentifier) must not expose \(otherTab.rootIdentifier)."
                )
            }

            if tab.name == "training" {
                assertSeededTrainingContent(in: app)
            }

            attachScreenshot(named: "shell-\(tab.name)-\(appearance.rawValue)")
        }
    }

    @discardableResult
    private func launchApp(scenario: Scenario, appearance: Appearance) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", scenario.rawValue,
            "-ui-test-appearance", appearance.rawValue,
        ]
        app.launch()
        return app
    }

    private func select(tabNamed name: String, in app: XCUIApplication) {
        guard let tab = tabs.first(where: { $0.name == name }) else {
            XCTFail("Unknown tab contract: \(name)")
            return
        }

        let tabElement = requireElement(
            app.descendants(matching: .any)[tab.tabIdentifier],
            "Expected visible tab \(tab.tabIdentifier) for deterministic scenario."
        )
        XCTAssertTrue(tabElement.isHittable, "Tab \(tab.tabIdentifier) must be hittable.")
        tabElement.tap()

        requireElement(
            app.descendants(matching: .any)[tab.rootIdentifier],
            "Selecting \(tab.tabIdentifier) must expose its distinct \(tab.rootIdentifier)."
        )
        requireElement(
            app.navigationBars[tab.title],
            "The \(tab.rootIdentifier) navigation heading must show the Turkish title “\(tab.title)”."
        )
    }

    private func assertSeededTrainingContent(in app: XCUIApplication) {
        let expectedProgram = "Tam Vücut v3 (Postür → Recomp)"
        let programName = requireElement(
            app.descendants(matching: .any)["training.program.name"],
            "Seeded Training content must expose a stable program-name element."
        )
        XCTAssertEqual(programName.label, expectedProgram, "The exact deterministic seed program must be visible.")

        assertOrderedRows(
            in: app,
            identifierPrefix: "training.phase-row.",
            expectedLabels: ["Temel", "İnşa", "İlerleme", "Konsolidasyon"]
        )
        assertOrderedRows(
            in: app,
            identifierPrefix: "training.day-row.",
            expectedLabels: ["Gün A", "Gün B", "Gün C"]
        )
    }

    private func assertOrderedRows(
        in app: XCUIApplication,
        identifierPrefix: String,
        expectedLabels: [String]
    ) {
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)
        )
        let countExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", expectedLabels.count),
            object: rows
        )
        let result = XCTWaiter.wait(for: [countExpectation], timeout: 8)
        XCTAssertEqual(
            result,
            .completed,
            "Expected exactly \(expectedLabels.count) ordered rows with prefix \(identifierPrefix); found \(rows.count)."
        )

        let elements = rows.allElementsBoundByIndex
        XCTAssertEqual(
            elements.map(\.identifier),
            expectedLabels.indices.map { "\(identifierPrefix)\($0)" },
            "Stable indexed row identifiers must prove collection count and order."
        )
        XCTAssertEqual(
            elements.map(\.label),
            expectedLabels,
            "Ordered row accessibility labels must match the deterministic Turkish seed values."
        )
    }

    @discardableResult
    private func requireElement(
        _ element: XCUIElement,
        _ message: String,
        timeout: TimeInterval = 5
    ) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
        return element
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
