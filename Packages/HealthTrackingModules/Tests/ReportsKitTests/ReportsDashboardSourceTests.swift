import Foundation
@testable import ReportsKit
import XCTest

final class ReportsDashboardSourceTests: XCTestCase {
    func testDefaultSourceHasEmptyCoverageAndNoProjectionRecords() {
        let source = ReportsDashboardSource()

        XCTAssertEqual(source.coverage, .empty)
        XCTAssertTrue(source.bodyMetricRecords.isEmpty)
        XCTAssertTrue(source.exerciseSetRecords.isEmpty)
        XCTAssertTrue(source.nutritionDayRecords.isEmpty)
    }

    func testSourcePreservesCallerProjectionRecordsWithoutReorderingOrDerivation() throws {
        let body = ReportBodyMetricRecord(
            id: try id("00000000-0000-4000-8000-000000000101"),
            date: try date("2024-03-20T09:00:00Z"),
            createdAt: try date("2024-03-20T09:00:01Z"),
            kind: .custom,
            customName: "Chest",
            value: 104.5,
            unit: "cm"
        )
        let exercise = ReportExerciseSetRecord(
            id: try id("00000000-0000-4000-8000-000000000201"),
            createdAt: try date("2024-03-21T09:01:00Z"),
            sessionID: try id("00000000-0000-4000-8000-000000000202"),
            sessionDate: try date("2024-03-21T09:00:00Z"),
            sessionCreatedAt: try date("2024-03-21T08:59:00Z"),
            exerciseTemplateID: try id("00000000-0000-4000-8000-000000000203"),
            exerciseName: "Bench Press",
            setIndex: 2,
            sessionCompleted: true,
            isWarmup: false,
            measurement: .weightedRepetitions,
            weightKg: 60,
            reps: 8,
            durationSec: nil,
            distanceSteps: nil
        )
        let nutrition = ReportNutritionDayRecord(
            id: try id("00000000-0000-4000-8000-000000000301"),
            date: try date("2024-03-22T00:00:00Z"),
            createdAt: try date("2024-03-22T20:00:00Z"),
            entryCount: 3,
            proteinTotalG: 132.5,
            proteinTargetG: 140
        )
        let coverage = ReportCoverage(
            observationDates: [body.date, exercise.sessionDate, nutrition.date]
        )

        let source = ReportsDashboardSource(
            coverage: coverage,
            bodyMetricRecords: [body],
            exerciseSetRecords: [exercise],
            nutritionDayRecords: [nutrition]
        )

        XCTAssertEqual(source.coverage, coverage)
        XCTAssertEqual(source.bodyMetricRecords, [body])
        XCTAssertEqual(source.exerciseSetRecords, [exercise])
        XCTAssertEqual(source.nutritionDayRecords, [nutrition])
        XCTAssertEqual(source.bodyMetricRecords.first?.customName, "Chest")
        XCTAssertEqual(source.exerciseSetRecords.first?.exerciseName, "Bench Press")
    }

    func testOptionalNumericZerosRemainPresentRatherThanBecomingMissing() throws {
        let exercise = ReportExerciseSetRecord(
            id: try id("00000000-0000-4000-8000-000000000401"),
            createdAt: try date("2024-03-23T09:01:00Z"),
            sessionID: try id("00000000-0000-4000-8000-000000000402"),
            sessionDate: try date("2024-03-23T09:00:00Z"),
            sessionCreatedAt: try date("2024-03-23T08:59:00Z"),
            exerciseTemplateID: try id("00000000-0000-4000-8000-000000000403"),
            exerciseName: "Timed Step",
            setIndex: 0,
            sessionCompleted: true,
            isWarmup: false,
            measurement: .duration,
            weightKg: 0,
            reps: 0,
            durationSec: 0,
            distanceSteps: 0
        )
        let nutrition = ReportNutritionDayRecord(
            id: try id("00000000-0000-4000-8000-000000000404"),
            date: try date("2024-03-23T00:00:00Z"),
            createdAt: try date("2024-03-23T20:00:00Z"),
            entryCount: 1,
            proteinTotalG: 0,
            proteinTargetG: 0
        )

        XCTAssertEqual(exercise.weightKg, .some(0))
        XCTAssertEqual(exercise.reps, .some(0))
        XCTAssertEqual(exercise.durationSec, .some(0))
        XCTAssertEqual(exercise.distanceSteps, .some(0))
        XCTAssertEqual(nutrition.proteinTotalG, 0)
        XCTAssertEqual(nutrition.proteinTargetG, .some(0))
    }

    func testProjectionRecordsAndEnumsAreEquatableAndSendable() {
        assertEquatableSendable(ReportBodyMetricKind.self)
        assertEquatableSendable(ReportBodyMetricRecord.self)
        assertEquatableSendable(ReportExerciseMeasurement.self)
        assertEquatableSendable(ReportExerciseSetRecord.self)
        assertEquatableSendable(ReportNutritionDayRecord.self)
        assertEquatableSendable(ReportsDashboardSource.self)
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}

    private func id(_ value: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw ProjectionFixtureFailure.invalidID
        }
        return id
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw ProjectionFixtureFailure.invalidDate
        }
        return date
    }
}

private enum ProjectionFixtureFailure: Error {
    case invalidDate
    case invalidID
}
