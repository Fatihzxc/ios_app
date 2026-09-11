import Foundation
@testable import ReportsKit
import XCTest

final class ProteinAdherenceBuilderTests: XCTestCase {
    func testEmptyLogIsMissingWhileActualZeroProteinEntryIsAnObservedMiss() throws {
        let report = try ProteinAdherenceBuilder.build(days: [
            day(id: 101, entryCount: 0, proteinTotalG: 0, proteinTargetG: 100),
            day(id: 102, entryCount: 1, proteinTotalG: 0, proteinTargetG: 100),
        ])

        XCTAssertEqual(report.observedDayCount, 1)
        XCTAssertEqual(report.targetDayCount, 1)
        XCTAssertEqual(report.hitDayCount, 0)
        XCTAssertEqual(report.excludedTargetlessDayCount, 0)
        XCTAssertEqual(report.adherencePercent, 0)
    }

    func testInvalidAndMissingTargetsAreExcludedAndZeroDenominatorIsNil() throws {
        let report = try ProteinAdherenceBuilder.build(days: [
            day(id: 201, entryCount: 1, proteinTotalG: 80, proteinTargetG: nil),
            day(id: 202, entryCount: 1, proteinTotalG: 80, proteinTargetG: 0),
            day(id: 203, entryCount: 1, proteinTotalG: 80, proteinTargetG: -1),
            day(id: 204, entryCount: 1, proteinTotalG: 80, proteinTargetG: .nan),
            day(id: 205, entryCount: 1, proteinTotalG: 80, proteinTargetG: .infinity),
        ])

        XCTAssertEqual(report.observedDayCount, 5)
        XCTAssertEqual(report.targetDayCount, 0)
        XCTAssertEqual(report.hitDayCount, 0)
        XCTAssertEqual(report.excludedTargetlessDayCount, 5)
        XCTAssertNil(report.adherencePercent)
        XCTAssertEqual(report.provenance, .currentProfileAppliedToObservedDays)
    }

    func testAdherenceUsesOnlyObservedDaysWithValidCurrentProfileTarget() throws {
        let report = try ProteinAdherenceBuilder.build(days: [
            day(id: 301, entryCount: 1, proteinTotalG: 99.999, proteinTargetG: 100),
            day(id: 302, entryCount: 2, proteinTotalG: 100, proteinTargetG: 100),
            day(id: 303, entryCount: 3, proteinTotalG: 150, proteinTargetG: 100),
            day(id: 304, entryCount: 0, proteinTotalG: 0, proteinTargetG: 100),
        ])

        XCTAssertEqual(report.observedDayCount, 3)
        XCTAssertEqual(report.targetDayCount, 3)
        XCTAssertEqual(report.hitDayCount, 2)
        XCTAssertEqual(report.excludedTargetlessDayCount, 0)
        XCTAssertEqual(
            try XCTUnwrap(report.adherencePercent),
            200.0 / 3.0,
            accuracy: 0.000_000_000_001
        )
        XCTAssertEqual(report.provenance, .currentProfileAppliedToObservedDays)
    }

    func testDuplicateObservedDayFailsWithStableIDsRegardlessOfInputOrder() throws {
        let lower = day(
            id: 401,
            entryCount: 1,
            proteinTotalG: 40,
            proteinTargetG: 100,
            dayOffset: 1
        )
        let higher = day(
            id: 402,
            entryCount: 1,
            proteinTotalG: 60,
            proteinTargetG: 100,
            dayOffset: 1
        )

        for records in [[higher, lower], [lower, higher]] {
            XCTAssertThrowsError(try ProteinAdherenceBuilder.build(days: records)) { error in
                XCTAssertEqual(
                    error as? ProteinAdherenceBuilderError,
                    .duplicateObservedDay(
                        date: lower.date,
                        recordIDs: [lower.id, higher.id]
                    )
                )
            }
        }
    }

    func testInvalidObservedDayFailureSelectsLowestStableID() throws {
        let lower = day(
            id: 501,
            entryCount: 1,
            proteinTotalG: -.infinity,
            proteinTargetG: 100,
            dayOffset: 1
        )
        let higher = day(
            id: 502,
            entryCount: 1,
            proteinTotalG: .nan,
            proteinTargetG: 100,
            dayOffset: 2
        )

        for records in [[higher, lower], [lower, higher]] {
            XCTAssertThrowsError(try ProteinAdherenceBuilder.build(days: records)) { error in
                XCTAssertEqual(
                    error as? ProteinAdherenceBuilderError,
                    .invalidObservedDay(id: lower.id)
                )
            }
        }
    }

    func testProteinReportContractsAreEquatableAndSendable() {
        assertEquatableSendable(ProteinTargetProvenance.self)
        assertEquatableSendable(ProteinAdherenceBuilderError.self)
        assertEquatableSendable(ProteinAdherenceReport.self)
    }

    private func day(
        id suffix: Int,
        entryCount: Int,
        proteinTotalG: Double,
        proteinTargetG: Double?,
        dayOffset: Int? = nil
    ) -> ReportNutritionDayRecord {
        let date = Date(timeIntervalSinceReferenceDate: Double((dayOffset ?? suffix) * 1_000))
        return ReportNutritionDayRecord(
            id: uuid(suffix),
            date: date,
            createdAt: date.addingTimeInterval(1),
            entryCount: entryCount,
            proteinTotalG: proteinTotalG,
            proteinTargetG: proteinTargetG
        )
    }

    private func uuid(_ suffix: Int) -> UUID {
        guard let value = UUID(
            uuidString: String(format: "00000000-0000-4000-8000-%012d", suffix)
        ) else {
            preconditionFailure("Invalid UUID fixture suffix: \(suffix)")
        }
        return value
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
