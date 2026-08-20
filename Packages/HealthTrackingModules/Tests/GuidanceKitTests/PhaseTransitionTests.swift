import Foundation
@testable import GuidanceKit
import XCTest

final class PhaseTransitionTests: XCTestCase {
    private let currentID = UUID(uuidString: "00000000-0000-4000-8000-000000000a01")!
    private let nextID = UUID(uuidString: "00000000-0000-4000-8000-000000000a02")!
    private let finalID = UUID(uuidString: "00000000-0000-4000-8000-000000000a03")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }

    func testEndOfMonthEstimateUsesCalendarAndBecomesDueAtTheExactBoundary() throws {
        let start = date(2026, 1, 31, 10)
        let estimatedStart = try XCTUnwrap(
            calendar.date(byAdding: .month, value: 1, to: start)
        )
        let input = PhaseTransition.Input(
            programStartDate: start,
            currentPhaseID: currentID,
            phases: phases(),
            evaluatedAt: estimatedStart.addingTimeInterval(-1)
        )

        guard case let .upcoming(upcoming) = PhaseTransition.evaluate(
            input,
            calendar: calendar
        ) else {
            XCTFail("The next phase must remain upcoming before its calendar boundary.")
            return
        }
        XCTAssertEqual(upcoming.estimatedStart, estimatedStart)
        XCTAssertEqual(upcoming.nextPhaseID, nextID)

        guard case let .review(review) = PhaseTransition.evaluate(
            .init(
                programStartDate: start,
                currentPhaseID: currentID,
                phases: phases(),
                evaluatedAt: estimatedStart
            ),
            calendar: calendar
        ) else {
            XCTFail("The checklist must become reviewable at the exact boundary.")
            return
        }
        XCTAssertEqual(review.estimatedStart, estimatedStart)
    }

    func testNextPhaseUsesOrderRatherThanInputOrderAndLastPhaseDoesNotInventANextPhase() {
        let start = date(2026, 1, 1)
        let shuffled = [phases()[2], phases()[0], phases()[1]]

        guard case let .review(review) = PhaseTransition.evaluate(
            .init(
                programStartDate: start,
                currentPhaseID: currentID,
                phases: shuffled,
                evaluatedAt: date(2026, 2, 1)
            ),
            calendar: calendar
        ) else {
            XCTFail("Expected the next ordered phase to be reviewable.")
            return
        }
        XCTAssertEqual(review.currentPhaseID, currentID)
        XCTAssertEqual(review.nextPhaseID, nextID)

        XCTAssertEqual(
            PhaseTransition.evaluate(
                .init(
                    programStartDate: start,
                    currentPhaseID: finalID,
                    phases: shuffled,
                    evaluatedAt: date(2027, 1, 1)
                ),
                calendar: calendar
            ),
            .finalPhase(currentPhaseID: finalID)
        )
    }

    func testChecklistUsesOnlyNonEmptySourceCriteriaAndMilestoneWithoutInventedThresholds() {
        let sourceCriteria = "Teknik rahat ve rutin sürdürülebilir"
        let sourceMilestone = "Temel faz tamamlandı"
        let sourcePhases = [
            phase(id: currentID, order: 1, start: 1, end: 1),
            phase(
                id: nextID,
                order: 2,
                start: 2,
                end: 4,
                entryCriteria: "  \(sourceCriteria)  ",
                milestone: sourceMilestone
            ),
        ]

        guard case let .review(review) = PhaseTransition.evaluate(
            .init(
                programStartDate: date(2026, 1, 1),
                currentPhaseID: currentID,
                phases: sourcePhases,
                evaluatedAt: date(2026, 2, 1)
            ),
            calendar: calendar
        ) else {
            XCTFail("Expected a phase review.")
            return
        }
        XCTAssertEqual(
            review.checklist,
            [
                .init(kind: .entryCriteria, text: sourceCriteria),
                .init(kind: .milestone, text: sourceMilestone),
            ]
        )
        XCTAssertFalse(
            review.checklist
                .map(\.text)
                .joined()
                .contains(where: { $0.isNumber })
        )

        let emptyTextPhases = [
            phase(id: currentID, order: 1, start: 1, end: 1),
            phase(
                id: nextID,
                order: 2,
                start: 2,
                end: 4,
                entryCriteria: " \n\t ",
                milestone: ""
            ),
        ]
        guard case let .review(emptyReview) = PhaseTransition.evaluate(
            .init(
                programStartDate: date(2026, 1, 1),
                currentPhaseID: currentID,
                phases: emptyTextPhases,
                evaluatedAt: date(2026, 2, 1)
            ),
            calendar: calendar
        ) else {
            XCTFail("Missing source text must not prevent an explicit review.")
            return
        }
        XCTAssertTrue(emptyReview.checklist.isEmpty)
    }

    func testConfirmSelectsNextPhaseWhileStayKeepsCurrentAndCreatesNoSilenceInterval() {
        let reviewedAt = date(2026, 2, 1, 9)
        let review = PhaseTransition.Review(
            currentPhaseID: currentID,
            nextPhaseID: nextID,
            estimatedStart: reviewedAt,
            checklist: []
        )

        XCTAssertEqual(
            PhaseTransition.resolve(review, choice: .confirm, at: reviewedAt),
            .init(
                selectedPhaseID: nextID,
                phaseStartedAt: reviewedAt,
                dismissesPriority: true,
                automaticReevaluationAt: nil
            )
        )
        XCTAssertEqual(
            PhaseTransition.resolve(review, choice: .stay, at: reviewedAt),
            .init(
                selectedPhaseID: currentID,
                phaseStartedAt: nil,
                dismissesPriority: true,
                automaticReevaluationAt: nil
            )
        )
    }

    func testMissingCurrentPhaseIsUnavailableAndEvaluationDoesNotMutateInput() {
        let input = PhaseTransition.Input(
            programStartDate: date(2026, 1, 1),
            currentPhaseID: UUID(),
            phases: phases(),
            evaluatedAt: date(2026, 2, 1)
        )
        let copy = input

        XCTAssertEqual(
            PhaseTransition.evaluate(input, calendar: calendar),
            .unavailable(.currentPhaseMissing)
        )
        XCTAssertEqual(input, copy)
        assertEquatableSendable(PhaseTransition.Phase.self)
        assertEquatableSendable(PhaseTransition.ChecklistKind.self)
        assertEquatableSendable(PhaseTransition.ChecklistItem.self)
        assertEquatableSendable(PhaseTransition.Input.self)
        assertEquatableSendable(PhaseTransition.Review.self)
        assertEquatableSendable(PhaseTransition.Recommendation.self)
        assertEquatableSendable(PhaseTransition.Choice.self)
        assertEquatableSendable(PhaseTransition.Resolution.self)
    }

    private func phases() -> [PhaseTransition.Phase] {
        [
            phase(id: currentID, order: 1, start: 1, end: 1),
            phase(
                id: nextID,
                order: 2,
                start: 2,
                end: 4,
                entryCriteria: "Temel tamamlandı",
                milestone: "İnşa fazına hazır"
            ),
            phase(id: finalID, order: 3, start: 5, end: 8),
        ]
    }

    private func phase(
        id: UUID,
        order: Int,
        start: Int,
        end: Int,
        entryCriteria: String = "",
        milestone: String = ""
    ) -> PhaseTransition.Phase {
        .init(
            id: id,
            orderIndex: order,
            monthStart: start,
            monthEnd: end,
            entryCriteria: entryCriteria,
            milestone: milestone
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
