import Foundation
import XCTest

final class TodayGuidanceUITests: XCTestCase {
    private enum Appearance: String, CaseIterable {
        case light
        case dark
    }

    private enum TextSize: String, CaseIterable {
        case standard
        case accessibility

        var launchArguments: [String] {
            switch self {
            case .standard:
                []
            case .accessibility:
                [
                    "-UIPreferredContentSizeCategoryName",
                    "UICTContentSizeCategoryAccessibilityXXXL",
                ]
            }
        }
    }

    private struct DirectiveEvidence {
        let scenario: String
        let name: String
        let identifier: String
    }

    private let evidence = [
        DirectiveEvidence(
            scenario: "today-train",
            name: "train",
            identifier: "today.directive.train"
        ),
        DirectiveEvidence(
            scenario: "today-rest",
            name: "rest",
            identifier: "today.directive.rest"
        ),
        DirectiveEvidence(
            scenario: "today-resume",
            name: "resume",
            identifier: "today.directive.resume"
        ),
        DirectiveEvidence(
            scenario: "today-deload",
            name: "deload",
            identifier: "today.alert.deload"
        ),
        DirectiveEvidence(
            scenario: "today-phase",
            name: "phase",
            identifier: "today.alert.phase"
        ),
        DirectiveEvidence(
            scenario: "today-reminder",
            name: "reminder",
            identifier: "today.alert.bloodwork"
        ),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEveryDirectiveClassHasLightDarkDefaultAndAccessibilityEvidence() {
        for appearance in Appearance.allCases {
            for textSize in TextSize.allCases {
                for item in evidence {
                    let app = launch(
                        scenario: item.scenario,
                        appearance: appearance,
                        textSize: textSize
                    )
                    require(
                        identified("root.today.content", in: app),
                        "Every Today evidence fixture must publish meaningful content."
                    )
                    let evidenceElement = require(
                        identified(item.identifier, in: app),
                        "The \(item.name) fixture must expose \(item.identifier)."
                    )
                    XCTAssertFalse(evidenceElement.label.isEmpty)
                    let phase = require(
                        identified("today.phase", in: app),
                        "Every directive class must expose the active phase line."
                    )
                    let context = require(
                        identified("today.directive.context", in: app),
                        "Every directive class must explain its context."
                    )
                    let primaryAction = require(
                        app.buttons["today.action.primary"],
                        "Every directive class needs one real primary action."
                    )
                    if textSize == .standard {
                        for element in [phase, evidenceElement, context, primaryAction] {
                            XCTAssertTrue(
                                element.isHittable,
                                "Phase, directive, context, alert and action must stay in the first default-Type viewport."
                            )
                            XCTAssertTrue(app.frame.contains(element.frame))
                        }
                    }
                    XCTAssertFalse(
                        identified("today.protein.consumed", in: app).exists,
                        "M1 must not fabricate consumed protein."
                    )
                    XCTAssertFalse(
                        identified("today.protein.progress", in: app).exists,
                        "M1 must not fabricate nutrition progress."
                    )
                    XCTAssertFalse(
                        identified("today.nutrition.action", in: app).exists,
                        "M1 must not expose an unavailable meal action."
                    )
                    attachScreenshot(
                        named: "today-\(item.name)-\(appearance.rawValue)-\(textSize.rawValue)"
                    )
                    app.terminate()
                }
            }
        }
    }

    func testTrainResumeAndRestOverrideActionsOpenTheRealSessionFlow() {
        for scenario in ["today-train", "today-resume", "today-rest"] {
            let app = launch(scenario: scenario, appearance: .light, textSize: .standard)
            let action = require(
                app.buttons["today.action.primary"],
                "The \(scenario) fixture must expose one real primary action."
            )
            XCTAssertTrue(action.isHittable)
            action.tap()
            require(
                identified("session.root", in: app),
                "The \(scenario) action must route into the repository-backed session flow."
            )
            app.terminate()
        }
    }

    func testOnlyHighestPriorityAlertIsExpandedAndRemainingCountIsVisible() {
        let app = launch(
            scenario: "today-priority",
            appearance: .light,
            textSize: .standard
        )

        require(
            identified("today.alert.activeSymptoms", in: app),
            "Active symptoms must outrank all other Today alerts."
        )
        let remaining = require(
            identified("today.alert.additional", in: app),
            "Hidden lower-priority alerts must be represented by +N."
        )
        XCTAssertEqual(remaining.label, "+5")
        XCTAssertFalse(identified("today.alert.ohp", in: app).exists)
        XCTAssertFalse(identified("today.alert.deload", in: app).exists)
        XCTAssertFalse(identified("today.alert.phase", in: app).exists)
        XCTAssertFalse(identified("today.alert.bloodwork", in: app).exists)
        XCTAssertFalse(identified("today.alert.measurement", in: app).exists)
    }

    func testLoadingStateAndEmptyErrorRetriesUseTheRealSnapshotLoad() {
        let loadingApp = launch(
            scenario: "loading",
            appearance: .light,
            textSize: .standard
        )
        require(
            identified("today.state.loading", in: loadingApp),
            "Today must expose its stable loading state to assistive technology."
        )
        loadingApp.terminate()

        for (scenario, stateIdentifier) in [
            ("today-empty-once", "today.state.empty"),
            ("today-error-once", "today.state.error"),
        ] {
            let app = launch(scenario: scenario, appearance: .light, textSize: .standard)
            let retry = require(
                app.buttons[stateIdentifier],
                "The \(scenario) fixture must expose one recoverable action."
            )
            XCTAssertTrue(retry.isHittable)
            retry.tap()
            require(
                identified("root.today.content", in: app),
                "Retry must fetch a new compact snapshot and recover."
            )
            app.terminate()
        }
    }

    func testColdLaunchPublishesFirstMeaningfulDirectiveWithinOneSecondMedian() throws {
        let storeIdentifier = UUID()
        let stabilizationLaunchCount = 5
        var samples: [Double] = []

        let preparationApp = launch(
            scenario: "seeded",
            appearance: .light,
            textSize: .standard,
            storeIdentifier: storeIdentifier,
            appliesLocaleOverride: false
        )
        require(
            identified("root.today.content", in: preparationApp),
            "The unique performance-test store must be seeded before measurement."
        )
        preparationApp.terminate()

        for _ in 0..<stabilizationLaunchCount {
            let app = launch(
                scenario: "seeded",
                appearance: .light,
                textSize: .standard,
                storeIdentifier: storeIdentifier,
                appliesLocaleOverride: false
            )
            require(
                identified("today.performance.firstMeaningful", in: app),
                "Every fixed stabilization launch must publish real Today content."
            )
            app.terminate()
        }

        for _ in 0..<5 {
            let app = launch(
                scenario: "seeded",
                appearance: .light,
                textSize: .standard,
                storeIdentifier: storeIdentifier,
                appliesLocaleOverride: false
            )
            let marker = require(
                identified("today.performance.firstMeaningful", in: app),
                "The UI-test build must expose the raw launch-to-content measurement."
            )
            let rawValue = try XCTUnwrap(marker.value as? String)
            let seconds = try XCTUnwrap(
                Double(rawValue),
                "The launch marker value must be raw seconds, not formatted prose."
            )
            samples.append(seconds)
            app.terminate()
        }

        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let evidenceObject: [String: Any] = [
            "clock": "ProcessInfo.systemUptime",
            "start": "HealthTrackingApp.init",
            "end": "TodayViewModel first content publication",
            "precondition": "one untimed launch seeds a unique local UI-test store",
            "sampleIsolation": "same seeded store, new app process for every sample",
            "localePolicy": "app default; no launch-time AppleLanguages override",
            "stabilizationPolicy": "five fixed unmeasured new-process launches",
            "stabilizationLaunchCount": stabilizationLaunchCount,
            "repeatCount": samples.count,
            "samplesSeconds": samples,
            "medianSeconds": median,
            "thresholdSeconds": 1.0,
        ]
        let evidenceData = try JSONSerialization.data(
            withJSONObject: evidenceObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        let attachment = XCTAttachment(
            data: evidenceData,
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = "today-cold-launch-raw"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertLessThanOrEqual(
            median,
            1,
            "The documented five-run median from app launch to first meaningful Today content must be ≤1 second. Raw samples: \(samples)"
        )
    }

    private func launch(
        scenario: String,
        appearance: Appearance,
        textSize: TextSize,
        storeIdentifier: UUID? = nil,
        appliesLocaleOverride: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", scenario,
            "-ui-test-appearance", appearance.rawValue,
        ] + textSize.launchArguments
        if appliesLocaleOverride {
            app.launchArguments += [
                "-AppleLanguages", "(tr)",
                "-AppleLocale", "tr_TR",
            ]
        }
        if let storeIdentifier {
            app.launchArguments += [
                "-ui-test-store-identifier",
                storeIdentifier.uuidString,
            ]
        }
        app.launch()
        return app
    }

    private func identified(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ message: String,
        timeout: TimeInterval = 8
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
