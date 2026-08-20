import Foundation
@testable import GuidanceKit
import XCTest

final class WorkoutRotationTests: XCTestCase {
    private let dayA = UUID(uuidString: "00000000-0000-4000-8000-000000000201")!
    private let dayB = UUID(uuidString: "00000000-0000-4000-8000-000000000202")!
    private let dayC = UUID(uuidString: "00000000-0000-4000-8000-000000000203")!

    func testNoCompletionHistorySelectsLowestOrderTemplate() {
        let outcome = WorkoutRotation.resolve(
            templates: templatesInNonDisplayOrder(),
            completions: []
        )

        XCTAssertEqual(outcome, .next(template(id: dayA, orderIndex: 1)))
    }

    func testCompletedHistoryRotatesByOrderIndexAndWrapsFromCToA() {
        let templates = templatesInNonDisplayOrder()
        let first = Date(timeIntervalSinceReferenceDate: 1_000)
        let second = Date(timeIntervalSinceReferenceDate: 2_000)

        XCTAssertEqual(
            WorkoutRotation.resolve(
                templates: templates,
                completions: [completion(id: 1, templateID: dayA, at: first)]
            ),
            .next(template(id: dayB, orderIndex: 2))
        )
        XCTAssertEqual(
            WorkoutRotation.resolve(
                templates: templates,
                completions: [
                    completion(id: 1, templateID: dayA, at: first),
                    completion(id: 2, templateID: dayB, at: second)
                ]
            ),
            .next(template(id: dayC, orderIndex: 3))
        )
        XCTAssertEqual(
            WorkoutRotation.resolve(
                templates: templates,
                completions: [completion(id: 3, templateID: dayC, at: second)]
            ),
            .next(template(id: dayA, orderIndex: 1))
        )
    }

    func testLatestCompletionUsesTimestampRatherThanInputOrder() {
        let outcome = WorkoutRotation.resolve(
            templates: templatesInNonDisplayOrder(),
            completions: [
                completion(id: 2, templateID: dayB, at: Date(timeIntervalSinceReferenceDate: 2_000)),
                completion(id: 1, templateID: dayA, at: Date(timeIntervalSinceReferenceDate: 1_000))
            ]
        )

        XCTAssertEqual(outcome, .next(template(id: dayC, orderIndex: 3)))
    }

    func testEmptyDuplicateAndUnknownTemplateInputsReturnExplicitInvalidData() {
        let duplicateID = [
            template(id: dayA, orderIndex: 1),
            template(id: dayA, orderIndex: 2)
        ]
        let duplicateOrder = [
            template(id: dayA, orderIndex: 1),
            template(id: dayB, orderIndex: 1)
        ]
        let unknownID = UUID(uuidString: "00000000-0000-4000-8000-000000000999")!

        XCTAssertEqual(
            WorkoutRotation.resolve(templates: [], completions: []),
            .invalid(.missingTemplates)
        )
        XCTAssertEqual(
            WorkoutRotation.resolve(templates: duplicateID, completions: []),
            .invalid(.duplicateTemplateID(dayA))
        )
        XCTAssertEqual(
            WorkoutRotation.resolve(templates: duplicateOrder, completions: []),
            .invalid(.duplicateOrderIndex(1))
        )
        XCTAssertEqual(
            WorkoutRotation.resolve(
                templates: templatesInNonDisplayOrder(),
                completions: [completion(id: 1, templateID: unknownID, at: .now)]
            ),
            .invalid(.unknownCompletedTemplate(unknownID))
        )
    }

    func testPublicRotationValuesAreEquatableAndSendable() {
        assertEquatableSendable(WorkoutRotation.Template.self)
        assertEquatableSendable(WorkoutRotation.Completion.self)
        assertEquatableSendable(WorkoutRotation.DataError.self)
        assertEquatableSendable(WorkoutRotation.Outcome.self)
    }

    private func templatesInNonDisplayOrder() -> [WorkoutRotation.Template] {
        [
            template(id: dayC, orderIndex: 3),
            template(id: dayA, orderIndex: 1),
            template(id: dayB, orderIndex: 2)
        ]
    }

    private func template(id: UUID, orderIndex: Int) -> WorkoutRotation.Template {
        .init(id: id, orderIndex: orderIndex)
    }

    private func completion(id value: Int, templateID: UUID, at date: Date) -> WorkoutRotation.Completion {
        .init(
            id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!,
            templateID: templateID,
            completedAt: date
        )
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
