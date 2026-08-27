import Foundation
@testable import HealthSafetyKit
import XCTest

final class MedicalSafetyPresentationTests: XCTestCase {
    private let frozenDisclaimer =
        "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir."

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

    // Mutation caught: replacing the safety notice with a vague warning would omit
    // the required stop, persistent/worsening, or professional-assessment guidance.
    func testOHPAndExplicitWorseningPublishTheRequiredGeneralStopNotice() throws {
        for trigger in [
            MedicalSafetyTrigger.overheadPressSymptom,
            .increasingSymptom,
        ] {
            let notice = try XCTUnwrap(
                MedicalSafetyPresentation.resolve(triggers: [trigger]).levelTwo
            )

            XCTAssertEqual(notice.kind, .stopAndProfessionalAssessment)
            XCTAssertTrue(notice.message.hasPrefix("Hareketi durdur."))
            XCTAssertTrue(notice.message.contains("kalıcı veya kötüleşen"))
            XCTAssertTrue(notice.message.contains("sağlık profesyoneli"))
            XCTAssertFalse(notice.requiresUrgentAssessment)
            assertContainsNoDiagnosticLanguage(notice.message)
        }
    }

    // Mutation caught: dropping the new/significantly-worsening qualification or
    // any cervical red flag would turn an urgent-information notice into a vague one.
    func testExplicitCervicalRedFlagPublishesQualifiedUrgentInformationWithoutDiagnosis() throws {
        let flags = Set(CervicalRedFlag.allCases)
        let notice = try XCTUnwrap(
            MedicalSafetyPresentation.resolve(
                triggers: [.cervicalRedFlags(flags)]
            ).levelTwo
        )

        XCTAssertEqual(notice.kind, .urgentAssessmentInformation)
        XCTAssertTrue(notice.message.hasPrefix("Hareketi durdur."))
        XCTAssertTrue(notice.requiresUrgentAssessment)
        XCTAssertTrue(notice.message.contains("yeni veya belirgin şekilde kötüleşen"))
        XCTAssertTrue(notice.message.contains("kol veya bacakta güçsüzlük ya da uyuşma"))
        XCTAssertTrue(notice.message.contains("el becerisinde kayıp"))
        XCTAssertTrue(notice.message.contains("denge veya yürümede değişiklik"))
        XCTAssertTrue(notice.message.contains("mesane veya bağırsak işlevinde değişiklik"))
        XCTAssertTrue(notice.message.contains("acil tıbbi değerlendirme"))
        assertContainsNoDiagnosticLanguage(notice.message)
    }

    func testRedFlagNoticeTakesPriorityOverGeneralTriggers() throws {
        let presentation = MedicalSafetyPresentation.resolve(
            triggers: [
                .overheadPressSymptom,
                .increasingSymptom,
                .cervicalRedFlags([.balanceOrWalkingChange]),
            ]
        )

        XCTAssertEqual(
            try XCTUnwrap(presentation.levelTwo).kind,
            .urgentAssessmentInformation
        )
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
}
