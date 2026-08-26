import CoreModels
import Foundation
@testable import MetricsKit
import XCTest

final class BodyMetricInputTests: XCTestCase {
    func testWeightAndWaistRequirePositiveFiniteCanonicalValues() throws {
        XCTAssertEqual(
            try BodyMetricValueInput.weight(kilograms: 82.5),
            try BodyMetricValueInput(
                type: .weight,
                customName: nil,
                value: 82.5,
                unit: "kg"
            )
        )
        XCTAssertEqual(
            try BodyMetricValueInput.waist(centimeters: 91.25),
            try BodyMetricValueInput(
                type: .waist,
                customName: nil,
                value: 91.25,
                unit: "cm"
            )
        )

        let invalidValues: [Double] = [0, -1, .nan, .infinity, -.infinity]
        for invalid in invalidValues {
            XCTAssertThrowsError(try BodyMetricValueInput.weight(kilograms: invalid)) {
                XCTAssertEqual($0 as? BodyMetricInputError, .invalidValue(type: .weight))
            }
            XCTAssertThrowsError(try BodyMetricValueInput.waist(centimeters: invalid)) {
                XCTAssertEqual($0 as? BodyMetricInputError, .invalidValue(type: .waist))
            }
        }
    }

    func testCanonicalTypesRejectWrongUnitsAndNames() {
        XCTAssertThrowsError(
            try BodyMetricValueInput(
                type: .weight,
                customName: nil,
                value: 180,
                unit: "lb"
            )
        ) {
            XCTAssertEqual(
                $0 as? BodyMetricInputError,
                .invalidCanonicalUnit(type: .weight, expected: "kg")
            )
        }
        XCTAssertThrowsError(
            try BodyMetricValueInput(
                type: .waist,
                customName: "Bel",
                value: 90,
                unit: "cm"
            )
        ) {
            XCTAssertEqual($0 as? BodyMetricInputError, .unexpectedCustomName(type: .waist))
        }
    }

    func testCustomMetricTrimsNameAndUnitAndRejectsBlankFields() throws {
        let input = try BodyMetricValueInput.custom(
            name: "  Boyun  ",
            value: 39.5,
            unit: "  cm  "
        )

        XCTAssertEqual(input.type, .custom)
        XCTAssertEqual(input.customName, "Boyun")
        XCTAssertEqual(input.value, 39.5)
        XCTAssertEqual(input.unit, "cm")

        XCTAssertThrowsError(
            try BodyMetricValueInput.custom(name: " \n ", value: 1, unit: "cm")
        ) {
            XCTAssertEqual($0 as? BodyMetricInputError, .missingCustomName)
        }
        XCTAssertThrowsError(
            try BodyMetricValueInput.custom(name: "Boyun", value: 1, unit: " \t ")
        ) {
            XCTAssertEqual($0 as? BodyMetricInputError, .missingCustomUnit)
        }
        XCTAssertThrowsError(
            try BodyMetricValueInput.custom(name: "Boyun", value: .nan, unit: "cm")
        ) {
            XCTAssertEqual($0 as? BodyMetricInputError, .invalidValue(type: .custom))
        }
    }

    func testBatchContainsEveryNonemptyRowAndNeverCreatesBlankZero() throws {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let custom = try BodyMetricValueInput.custom(name: "Boyun", value: 39, unit: "cm")
        let batch = try BodyMetricBatchInput(
            date: date,
            weightKilograms: 82,
            waistCentimeters: 91,
            customMetrics: [custom]
        )

        XCTAssertEqual(batch.date, date)
        XCTAssertEqual(batch.values.map(\.type), [.weight, .waist, .custom])
        XCTAssertFalse(batch.values.contains(where: { $0.value == 0 }))

        let weightOnly = try BodyMetricBatchInput(
            date: date,
            weightKilograms: 82,
            waistCentimeters: nil,
            customMetrics: []
        )
        XCTAssertEqual(weightOnly.values.map(\.type), [.weight])

        XCTAssertThrowsError(
            try BodyMetricBatchInput(
                date: date,
                weightKilograms: nil,
                waistCentimeters: nil,
                customMetrics: []
            )
        ) {
            XCTAssertEqual($0 as? BodyMetricInputError, .emptyBatch)
        }

        XCTAssertThrowsError(
            try BodyMetricBatchInput(
                date: date,
                weightKilograms: nil,
                waistCentimeters: nil,
                customMetrics: [try .weight(kilograms: 80)]
            )
        ) {
            XCTAssertEqual(
                $0 as? BodyMetricInputError,
                .unexpectedBatchMetricType(.weight)
            )
        }
    }

    func testMetricAndImperialPresentationRoundTripsWithoutChangingCanonicalValue() throws {
        let weight = 82.5
        let pounds = BodyMetricUnitConverter.pounds(fromKilograms: weight)
        XCTAssertEqual(
            BodyMetricUnitConverter.kilograms(fromPounds: pounds),
            weight,
            accuracy: 0.000_001
        )

        let waist = 91.25
        let inches = BodyMetricUnitConverter.inches(fromCentimeters: waist)
        XCTAssertEqual(
            BodyMetricUnitConverter.centimeters(fromInches: inches),
            waist,
            accuracy: 0.000_001
        )
    }

    func testSnapshotsSortNewestThenCreatedThenStableUUID() {
        let older = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000303"),
            date: Date(timeIntervalSinceReferenceDate: 100),
            createdAt: Date(timeIntervalSinceReferenceDate: 500)
        )
        let earlierCreated = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000302"),
            date: Date(timeIntervalSinceReferenceDate: 200),
            createdAt: Date(timeIntervalSinceReferenceDate: 400)
        )
        let stableFirst = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000300"),
            date: Date(timeIntervalSinceReferenceDate: 200),
            createdAt: Date(timeIntervalSinceReferenceDate: 500)
        )
        let stableSecond = snapshot(
            id: uuid("00000000-0000-4000-8000-000000000301"),
            date: Date(timeIntervalSinceReferenceDate: 200),
            createdAt: Date(timeIntervalSinceReferenceDate: 500)
        )

        XCTAssertEqual(
            [older, earlierCreated, stableSecond, stableFirst]
                .sorted(by: BodyMetricOrdering.newestFirst)
                .map(\.id),
            [stableFirst.id, stableSecond.id, earlierCreated.id, older.id]
        )
    }

    private func snapshot(id: UUID, date: Date, createdAt: Date) -> BodyMetricSnapshot {
        BodyMetricSnapshot(
            id: id,
            createdAt: createdAt,
            updatedAt: createdAt,
            date: date,
            type: .weight,
            customName: nil,
            value: 80,
            unit: "kg"
        )
    }

    private func uuid(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID: \(value)")
        }
        return id
    }
}
