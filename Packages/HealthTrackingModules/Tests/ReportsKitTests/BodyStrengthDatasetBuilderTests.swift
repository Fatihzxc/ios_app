@testable import ReportsKit
import Foundation
import GuidanceKit
import XCTest

final class BodyStrengthDatasetBuilderTests: XCTestCase {
    func testBodyChartKeepsLatestActualObservationPerLocalDayAndSeries() throws {
        let calendar = try istanbulCalendar()
        let interval = ReportDateInterval(
            start: try date("2024-03-30T21:00:00Z"),
            endExclusive: try date("2024-04-03T21:00:00Z")
        )
        let winningWeightID = uuid("00000000-0000-4000-8000-000000000101")
        let records = [
            bodyMetric(
                id: uuid("00000000-0000-4000-8000-000000000100"),
                date: try date("2024-03-30T20:59:59Z"),
                createdAt: try date("2024-03-30T20:59:59Z"),
                value: 99
            ),
            bodyMetric(
                id: uuid("00000000-0000-4000-8000-000000000104"),
                date: try date("2024-03-31T19:00:00Z"),
                createdAt: try date("2024-03-31T19:01:00Z"),
                value: 82
            ),
            bodyMetric(
                id: uuid("00000000-0000-4000-8000-000000000103"),
                date: try date("2024-03-31T20:00:00Z"),
                createdAt: try date("2024-03-31T20:00:01Z"),
                value: 81
            ),
            bodyMetric(
                id: uuid("00000000-0000-4000-8000-000000000102"),
                date: try date("2024-03-31T20:00:00Z"),
                createdAt: try date("2024-03-31T20:00:02Z"),
                value: 80
            ),
            bodyMetric(
                id: winningWeightID,
                date: try date("2024-03-31T20:00:00Z"),
                createdAt: try date("2024-03-31T20:00:02Z"),
                value: 79
            ),
            bodyMetric(
                id: uuid("00000000-0000-4000-8000-000000000105"),
                date: try date("2024-03-31T10:00:00Z"),
                createdAt: try date("2024-03-31T10:01:00Z"),
                kind: .waist,
                value: 91,
                unit: "cm"
            ),
            bodyMetric(
                id: uuid("00000000-0000-4000-8000-000000000106"),
                date: try date("2024-04-02T09:00:00Z"),
                createdAt: try date("2024-04-02T09:01:00Z"),
                value: 78
            ),
            bodyMetric(
                id: uuid("00000000-0000-4000-8000-000000000107"),
                date: interval.endExclusive,
                createdAt: interval.endExclusive,
                value: 77
            ),
        ]

        let report = try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: Array(records.reversed()),
            exerciseSetRecords: [],
            interval: interval,
            calendar: calendar
        )

        XCTAssertEqual(report.bodyMetricPoints.map(\.observationID), [
            uuid("00000000-0000-4000-8000-000000000105"),
            winningWeightID,
            uuid("00000000-0000-4000-8000-000000000106"),
        ])
        XCTAssertEqual(report.bodyMetricPoints.map(\.value), [91, 79, 78])
        XCTAssertEqual(report.bodyMetricPoints.map(\.kind), [.waist, .weight, .weight])
        XCTAssertFalse(report.bodyMetricPoints.contains(where: { $0.value == 0 }))
        XCTAssertEqual(report.bodyMetricCoverage.observedCount, 3)
        XCTAssertEqual(report.bodyMetricCoverage.firstObservationAt, try date("2024-03-31T10:00:00Z"))
        XCTAssertEqual(report.bodyMetricCoverage.lastObservationAt, try date("2024-04-02T09:00:00Z"))
    }

    func testStrengthUsesCompletedNonWarmupSetsAndCanonicalSessionMaximumEpley() throws {
        let sessionID = uuid("00000000-0000-4000-8000-000000000201")
        let exerciseID = uuid("00000000-0000-4000-8000-000000000202")
        let sessionDate = try date("2024-04-01T09:00:00Z")
        let records = [
            exerciseSet(
                id: uuid("00000000-0000-4000-8000-000000000210"),
                sessionID: sessionID,
                sessionDate: sessionDate,
                exerciseID: exerciseID,
                setIndex: 0,
                weightKg: 100,
                reps: 5
            ),
            exerciseSet(
                id: uuid("00000000-0000-4000-8000-000000000211"),
                sessionID: sessionID,
                sessionDate: sessionDate,
                exerciseID: exerciseID,
                setIndex: 1,
                weightKg: 120,
                reps: 5
            ),
            exerciseSet(
                id: uuid("00000000-0000-4000-8000-000000000212"),
                sessionID: sessionID,
                sessionDate: sessionDate,
                exerciseID: exerciseID,
                setIndex: 2,
                isWarmup: true,
                weightKg: 200,
                reps: 10
            ),
            exerciseSet(
                id: uuid("00000000-0000-4000-8000-000000000213"),
                sessionID: sessionID,
                sessionDate: sessionDate,
                exerciseID: exerciseID,
                setIndex: 3,
                sessionCompleted: false,
                weightKg: 300,
                reps: 10
            ),
        ]
        let interval = ReportDateInterval(
            start: try date("2024-04-01T00:00:00Z"),
            endExclusive: try date("2024-04-02T00:00:00Z")
        )

        let report = try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: [],
            exerciseSetRecords: Array(records.reversed()),
            interval: interval,
            calendar: try istanbulCalendar()
        )

        let point = try XCTUnwrap(report.strengthSessionPoints.only)
        XCTAssertEqual(point.sessionID, sessionID)
        XCTAssertEqual(point.exerciseTemplateID, exerciseID)
        XCTAssertEqual(point.eligibleSetCount, 2)
        XCTAssertEqual(
            try XCTUnwrap(point.volumeKg),
            1_100,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(point.estimatedOneRepMaxKg),
            140,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(report.strengthCoverage.observedCount, 1)
    }

    func testOnlyWeightedRepetitionsProduceEpleyWhileEveryActualKindRemainsVisible() throws {
        let interval = ReportDateInterval(
            start: try date("2024-04-01T00:00:00Z"),
            endExclusive: try date("2024-04-03T00:00:00Z")
        )
        let measurementFixtures: [(
            measurement: ReportExerciseMeasurement,
            weightKg: Double?,
            reps: Int?,
            durationSec: Int?,
            distanceSteps: Int?
        )] = [
            (.weightedRepetitions, 17.5, 8, nil, nil),
            (.repetitions, nil, 8, nil, nil),
            (.duration, nil, nil, 60, nil),
            (.steps, 20, nil, nil, 40),
            (.quality, nil, 12, nil, nil),
        ]
        let records = measurementFixtures.enumerated().map { offset, fixture in
            exerciseSet(
                id: uuid(String(format: "00000000-0000-4000-8000-%012d", 300 + offset)),
                sessionID: uuid(String(format: "00000000-0000-4000-8000-%012d", 310 + offset)),
                sessionDate: interval.start.addingTimeInterval(100 + Double(offset)),
                exerciseID: uuid(String(format: "00000000-0000-4000-8000-%012d", 320 + offset)),
                setIndex: 0,
                measurement: fixture.measurement,
                weightKg: fixture.weightKg,
                reps: fixture.reps,
                durationSec: fixture.durationSec,
                distanceSteps: fixture.distanceSteps
            )
        }

        let report = try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: [],
            exerciseSetRecords: records.shuffled(),
            interval: interval,
            calendar: try istanbulCalendar()
        )

        XCTAssertEqual(report.strengthSessionPoints.count, 5)
        let byMeasurement = Dictionary(
            uniqueKeysWithValues: zip(measurementFixtures.map(\.measurement), report.strengthSessionPoints)
        )
        XCTAssertEqual(
            try XCTUnwrap(byMeasurement[.weightedRepetitions]?.estimatedOneRepMaxKg),
            22.166_666_666_666_664,
            accuracy: 0
        )
        XCTAssertNil(byMeasurement[.repetitions]?.estimatedOneRepMaxKg)
        XCTAssertNil(byMeasurement[.duration]?.estimatedOneRepMaxKg)
        XCTAssertNil(byMeasurement[.steps]?.estimatedOneRepMaxKg)
        XCTAssertNil(byMeasurement[.quality]?.estimatedOneRepMaxKg)
        XCTAssertNil(byMeasurement[.repetitions]?.volumeKg)
        XCTAssertNil(byMeasurement[.duration]?.volumeKg)
        XCTAssertNil(byMeasurement[.steps]?.volumeKg)
        XCTAssertNil(byMeasurement[.quality]?.volumeKg)
    }

    func testActualZeroVolumeRemainsObservedWhileMissingVolumeRemainsNil() throws {
        let interval = ReportDateInterval(
            start: try date("2024-04-01T00:00:00Z"),
            endExclusive: try date("2024-04-02T00:00:00Z")
        )
        let zero = exerciseSet(
            id: uuid("00000000-0000-4000-8000-000000000351"),
            sessionID: uuid("00000000-0000-4000-8000-000000000352"),
            sessionDate: interval.start.addingTimeInterval(1),
            exerciseID: uuid("00000000-0000-4000-8000-000000000353"),
            setIndex: 0,
            weightKg: 0,
            reps: 10
        )
        let missing = exerciseSet(
            id: uuid("00000000-0000-4000-8000-000000000354"),
            sessionID: uuid("00000000-0000-4000-8000-000000000355"),
            sessionDate: interval.start.addingTimeInterval(2),
            exerciseID: uuid("00000000-0000-4000-8000-000000000356"),
            setIndex: 0,
            measurement: .duration,
            weightKg: nil,
            reps: nil,
            durationSec: 30
        )

        let report = try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: [],
            exerciseSetRecords: [missing, zero],
            interval: interval,
            calendar: try istanbulCalendar()
        )

        XCTAssertEqual(try XCTUnwrap(report.strengthSessionPoints[0].volumeKg), 0)
        XCTAssertNil(report.strengthSessionPoints[1].volumeKg)
    }

    func testExtremeWeightedRepetitionsFailTypedBeforeCanonicalEpleyCanOverflow() throws {
        let interval = ReportDateInterval(
            start: try date("2024-04-01T00:00:00Z"),
            endExclusive: try date("2024-04-02T00:00:00Z")
        )
        let recordID = uuid("00000000-0000-4000-8000-000000000361")
        let record = exerciseSet(
            id: recordID,
            sessionID: uuid("00000000-0000-4000-8000-000000000362"),
            sessionDate: interval.start.addingTimeInterval(1),
            exerciseID: uuid("00000000-0000-4000-8000-000000000363"),
            setIndex: 0,
            weightKg: 1,
            reps: Int.max
        )

        XCTAssertNil(EpleyEstimate.calculate(weightKg: 1, reps: Int.max))

        XCTAssertThrowsError(try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: [],
            exerciseSetRecords: [record],
            interval: interval,
            calendar: try istanbulCalendar()
        )) { error in
            XCTAssertEqual(
                error as? BodyStrengthDatasetError,
                .invalidRepetitionRange(recordID: recordID, reps: Int.max)
            )
        }
    }

    func testLogicalDuplicateSetIndexesFailDeterministicallyBeforeAggregation() throws {
        let interval = ReportDateInterval(
            start: try date("2024-04-01T00:00:00Z"),
            endExclusive: try date("2024-04-02T00:00:00Z")
        )
        let sessionID = uuid("00000000-0000-4000-8000-000000000371")
        let exerciseID = uuid("00000000-0000-4000-8000-000000000372")
        let lowerID = uuid("00000000-0000-4000-8000-000000000373")
        let higherID = uuid("00000000-0000-4000-8000-000000000374")
        let duplicateRecords = [lowerID, higherID].map { id in
            exerciseSet(
                id: id,
                sessionID: sessionID,
                sessionDate: interval.start.addingTimeInterval(1),
                exerciseID: exerciseID,
                setIndex: 0,
                weightKg: 30,
                reps: 10
            )
        }

        for records in [duplicateRecords, Array(duplicateRecords.reversed())] {
            XCTAssertThrowsError(try BodyStrengthDatasetBuilder.build(
                bodyMetricRecords: [],
                exerciseSetRecords: records,
                interval: interval,
                calendar: try istanbulCalendar()
            )) { error in
                XCTAssertEqual(
                    error as? BodyStrengthDatasetError,
                    .duplicateSetIndex(
                        sessionID: sessionID,
                        exerciseTemplateID: exerciseID,
                        setIndex: 0,
                        recordIDs: [lowerID, higherID]
                    )
                )
            }
        }
    }

    func testLogicalDuplicateSetIndexesIncludeWarmupsButIgnoreIrrelevantSessions() throws {
        let interval = ReportDateInterval(
            start: try date("2024-04-01T00:00:00Z"),
            endExclusive: try date("2024-04-02T00:00:00Z")
        )
        let sessionID = uuid("00000000-0000-4000-8000-000000000375")
        let exerciseID = uuid("00000000-0000-4000-8000-000000000376")
        let workingID = uuid("00000000-0000-4000-8000-000000000377")
        let warmupID = uuid("00000000-0000-4000-8000-000000000378")
        let secondWarmupID = uuid("00000000-0000-4000-8000-000000000379")
        let working = exerciseSet(
            id: workingID,
            sessionID: sessionID,
            sessionDate: interval.start.addingTimeInterval(1),
            exerciseID: exerciseID,
            setIndex: 0,
            weightKg: 30,
            reps: 10
        )
        let warmup = exerciseSet(
            id: warmupID,
            sessionID: sessionID,
            sessionDate: working.sessionDate,
            exerciseID: exerciseID,
            setIndex: 0,
            isWarmup: true,
            weightKg: 20,
            reps: 10
        )
        let secondWarmup = exerciseSet(
            id: secondWarmupID,
            sessionID: sessionID,
            sessionDate: working.sessionDate,
            exerciseID: exerciseID,
            setIndex: 0,
            isWarmup: true,
            weightKg: 10,
            reps: 10
        )

        for fixture in [
            (records: [working, warmup], ids: [workingID, warmupID]),
            (records: [secondWarmup, warmup], ids: [warmupID, secondWarmupID]),
        ] {
            XCTAssertThrowsError(try BodyStrengthDatasetBuilder.build(
                bodyMetricRecords: [],
                exerciseSetRecords: fixture.records,
                interval: interval,
                calendar: try istanbulCalendar()
            )) { error in
                XCTAssertEqual(
                    error as? BodyStrengthDatasetError,
                    .duplicateSetIndex(
                        sessionID: sessionID,
                        exerciseTemplateID: exerciseID,
                        setIndex: 0,
                        recordIDs: fixture.ids
                    )
                )
            }
        }

        let irrelevantDuplicates = [
            exerciseSet(
                id: uuid("00000000-0000-4000-8000-000000000460"),
                sessionID: uuid("00000000-0000-4000-8000-000000000461"),
                sessionDate: interval.start,
                exerciseID: exerciseID,
                setIndex: 0,
                sessionCompleted: false,
                weightKg: 30,
                reps: 10
            ),
            exerciseSet(
                id: uuid("00000000-0000-4000-8000-000000000462"),
                sessionID: uuid("00000000-0000-4000-8000-000000000461"),
                sessionDate: interval.start,
                exerciseID: exerciseID,
                setIndex: 0,
                sessionCompleted: false,
                weightKg: 30,
                reps: 10
            ),
            exerciseSet(
                id: uuid("00000000-0000-4000-8000-000000000463"),
                sessionID: uuid("00000000-0000-4000-8000-000000000464"),
                sessionDate: interval.endExclusive,
                exerciseID: exerciseID,
                setIndex: 0,
                weightKg: 30,
                reps: 10
            ),
            exerciseSet(
                id: uuid("00000000-0000-4000-8000-000000000465"),
                sessionID: uuid("00000000-0000-4000-8000-000000000464"),
                sessionDate: interval.endExclusive,
                exerciseID: exerciseID,
                setIndex: 0,
                weightKg: 30,
                reps: 10
            ),
        ]
        let isolated = try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: [],
            exerciseSetRecords: irrelevantDuplicates,
            interval: interval,
            calendar: try istanbulCalendar()
        )
        XCTAssertTrue(isolated.strengthSessionPoints.isEmpty)
    }

    func testMultipleInvalidStrengthGroupsChooseLowestStableKey() throws {
        let interval = ReportDateInterval(
            start: try date("2024-04-01T00:00:00Z"),
            endExclusive: try date("2024-04-02T00:00:00Z")
        )
        let lowerSessionID = uuid("00000000-0000-4000-8000-000000000421")
        let lowerExerciseID = uuid("00000000-0000-4000-8000-000000000422")
        let higherSessionID = uuid("00000000-0000-4000-8000-000000000431")
        let higherExerciseID = uuid("00000000-0000-4000-8000-000000000432")
        let lowerGroup = [
            exerciseSet(
                id: uuid("00000000-0000-4000-8000-000000000423"),
                sessionID: lowerSessionID,
                sessionDate: interval.start.addingTimeInterval(200),
                exerciseID: lowerExerciseID,
                exerciseName: "Squat",
                setIndex: 0,
                weightKg: 30,
                reps: 10
            ),
            exerciseSet(
                id: uuid("00000000-0000-4000-8000-000000000424"),
                sessionID: lowerSessionID,
                sessionDate: interval.start.addingTimeInterval(200),
                exerciseID: lowerExerciseID,
                exerciseName: "Different squat",
                setIndex: 1,
                weightKg: 30,
                reps: 10
            ),
        ]
        let higherGroup = [
            exerciseSet(
                id: uuid("00000000-0000-4000-8000-000000000433"),
                sessionID: higherSessionID,
                sessionDate: interval.start.addingTimeInterval(100),
                exerciseID: higherExerciseID,
                exerciseName: "Bench",
                setIndex: 0,
                weightKg: 30,
                reps: 10
            ),
            exerciseSet(
                id: uuid("00000000-0000-4000-8000-000000000434"),
                sessionID: higherSessionID,
                sessionDate: interval.start.addingTimeInterval(100),
                exerciseID: higherExerciseID,
                exerciseName: "Different bench",
                setIndex: 1,
                weightKg: 30,
                reps: 10
            ),
        ]

        let records = lowerGroup + higherGroup
        for input in [records, Array(records.reversed())] {
            XCTAssertThrowsError(try BodyStrengthDatasetBuilder.build(
                bodyMetricRecords: [],
                exerciseSetRecords: input,
                interval: interval,
                calendar: try istanbulCalendar()
            )) { error in
                XCTAssertEqual(
                    error as? BodyStrengthDatasetError,
                    .inconsistentStrengthGroup(
                        sessionID: lowerSessionID,
                        exerciseTemplateID: lowerExerciseID,
                        field: .exerciseName
                    )
                )
            }
        }
    }

    func testMixedStrengthGroupMetadataFailsWithDeterministicTypedField() throws {
        let interval = ReportDateInterval(
            start: try date("2024-04-01T00:00:00Z"),
            endExclusive: try date("2024-04-02T00:00:00Z")
        )
        let sessionID = uuid("00000000-0000-4000-8000-000000000381")
        let exerciseID = uuid("00000000-0000-4000-8000-000000000382")
        let baseline = exerciseSet(
            id: uuid("00000000-0000-4000-8000-000000000383"),
            sessionID: sessionID,
            sessionDate: interval.start.addingTimeInterval(10),
            sessionCreatedAt: interval.start.addingTimeInterval(5),
            exerciseID: exerciseID,
            exerciseName: "Squat",
            setIndex: 0,
            weightKg: 30,
            reps: 10
        )
        let fixtures: [(ReportStrengthGroupField, ReportExerciseSetRecord)] = [
            (
                .sessionDate,
                exerciseSet(
                    id: uuid("00000000-0000-4000-8000-000000000384"),
                    sessionID: sessionID,
                    sessionDate: interval.start.addingTimeInterval(11),
                    sessionCreatedAt: baseline.sessionCreatedAt,
                    exerciseID: exerciseID,
                    exerciseName: baseline.exerciseName,
                    setIndex: 1,
                    weightKg: 30,
                    reps: 10
                )
            ),
            (
                .sessionCreatedAt,
                exerciseSet(
                    id: uuid("00000000-0000-4000-8000-000000000385"),
                    sessionID: sessionID,
                    sessionDate: baseline.sessionDate,
                    sessionCreatedAt: baseline.sessionCreatedAt.addingTimeInterval(1),
                    exerciseID: exerciseID,
                    exerciseName: baseline.exerciseName,
                    setIndex: 1,
                    weightKg: 30,
                    reps: 10
                )
            ),
            (
                .exerciseName,
                exerciseSet(
                    id: uuid("00000000-0000-4000-8000-000000000386"),
                    sessionID: sessionID,
                    sessionDate: baseline.sessionDate,
                    sessionCreatedAt: baseline.sessionCreatedAt,
                    exerciseID: exerciseID,
                    exerciseName: "Different",
                    setIndex: 1,
                    weightKg: 30,
                    reps: 10
                )
            ),
            (
                .measurement,
                exerciseSet(
                    id: uuid("00000000-0000-4000-8000-000000000387"),
                    sessionID: sessionID,
                    sessionDate: baseline.sessionDate,
                    sessionCreatedAt: baseline.sessionCreatedAt,
                    exerciseID: exerciseID,
                    exerciseName: baseline.exerciseName,
                    setIndex: 1,
                    measurement: .repetitions,
                    weightKg: nil,
                    reps: 10
                )
            ),
        ]

        for fixture in fixtures {
            XCTAssertThrowsError(try BodyStrengthDatasetBuilder.build(
                bodyMetricRecords: [],
                exerciseSetRecords: [fixture.1, baseline],
                interval: interval,
                calendar: try istanbulCalendar()
            )) { error in
                XCTAssertEqual(
                    error as? BodyStrengthDatasetError,
                    .inconsistentStrengthGroup(
                        sessionID: sessionID,
                        exerciseTemplateID: exerciseID,
                        field: fixture.0
                    )
                )
            }
        }
    }

    func testInjectedLosAngelesCalendarReducesAcrossUTCDatesAndExposesLocalDay() throws {
        let calendar = try calendar(timeZoneIdentifier: "America/Los_Angeles")
        let interval = ReportDateInterval(
            start: try date("2024-03-10T08:00:00Z"),
            endExclusive: try date("2024-03-11T07:00:00Z")
        )
        let earlier = bodyMetric(
            id: uuid("00000000-0000-4000-8000-000000000391"),
            date: try date("2024-03-10T09:30:00Z"),
            createdAt: try date("2024-03-10T09:31:00Z"),
            value: 80
        )
        let laterAcrossUTCDate = bodyMetric(
            id: uuid("00000000-0000-4000-8000-000000000392"),
            date: try date("2024-03-11T06:30:00Z"),
            createdAt: try date("2024-03-11T06:31:00Z"),
            value: 79
        )

        let report = try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: [earlier, laterAcrossUTCDate],
            exerciseSetRecords: [],
            interval: interval,
            calendar: calendar
        )

        let point = try XCTUnwrap(report.bodyMetricPoints.only)
        XCTAssertEqual(point.observationID, laterAcrossUTCDate.id)
        XCTAssertEqual(point.localDay, try date("2024-03-10T08:00:00Z"))
    }

    func testStrengthOrderingAndHalfOpenBoundaryAreIndependentOfInputOrder() throws {
        let start = try date("2024-04-01T00:00:00Z")
        let end = try date("2024-04-02T00:00:00Z")
        let interval = ReportDateInterval(start: start, endExclusive: end)
        let atStart = exerciseSet(
            id: uuid("00000000-0000-4000-8000-000000000410"),
            sessionID: uuid("00000000-0000-4000-8000-000000000401"),
            sessionDate: start,
            exerciseID: uuid("00000000-0000-4000-8000-000000000405"),
            exerciseName: "Squat",
            setIndex: 0,
            weightKg: 50,
            reps: 5
        )
        let sameDateEarlierSession = exerciseSet(
            id: uuid("00000000-0000-4000-8000-000000000411"),
            sessionID: uuid("00000000-0000-4000-8000-000000000402"),
            sessionDate: start.addingTimeInterval(1),
            sessionCreatedAt: start.addingTimeInterval(1),
            exerciseID: uuid("00000000-0000-4000-8000-000000000406"),
            exerciseName: "Bench",
            setIndex: 0,
            weightKg: 40,
            reps: 5
        )
        let atEnd = exerciseSet(
            id: uuid("00000000-0000-4000-8000-000000000412"),
            sessionID: uuid("00000000-0000-4000-8000-000000000403"),
            sessionDate: end,
            exerciseID: uuid("00000000-0000-4000-8000-000000000407"),
            setIndex: 0,
            weightKg: 60,
            reps: 5
        )

        let forward = try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: [],
            exerciseSetRecords: [atEnd, sameDateEarlierSession, atStart],
            interval: interval,
            calendar: try istanbulCalendar()
        )
        let reverse = try BodyStrengthDatasetBuilder.build(
            bodyMetricRecords: [],
            exerciseSetRecords: [atStart, sameDateEarlierSession, atEnd],
            interval: interval,
            calendar: try istanbulCalendar()
        )

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward.strengthSessionPoints.map(\.sessionID), [atStart.sessionID, sameDateEarlierSession.sessionID])
    }

    private func bodyMetric(
        id: UUID,
        date: Date,
        createdAt: Date,
        kind: ReportBodyMetricKind = .weight,
        customName: String? = nil,
        value: Double,
        unit: String = "kg"
    ) -> ReportBodyMetricRecord {
        ReportBodyMetricRecord(
            id: id,
            date: date,
            createdAt: createdAt,
            kind: kind,
            customName: customName,
            value: value,
            unit: unit
        )
    }

    private func exerciseSet(
        id: UUID,
        sessionID: UUID,
        sessionDate: Date,
        sessionCreatedAt: Date? = nil,
        exerciseID: UUID,
        exerciseName: String = "Exercise",
        setIndex: Int,
        sessionCompleted: Bool = true,
        isWarmup: Bool = false,
        measurement: ReportExerciseMeasurement = .weightedRepetitions,
        weightKg: Double?,
        reps: Int?,
        durationSec: Int? = nil,
        distanceSteps: Int? = nil
    ) -> ReportExerciseSetRecord {
        ReportExerciseSetRecord(
            id: id,
            createdAt: sessionDate.addingTimeInterval(Double(setIndex)),
            sessionID: sessionID,
            sessionDate: sessionDate,
            sessionCreatedAt: sessionCreatedAt ?? sessionDate,
            exerciseTemplateID: exerciseID,
            exerciseName: exerciseName,
            setIndex: setIndex,
            sessionCompleted: sessionCompleted,
            isWarmup: isWarmup,
            measurement: measurement,
            weightKg: weightKg,
            reps: reps,
            durationSec: durationSec,
            distanceSteps: distanceSteps
        )
    }

    private func istanbulCalendar() throws -> Calendar {
        try calendar(timeZoneIdentifier: "Europe/Istanbul")
    }

    private func calendar(timeZoneIdentifier: String) throws -> Calendar {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw FixtureError.invalidTimeZone
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let result = formatter.date(from: value) else {
            throw FixtureError.invalidDate(value)
        }
        return result
    }

    private func uuid(_ value: String) -> UUID {
        guard let result = UUID(uuidString: value) else {
            preconditionFailure("Invalid fixture UUID: \(value)")
        }
        return result
    }

    private enum FixtureError: Error {
        case invalidDate(String)
        case invalidTimeZone
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? self[0] : nil
    }
}
