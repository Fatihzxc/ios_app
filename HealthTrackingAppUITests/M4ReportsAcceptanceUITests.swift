import Foundation
import XCTest

final class M4ReportsAcceptanceUITests: XCTestCase {
    private enum ExportBehavior: String {
        case success
        case failOnce = "fail-once"
        case slowOnce = "slow-once"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testUS7DashboardUsesEveryRangeAndShowsHonestObservedEvidence() {
        let app = launch(exportBehavior: .success)
        defer { app.terminate() }
        openProgress(in: app)

        requireByScrolling(
            identified("reports.chart.body.kg.segment.1", in: app),
            in: app,
            "The shipped dashboard must chart deterministic weight observations."
        )
        requireByScrolling(
            identified("reports.chart.body.cm.segment.1", in: app),
            in: app,
            "The shipped dashboard must chart deterministic waist observations."
        )
        requireByScrolling(
            identified(
                "reports.chart.strength.00000000-0000-4000-8000-00000000a401.volume.segment.1",
                in: app
            ),
            in: app,
            "The weighted movement must expose volume and estimated-one-rep-max evidence."
        )
        requireByScrolling(identified("reports.protein", in: app), in: app)

        let proteinEvidence = requireByScrolling(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "uygun hedef günü")
            ).firstMatch,
            in: app,
            "Protein adherence must publish its eligible-day denominator."
        )
        XCTAssertTrue(proteinEvidence.label.contains("dışlandı"))
        requireByScrolling(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Güncel profil hedefi")
            ).firstMatch,
            in: app,
            "Protein provenance must state that the current profile target is applied only to observed days."
        )

        requireByScrolling(identified("reports.chart.sleep.segment.1", in: app), in: app)
        requireByScrolling(identified("reports.chart.mood.segment.1", in: app), in: app)
        requireByScrolling(identified("reports.chart.posture.segment.1", in: app), in: app)
        requireByScrolling(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "kayıt boşluğu")
            ).firstMatch,
            in: app,
            "Missing lifestyle days must be described as gaps instead of connected zeroes."
        )
        requireByScrolling(identified("reports.phase", in: app), in: app)
        requireByScrolling(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Kısmi geçmiş")
            ).firstMatch,
            in: app,
            "A current-state-only phase timeline must remain explicitly partial."
        )

        let rangeIdentifiers = [
            "reports.range.one_month",
            "reports.range.three_months",
            "reports.range.six_months",
            "reports.range.one_year",
        ]
        for identifier in rangeIdentifiers {
            let range = requireByScrolling(identified(identifier, in: app), in: app)
            range.tap()
            waitUntilSelected(range)
            requireByScrolling(identified("reports.summary", in: app), in: app)
            requireByScrolling(
                identified("reports.chart.body.kg.segment.1", in: app),
                in: app
            )
        }

        let strengthTable = requireByScrolling(
            identified(
                "reports.table.strength.00000000-0000-4000-8000-00000000a401.volume.segment.1",
                in: app
            ),
            in: app
        )
        strengthTable.tap()
        requireByScrolling(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "hacim"))
                .firstMatch,
            in: app
        )
        requireByScrolling(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1RM"))
                .firstMatch,
            in: app
        )
        attachScreenshot(named: "m4-reports-us7")
    }

    func testTwoReadyPhotosShareOnlyAfterExplicitUserAction() {
        let app = launch(exportBehavior: .success)
        defer { app.terminate() }
        openProgress(in: app)

        let photos = require(identified("progress.photos.action", in: app))
        makeHittable(photos, in: app)
        photos.tap()
        require(identified("photos.gallery.content", in: app))

        let share = app.buttons["photos.compare.share"]
        XCTAssertFalse(share.exists)
        for photoID in [
            "00000000-0000-0000-0000-000000000201",
            "00000000-0000-0000-0000-000000000202",
        ] {
            let selection = require(app.buttons["photos.gallery.select.\(photoID)"])
            makeHittable(selection, in: app)
            selection.tap()
        }

        require(identified("photos.compare.content", in: app))
        require(share, "Exactly two ready photos must enable the share-safe comparison.")
        XCTAssertGreaterThanOrEqual(share.frame.height + 0.01, 52)
        XCTAssertFalse(identified("photos.compare.share.sheet", in: app).exists)
        attachScreenshot(named: "m4-reports-photo-share")
        share.tap()
        require(
            identified("photos.compare.share.sheet", in: app),
            "The real system activity host must appear only after the explicit share tap."
        )
    }

    func testCSVJSONAndBothExportsUseRealShareAndCleanEveryArtifact() {
        let app = launch(exportBehavior: .success)
        defer { app.terminate() }
        openExport(in: app)
        assertWorkspaceCountEventually(0, in: app)

        for (formatIndex, includesPhotos) in [(0, false), (1, false), (2, true)] {
            selectExportFormat(at: formatIndex, in: app)
            if includesPhotos {
                let photos = require(app.switches["reports.export.photos"])
                if photos.value as? String != "1" { photos.tap() }
            } else {
                XCTAssertFalse(app.switches["reports.export.photos"].exists)
            }
            let generate = require(app.buttons["reports.export.generate"])
            makeHittable(generate, in: app)
            generate.tap()
            let share = require(
                app.buttons["reports.export.share"],
                "Each selected export format must produce a shareable artifact.",
                timeout: 20
            )
            assertWorkspaceCountEventually(1, in: app)
            if formatIndex == 2 {
                attachScreenshot(named: "m4-reports-export-both")
            }
            makeHittable(share, in: app)
            share.tap()
            let activity = require(
                identified("reports.export.share.sheet", in: app),
                "The shipped export must present the real system activity host."
            )
            dragDownToDismiss(activity.exists ? activity : app)
            waitForDisappearance(
                of: activity,
                message: "Cancelling the activity sheet must dismiss the exact share request."
            )
            assertWorkspaceCountEventually(0, in: app)
        }
    }

    func testExportFailureKeepsSelectionAndRetryThenDismissalCleansArtifact() {
        let app = launch(exportBehavior: .failOnce)
        defer { app.terminate() }
        openExport(in: app)
        selectExportFormat(at: 2, in: app)
        let photos = require(app.switches["reports.export.photos"])
        photos.tap()

        require(app.buttons["reports.export.generate"]).tap()
        require(identified("reports.export.error", in: app), timeout: 15)
        XCTAssertEqual(photos.value as? String, "1")
        assertWorkspaceCountEventually(0, in: app)

        require(app.buttons["reports.export.retry"]).tap()
        require(app.buttons["reports.export.share"], timeout: 20)
        XCTAssertEqual(photos.value as? String, "1")
        assertWorkspaceCountEventually(1, in: app)
        dismissExportSheet(in: app)
        assertWorkspaceCountEventually(0, in: app)
    }

    func testSlowExportCanCancelAndRetryWithoutLeavingTemporaryFiles() {
        let app = launch(exportBehavior: .slowOnce)
        defer { app.terminate() }
        openExport(in: app)

        require(app.buttons["reports.export.generate"]).tap()
        require(identified("reports.export.progress", in: app), timeout: 8)
        require(app.buttons["reports.export.cancel"]).tap()
        require(app.buttons["reports.export.generate"], timeout: 8)
        assertWorkspaceCountEventually(0, in: app)

        require(app.buttons["reports.export.generate"]).tap()
        require(app.buttons["reports.export.share"], timeout: 20)
        assertWorkspaceCountEventually(1, in: app)
        dismissExportSheet(in: app)
        assertWorkspaceCountEventually(0, in: app)
    }

    private func launch(exportBehavior: ExportBehavior) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TZ"] = "Europe/Istanbul"
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m4-reports",
            "-ui-test-appearance", "light",
            "-ui-test-store-identifier", UUID().uuidString,
            "-ui-test-now", "2026-09-02T09:00:00Z",
            "-ui-test-time-zone", "Europe/Istanbul",
            "-ui-test-reports-export-behavior", exportBehavior.rawValue,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        app.launch()
        acknowledgeMedicalExplanationIfNeeded(in: app)
        require(identified("root.today.content", in: app))
        return app
    }

    private func acknowledgeMedicalExplanationIfNeeded(in app: XCUIApplication) {
        let acknowledgement = app.buttons["medical.explanation.l0.acknowledge"]
        if acknowledgement.waitForExistence(timeout: 2) { acknowledgement.tap() }
    }

    private func openProgress(in app: XCUIApplication) {
        require(identified("tab.progress", in: app)).tap()
        require(identified("root.progress", in: app))
        require(identified("reports.dashboard", in: app))
    }

    private func openExport(in app: XCUIApplication) {
        openProgress(in: app)
        let open = requireByScrolling(identified("reports.export.open", in: app), in: app)
        open.tap()
        require(identified("reports.export.range", in: app))
    }

    private func selectExportFormat(at index: Int, in app: XCUIApplication) {
        let control = require(app.segmentedControls["reports.export.format"])
        let button = control.buttons.element(boundBy: index)
        require(button)
        button.tap()
        XCTAssertTrue(button.isSelected)
    }

    private func dismissExportSheet(in app: XCUIApplication) {
        let sheet = app.sheets.firstMatch
        let exportRange = identified("reports.export.range", in: app)
        dragDownToDismiss(sheet.exists ? sheet : app)
        waitForDisappearance(
            of: exportRange,
            message: "Dismissing the export sheet must leave the real Progress dashboard."
        )
    }

    private func waitUntilSelected(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func assertWorkspaceCountEventually(_ expected: Int, in app: XCUIApplication) {
        let evidence = require(
            identified("m4.reports.export-workspace-count", in: app),
            "M4 acceptance must expose only the count of real owned export workspaces."
        )
        let value = String(expected)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: evidence
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 12),
            .completed,
            "Expected \(expected) owned export workspaces; found \(String(describing: evidence.value))."
        )
    }

    private func dragDownToDismiss(_ surface: XCUIElement) {
        let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func waitForDisappearance(of element: XCUIElement, message: String) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, message)
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<36 {
            let frame = element.frame
            let visible = !frame.isEmpty
                && frame.minY >= app.frame.minY + 44
                && frame.maxY <= app.frame.maxY - 44
            if element.exists, element.isHittable, visible { return }
            let towardTop = frame.isEmpty || frame.midY >= app.frame.midY
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
            let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
            (towardTop ? lower : upper).press(
                forDuration: 0.05,
                thenDragTo: towardTop ? upper : lower
            )
        }
        XCTFail("Unable to make M4 acceptance element hittable: \(element.identifier)")
    }

    @discardableResult
    private func requireByScrolling(
        _ element: XCUIElement,
        in app: XCUIApplication,
        _ message: String = "Required M4 acceptance element is missing."
    ) -> XCUIElement {
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))

        for searchesDown in [true, false] {
            for _ in 0..<40 {
                if element.exists {
                    let frame = element.frame
                    let visible = !frame.isEmpty
                        && frame.minY >= app.frame.minY + 44
                        && frame.maxY <= app.frame.maxY - 44
                    if element.isHittable, visible {
                        return require(element, message, timeout: 1)
                    }
                }
                (searchesDown ? lower : upper).press(
                    forDuration: 0.05,
                    thenDragTo: searchesDown ? upper : lower
                )
            }
        }

        _ = require(element, message, timeout: 1)
        XCTAssertTrue(
            element.isHittable,
            "Required M4 acceptance element is not hittable after bounded real scrolling."
        )
        return element
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M4 acceptance element is missing.",
        timeout: TimeInterval = 15
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
