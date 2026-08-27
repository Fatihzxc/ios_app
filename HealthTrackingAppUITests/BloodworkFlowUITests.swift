import Foundation
import XCTest

final class BloodworkFlowUITests: XCTestCase {
    private let disclaimer =
        "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAddEditDeleteAndRelaunchKeepsPermanentDisclaimer() {
        let storeIdentifier = UUID()
        let app = launch(
            appearance: "light",
            storeIdentifier: storeIdentifier
        )
        openBloodwork(in: app)

        assertDisclaimer(in: app)
        require(
            identified("bloodwork.list.error", in: app),
            "The injected load failure must keep an inline retry path."
        )
        require(identified("bloodwork.list.retry", in: app)).tap()
        assertDisclaimer(in: app)
        require(identified("bloodwork.list.empty", in: app))
        attachScreenshot(named: "m3-bloodwork-empty-light")

        require(identified("bloodwork.add", in: app)).tap()
        assertDisclaimer(in: app)
        require(identified("bloodwork.editor.content", in: app))
        replaceText(in: textField("bloodwork.editor.marker", in: app), with: "Ferritin", app: app)
        replaceText(in: textField("bloodwork.editor.value", in: app), with: "18.5", app: app)
        replaceText(in: textField("bloodwork.editor.unit", in: app), with: "ng/mL", app: app)
        replaceText(in: textField("bloodwork.editor.note", in: app), with: "Sabah ölçümü", app: app)
        require(identified("bloodwork.editor.save", in: app)).tap()
        require(
            identified("bloodwork.editor.save-error", in: app),
            "The first create failure must preserve the editor values."
        )
        let failedMarker = textField("bloodwork.editor.marker", in: app)
        XCTAssertEqual(failedMarker.value as? String, "Ferritin")
        XCTAssertFalse(
            failedMarker.isEnabled,
            "A retry that owns an exact health-data payload must lock edited fields."
        )
        require(identified("bloodwork.editor.retry", in: app)).tap()

        require(identified("bloodwork.detail.content", in: app))
        assertDisclaimer(in: app)
        XCTAssertTrue(require(identified("bloodwork.detail.value", in: app)).label.contains("18,5"))
        attachScreenshot(named: "m3-bloodwork-detail-light")

        require(identified("bloodwork.detail.edit", in: app)).tap()
        assertDisclaimer(in: app)
        replaceText(in: textField("bloodwork.editor.value", in: app), with: "19", app: app)
        require(identified("bloodwork.editor.save", in: app)).tap()
        require(identified("bloodwork.detail.content", in: app))
        XCTAssertTrue(require(identified("bloodwork.detail.value", in: app)).label.contains("19"))
        app.terminate()

        let relaunched = launch(
            appearance: "light",
            storeIdentifier: storeIdentifier
        )
        openBloodwork(in: relaunched)
        require(identified("bloodwork.list.error", in: relaunched))
        require(identified("bloodwork.list.retry", in: relaunched)).tap()
        let persisted = require(
            firstIdentified(
                prefix: "bloodwork.row.",
                labelContaining: "Ferritin",
                in: relaunched
            ),
            "The edited bloodwork reference must survive a new app process."
        )
        makeHittable(persisted, in: relaunched)
        persisted.tap()
        require(identified("bloodwork.detail.content", in: relaunched))
        assertDisclaimer(in: relaunched)
        let delete = require(identified("bloodwork.detail.delete", in: relaunched))
        makeHittable(delete, in: relaunched)
        XCTAssertGreaterThanOrEqual(delete.frame.height + 0.01, 52)
        delete.tap()
        require(identified("bloodwork.detail.delete-confirm", in: relaunched)).tap()
        require(identified("bloodwork.list.empty", in: relaunched))
        assertDisclaimer(in: relaunched)
    }

    func testDarkHighContrastAndAX5KeepEditorAndDisclaimerReadable() {
        let dark = launch(
            appearance: "dark",
            extraArguments: ["-UIAccessibilityDarkerSystemColorsEnabled", "YES"]
        )
        openBloodwork(in: dark)
        require(identified("bloodwork.list.retry", in: dark)).tap()
        require(identified("bloodwork.add", in: dark)).tap()
        assertDisclaimer(in: dark)
        require(textField("bloodwork.editor.marker", in: dark))
        attachScreenshot(named: "m3-bloodwork-editor-dark-high-contrast")
        dark.terminate()

        let ax5 = launch(
            appearance: "light",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        openBloodwork(in: ax5)
        require(identified("bloodwork.list.retry", in: ax5)).tap()
        require(identified("bloodwork.add", in: ax5)).tap()
        assertDisclaimer(in: ax5)
        let save = require(identified("bloodwork.editor.save", in: ax5))
        makeHittable(save, in: ax5)
        XCTAssertTrue(save.isHittable)
        XCTAssertGreaterThanOrEqual(save.frame.height + 0.01, 52)
        attachScreenshot(named: "m3-bloodwork-editor-ax5")
    }

    private func launch(
        appearance: String,
        storeIdentifier: UUID? = nil,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", "m3-bloodwork",
            "-ui-test-appearance", appearance,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ] + extraArguments
        if let storeIdentifier {
            app.launchArguments += [
                "-ui-test-store-identifier",
                storeIdentifier.uuidString,
            ]
        }
        app.launch()
        return app
    }

    private func openBloodwork(in app: XCUIApplication) {
        require(identified("tab.progress", in: app)).tap()
        require(identified("root.progress", in: app))
        require(
            identified("health-check.history.error", in: app),
            "Bloodwork access must remain available when health-check loading fails."
        )
        let open = require(identified("bloodwork.open", in: app))
        makeHittable(open, in: app)
        open.tap()
        require(identified("bloodwork.list.content", in: app))
    }

    private func assertDisclaimer(in app: XCUIApplication) {
        let element = require(identified("bloodwork.disclaimer.l1", in: app))
        XCTAssertEqual(element.label, disclaimer)
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

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            if element.exists, element.isHittable { return }
            if element.exists,
               !element.frame.isEmpty,
               element.frame.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func textField(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.textFields[identifier]
    }

    private func firstIdentified(
        prefix: String,
        labelContaining: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                    prefix,
                    labelContaining
                )
            )
            .firstMatch
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String = "Required M3.6 bloodwork element is missing.",
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
