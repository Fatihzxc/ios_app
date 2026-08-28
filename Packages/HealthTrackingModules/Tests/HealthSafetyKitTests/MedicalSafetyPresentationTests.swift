import Foundation
@testable import HealthSafetyKit
import XCTest

final class MedicalSafetyPresentationTests: XCTestCase {
    private let frozenDisclaimer =
        "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."
    private let expectedGeneralMessage =
        "Hareketi durdur. Kalıcı veya kötüleşen belirtiler bir sağlık profesyoneli "
        + "tarafından değerlendirilmelidir. Yeni veya belirgin şekilde kötüleşen kol veya "
        + "bacakta güçsüzlük ya da uyuşma, el becerisinde kayıp, denge veya yürümede "
        + "değişiklik ya da mesane veya bağırsak işlevinde değişiklik acil tıbbi "
        + "değerlendirme gerektirir."
    private let expectedUrgentMessage =
        "Hareketi durdur. Yeni veya belirgin şekilde kötüleşen kol veya bacakta "
        + "güçsüzlük ya da uyuşma, el becerisinde kayıp, denge veya yürümede "
        + "değişiklik ya da mesane veya bağırsak "
        + "işlevinde değişiklik acil tıbbi değerlendirme gerektirir."

    func testPermanentDisclaimerUsesTheFrozenTurkishCopy() {
        XCTAssertEqual(
            MedicalDisclaimerPresentation.permanent.text,
            frozenDisclaimer
        )
        XCTAssertTrue(MedicalDisclaimerPresentation.permanent.isAlwaysVisible)
    }

    func testNoTriggerPublishesOnlyThePermanentDisclaimer() {
        let presentation = MedicalSafetyPresentation.resolve(triggers: [])

        XCTAssertEqual(presentation.disclaimer.text, frozenDisclaimer)
        XCTAssertNil(presentation.levelTwo)
    }

    // Mutation caught: replacing either general trigger with a vague warning would
    // omit the complete professional-assessment and cervical red-flag information.
    func testOHPAndIncreasingSymptomsPublishCompleteGeneralLevelTwoInformation() throws {
        for trigger in [
            MedicalSafetyTrigger.overheadPressSymptom,
            .increasingSymptom,
        ] {
            try assertCompleteGeneralNotice(for: trigger)
        }
    }

    // Mutation caught: defining a missing-answer case without resolving it would
    // leave structured OHP .notAsked/.uncertain responses without fail-closed L2.
    func testMissingSymptomAnswerPublishesCompleteNonUrgentFailClosedLevelTwo() throws {
        try assertCompleteGeneralNotice(for: .missingSymptomAnswer)
    }

    // Mutation caught: handling only a combined flag set, or giving any individual
    // flag lower priority than a general trigger, would leave one red flag non-urgent.
    func testEachCervicalRedFlagAlonePublishesExactUrgentMessageAndOverridesEveryGeneralTrigger() throws {
        let generalTriggers: [MedicalSafetyTrigger] = [
            .overheadPressSymptom,
            .increasingSymptom,
            .missingSymptomAnswer,
        ]

        for flag in CervicalRedFlag.allCases {
            try assertExactUrgentNotice(
                triggers: [.cervicalRedFlags([flag])]
            )

            for generalTrigger in generalTriggers {
                try assertExactUrgentNotice(
                    triggers: [generalTrigger, .cervicalRedFlags([flag])]
                )
            }
        }
    }

    private func assertCompleteGeneralNotice(
        for trigger: MedicalSafetyTrigger,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let notice = try XCTUnwrap(
            MedicalSafetyPresentation.resolve(triggers: [trigger]).levelTwo,
            file: file,
            line: line
        )

        XCTAssertEqual(
            notice.kind,
            .stopAndProfessionalAssessment,
            file: file,
            line: line
        )
        XCTAssertEqual(
            notice.message,
            expectedGeneralMessage,
            file: file,
            line: line
        )
        XCTAssertFalse(notice.requiresUrgentAssessment, file: file, line: line)
        assertContainsNoDiagnosticLanguage(notice.message, file: file, line: line)
        assertContainsNoNumericMedicalThreshold(notice.message, file: file, line: line)
    }

    private func assertExactUrgentNotice(
        triggers: Set<MedicalSafetyTrigger>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let notice = try XCTUnwrap(
            MedicalSafetyPresentation.resolve(triggers: triggers).levelTwo,
            file: file,
            line: line
        )

        XCTAssertEqual(notice.kind, .urgentAssessmentInformation, file: file, line: line)
        XCTAssertTrue(notice.requiresUrgentAssessment, file: file, line: line)
        XCTAssertEqual(notice.message, expectedUrgentMessage, file: file, line: line)
        assertContainsNoDiagnosticLanguage(notice.message, file: file, line: line)
        assertContainsNoNumericMedicalThreshold(notice.message, file: file, line: line)
    }

    private func assertContainsNoDiagnosticLanguage(
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lowered = value.lowercased(with: Locale(identifier: "tr_TR"))
        for prohibited in ["tanı", "teşhis", "hastalığın var", "normal", "anormal"] {
            XCTAssertFalse(
                lowered.contains(prohibited),
                "Safety copy must remain informational: \(prohibited)",
                file: file,
                line: line
            )
        }
    }

    private func assertContainsNoNumericMedicalThreshold(
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(
            value.range(of: #"\d"#, options: .regularExpression),
            "Safety copy must not invent a numeric medical threshold.",
            file: file,
            line: line
        )
    }
}
