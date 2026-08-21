import Foundation
import XCTest

final class M1AcceptanceUITests: XCTestCase {
    private struct ExerciseContract {
        let name: String
        let family: String
        let safety: String
        let needsRepsSeed: Bool

        init(
            _ name: String,
            _ family: String,
            _ safety: String,
            needsRepsSeed: Bool = false
        ) {
            self.name = name
            self.family = family
            self.safety = safety
            self.needsRepsSeed = needsRepsSeed
        }
    }

    private let days: [[ExerciseContract]] = [
        [
            .init("Goblet Squat", "weightReps", "3sn eksantrik; topuk kalkarsa plaka"),
            .init("Chin-up", "reps", "faile gitme; boyun nötr"),
            .init("DB Floor Press", "weightReps", "dirsek 45°, yerde 1sn"),
            .init("DB Romanian Deadlift", "weightReps", "kalça menteşesi; bel değil hamstring"),
            .init("Prone Y-T-W", "reps", "ağırlıksız; tepede 2sn"),
            .init("Face Pull (bant)", "reps", "hafif; omuz yukarı kalkmasın"),
            .init("Tek Bacak Calf Raise", "reps", "1.set düz diz, 2.set bükük"),
            .init("Plank / Pallof", "duration", "haftada 1 Pallof"),
        ],
        [
            .init("DB RDL (çift)", "weightReps", "A'dan ağır; DB bacaktan uzaklaşmasın"),
            .init("Tek Kol DB Row", "weightReps", "gövde döndürme"),
            .init("Push-up", "reps", "kolaysa ayak yüksekte"),
            .init("DB Overhead Press", "weightReps", "Sağ işaret parmağı uyuşursa kes → Half-Kneeling DB Press"),
            .init("Bulgarian Split Squat", "weightReps", "gövde dik/hafif öne"),
            .init("Glute Bridge / Hip Thrust", "reps", "topuktan it; beli yaylandırma"),
            .init("Wall Slide", "reps", "temas kaybolmadan"),
            .init("Dead Bug", "reps", "bel yerden kalkmasın"),
            .init("Copenhagen Plank", "duration", "aşama: diz → ayak sehpada"),
        ],
        [
            .init("Reverse Lunge (DB)", "weightReps", "ağırlık ön ayakta"),
            .init("Nordic Hamstring Curl", "reps", "İlk 2 hafta 2×3'ü aşma (DOMS)"),
            .init("Pull-up / bantlı", "reps", "skapular set; zorsa bant", needsRepsSeed: true),
            .init("Bantlı / Tek Kol Row", "reps", "bitişte en zor"),
            .init("Half-Kneeling DB Press", "weightReps", "OHP'de semptomda dönüş yeri"),
            .init("DB Lateral Raise", "weightReps", "omuz hizasında dur"),
            .init("Farmer's Carry", "steps", "en ağır 2 DB"),
            .init("Curl", "weightReps", "curl 10 kg başlangıç"),
            .init("Triceps", "reps", "başlangıç ağırlığını ilk kayıtta seç"),
            .init("Side Plank / Pallof", "duration", "kalça düşerse bitti"),
        ],
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWeekABCAndAllTwentySevenSeedExercisesPublishMeasurementAndSafety() {
        var auditedExerciseCount = 0

        for (dayIndex, exercises) in days.enumerated() {
            let app = launch(scenario: "m1-acceptance-catalog")
            selectTraining(in: app)
            tap("training.day-row.\(dayIndex)", in: app)

            if identified("session.ohp.question", in: app).waitForExistence(timeout: 1) {
                tap("session.ohp.prior.symptom-free", in: app)
            }
            tap("session.warmup.skip", in: app)

            for exercise in exercises {
                let name = require(
                    app.staticTexts["session.exercise.name"],
                    "Every seed exercise must publish a semantic name."
                )
                waitForLabel(exercise.name, on: name)
                require(
                    identified("session.set.family.\(exercise.family)", in: app),
                    "\(exercise.name) must publish its exact measurement family."
                )
                XCTAssertEqual(
                    require(
                        app.staticTexts["session.exercise.safety"],
                        "\(exercise.name) must publish its safety note."
                    ).label,
                    exercise.safety
                )

                if auditedExerciseCount == 0 {
                    attachScreenshot(named: "m1-acceptance-catalog")
                }
                if exercise.family == "weightReps" {
                    tap("session.set.weight.increment", in: app)
                }
                if exercise.needsRepsSeed {
                    tap("session.set.reps.increment", in: app)
                }
                tap("session.set.save", in: app)
                waitForLabel(
                    "1 / 1",
                    on: require(
                        app.staticTexts["session.exercise.completedSets"],
                        "The acceptance fixture must reduce each exercise to one working set."
                    )
                )
                tap("session.exercise.next", in: app)
                auditedExerciseCount += 1
            }

            require(
                identified("session.stage.cooldown", in: app),
                "Every exact A/B/C catalog must finish at cooldown."
            )
            app.terminate()
        }

        XCTAssertEqual(auditedExerciseCount, 27)
    }

    func testMissingRIRAndUnansweredOHPCannotPublishAnIncrease() {
        let missingRIR = launch(scenario: "progression-missing-rir")
        tap("today.action.primary", in: missingRIR)
        tap("session.warmup.skip", in: missingRIR)
        let hold = require(
            missingRIR.staticTexts["session.exercise.recommendation"],
            "Missing RIR needs a visible progression hold."
        )
        XCTAssertTrue(hold.label.contains("RIR"))
        XCTAssertFalse(hold.label.contains("+2,5"))
        missingRIR.terminate()

        let unansweredOHP = launch(scenario: "ohp-safety")
        tap("today.action.primary", in: unansweredOHP)
        require(
            identified("session.ohp.question", in: unansweredOHP),
            "An unanswered OHP history must block the deck with one explicit question."
        )
        XCTAssertFalse(identified("session.stage.exercise", in: unansweredOHP).exists)
        let visibleText = unansweredOHP.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .joined(separator: " ")
        XCTAssertFalse(visibleText.contains("+2,5"))
        attachScreenshot(named: "m1-acceptance-progression-safety")
    }

    func testFirstPerformanceIsBaselineAndOnlyARealImprovementIsPresentedAsPR() {
        let baseline = launch(scenario: "m1-pr-baseline")
        openFirstTrainingDay(in: baseline)
        tap("session.warmup.skip", in: baseline)
        tap("session.set.weight.increment", in: baseline)
        tap("session.set.save", in: baseline)
        tap("session.exercise.finish-incomplete", in: baseline)
        require(
            identified("session.stage.summary", in: baseline),
            "The baseline fixture must reach summary."
        )
        XCTAssertFalse(
            identified("session.summary.personalRecords", in: baseline).exists,
            "A first performance is a baseline, never a personal record."
        )
        baseline.terminate()

        let improved = launch(scenario: "m1-pr-new")
        openFirstTrainingDay(in: improved)
        tap("session.warmup.skip", in: improved)
        tap("session.set.weight.increment", in: improved)
        tap("session.set.save", in: improved)
        tap("session.exercise.finish-incomplete", in: improved)
        let records = require(
            identified("session.summary.personalRecords", in: improved),
            "A real improvement over stored history must be presented as a PR."
        )
        XCTAssertFalse(records.label.isEmpty)
        attachScreenshot(named: "m1-acceptance-personal-records")
    }

    func testHapticKillSwitchPersistsAcrossRelaunch() {
        let storeIdentifier = UUID()
        let first = launch(scenario: "seeded", storeIdentifier: storeIdentifier)
        selectSettings(in: first)
        let firstToggle = require(
            first.switches["settings.haptics-toggle"],
            "Settings must expose the persisted haptic kill switch."
        )
        waitForValue("1", on: firstToggle)
        firstToggle.tap()
        waitForValue("0", on: firstToggle)
        first.terminate()

        let relaunched = launch(scenario: "seeded", storeIdentifier: storeIdentifier)
        selectSettings(in: relaunched)
        let persistedToggle = require(
            relaunched.switches["settings.haptics-toggle"],
            "The haptic kill switch must exist after relaunch."
        )
        waitForValue("0", on: persistedToggle)
        attachScreenshot(named: "m1-acceptance-haptics-disabled")
    }

    private func launch(
        scenario: String,
        storeIdentifier: UUID? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-test-scenario", scenario,
            "-ui-test-appearance", "light",
            "-AppleLanguages", "(tr)",
            "-AppleLocale", "tr_TR",
        ]
        if let storeIdentifier {
            app.launchArguments += [
                "-ui-test-store-identifier",
                storeIdentifier.uuidString,
            ]
        }
        app.launch()
        require(
            identified("root.today.content", in: app),
            "Every M1 acceptance fixture must load through real Today content."
        )
        return app
    }

    private func openFirstTrainingDay(in app: XCUIApplication) {
        selectTraining(in: app)
        tap("training.day-row.0", in: app)
    }

    private func selectTraining(in app: XCUIApplication) {
        tap("tab.training", in: app)
        require(
            identified("root.training.content", in: app),
            "Training content must finish loading."
        )
    }

    private func selectSettings(in app: XCUIApplication) {
        tap("tab.settings", in: app)
        require(
            identified("root.settings.content", in: app),
            "Settings content must finish loading."
        )
    }

    private func tap(_ identifier: String, in app: XCUIApplication) {
        let element = require(identified(identifier, in: app), "Missing action \(identifier).")
        makeHittable(element, in: app)
        XCTAssertTrue(element.isHittable, "\(identifier) must become hittable.")
        element.tap()
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var remainingScrolls = 14
        while !element.isHittable, remainingScrolls > 0 {
            let frame = element.frame
            if !frame.isEmpty, frame.midY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            remainingScrolls -= 1
        }
    }

    private func waitForLabel(_ expected: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 8),
            .completed,
            "Expected label \(expected); found \(element.label)."
        )
    }

    private func waitForValue(_ expected: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expected),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 8),
            .completed,
            "Expected value \(expected); found \(String(describing: element.value))."
        )
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
