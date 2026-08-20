import Foundation
@testable import GuidanceKit
import XCTest

final class PersonalRecordTests: XCTestCase {
    func testCentralEpleyEstimateUsesFullPrecisionAndRejectsInvalidInputs() throws {
        XCTAssertEqual(
            try XCTUnwrap(EpleyEstimate.calculate(weightKg: 30, reps: 10)),
            40,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(EpleyEstimate.calculate(weightKg: 17.5, reps: 8)),
            22.166_666_666_666_668,
            accuracy: 0.000_000_000_001
        )
        XCTAssertFalse(EpleyEstimate.isImprovement(40.000_000_000_1, over: 40))
        XCTAssertTrue(EpleyEstimate.isImprovement(40.000_001, over: 40))

        for invalid in [
            EpleyEstimate.calculate(weightKg: nil, reps: 10),
            EpleyEstimate.calculate(weightKg: 20, reps: nil),
            EpleyEstimate.calculate(weightKg: 0, reps: 10),
            EpleyEstimate.calculate(weightKg: -1, reps: 10),
            EpleyEstimate.calculate(weightKg: 20, reps: 0),
            EpleyEstimate.calculate(weightKg: 20, reps: -1),
        ] {
            XCTAssertNil(invalid)
        }
    }

    func testWeightedRecordsUseEpleyWithBaselineTieNewRecordAndWarmupExclusion() {
        let warmup = attempt(1, .weightedReps(weightKg: 10, reps: 20), isWarmup: true)
        let invalid = attempt(2, .weightedReps(weightKg: nil, reps: 10))
        let baseline = attempt(3, .weightedReps(weightKg: 20, reps: 10))
        let tie = attempt(4, .weightedReps(weightKg: 20, reps: 10))
        let record = attempt(5, .weightedReps(weightKg: 20, reps: 11))

        let results = resultMap(
            PersonalRecordDetector.evaluate([record, invalid, tie, warmup, baseline])
        )

        XCTAssertEqual(results[warmup.id]?.outcome, .excluded(.warmupSet))
        XCTAssertEqual(results[invalid.id]?.outcome, .excluded(.invalidMeasurement))
        XCTAssertEqual(
            results[baseline.id]?.outcome,
            .baseline(value: 26.666_666_666_666_664)
        )
        XCTAssertEqual(
            results[tie.id]?.outcome,
            .notRecord(
                value: 26.666_666_666_666_664,
                previousBest: 26.666_666_666_666_664
            )
        )
        XCTAssertEqual(
            results[record.id]?.outcome,
            .newRecord(
                value: 27.333_333_333_333_332,
                previousBest: 26.666_666_666_666_664
            )
        )
    }

    func testBodyweightRepsAndDurationCompareOnlyTheSameNormalizedVariant() {
        let pushupBaseline = attempt(
            1,
            .bodyweightReps(reps: 10, performedVariant: "Push-up")
        )
        let inclineBaseline = attempt(
            2,
            .bodyweightReps(reps: 20, performedVariant: "Incline Push-up")
        )
        let pushupRecord = attempt(
            3,
            .bodyweightReps(reps: 11, performedVariant: " Push-up ")
        )
        let plankBaseline = attempt(
            4,
            .duration(seconds: 30, performedVariant: "Plank")
        )
        let pallofBaseline = attempt(
            5,
            .duration(seconds: 60, performedVariant: "Pallof")
        )
        let plankRecord = attempt(
            6,
            .duration(seconds: 31, performedVariant: "Plank")
        )

        let results = resultMap(
            PersonalRecordDetector.evaluate([
                plankRecord,
                inclineBaseline,
                pushupRecord,
                pallofBaseline,
                pushupBaseline,
                plankBaseline,
            ])
        )

        XCTAssertEqual(results[pushupBaseline.id]?.outcome, .baseline(value: 10))
        XCTAssertEqual(results[inclineBaseline.id]?.outcome, .baseline(value: 20))
        XCTAssertEqual(
            results[pushupRecord.id]?.outcome,
            .newRecord(value: 11, previousBest: 10)
        )
        XCTAssertEqual(results[plankBaseline.id]?.outcome, .baseline(value: 30))
        XCTAssertEqual(results[pallofBaseline.id]?.outcome, .baseline(value: 60))
        XCTAssertEqual(
            results[plankRecord.id]?.outcome,
            .newRecord(value: 31, previousBest: 30)
        )
    }

    func testMissingVariantFormsOneDefaultGroupButNeverBeatsADifferentVariant() {
        let defaultBaseline = attempt(
            1,
            .bodyweightReps(reps: 8, performedVariant: nil)
        )
        let namedBaseline = attempt(
            2,
            .bodyweightReps(reps: 20, performedVariant: "Band")
        )
        let defaultRecord = attempt(
            3,
            .bodyweightReps(reps: 9, performedVariant: " \n ")
        )

        let results = resultMap(
            PersonalRecordDetector.evaluate([
                namedBaseline,
                defaultRecord,
                defaultBaseline,
            ])
        )

        XCTAssertEqual(results[defaultBaseline.id]?.outcome, .baseline(value: 8))
        XCTAssertEqual(results[namedBaseline.id]?.outcome, .baseline(value: 20))
        XCTAssertEqual(
            results[defaultRecord.id]?.outcome,
            .newRecord(value: 9, previousBest: 8)
        )
    }

    func testStepsRequireMoreStepsAtTheSameOrHigherActualLoad() {
        let baseline = attempt(1, .steps(count: 100, loadKg: 10))
        let lowerLoadMoreSteps = attempt(2, .steps(count: 120, loadKg: 5))
        let higherLoadFewerSteps = attempt(3, .steps(count: 90, loadKg: 15))
        let sameLoadRecord = attempt(4, .steps(count: 101, loadKg: 10))
        let higherLoadRecord = attempt(5, .steps(count: 102, loadKg: 20))

        let results = resultMap(
            PersonalRecordDetector.evaluate([
                higherLoadRecord,
                sameLoadRecord,
                lowerLoadMoreSteps,
                baseline,
                higherLoadFewerSteps,
            ])
        )

        XCTAssertEqual(results[baseline.id]?.outcome, .baseline(value: 100))
        XCTAssertEqual(
            results[lowerLoadMoreSteps.id]?.outcome,
            .notRecord(value: 120, previousBest: 100)
        )
        XCTAssertEqual(
            results[higherLoadFewerSteps.id]?.outcome,
            .notRecord(value: 90, previousBest: 100)
        )
        XCTAssertEqual(
            results[sameLoadRecord.id]?.outcome,
            .newRecord(value: 101, previousBest: 100)
        )
        XCTAssertEqual(
            results[higherLoadRecord.id]?.outcome,
            .newRecord(value: 102, previousBest: 101)
        )
    }

    func testOptionalStepLoadBehavesAsZeroExternalLoad() {
        let unloaded = attempt(1, .steps(count: 50, loadKg: nil))
        let loaded = attempt(2, .steps(count: 51, loadKg: 5))
        let unloadedAgain = attempt(3, .steps(count: 100, loadKg: nil))
        let results = resultMap(
            PersonalRecordDetector.evaluate([unloadedAgain, loaded, unloaded])
        )

        XCTAssertEqual(results[unloaded.id]?.outcome, .baseline(value: 50))
        XCTAssertEqual(
            results[loaded.id]?.outcome,
            .newRecord(value: 51, previousBest: 50)
        )
        XCTAssertEqual(
            results[unloadedAgain.id]?.outcome,
            .notRecord(value: 100, previousBest: 51)
        )
    }

    func testTiesAndEveryInvalidMeasurementNeverProduceARecord() {
        let invalidAttempts = [
            attempt(1, .bodyweightReps(reps: nil, performedVariant: nil)),
            attempt(2, .bodyweightReps(reps: 0, performedVariant: nil)),
            attempt(3, .duration(seconds: nil, performedVariant: "Plank")),
            attempt(4, .duration(seconds: -1, performedVariant: "Plank")),
            attempt(5, .steps(count: nil, loadKg: 10)),
            attempt(6, .steps(count: 0, loadKg: 10)),
            attempt(7, .steps(count: 10, loadKg: -1)),
        ]
        let results = PersonalRecordDetector.evaluate(invalidAttempts)

        XCTAssertEqual(results.count, invalidAttempts.count)
        XCTAssertTrue(results.allSatisfy { $0.outcome == .excluded(.invalidMeasurement) })
    }

    func testEditedAndDeletedHistoryIsRecalculatedFromTheSuppliedAttempts() {
        let baseline = attempt(1, .bodyweightReps(reps: 10, performedVariant: "Push-up"))
        let deletedRecord = attempt(2, .bodyweightReps(reps: 12, performedVariant: "Push-up"))
        let latest = attempt(3, .bodyweightReps(reps: 11, performedVariant: "Push-up"))

        let original = resultMap(
            PersonalRecordDetector.evaluate([latest, deletedRecord, baseline])
        )
        XCTAssertEqual(
            original[latest.id]?.outcome,
            .notRecord(value: 11, previousBest: 12)
        )

        let afterDelete = resultMap(PersonalRecordDetector.evaluate([latest, baseline]))
        XCTAssertEqual(
            afterDelete[latest.id]?.outcome,
            .newRecord(value: 11, previousBest: 10)
        )

        let editedBaseline = PersonalRecordDetector.Attempt(
            id: baseline.id,
            completedAt: baseline.completedAt,
            measurement: .bodyweightReps(reps: 13, performedVariant: "Push-up")
        )
        let afterEdit = resultMap(
            PersonalRecordDetector.evaluate([latest, editedBaseline])
        )
        XCTAssertEqual(
            afterEdit[latest.id]?.outcome,
            .notRecord(value: 11, previousBest: 13)
        )
    }

    func testPublicValuesAreEquatableSendableAndInputIsImmutable() {
        let input = [attempt(1, .duration(seconds: 30, performedVariant: "Plank"))]
        let copy = input
        _ = PersonalRecordDetector.evaluate(input)

        XCTAssertEqual(input, copy)
        assertEquatableSendable(PersonalRecordDetector.Measurement.self)
        assertEquatableSendable(PersonalRecordDetector.Attempt.self)
        assertEquatableSendable(PersonalRecordDetector.ExclusionReason.self)
        assertEquatableSendable(PersonalRecordDetector.Outcome.self)
        assertEquatableSendable(PersonalRecordDetector.Result.self)
    }

    private func attempt(
        _ offset: Int,
        _ measurement: PersonalRecordDetector.Measurement,
        isWarmup: Bool = false
    ) -> PersonalRecordDetector.Attempt {
        PersonalRecordDetector.Attempt(
            id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", offset))!,
            completedAt: Date(timeIntervalSinceReferenceDate: Double(offset)),
            measurement: measurement,
            isWarmupSet: isWarmup
        )
    }

    private func resultMap(
        _ results: [PersonalRecordDetector.Result]
    ) -> [UUID: PersonalRecordDetector.Result] {
        Dictionary(uniqueKeysWithValues: results.map { ($0.attemptID, $0) })
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}
