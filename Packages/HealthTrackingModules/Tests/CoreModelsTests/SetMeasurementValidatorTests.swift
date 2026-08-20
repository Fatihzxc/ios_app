import CoreModels
import XCTest

final class SetMeasurementValidatorTests: XCTestCase {
    func testEachMeasurementKindAcceptsItsUnambiguousInput() throws {
        let cases: [(ExerciseMeasurementKind, SetMeasurementInput)] = [
            (.weightReps, .init(weightKg: 0, reps: 8)),
            (.reps, .init(reps: 12)),
            (.duration, .init(durationSec: 30)),
            (.steps, .init(distanceSteps: 20)),
            (.quality, .init(performedVariant: "Pallof", rir: 3))
        ]

        for (kind, input) in cases {
            XCTAssertNoThrow(try SetMeasurementValidator.validate(input, for: kind))
        }
    }

    func testWeightRepsRequiresBothWeightAndRepsAndPreservesZeroWeight() throws {
        let zeroWeight = SetMeasurementInput(weightKg: 0, reps: 10)

        XCTAssertEqual(zeroWeight.weightKg, 0)
        XCTAssertNoThrow(try SetMeasurementValidator.validate(zeroWeight, for: .weightReps))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(reps: 10), for: .weightReps))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(weightKg: 0), for: .weightReps))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(), for: .weightReps))
    }

    func testEachMeasuredKindRejectsItsMissingRequiredValue() {
        let cases: [(ExerciseMeasurementKind, SetMeasurementInput)] = [
            (.reps, .init()),
            (.duration, .init()),
            (.steps, .init())
        ]

        for (kind, input) in cases {
            XCTAssertThrowsError(try SetMeasurementValidator.validate(input, for: kind))
        }
    }

    func testValidatorRejectsNonPositiveRepsDurationAndSteps() {
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(weightKg: 1, reps: 0), for: .weightReps))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(reps: -1), for: .reps))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(durationSec: 0), for: .duration))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(distanceSteps: -1), for: .steps))
    }

    func testValidatorRejectsInvalidOptionalWeightAndRIR() {
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(weightKg: .nan, reps: 1), for: .weightReps))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(weightKg: .infinity, reps: 1), for: .weightReps))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(weightKg: -.infinity, reps: 1), for: .reps))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(weightKg: -0.1, distanceSteps: 1), for: .steps))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(rir: -1), for: .quality))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(rir: 11), for: .quality))
    }

    func testRepsAndStepsAllowFiniteNonnegativeOptionalWeight() {
        XCTAssertNoThrow(try SetMeasurementValidator.validate(.init(weightKg: 0, reps: 1), for: .reps))
        XCTAssertNoThrow(try SetMeasurementValidator.validate(.init(weightKg: 2.5, distanceSteps: 1), for: .steps))
    }

    func testQualityAcceptsRecordOnlyOrOnePositiveOptionalMeasurement() {
        XCTAssertNoThrow(try SetMeasurementValidator.validate(.init(), for: .quality))
        XCTAssertNoThrow(try SetMeasurementValidator.validate(.init(reps: 1), for: .quality))
        XCTAssertNoThrow(try SetMeasurementValidator.validate(.init(durationSec: 1), for: .quality))
    }

    func testQualityRejectsAmbiguousOrNonpositiveOptionalMeasurements() {
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(reps: 1, durationSec: 1), for: .quality))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(weightKg: 1), for: .quality))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(distanceSteps: 1), for: .quality))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(reps: 0), for: .quality))
        XCTAssertThrowsError(try SetMeasurementValidator.validate(.init(durationSec: 0), for: .quality))
    }

    func testRIRBoundariesAreValid() {
        XCTAssertNoThrow(try SetMeasurementValidator.validate(.init(), for: .quality))
        XCTAssertNoThrow(try SetMeasurementValidator.validate(.init(rir: 0), for: .quality))
        XCTAssertNoThrow(try SetMeasurementValidator.validate(.init(rir: 10), for: .quality))
    }

    func testValidationFailuresExposeStableTypedReasons() {
        assertValidationError(.requiredMeasurementMissing, input: .init(), kind: .reps)
        assertValidationError(.invalidMeasurement, input: .init(durationSec: 0), kind: .duration)
        assertValidationError(.invalidWeight, input: .init(weightKg: .nan, reps: 1), kind: .weightReps)
        assertValidationError(.invalidRIR, input: .init(rir: 11), kind: .quality)
        assertValidationError(
            .ambiguousMeasurement,
            input: .init(reps: 1, durationSec: 1),
            kind: .quality
        )
    }

    func testValidatorRejectsConflictingMeasurementFields() {
        let cases: [(ExerciseMeasurementKind, SetMeasurementInput)] = [
            (.weightReps, .init(weightKg: 1, reps: 1, durationSec: 10)),
            (.weightReps, .init(weightKg: 1, reps: 1, distanceSteps: 10)),
            (.reps, .init(reps: 1, durationSec: 10)),
            (.reps, .init(reps: 1, distanceSteps: 10)),
            (.duration, .init(weightKg: 1, durationSec: 10)),
            (.duration, .init(reps: 1, durationSec: 10)),
            (.duration, .init(durationSec: 10, distanceSteps: 10)),
            (.steps, .init(reps: 1, distanceSteps: 10)),
            (.steps, .init(durationSec: 10, distanceSteps: 10))
        ]

        for (kind, input) in cases {
            XCTAssertThrowsError(try SetMeasurementValidator.validate(input, for: kind))
        }
    }

    func testMealCategoryRequiresCustomNameOnlyForCustomKind() throws {
        XCTAssertNoThrow(try MealCategory(kind: .breakfast))
        XCTAssertNoThrow(try MealCategory(kind: .custom, customName: "Gece öğünü"))
        XCTAssertThrowsError(try MealCategory(kind: .custom))
        XCTAssertThrowsError(try MealCategory(kind: .custom, customName: " \n"))
        XCTAssertThrowsError(try MealCategory(kind: .snack, customName: "Atıştırmalık"))
    }
    func testMealCategoryDecodingEnforcesCustomNameInvariant() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(MealCategory.self, from: Data(#"{"kind":"custom","customName":"Gece"}"#.utf8)),
            try MealCategory(kind: .custom, customName: "Gece")
        )
        XCTAssertThrowsError(try decoder.decode(MealCategory.self, from: Data(#"{"kind":"custom"}"#.utf8)))
        XCTAssertThrowsError(
            try decoder.decode(MealCategory.self, from: Data(#"{"kind":"breakfast","customName":"Kahvaltı"}"#.utf8))
        )
    }

    private func assertValidationError(
        _ expected: SetMeasurementValidationError,
        input: SetMeasurementInput,
        kind: ExerciseMeasurementKind,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try SetMeasurementValidator.validate(input, for: kind)
            XCTFail("Expected validation to fail", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SetMeasurementValidationError, expected, file: file, line: line)
        }
    }
}
