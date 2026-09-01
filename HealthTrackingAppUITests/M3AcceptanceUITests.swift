import Foundation
import XCTest

final class M3AcceptanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testReportDashboardFetchLifecycleAcrossRootSheetDismissals() {
        let app = launch(storeIdentifier: UUID())
        defer { app.terminate() }
        let progressMetricsAction = ["progress", "metrics", "action"]
            .joined(separator: ".")

        require(identified("root.today.content", in: app))
        assertReportFetchCountRemains(0, in: app)

        openAndCloseSheet(
            action: "today.metrics.action",
            content: "metrics.entry.weight",
            close: "metrics.entry.close",
            in: app
        )
        assertReportFetchCountRemains(0, in: app)

        openProgress(in: app)
        assertReportFetchCountEventually(1, in: app)

        openAndCloseSheet(
            action: progressMetricsAction,
            content: "metrics.entry.weight",
            close: "metrics.entry.close",
            in: app
        )
        assertReportFetchCountEventually(2, in: app)

        openAndSwipeDismissSheet(
            action: progressMetricsAction,
            content: "metrics.entry.weight",
            in: app
        )
        assertReportFetchCountEventually(3, in: app)

        require(identified("tab.today", in: app)).tap()
        require(identified("root.today.content", in: app))
        openProgress(in: app)
        assertReportFetchCountEventually(4, in: app)
        assertReportFetchCountRemains(4, in: app)
    }

    func testTodayAndProgressExposeEveryM3TrackerEntryThroughOneLazyRouter() {
        let probe = launch(storeIdentifier: UUID())
        openProgress(in: probe)
        require(
            identified("progress.metrics.action", in: probe),
            "The shipped Progress hub must expose the body-metric quick action."
        )
        assertExactlyOneProgressEntryActionPerTracker(in: probe)
        probe.terminate()

        let app = launch(storeIdentifier: UUID())
        require(identified("root.today.content", in: app))
        assertRouterInstantiationCount(0, in: app)

        openAndCloseSheet(
            action: "today.metrics.action",
            content: "metrics.entry.weight",
            close: "metrics.entry.close",
            in: app
        )
        assertRouterInstantiationCount(1, in: app)
        openAndCloseSheet(
            action: "today.lifestyle.action",
            content: "lifestyle.entry.loaded",
            close: "lifestyle.entry.close",
            in: app
        )
        openAndCloseSheet(
            action: "today.posture.action",
            content: "posture.entry.loaded",
            close: "posture.entry.close",
            in: app
        )
        openAndCloseSheet(
            action: "today.health-check.action",
            content: "health-check.list.loaded",
            close: "health-check.close",
            in: app
        )
        openAndCloseSheet(
            action: "today.bloodwork.action",
            content: "bloodwork.list.content",
            close: "bloodwork.close",
            in: app
        )

        openProgress(in: app)
        let routes: [(action: String, content: String, close: String)] = [
            ("progress.metrics.action", "metrics.entry.weight", "metrics.entry.close"),
            ("progress.lifestyle.action", "lifestyle.entry.loaded", "lifestyle.entry.close"),
            ("progress.posture.action", "posture.entry.loaded", "posture.entry.close"),
            ("progress.health-check.action", "health-check.list.loaded", "health-check.close"),
            ("progress.bloodwork.action", "bloodwork.list.content", "bloodwork.close"),
            ("progress.photos.action", "photos.lifecycle.content", "photos.close"),
        ]
        for route in routes {
            openAndCloseSheet(
                action: route.action,
                content: route.content,
                close: route.close,
                in: app
            )
            assertRouterInstantiationCount(1, in: app)
        }
    }

    func testUS6AndUS8SummariesSurviveProgressSameDayEditAndRelaunch() {
        let storeIdentifier = UUID()
        let app = launch(storeIdentifier: storeIdentifier)
        assertFixedNowEvidence("2026-08-27T10:00:00Z", in: app)
        openProgress(in: app)
        openLifestyleFromProgress(in: app)

        replaceText(in: textField("lifestyle.sleep.duration", in: app), with: "7", app: app)
        replaceText(in: textField("lifestyle.sleep.quality", in: app), with: "8", app: app)
        replaceText(in: textField("lifestyle.mood.score", in: app), with: "6", app: app)
        require(identified("lifestyle.entry.save", in: app)).tap()
        require(identified("lifestyle.entry.saved", in: app))
        require(identified("lifestyle.entry.close", in: app)).tap()

        assertLifestyleSummary(
            sectionCount: "2",
            duration: "7",
            quality: "8",
            moodScore: "6",
            in: app
        )
        openLifestyleFromProgress(in: app)
        XCTAssertEqual(textField("lifestyle.sleep.duration", in: app).value as? String, "7")
        replaceText(in: textField("lifestyle.sleep.quality", in: app), with: "9", app: app)
        replaceText(in: textField("lifestyle.mood.score", in: app), with: "7", app: app)
        require(identified("lifestyle.entry.save", in: app)).tap()
        require(identified("lifestyle.entry.saved", in: app))
        require(identified("lifestyle.entry.close", in: app)).tap()

        assertLifestyleSummary(
            sectionCount: "2",
            duration: "7",
            quality: "9",
            moodScore: "7",
            in: app
        )
        attachScreenshot(named: "m3-acceptance-us6-progress-light")
        require(identified("tab.today", in: app)).tap()
        let bloodwork = require(identified("today.bloodwork.action", in: app))
        makeHittable(bloodwork, in: app)
        attachScreenshot(named: "m3-acceptance-us8-today-light")
        app.terminate()

        let relaunched = launch(storeIdentifier: storeIdentifier)
        openProgress(in: relaunched)
        assertLifestyleSummary(
            sectionCount: "2",
            duration: "7",
            quality: "9",
            moodScore: "7",
            in: relaunched
        )
        require(identified("tab.today", in: relaunched)).tap()
        require(identified("today.bloodwork.action", in: relaunched))
    }

    private func launch(storeIdentifier: UUID) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m3-health-checks",
            "-ui-test-appearance", "light",
            "-ui-test-store-identifier", storeIdentifier.uuidString,
            "-ui-test-now", "2026-08-27T10:00:00Z",
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()
        return app
    }

    private func openProgress(in app: XCUIApplication) {
        require(identified("tab.progress", in: app)).tap()
        require(identified("root.progress", in: app))
        require(identified("metrics.history.loaded", in: app))
    }

    private func openLifestyleFromProgress(in app: XCUIApplication) {
        let action = require(identified("progress.lifestyle.action", in: app))
        makeHittable(action, in: app)
        action.tap()
        require(identified("lifestyle.entry.loaded", in: app))
    }

    private func openAndCloseSheet(
        action: String,
        content: String,
        close: String,
        in app: XCUIApplication
    ) {
        let actionElement = require(identified(action, in: app), "Missing route action: \(action)")
        makeHittable(actionElement, in: app)
        actionElement.tap()
        let contentElement = require(
            identified(content, in: app),
            "Missing routed content: \(content)"
        )
        let closeElement = require(app.buttons[close], "Missing close action: \(close)")
        makeHittable(closeElement, in: app)
        closeElement.tap()
        waitForDisappearance(
            of: contentElement,
            message: "The explicit close action must dismiss \(content)."
        )
    }

    private func openAndSwipeDismissSheet(
        action: String,
        content: String,
        in app: XCUIApplication
    ) {
        let actionElement = require(identified(action, in: app), "Missing route action: \(action)")
        makeHittable(actionElement, in: app)
        actionElement.tap()
        let contentElement = require(
            identified(content, in: app),
            "Missing routed content: \(content)"
        )
        let sheet = app.sheets.firstMatch
        if sheet.waitForExistence(timeout: 2) {
            dragDownToDismiss(sheet)
        } else {
            dragDownToDismiss(app)
        }
        waitForDisappearance(
            of: contentElement,
            message: "The interactive swipe must dismiss \(content)."
        )
    }

    private func dragDownToDismiss(_ surface: XCUIElement) {
        let start = surface.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)
        )
        let end = surface.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)
        )
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func assertReportFetchCountEventually(
        _ expected: Int,
        in app: XCUIApplication
    ) {
        let evidence = reportFetchEvidence(in: app)
        let value = String(expected)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: evidence
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 8),
            .completed,
            "Expected report fetch count \(value); found \(String(describing: evidence.value))."
        )
        XCTAssertEqual(evidence.value as? String, value)
    }

    private func assertReportFetchCountRemains(
        _ expected: Int,
        in app: XCUIApplication
    ) {
        let evidence = reportFetchEvidence(in: app)
        let value = String(expected)
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", value),
            object: evidence
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [changed], timeout: 1),
            .timedOut,
            "Report fetch count must remain \(value); found \(String(describing: evidence.value))."
        )
        XCTAssertEqual(evidence.value as? String, value)
    }

    private func reportFetchEvidence(in app: XCUIApplication) -> XCUIElement {
        require(
            identified("m4.reports.dashboard-fetch-count", in: app),
            "M4.8 acceptance must expose DEBUG-only dashboard-fetch evidence."
        )
    }

    private func assertRouterInstantiationCount(_ expected: String, in app: XCUIApplication) {
        let evidence = require(
            identified("m3.tracker-router.instantiation-count", in: app),
            "M3 acceptance must expose DEBUG-only lazy-router evidence."
        )
        XCTAssertEqual(evidence.value as? String, expected)
    }

    private func assertRouterInstantiationCount(_ expected: Int, in app: XCUIApplication) {
        assertRouterInstantiationCount(String(expected), in: app)
    }

    private func assertExactlyOneProgressEntryActionPerTracker(in app: XCUIApplication) {
        let identifiers = [
            "progress.metrics.action",
            "progress.lifestyle.action",
            "progress.posture.action",
            "progress.health-check.action",
            "progress.bloodwork.action",
            "progress.photos.action",
            "photos.open",
        ]
        let visibleEntryActionCount = identifiers.reduce(into: 0) { count, identifier in
            count += app.buttons.matching(identifier: identifier).count
        }
        XCTAssertEqual(
            visibleEntryActionCount,
            6,
            "Progress must expose one entry action per M3 tracker without a duplicate photo route."
        )
    }

    private func assertFixedNowEvidence(_ expected: String, in app: XCUIApplication) {
        let evidence = require(
            identified("m3.fixed-now", in: app),
            "M3 acceptance must observe AppDomainContext's fixed DEBUG clock."
        )
        XCTAssertEqual(evidence.value as? String, expected)
    }

    private func assertLifestyleSummary(
        sectionCount: String,
        duration: String,
        quality: String,
        moodScore: String,
        in app: XCUIApplication
    ) {
        let loaded = require(identified("lifestyle.progress.loaded", in: app))
        makeHittable(loaded, in: app)
        XCTAssertEqual(loaded.value as? String, sectionCount)
        let sleep = require(identified("lifestyle.progress.sleep.summary", in: app))
        makeHittable(sleep, in: app)
        let sleepValue = (sleep.value as? String) ?? sleep.label
        XCTAssertTrue(
            sleepValue.contains(duration),
            "The same-day edit must retain the latest sleep duration."
        )
        XCTAssertTrue(
            sleepValue.contains(quality),
            "The same-day edit must publish the latest sleep quality."
        )
        let mood = require(identified("lifestyle.progress.mood.summary", in: app))
        makeHittable(mood, in: app)
        XCTAssertTrue(
            ((mood.value as? String) ?? mood.label).contains(moodScore),
            "The same-day edit must publish the latest mood score."
        )
    }

    private func replaceText(
        in element: XCUIElement,
        with value: String,
        app: XCUIApplication
    ) {
        makeHittable(element, in: app)
        require(element).tap()
        let current = (element.value as? String) ?? ""
        if !current.isEmpty {
            element.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
            )
        }
        element.typeText(value)
        let dismiss = app.buttons["quick-entry.keyboard.dismiss"]
        if dismiss.waitForExistence(timeout: 2) {
            dismiss.tap()
        }
    }

    private func waitForDisappearance(of element: XCUIElement, message: String) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            message
        )
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            if element.exists, element.isHittable { return }
            let frame = element.frame
            if element.exists, !frame.isEmpty, frame.midY < app.frame.midY {
                shortDrag(towardTop: false, in: app)
            } else {
                shortDrag(towardTop: true, in: app)
            }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Element must become hittable: \(element.identifier)")
    }

    private func shortDrag(towardTop: Bool, in app: XCUIApplication) {
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        let start = towardTop ? lower : upper
        let end = towardTop ? upper : lower
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func textField(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.textFields[identifier]
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M3 acceptance element is missing.",
        timeout: TimeInterval = 12
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
