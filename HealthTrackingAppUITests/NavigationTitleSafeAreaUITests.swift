import XCTest
import Vision

final class NavigationTitleSafeAreaUITests: XCTestCase {
    private enum Scenario: String {
        case seeded
        case errorOnce = "error-once"
    }

    private struct TabContract {
        let name: String
        let title: String

        var tabIdentifier: String { "tab.\(name)" }
        var rootIdentifier: String { "root.\(name)" }
        var contentIdentifier: String { "root.\(name).content" }
    }

    private struct CapturedTab {
        let contract: TabContract
        let screenshot: XCUIScreenshot
        let statusBarFrame: CGRect
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

    func testSeededTrainingNavigationTitleDoesNotOverlapStatusBar() {
        let app = launchApp(scenario: .seeded)

        guard let capture = replaySeededMatrix(
            through: "training",
            targetScreenshotNamed: "navigation-safe-area-training-seeded",
            in: app
        ) else {
            return
        }
        assertRenderedNavigationTitle(
            capture.contract.title,
            in: capture.screenshot,
            staysBelow: capture.statusBarFrame
        )
    }

    func testSeededProgressNavigationTitleDoesNotOverlapStatusBar() {
        let app = launchApp(scenario: .seeded)

        guard let capture = replaySeededMatrix(
            through: "progress",
            targetScreenshotNamed: "navigation-safe-area-progress-seeded",
            in: app
        ) else {
            return
        }
        assertRenderedNavigationTitle(
            capture.contract.title,
            in: capture.screenshot,
            staysBelow: capture.statusBarFrame
        )
    }

    private func replaySeededMatrix(
        through targetName: String,
        targetScreenshotNamed targetScreenshotName: String,
        in app: XCUIApplication
    ) -> CapturedTab? {
        guard tabs.contains(where: { $0.name == targetName }) else {
            XCTFail("The navigation-title test contract must contain \(targetName).")
            return nil
        }

        for tab in tabs {
            let tabElement = requireElement(
                app.descendants(matching: .any)[tab.tabIdentifier],
                "Expected visible tab \(tab.tabIdentifier) for deterministic seeded scenario."
            )
            XCTAssertTrue(tabElement.isHittable, "Tab \(tab.tabIdentifier) must be visible and hittable.")
        }

        var capturedTarget: CapturedTab?
        for tab in tabs {
            select(tab: tab, in: app)
            requireElement(
                app.descendants(matching: .any)[tab.contentIdentifier],
                "The loaded \(tab.rootIdentifier) must expose \(tab.contentIdentifier) before title inspection."
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

            let screenshotName = tab.name == targetName
                ? targetScreenshotName
                : "navigation-safe-area-\(targetName)-replay-\(tab.name)-seeded"
            let screenshot = attachScreenshot(named: screenshotName)
            if tab.name == targetName {
                let statusBarFrame = assertLiveNavigationTitle(
                    tab.title,
                    staysBelowStatusBarIn: app
                )
                capturedTarget = CapturedTab(
                    contract: tab,
                    screenshot: screenshot,
                    statusBarFrame: statusBarFrame
                )
            }
        }

        guard let capturedTarget else {
            XCTFail("The seeded replay must capture its requested \(targetName) target.")
            return nil
        }
        return capturedTarget
    }

    func testErrorOnceTrainingNavigationTitleDoesNotOverlapStatusBar() {
        let app = launchApp(scenario: .errorOnce)

        guard let trainingTab = tabs.first(where: { $0.name == "training" }) else {
            XCTFail("The navigation-title test contract must contain Training.")
            return
        }
        select(tab: trainingTab, in: app)

        let retry = requireElement(
            app.buttons["foundation.state.error"],
            "The error-once scenario must expose one deterministic accessible retry button."
        )
        XCTAssertEqual(
            app.buttons.matching(identifier: "foundation.state.error").count,
            1,
            "The error state must expose exactly one accessible retry button."
        )
        XCTAssertEqual(retry.label, "Yeniden dene", "The retry button must use its exact localized label.")
        XCTAssertTrue(retry.isHittable, "The foundation retry button must be hittable.")

        let screenshot = attachScreenshot(named: "navigation-safe-area-training-error")
        let statusBarFrame = assertLiveNavigationTitle(
            trainingTab.title,
            staysBelowStatusBarIn: app
        )
        retry.tap()

        requireElement(
            app.descendants(matching: .any)["foundation.state.loading"],
            "Retry must expose an observable loading state before seeded content appears.",
            timeout: 2
        )
        assertSeededTrainingContent(in: app)

        assertRenderedNavigationTitle(
            trainingTab.title,
            in: screenshot,
            staysBelow: statusBarFrame
        )
    }

    @discardableResult
    private func launchApp(scenario: Scenario) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", scenario.rawValue,
            "-ui-test-appearance", "light",
        ]
        app.launch()
        return app
    }

    private func select(tab: TabContract, in app: XCUIApplication) {
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

    private func assertLiveNavigationTitle(
        _ title: String,
        staysBelowStatusBarIn app: XCUIApplication
    ) -> CGRect {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let statusBar = requireElement(
            springboard.statusBars.firstMatch,
            "SpringBoard must expose the system status bar to establish the safe-region boundary."
        )
        let navigationBar = requireElement(
            app.navigationBars[title],
            "Expected a navigation bar titled “\(title)”."
        )
        let titleElement = requireElement(
            navigationBar.staticTexts[title].firstMatch,
            "The navigation title “\(title)” must be exposed as visible text."
        )

        let titleFrame = titleElement.frame
        let statusBarFrame = statusBar.frame
        let frameDiagnostics = "titleFrame=\(titleFrame), statusBarFrame=\(statusBarFrame)"

        XCTAssertFalse(
            statusBarFrame.isEmpty,
            "The status bar must expose a rendered safe-region frame; \(frameDiagnostics)."
        )
        XCTAssertTrue(
            titleElement.isHittable,
            "The navigation title “\(title)” must be visible onscreen; \(frameDiagnostics)."
        )
        XCTAssertFalse(
            titleFrame.isEmpty,
            "The navigation title “\(title)” must have a rendered frame; \(frameDiagnostics)."
        )

        let coordinateRoundingTolerance: CGFloat = 1
        XCTAssertGreaterThanOrEqual(
            titleFrame.minY,
            statusBarFrame.maxY - coordinateRoundingTolerance,
            "The navigation title “\(title)” must stay below the status-bar safe region; \(frameDiagnostics)."
        )
        return statusBarFrame
    }

    private func assertRenderedNavigationTitle(
        _ title: String,
        in screenshot: XCUIScreenshot,
        staysBelow statusBarFrame: CGRect
    ) {
        guard let cgImage = screenshot.image.cgImage else {
            XCTFail("The captured screen must expose pixels for Vision OCR.")
            return
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.customWords = [title]
        if let supportedLanguages = try? request.supportedRecognitionLanguages(),
           let turkishLanguage = supportedLanguages.first(where: {
               $0.lowercased().hasPrefix("tr")
           }) {
            request.recognitionLanguages = [turkishLanguage]
        }

        do {
            try VNImageRequestHandler(
                cgImage: cgImage,
                orientation: .up,
                options: [:]
            ).perform([request])
        } catch {
            XCTFail("Vision OCR must process the captured navigation-title screenshot: \(error)")
            return
        }

        let imageSize = screenshot.image.size
        let normalizedTitle = normalizedOCRText(title)
        let recognized = (request.results ?? []).compactMap { observation -> (String, CGRect)? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            let bounds = observation.boundingBox
            let screenFrame = CGRect(
                x: bounds.minX * imageSize.width,
                y: (1 - bounds.maxY) * imageSize.height,
                width: bounds.width * imageSize.width,
                height: bounds.height * imageSize.height
            )
            guard screenFrame.midY < imageSize.height / 2 else {
                return nil
            }
            return (candidate.string, screenFrame)
        }

        guard let renderedTitle = recognized.first(where: {
            normalizedOCRText($0.0) == normalizedTitle
        }) else {
            let recognizedTopHalf = recognized.map(\.0).joined(separator: " | ")
            XCTFail(
                "Vision OCR must find the exact navigation title “\(title)” in the top half; "
                    + "recognizedTopHalf=\(recognizedTopHalf)."
            )
            return
        }

        let renderedTitleFrame = renderedTitle.1
        XCTAssertGreaterThanOrEqual(
            renderedTitleFrame.minY,
            statusBarFrame.maxY,
            "The rendered navigation title “\(title)” must stay below the status bar; "
                + "ocrTitleFrame=\(renderedTitleFrame), statusBarFrame=\(statusBarFrame)."
        )
    }

    private func normalizedOCRText(_ text: String) -> String {
        text
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .replacingOccurrences(of: "ı", with: "i")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    @discardableResult
    private func attachScreenshot(named name: String) -> XCUIScreenshot {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return screenshot
    }
}
