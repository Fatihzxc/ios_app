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
    }

    private let evidence = [
        DirectiveEvidence(
            scenario: "today-train",
            name: "train"
        ),
        DirectiveEvidence(
            scenario: "today-rest",
            name: "rest"
        ),
        DirectiveEvidence(
            scenario: "today-resume",
            name: "resume"
        ),
        DirectiveEvidence(
            scenario: "today-deload",
            name: "deload"
        ),
        DirectiveEvidence(
            scenario: "today-phase",
            name: "phase"
        ),
        DirectiveEvidence(
            scenario: "today-reminder",
            name: "reminder"
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
                    let summary = require(
                        identified("today.accessibility.summary", in: app),
                        "Every directive class must combine phase, directive and context for VoiceOver."
                    )
                    XCTAssertFalse(summary.label.isEmpty)
                    let primaryAction = require(
                        app.buttons["today.action.primary"],
                        "Every directive class needs one real primary action."
                    )
                    if textSize == .standard {
                        for element in [summary, primaryAction] {
                            XCTAssertTrue(
                                element.isHittable,
                                "The Today summary and action must stay in the first default-Type viewport."
                            )
                            XCTAssertTrue(app.frame.contains(element.frame))
                        }
                    }
                    let consumed = require(
                        identified("today.protein.consumed", in: app),
                        "M2 must publish repository-backed consumed protein."
                    )
                    XCTAssertFalse((consumed.value as? String)?.isEmpty ?? true)
                    require(
                        identified("today.protein.progress", in: app),
                        "M2 must expose target progress without changing the workout directive."
                    )
                    let mealAction = require(
                        identified("today.nutrition.action", in: app),
                        "M2 must expose the secondary app-owned meal route."
                    )
                    XCTAssertNotEqual(
                        mealAction.identifier,
                        primaryAction.identifier,
                        "The nutrition route must not replace the primary training action."
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
        var phaseSamples: [[String: Double]] = []
        let phaseNames = [
            "environment",
            "container",
            "dependencyEntry",
            "dependencyContext",
            "dependencyRepository",
            "dependencyRouting",
            "dependencyViewModel",
            "dependencies",
            "seed",
            "today",
        ]

        let preparationApp = launch(
            scenario: "seeded",
            appearance: .light,
            textSize: .standard,
            storeIdentifier: storeIdentifier,
            appliesLocaleOverride: false,
            exposesLaunchPerformanceEvidence: true
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
                appliesLocaleOverride: false,
                exposesLaunchPerformanceEvidence: true
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
                appliesLocaleOverride: false,
                exposesLaunchPerformanceEvidence: true
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
            let phaseMarker = require(
                identified("today.performance.breakdown", in: app),
                "Every measured launch must expose phase-level timing evidence."
            )
            let phaseRawValue = try XCTUnwrap(phaseMarker.value as? String)
            let phaseData = try XCTUnwrap(phaseRawValue.data(using: .utf8))
            let phaseObject = try JSONSerialization.jsonObject(with: phaseData)
            let phaseDictionary = try XCTUnwrap(phaseObject as? [String: Any])
            var phases: [String: Double] = [:]
            for phaseName in phaseNames {
                phases[phaseName] = try XCTUnwrap(
                    phaseDictionary[phaseName] as? Double,
                    "Missing numeric \(phaseName) launch checkpoint."
                )
            }
            for (earlier, later) in zip(phaseNames, phaseNames.dropFirst()) {
                XCTAssertLessThanOrEqual(
                    try XCTUnwrap(phases[earlier]),
                    try XCTUnwrap(phases[later]),
                    "Launch checkpoints must be monotonic: \(earlier) before \(later)."
                )
            }
            XCTAssertEqual(
                try XCTUnwrap(phases["today"]),
                seconds,
                accuracy: 0.000_001,
                "The final phase checkpoint must use the existing launch-to-content boundary."
            )
            samples.append(seconds)
            phaseSamples.append(phases)
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
            "phaseSamplesSeconds": phaseSamples,
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
        appliesLocaleOverride: Bool = true,
        exposesLaunchPerformanceEvidence: Bool = false
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
        if exposesLaunchPerformanceEvidence {
            app.launchArguments.append("-ui-test-launch-performance-evidence")
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
