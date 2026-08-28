import Foundation
import HealthSafetyKit
@testable import MetricsKit
import XCTest

final class PostureMetricInputTests: XCTestCase {
    func testOptionalWallTestAndInclusiveSymptomRangePreserveExplicitZero() throws {
        let date = Date(timeIntervalSinceReferenceDate: 10_000)
        let minimum = try PostureMetricInput(
            date: date,
            wallTestPass: nil,
            symptomScore: 0,
            region: nil,
            note: nil
        )
        let maximum = try PostureMetricInput(
            date: date,
            wallTestPass: false,
            symptomScore: 10,
            region: nil,
            note: nil
        )

        XCTAssertNil(minimum.wallTestPass)
        XCTAssertEqual(minimum.symptomScore, 0)
        XCTAssertEqual(maximum.wallTestPass, false)
        XCTAssertEqual(maximum.symptomScore, 10)

        for invalid in [-1, 11, Int.min, Int.max] {
            XCTAssertThrowsError(
                try PostureMetricInput(
                    date: date,
                    wallTestPass: nil,
                    symptomScore: invalid,
                    region: nil,
                    note: nil
                )
            ) {
                XCTAssertEqual(
                    $0 as? PostureMetricInputError,
                    .invalidSymptomScore(invalid)
                )
            }
        }
    }

    func testRegionAndNoteAreTrimmedAndBlankOptionalsCollapseToNil() throws {
        let input = try PostureMetricInput(
            date: Date(timeIntervalSinceReferenceDate: 10_100),
            wallTestPass: nil,
            symptomScore: nil,
            region: "  Boyun ve sağ kol  \n",
            note: "  OHP sırasında başladı.  "
        )

        XCTAssertEqual(input.region, "Boyun ve sağ kol")
        XCTAssertEqual(input.note, "OHP sırasında başladı.")

        let wallOnly = try PostureMetricInput(
            date: input.date,
            wallTestPass: true,
            symptomScore: nil,
            region: " \t ",
            note: "\n"
        )
        XCTAssertNil(wallOnly.region)
        XCTAssertNil(wallOnly.note)
    }

    func testAtLeastOneMeaningfulFieldIsRequired() {
        XCTAssertThrowsError(
            try PostureMetricInput(
                date: Date(timeIntervalSinceReferenceDate: 10_200),
                wallTestPass: nil,
                symptomScore: nil,
                region: "   ",
                note: "\n"
            )
        ) {
            XCTAssertEqual($0 as? PostureMetricInputError, .empty)
        }
    }

    func testHistoryOrdersByDateThenCreationThenStableUUID() throws {
        let oldest = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000401"),
            date: 100,
            createdAt: 500
        )
        let earlierCreated = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000402"),
            date: 200,
            createdAt: 400
        )
        let stableFirst = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000403"),
            date: 200,
            createdAt: 500
        )
        let stableSecond = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000404"),
            date: 200,
            createdAt: 500
        )

        XCTAssertEqual(
            [oldest, earlierCreated, stableSecond, stableFirst]
                .sorted(by: PostureMetricOrdering.newestFirst)
                .map(\.id),
            [stableFirst.id, stableSecond.id, earlierCreated.id, oldest.id]
        )
    }

    func testWorseningRequiresTwoExplicitScoresAndOnlyThenProducesSafetyTrigger() {
        XCTAssertNil(PostureSymptomTrend.compare(current: nil, previous: 3))
        XCTAssertNil(PostureSymptomTrend.compare(current: 5, previous: nil))
        XCTAssertEqual(
            PostureSymptomTrend.compare(current: 5, previous: 5),
            .unchanged
        )
        XCTAssertEqual(
            PostureSymptomTrend.compare(current: 3, previous: 5),
            .decreased(by: 2)
        )

        let increasing = PostureSymptomTrend.compare(current: 7, previous: 5)
        XCTAssertEqual(increasing, .increased(by: 2))
        XCTAssertEqual(increasing?.safetyTrigger, .increasingSymptom)
        XCTAssertNil(PostureSymptomTrend.unchanged.safetyTrigger)
    }

    private func snapshot(
        id: UUID,
        date: TimeInterval,
        createdAt: TimeInterval
    ) -> PostureMetricSnapshot {
        PostureMetricSnapshot(
            id: id,
            createdAt: Date(timeIntervalSinceReferenceDate: createdAt),
            updatedAt: Date(timeIntervalSinceReferenceDate: createdAt),
            date: Date(timeIntervalSinceReferenceDate: date),
            wallTestPass: nil,
            symptomScore: 3,
            region: "Boyun",
            note: nil
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
