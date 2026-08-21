import XCTest

final class AccessibilitySmokeUITests: XCTestCase {
    private enum Appearance: String {
        case light
        case dark
    }

    private struct TabContract {
        let name: String
        let title: String

        var tabIdentifier: String { "tab.\(name)" }
        var rootIdentifier: String { "root.\(name)" }
        var primaryContentIdentifier: String { "root.\(name).content" }
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

    func testAccessibilityXXXLTraversesEveryRootWithoutDuplicateOrClippedControls() throws {
        for appearance in [Appearance.light, .dark] {
            let app = launchApp(scenario: "seeded", appearance: appearance)

            for tab in tabs {
                let tabControl = requireExactlyOne(
                    app.descendants(matching: .any).matching(identifier: tab.tabIdentifier),
                    "\(tab.tabIdentifier) must be a unique stable tab control."
                )
                XCTAssertEqual(tabControl.label, tab.title, "\(tab.tabIdentifier) must expose its exact Turkish VoiceOver label.")
                XCTAssertTrue(tabControl.isHittable, "\(tab.tabIdentifier) must remain hittable at accessibility XXXL.")
                XCTAssertTrue(app.frame.contains(tabControl.frame), "\(tab.tabIdentifier) must not be clipped at accessibility XXXL.")

                tabControl.tap()
                let root = requireExactlyOne(
                    app.descendants(matching: .any).matching(identifier: tab.rootIdentifier),
                    "\(tab.rootIdentifier) must be a unique stable root."
                )
                XCTAssertTrue(root.isHittable, "\(tab.rootIdentifier) must remain hittable at accessibility XXXL.")
                assertVisibleWithinApp(root, named: tab.rootIdentifier, in: app)
                let title = requireExactlyOne(
                    app.navigationBars.matching(identifier: tab.title),
                    "\(tab.rootIdentifier) must retain its exact navigation title."
                )
                XCTAssertTrue(title.isHittable, "The \(tab.title) navigation title must remain hittable at accessibility XXXL.")
                assertVisibleWithinApp(title, named: "navigation title \(tab.title)", in: app)
                let primaryContent = requireElement(
                    app.descendants(matching: .any)
                        .matching(identifier: tab.primaryContentIdentifier)
                        .firstMatch,
                    "\(tab.primaryContentIdentifier) must expose visible primary content."
                )
                XCTAssertTrue(primaryContent.isHittable, "\(tab.primaryContentIdentifier) must remain hittable at accessibility XXXL.")
                assertVisibleWithinApp(primaryContent, named: tab.primaryContentIdentifier, in: app)
                // This fixture is already pinned to AX5. Asking Xcode to vary Dynamic Type
                // beyond that maximum emits an element-less "unsupported" issue. The
                // default-through-AX5 session matrix owns Dynamic Type variation; this
                // smoke pass audits the actual AX5 render for detection, hit regions and clipping.
                try app.performAccessibilityAudit(
                    for: [.elementDetection, .hitRegion, .textClipped]
                )
            }

            attachScreenshot(named: "accessibility-xxxl-\(appearance.rawValue)")
        }
    }

    func testVoiceOverContractsCoverSeededRowsStatesAndGalleryControls() {
        let seeded = launchApp(scenario: "seeded", appearance: .light)
        select(tabNamed: "training", in: seeded)
        let phases = [
            ("Temel", "1–2. aylar. Antrenman odağı: Teknik + alışkanlık; OHP kademeli giriş; ölçümleri başlat. Beslenme odağı: Ölçülü açık; 120 g protein. Hedef: Alışkanlık + baseline + check-up."),
            ("İnşa", "3–6. aylar. Antrenman odağı: Çift progresyon; 10 kg yükler tırmanır; 20 kg tavan. Beslenme odağı: Açığı sürdür; bel+güç izle. Hedef: Bel↓, güç↑, ayarlanabilir DB."),
            ("İlerleme", "7–9. aylar. Antrenman odağı: Ağır DB; bileşiklerde ağır/az tekrar (kemik). Beslenme odağı: Kilo düştükçe açığı yeniden kalibre. Hedef: Güç sıçraması + beslenme ayarı."),
            ("Konsolidasyon", "10–12. aylar. Antrenman odağı: Hacim eklemeyi durdur; kaliteyi koru. Beslenme odağı: Sürdürülebilir bakım. Hedef: Veriye dayalı 2. yıl kararı."),
        ]
        for (index, phase) in phases.enumerated() {
            assertVoiceOver(
                requireExactlyOne(seeded.descendants(matching: .any).matching(identifier: "training.phase-row.\(index)"), "Seeded phase row \(index) is required."),
                label: phase.0,
                value: phase.1
            )
        }

        let days = [
            ("Gün A", "Squat Ağırlıklı"),
            ("Gün B", "Hinge Ağırlıklı"),
            ("Gün C", "Unilateral + Taşıma"),
        ]
        for (index, day) in days.enumerated() {
            assertVoiceOver(
                requireExactlyOne(seeded.descendants(matching: .any).matching(identifier: "training.day-row.\(index)"), "Seeded workout-day row \(index) is required."),
                label: day.0,
                value: day.1
            )
        }

        select(tabNamed: "settings", in: seeded)
        let galleryLink = requireExactlyOne(
            seeded.buttons.matching(identifier: "settings.gallery-link"),
            "Settings must expose one accessible gallery control."
        )
        XCTAssertEqual(galleryLink.label, "Tasarım sistemi galerisi", "The gallery route must expose its localized VoiceOver label.")
        galleryLink.tap()
        let galleryActions = seeded.buttons.matching(
            NSPredicate(format: "label == %@", "Kaydı başlat")
        )
        requireCount(
            galleryActions,
            expected: 2,
            "The light and dark gallery examples must each expose their primary action to VoiceOver."
        )
        for index in 0..<2 {
            let galleryAction = galleryActions.element(boundBy: index)
            XCTAssertEqual(galleryAction.label, "Kaydı başlat", "Each gallery primary action must expose its explicit accessibility label.")
            XCTAssertFalse(galleryAction.isEnabled, "Each gallery evidence action must remain disabled.")
        }

        seeded.terminate()
        assertStateVoiceOver(scenario: "loading", identifier: "foundation.state.loading", label: "Yükleniyor")
        assertStateVoiceOver(scenario: "empty-once", identifier: "foundation.state.empty", label: "Programı yeniden yükle")
        assertStateVoiceOver(scenario: "error-once", identifier: "foundation.state.error", label: "Yeniden dene")
    }

    private func assertStateVoiceOver(scenario: String, identifier: String, label: String) {
        let app = launchApp(scenario: scenario, appearance: .light)
        select(tabNamed: "training", in: app)
        let state = requireExactlyOne(
            app.descendants(matching: .any).matching(identifier: identifier),
            "\(identifier) must be a unique accessibility state contract."
        )
        XCTAssertEqual(state.label, label, "\(identifier) must expose its exact localized VoiceOver label.")
        XCTAssertTrue(state.isHittable, "\(identifier) must remain reachable by VoiceOver.")
    }

    private func launchApp(scenario: String, appearance: Appearance) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", scenario,
            "-ui-test-appearance", appearance.rawValue,
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        return app
    }

    private func select(tabNamed name: String, in app: XCUIApplication) {
        guard let tab = tabs.first(where: { $0.name == name }) else {
            XCTFail("Unknown tab contract: \(name)")
            return
        }

        let control = requireExactlyOne(
            app.descendants(matching: .any).matching(identifier: tab.tabIdentifier),
            "Expected tab \(tab.tabIdentifier)."
        )
        control.tap()
        _ = requireExactlyOne(
            app.descendants(matching: .any).matching(identifier: tab.rootIdentifier),
            "Selecting \(tab.tabIdentifier) must expose \(tab.rootIdentifier)."
        )
    }

    private func assertVoiceOver(_ element: XCUIElement, label: String, value: String) {
        XCTAssertEqual(element.label, label, "The VoiceOver label must be exact.")
        XCTAssertEqual(element.value as? String, value, "The VoiceOver value must be exact.")
    }

    private func assertVisibleWithinApp(_ element: XCUIElement, named name: String, in app: XCUIApplication) {
        XCTAssertFalse(element.frame.isEmpty, "\(name) must have a rendered frame at accessibility XXXL.")
        XCTAssertTrue(app.frame.contains(element.frame), "\(name) must be fully contained by the app window at accessibility XXXL.")
    }

    @discardableResult
    private func requireExactlyOne(_ query: XCUIElementQuery, _ message: String) -> XCUIElement {
        requireCount(query, expected: 1, message)
        return query.firstMatch
    }

    private func requireCount(_ query: XCUIElementQuery, expected: Int, _ message: String) {
        let countExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", expected),
            object: query
        )
        XCTAssertEqual(XCTWaiter.wait(for: [countExpectation], timeout: 8), .completed, "\(message) Found \(query.count).")
    }

    @discardableResult
    private func requireElement(_ element: XCUIElement, _ message: String) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: 8), message)
        return element
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
