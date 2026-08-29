import CoreModels
@testable import PersistenceKit
import ReportsKit
import SwiftData
import XCTest

@MainActor
final class ReportsRepositoryTests: XCTestCase {
    func testNutritionProjectionUsesActualEntriesLocalDaysSnapshotsAndCurrentProfileWithoutMutation() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let calendar = istanbulCalendar()
        let interval = ReportDateInterval(
            start: try date("2024-03-30T21:00:00Z"),
            endExclusive: try date("2024-04-03T21:00:00Z")
        )
        writer.insert(UserProfile(
            id: uuid("00000000-0000-4000-8000-000000002001"),
            proteinTargetG: 100
        ))

        let zeroDay = nutritionLog(
            id: uuid("00000000-0000-4000-8000-000000002101"),
            date: try date("2024-03-31T10:00:00Z")
        )
        let hitDay = nutritionLog(
            id: uuid("00000000-0000-4000-8000-000000002102"),
            date: try date("2024-03-31T21:00:00Z")
        )
        let missDay = nutritionLog(
            id: uuid("00000000-0000-4000-8000-000000002103"),
            date: try date("2024-04-02T20:59:59Z")
        )
        let emptyDay = nutritionLog(
            id: uuid("00000000-0000-4000-8000-000000002104"),
            date: try date("2024-04-02T21:00:00Z")
        )
        let outsideDay = nutritionLog(
            id: uuid("00000000-0000-4000-8000-000000002105"),
            date: interval.endExclusive
        )
        let entries = [
            mealEntry(
                id: uuid("00000000-0000-4000-8000-000000002201"),
                proteinG: 0,
                loggedAt: interval.endExclusive.addingTimeInterval(10_000),
                log: zeroDay
            ),
            mealEntry(
                id: uuid("00000000-0000-4000-8000-000000002202"),
                proteinG: 40,
                loggedAt: interval.start.addingTimeInterval(-10_000),
                log: hitDay
            ),
            mealEntry(
                id: uuid("00000000-0000-4000-8000-000000002203"),
                proteinG: 70,
                loggedAt: interval.start.addingTimeInterval(-9_000),
                log: hitDay
            ),
            mealEntry(
                id: uuid("00000000-0000-4000-8000-000000002204"),
                proteinG: 50,
                loggedAt: interval.start.addingTimeInterval(1_000),
                log: missDay
            ),
            mealEntry(
                id: uuid("00000000-0000-4000-8000-000000002205"),
                proteinG: .nan,
                loggedAt: interval.endExclusive,
                log: outsideDay
            ),
        ]
        zeroDay.mealEntries = [entries[0]]
        hitDay.mealEntries = [entries[2], entries[1]]
        missDay.mealEntries = [entries[3]]
        outsideDay.mealEntries = [entries[4]]
        for log in [outsideDay, emptyDay, missDay, hitDay, zeroDay] { writer.insert(log) }
        for entry in entries.reversed() { writer.insert(entry) }
        try writer.save()

        let reader = ModelContext(container)
        let repository = SwiftDataReportsRepository(modelContext: reader, calendar: calendar)
        let before = try nutritionFieldSnapshot(in: container)
        XCTAssertFalse(reader.hasChanges)

        let first = try await repository.fetchDashboardSource(in: interval)
        let second = try await repository.fetchDashboardSource(in: interval)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.nutritionDayRecords.map(\.id), [zeroDay.id, hitDay.id, missDay.id])
        XCTAssertEqual(first.nutritionDayRecords.map(\.date), [
            calendar.startOfDay(for: zeroDay.date),
            calendar.startOfDay(for: hitDay.date),
            calendar.startOfDay(for: missDay.date),
        ])
        XCTAssertEqual(first.nutritionDayRecords.map(\.entryCount), [1, 2, 1])
        XCTAssertEqual(first.nutritionDayRecords.map(\.proteinTotalG), [0, 110, 50])
        XCTAssertEqual(first.nutritionDayRecords.map(\.proteinTargetG), [100, 100, 100])
        XCTAssertEqual(first.coverage.observedCount, 3)
        XCTAssertFalse(reader.hasChanges)
        XCTAssertEqual(try nutritionFieldSnapshot(in: container), before)
    }

    func testMissingOrInvalidCurrentProfileTargetProducesTargetlessObservedDays() async throws {
        let targets: [Double?] = [nil, .nan, 0, -1, .infinity]
        for target in targets {
            let container = try ModelContainerFactory.make(for: .inMemory)
            let writer = ModelContext(container)
            let log = nutritionLog(
                id: uuid("00000000-0000-4000-8000-000000002301"),
                date: Date(timeIntervalSinceReferenceDate: 1_000)
            )
            let entry = mealEntry(
                id: uuid("00000000-0000-4000-8000-000000002302"),
                proteinG: 80,
                loggedAt: log.date,
                log: log
            )
            log.mealEntries = [entry]
            if let target {
                writer.insert(UserProfile(proteinTargetG: target))
            }
            writer.insert(log)
            writer.insert(entry)
            try writer.save()

            let source = try await reportsRepository(in: ModelContext(container))
                .fetchDashboardSource(in: broadInterval())

            XCTAssertEqual(source.nutritionDayRecords.count, 1)
            XCTAssertNil(source.nutritionDayRecords.first?.proteinTargetG)
        }
    }

    func testNutritionDuplicateLogicalDayAndProfileAmbiguityFailDeterministically() async throws {
        let calendar = istanbulCalendar()
        let duplicateDayInterval = ReportDateInterval(
            start: try date("2024-03-31T21:00:00Z"),
            endExclusive: try date("2024-04-01T21:00:00Z")
        )
        let lowerLogID = uuid("00000000-0000-4000-8000-000000002401")
        let higherLogID = uuid("00000000-0000-4000-8000-000000002402")
        for reverse in [false, true] {
            let container = try ModelContainerFactory.make(for: .inMemory)
            let writer = ModelContext(container)
            let logs = [
                nutritionLog(id: lowerLogID, date: try date("2024-04-01T01:00:00Z")),
                nutritionLog(id: higherLogID, date: try date("2024-04-01T20:00:00Z")),
            ]
            let orderedLogs = reverse ? Array(logs.reversed()) : logs
            for log in orderedLogs { writer.insert(log) }
            try writer.save()

            do {
                _ = try await SwiftDataReportsRepository(
                    modelContext: ModelContext(container),
                    calendar: calendar
                ).fetchDashboardSource(in: duplicateDayInterval)
                XCTFail("Expected duplicate local nutrition day integrity failure.")
            } catch {
                XCTAssertEqual(
                    error as? ReportsRepositoryIntegrityError,
                    .duplicateNutritionDay(
                        localDay: calendar.startOfDay(for: logs[0].date),
                        nutritionLogIDs: [lowerLogID, higherLogID]
                    )
                )
            }
        }

        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let log = nutritionLog(
            id: uuid("00000000-0000-4000-8000-000000002403"),
            date: Date(timeIntervalSinceReferenceDate: 1_000)
        )
        let entry = mealEntry(
            id: uuid("00000000-0000-4000-8000-000000002404"),
            proteinG: 80,
            loggedAt: log.date,
            log: log
        )
        log.mealEntries = [entry]
        let lowerProfileID = uuid("00000000-0000-4000-8000-000000002405")
        let higherProfileID = uuid("00000000-0000-4000-8000-000000002406")
        writer.insert(UserProfile(id: higherProfileID, proteinTargetG: 90))
        writer.insert(UserProfile(id: lowerProfileID, proteinTargetG: 100))
        writer.insert(log)
        writer.insert(entry)
        try writer.save()

        do {
            _ = try await reportsRepository(in: ModelContext(container))
                .fetchDashboardSource(in: broadInterval())
            XCTFail("Expected ambiguous current profile integrity failure.")
        } catch {
            XCTAssertEqual(
                error as? ReportsRepositoryIntegrityError,
                .ambiguousUserProfiles(profileIDs: [lowerProfileID, higherProfileID])
            )
        }
    }

    func testSelectedNutritionEntryCorruptionAndMissingRelationshipFailWithStableTypedErrors() async throws {
        let lowerID = uuid("00000000-0000-4000-8000-000000002501")
        let higherID = uuid("00000000-0000-4000-8000-000000002502")
        for reverse in [false, true] {
            let container = try ModelContainerFactory.make(for: .inMemory)
            let writer = ModelContext(container)
            let log = nutritionLog(
                id: uuid("00000000-0000-4000-8000-000000002503"),
                date: Date(timeIntervalSinceReferenceDate: 1_000)
            )
            let entries = [
                mealEntry(id: lowerID, proteinG: -.infinity, loggedAt: log.date, log: log),
                mealEntry(id: higherID, proteinG: .nan, loggedAt: log.date, log: log),
            ]
            log.mealEntries = entries
            writer.insert(log)
            let orderedEntries = reverse ? Array(entries.reversed()) : entries
            for entry in orderedEntries { writer.insert(entry) }
            try writer.save()

            do {
                _ = try await reportsRepository(in: ModelContext(container))
                    .fetchDashboardSource(in: broadInterval())
                XCTFail("Expected invalid resolved nutrition snapshot.")
            } catch {
                XCTAssertEqual(
                    error as? ReportsRepositoryIntegrityError,
                    .invalidMealEntry(id: lowerID)
                )
            }
        }

        let orphanContainer = try ModelContainerFactory.make(for: .inMemory)
        let orphanWriter = ModelContext(orphanContainer)
        let orphanID = uuid("00000000-0000-4000-8000-000000002504")
        orphanWriter.insert(mealEntry(
            id: orphanID,
            proteinG: 20,
            loggedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            log: nil
        ))
        try orphanWriter.save()
        let orphanReader = ModelContext(orphanContainer)

        do {
            _ = try await reportsRepository(in: orphanReader)
                .fetchDashboardSource(in: broadInterval())
            XCTFail("Expected missing nutrition-day relationship.")
        } catch {
            XCTAssertEqual(
                error as? ReportsRepositoryIntegrityError,
                .mealEntryMissingNutritionLog(id: orphanID)
            )
        }
        XCTAssertFalse(orphanReader.hasChanges)
    }

    func testSelectedNutritionIdentityCollisionsFailWithoutRebindingRows() async throws {
        let sharedLogID = uuid("00000000-0000-4000-8000-000000002601")
        let logContainer = try ModelContainerFactory.make(for: .inMemory)
        let logWriter = ModelContext(logContainer)
        let selectedLog = nutritionLog(
            id: sharedLogID,
            date: Date(timeIntervalSinceReferenceDate: 1_000)
        )
        let collidingOutsideLog = nutritionLog(
            id: sharedLogID,
            date: Date(timeIntervalSinceReferenceDate: 20_000)
        )
        let selectedEntry = mealEntry(
            id: uuid("00000000-0000-4000-8000-000000002602"),
            proteinG: 20,
            loggedAt: selectedLog.date,
            log: selectedLog
        )
        selectedLog.mealEntries = [selectedEntry]
        logWriter.insert(selectedLog)
        logWriter.insert(collidingOutsideLog)
        logWriter.insert(selectedEntry)
        try logWriter.save()

        do {
            _ = try await reportsRepository(in: ModelContext(logContainer))
                .fetchDashboardSource(in: broadInterval())
            XCTFail("Expected selected nutrition-log identity collision.")
        } catch {
            XCTAssertEqual(
                error as? ReportsRepositoryIntegrityError,
                .duplicateNutritionLogIDs(id: sharedLogID, count: 2)
            )
        }

        let entryContainer = try ModelContainerFactory.make(for: .inMemory)
        let entryWriter = ModelContext(entryContainer)
        let log = nutritionLog(
            id: uuid("00000000-0000-4000-8000-000000002603"),
            date: Date(timeIntervalSinceReferenceDate: 1_000)
        )
        let sharedEntryID = uuid("00000000-0000-4000-8000-000000002604")
        let entries = [
            mealEntry(id: sharedEntryID, proteinG: 20, loggedAt: log.date, log: log),
            mealEntry(id: sharedEntryID, proteinG: 30, loggedAt: log.date, log: log),
        ]
        log.mealEntries = entries
        entryWriter.insert(log)
        for entry in entries { entryWriter.insert(entry) }
        try entryWriter.save()

        do {
            _ = try await reportsRepository(in: ModelContext(entryContainer))
                .fetchDashboardSource(in: broadInterval())
            XCTFail("Expected selected meal-entry identity collision.")
        } catch {
            XCTAssertEqual(
                error as? ReportsRepositoryIntegrityError,
                .duplicateMealEntryIDs(id: sharedEntryID, count: 2)
            )
        }
    }

    func testFetchPreservesEveryValidInRangeRowWithDeterministicMappingsAndNoMutation() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let start = try date("2024-04-01T00:00:00Z")
        let end = try date("2024-04-03T00:00:00Z")
        let interval = ReportDateInterval(start: start, endExclusive: end)
        let bodyIDs = [
            uuid("00000000-0000-4000-8000-000000001001"),
            uuid("00000000-0000-4000-8000-000000001002"),
            uuid("00000000-0000-4000-8000-000000001003"),
        ]
        writer.insert(bodyMetric(id: bodyIDs[2], date: start.addingTimeInterval(20), value: 78))
        writer.insert(bodyMetric(id: bodyIDs[0], date: start, value: 80))
        writer.insert(bodyMetric(id: bodyIDs[1], date: start.addingTimeInterval(10), value: 79))
        writer.insert(bodyMetric(
            id: uuid("00000000-0000-4000-8000-000000001004"),
            date: end,
            value: 77
        ))

        let exerciseFixtures: [(UUID, String, ExerciseMeasurementKind)] = [
            (uuid("00000000-0000-4000-8000-000000001101"), "Weighted", .weightReps),
            (uuid("00000000-0000-4000-8000-000000001102"), "Bodyweight", .reps),
            (uuid("00000000-0000-4000-8000-000000001103"), "Duration", .duration),
            (uuid("00000000-0000-4000-8000-000000001104"), "Steps", .steps),
            (uuid("00000000-0000-4000-8000-000000001105"), "Quality", .quality),
        ]
        for fixture in exerciseFixtures.reversed() {
            writer.insert(exercise(id: fixture.0, name: fixture.1, measurement: fixture.2))
        }

        let completedSessionID = uuid("00000000-0000-4000-8000-000000001201")
        let completedSession = WorkoutSession(
            id: completedSessionID,
            createdAt: start.addingTimeInterval(100),
            updatedAt: start.addingTimeInterval(100),
            date: start.addingTimeInterval(200),
            status: .completed
        )
        let completedSets = [
            setLog(
                id: uuid("00000000-0000-4000-8000-000000001301"),
                exerciseID: exerciseFixtures[0].0,
                setIndex: 0,
                weightKg: 30,
                reps: 10,
                session: completedSession
            ),
            setLog(
                id: uuid("00000000-0000-4000-8000-000000001302"),
                exerciseID: exerciseFixtures[1].0,
                setIndex: 1,
                weightKg: 15,
                reps: 8,
                session: completedSession
            ),
            setLog(
                id: uuid("00000000-0000-4000-8000-000000001303"),
                exerciseID: exerciseFixtures[2].0,
                setIndex: 2,
                durationSec: 60,
                session: completedSession
            ),
            setLog(
                id: uuid("00000000-0000-4000-8000-000000001304"),
                exerciseID: exerciseFixtures[3].0,
                setIndex: 3,
                weightKg: 20,
                distanceSteps: 40,
                session: completedSession
            ),
            setLog(
                id: uuid("00000000-0000-4000-8000-000000001305"),
                exerciseID: exerciseFixtures[4].0,
                setIndex: 4,
                reps: 12,
                isWarmup: true,
                session: completedSession
            ),
        ]
        completedSession.setLogs = Array(completedSets.reversed())
        writer.insert(completedSession)
        for set in completedSets { writer.insert(set) }

        let plannedSession = WorkoutSession(
            id: uuid("00000000-0000-4000-8000-000000001202"),
            date: start.addingTimeInterval(300),
            status: .planned
        )
        let plannedSet = setLog(
            id: uuid("00000000-0000-4000-8000-000000001306"),
            exerciseID: exerciseFixtures[0].0,
            setIndex: 0,
            weightKg: 100,
            reps: 10,
            session: plannedSession
        )
        plannedSession.setLogs = [plannedSet]
        writer.insert(plannedSession)
        writer.insert(plannedSet)

        let endSession = WorkoutSession(
            id: uuid("00000000-0000-4000-8000-000000001203"),
            date: end,
            status: .completed
        )
        let endSet = setLog(
            id: uuid("00000000-0000-4000-8000-000000001307"),
            exerciseID: exerciseFixtures[0].0,
            setIndex: 0,
            weightKg: 200,
            reps: 10,
            session: endSession
        )
        endSession.setLogs = [endSet]
        writer.insert(endSession)
        writer.insert(endSet)
        try writer.save()

        let reader = ModelContext(container)
        let repository = reportsRepository(in: reader)
        let countsBefore = try persistedCounts(in: container)
        let fieldsBefore = try persistedFieldSnapshot(in: container)
        XCTAssertFalse(reader.hasChanges)

        let first = try await repository.fetchDashboardSource(in: interval)
        let second = try await repository.fetchDashboardSource(in: interval)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.bodyMetricRecords.map(\.id), bodyIDs)
        XCTAssertEqual(first.bodyMetricRecords.map(\.value), [80, 79, 78])
        XCTAssertEqual(first.exerciseSetRecords.map(\.id), completedSets.map(\.id))
        XCTAssertTrue(first.exerciseSetRecords.allSatisfy(\.sessionCompleted))
        XCTAssertEqual(
            first.exerciseSetRecords.map(\.measurement),
            [.weightedRepetitions, .repetitions, .duration, .steps, .quality]
        )
        XCTAssertEqual(first.exerciseSetRecords.map(\.exerciseName), exerciseFixtures.map { $0.1 })
        XCTAssertEqual(first.exerciseSetRecords.map(\.isWarmup), [false, false, false, false, true])
        XCTAssertFalse(reader.hasChanges)
        let countsAfter = try persistedCounts(in: container)
        XCTAssertEqual(countsAfter.bodyMetrics, countsBefore.bodyMetrics)
        XCTAssertEqual(countsAfter.sessions, countsBefore.sessions)
        XCTAssertEqual(countsAfter.setLogs, countsBefore.setLogs)
        XCTAssertEqual(countsAfter.exercises, countsBefore.exercises)
        XCTAssertEqual(try persistedFieldSnapshot(in: container), fieldsBefore)
    }

    func testInvalidBodyMetricFiniteOrCanonicalMappingFailsClosedWithoutMutation() async throws {
        let invalidFixtures: [(UUID, BodyMetric)] = [
            (
                uuid("00000000-0000-4000-8000-000000001401"),
                bodyMetric(
                    id: uuid("00000000-0000-4000-8000-000000001401"),
                    date: Date(timeIntervalSinceReferenceDate: 1_000),
                    value: .nan
                )
            ),
            (
                uuid("00000000-0000-4000-8000-000000001402"),
                BodyMetric(
                    id: uuid("00000000-0000-4000-8000-000000001402"),
                    date: Date(timeIntervalSinceReferenceDate: 1_000),
                    type: .custom,
                    customName: "  Boyun  ",
                    value: 39,
                    unit: " cm "
                )
            ),
        ]

        for fixture in invalidFixtures {
            let container = try ModelContainerFactory.make(for: .inMemory)
            let writer = ModelContext(container)
            writer.insert(fixture.1)
            try writer.save()
            let reader = ModelContext(container)
            let repository = reportsRepository(in: reader)

            do {
                _ = try await repository.fetchDashboardSource(in: broadInterval())
                XCTFail("Expected invalid persisted body data to fail closed.")
            } catch {
                XCTAssertEqual(
                    error as? ReportsRepositoryIntegrityError,
                    .invalidBodyMetric(id: fixture.0)
                )
            }
            XCTAssertFalse(reader.hasChanges)
            XCTAssertEqual(try persistedCounts(in: container).bodyMetrics, 1)
        }
    }

    func testInvalidExerciseFiniteAndRangeDataFailsClosedWithoutMutation() async throws {
        let exerciseID = uuid("00000000-0000-4000-8000-000000001501")
        let invalidSetIDs = [
            uuid("00000000-0000-4000-8000-000000001502"),
            uuid("00000000-0000-4000-8000-000000001503"),
        ]

        for (index, invalidSetID) in invalidSetIDs.enumerated() {
            let container = try ModelContainerFactory.make(for: .inMemory)
            let writer = ModelContext(container)
            writer.insert(exercise(id: exerciseID, name: "Squat", measurement: .weightReps))
            let session = WorkoutSession(
                id: uuid(String(format: "00000000-0000-4000-8000-%012d", 1_510 + index)),
                date: Date(timeIntervalSinceReferenceDate: 1_000),
                status: .completed
            )
            let invalid = setLog(
                id: invalidSetID,
                exerciseID: exerciseID,
                setIndex: index == 0 ? -1 : 0,
                weightKg: index == 0 ? 30 : .infinity,
                reps: 10,
                session: session
            )
            session.setLogs = [invalid]
            writer.insert(session)
            writer.insert(invalid)
            try writer.save()
            let reader = ModelContext(container)
            let repository = reportsRepository(in: reader)

            do {
                _ = try await repository.fetchDashboardSource(in: broadInterval())
                XCTFail("Expected invalid persisted exercise data to fail closed.")
            } catch {
                XCTAssertEqual(
                    error as? ReportsRepositoryIntegrityError,
                    .invalidExerciseSet(id: invalidSetID)
                )
            }
            XCTAssertFalse(reader.hasChanges)
            XCTAssertEqual(try persistedCounts(in: container).setLogs, 1)
        }
    }

    func testMissingSetSessionAndMissingExerciseMappingFailWithTypedIntegrityErrors() async throws {
        let orphanContainer = try ModelContainerFactory.make(for: .inMemory)
        let orphanWriter = ModelContext(orphanContainer)
        let orphanID = uuid("00000000-0000-4000-8000-000000001601")
        orphanWriter.insert(setLog(
            id: orphanID,
            exerciseID: uuid("00000000-0000-4000-8000-000000001602"),
            setIndex: 0,
            weightKg: 30,
            reps: 10,
            session: nil
        ))
        try orphanWriter.save()
        let orphanReader = ModelContext(orphanContainer)
        let orphanRepository = reportsRepository(in: orphanReader)

        do {
            _ = try await orphanRepository.fetchDashboardSource(in: broadInterval())
            XCTFail("Expected a missing workout-session relationship.")
        } catch {
            XCTAssertEqual(
                error as? ReportsRepositoryIntegrityError,
                .setLogMissingWorkoutSession(id: orphanID)
            )
        }
        XCTAssertFalse(orphanReader.hasChanges)

        let mappingContainer = try ModelContainerFactory.make(for: .inMemory)
        let mappingWriter = ModelContext(mappingContainer)
        let missingExerciseID = uuid("00000000-0000-4000-8000-000000001603")
        let mappedSetID = uuid("00000000-0000-4000-8000-000000001604")
        let session = WorkoutSession(
            id: uuid("00000000-0000-4000-8000-000000001605"),
            date: Date(timeIntervalSinceReferenceDate: 1_000),
            status: .completed
        )
        let mappedSet = setLog(
            id: mappedSetID,
            exerciseID: missingExerciseID,
            setIndex: 0,
            weightKg: 30,
            reps: 10,
            session: session
        )
        session.setLogs = [mappedSet]
        mappingWriter.insert(session)
        mappingWriter.insert(mappedSet)
        try mappingWriter.save()
        let mappingReader = ModelContext(mappingContainer)
        let mappingRepository = reportsRepository(in: mappingReader)

        do {
            _ = try await mappingRepository.fetchDashboardSource(in: broadInterval())
            XCTFail("Expected a missing exercise-template mapping.")
        } catch {
            XCTAssertEqual(
                error as? ReportsRepositoryIntegrityError,
                .missingExerciseTemplate(setLogID: mappedSetID, exerciseTemplateID: missingExerciseID)
            )
        }
        XCTAssertFalse(mappingReader.hasChanges)
    }

    func testExtremeWeightedRepetitionsFailWithTypedRangeIntegrityErrorWithoutTrapping() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let exerciseID = uuid("00000000-0000-4000-8000-000000001701")
        let setID = uuid("00000000-0000-4000-8000-000000001702")
        writer.insert(exercise(id: exerciseID, name: "Squat", measurement: .weightReps))
        let session = WorkoutSession(
            id: uuid("00000000-0000-4000-8000-000000001703"),
            date: Date(timeIntervalSinceReferenceDate: 1_000),
            status: .completed
        )
        let extreme = setLog(
            id: setID,
            exerciseID: exerciseID,
            setIndex: 0,
            weightKg: 1,
            reps: Int.max,
            session: session
        )
        session.setLogs = [extreme]
        writer.insert(session)
        writer.insert(extreme)
        try writer.save()
        let reader = ModelContext(container)
        let repository = reportsRepository(in: reader)

        do {
            _ = try await repository.fetchDashboardSource(in: broadInterval())
            XCTFail("Expected extreme repetitions to fail before projection reaches Epley.")
        } catch {
            XCTAssertEqual(
                error as? ReportsRepositoryIntegrityError,
                .invalidExerciseRepetitionRange(id: setID, reps: Int.max)
            )
        }
        XCTAssertFalse(reader.hasChanges)
    }

    func testLogicalDuplicateSetIndexesFailDeterministicallyWithoutMutation() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let exerciseID = uuid("00000000-0000-4000-8000-000000001711")
        let sessionID = uuid("00000000-0000-4000-8000-000000001712")
        let lowerID = uuid("00000000-0000-4000-8000-000000001713")
        let higherID = uuid("00000000-0000-4000-8000-000000001714")
        writer.insert(exercise(id: exerciseID, name: "Squat", measurement: .weightReps))
        let session = WorkoutSession(
            id: sessionID,
            date: Date(timeIntervalSinceReferenceDate: 1_000),
            status: .completed
        )
        let sets = [higherID, lowerID].map { id in
            setLog(
                id: id,
                exerciseID: exerciseID,
                setIndex: 0,
                weightKg: 30,
                reps: 10,
                session: session
            )
        }
        session.setLogs = sets
        writer.insert(session)
        for set in sets { writer.insert(set) }
        try writer.save()
        let reader = ModelContext(container)
        let repository = reportsRepository(in: reader)
        let before = try persistedFieldSnapshot(in: container)

        do {
            _ = try await repository.fetchDashboardSource(in: broadInterval())
            XCTFail("Expected a logical duplicate set index integrity error.")
        } catch {
            XCTAssertEqual(
                error as? ReportsRepositoryIntegrityError,
                .duplicateSetIndex(
                    sessionID: sessionID,
                    exerciseTemplateID: exerciseID,
                    setIndex: 0,
                    setLogIDs: [lowerID, higherID]
                )
            )
        }
        XCTAssertFalse(reader.hasChanges)
        XCTAssertEqual(try persistedFieldSnapshot(in: container), before)
    }

    func testOutOfRangeCorruptionAndOrphansDoNotPoisonSelectedInterval() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let end = Date(timeIntervalSinceReferenceDate: 2_000)
        let interval = ReportDateInterval(start: start, endExclusive: end)
        let selectedBodyID = uuid("00000000-0000-4000-8000-000000001721")
        writer.insert(bodyMetric(id: selectedBodyID, date: start.addingTimeInterval(10), value: 80))
        writer.insert(bodyMetric(
            id: uuid("00000000-0000-4000-8000-000000001722"),
            date: end.addingTimeInterval(100),
            value: .nan
        ))

        let exerciseID = uuid("00000000-0000-4000-8000-000000001723")
        writer.insert(exercise(id: exerciseID, name: "Squat", measurement: .weightReps))
        let selectedSession = WorkoutSession(
            id: uuid("00000000-0000-4000-8000-000000001724"),
            date: start.addingTimeInterval(20),
            status: .completed
        )
        let selectedSet = setLog(
            id: uuid("00000000-0000-4000-8000-000000001725"),
            exerciseID: exerciseID,
            setIndex: 0,
            weightKg: 30,
            reps: 10,
            session: selectedSession
        )
        selectedSession.setLogs = [selectedSet]
        writer.insert(selectedSession)
        writer.insert(selectedSet)

        let outsideSession = WorkoutSession(
            id: uuid("00000000-0000-4000-8000-000000001726"),
            date: end.addingTimeInterval(100),
            status: .completed
        )
        let invalidOutsideSet = setLog(
            id: uuid("00000000-0000-4000-8000-000000001727"),
            exerciseID: exerciseID,
            setIndex: -1,
            weightKg: .infinity,
            reps: 10,
            session: outsideSession
        )
        outsideSession.setLogs = [invalidOutsideSet]
        writer.insert(outsideSession)
        writer.insert(invalidOutsideSet)

        let unrelatedDuplicateID = uuid("00000000-0000-4000-8000-000000001730")
        writer.insert(WorkoutSession(
            id: unrelatedDuplicateID,
            date: end.addingTimeInterval(300),
            status: .completed
        ))
        writer.insert(WorkoutSession(
            id: unrelatedDuplicateID,
            date: end.addingTimeInterval(400),
            status: .planned
        ))

        writer.insert(setLog(
            id: uuid("00000000-0000-4000-8000-000000001728"),
            exerciseID: uuid("00000000-0000-4000-8000-000000001729"),
            setIndex: -1,
            weightKg: .infinity,
            reps: Int.max,
            completedAt: end.addingTimeInterval(200),
            session: nil
        ))
        try writer.save()
        let reader = ModelContext(container)
        let repository = reportsRepository(in: reader)
        let before = try persistedFieldSnapshot(in: container)

        let source = try await repository.fetchDashboardSource(in: interval)

        XCTAssertEqual(source.bodyMetricRecords.map(\.id), [selectedBodyID])
        XCTAssertEqual(source.exerciseSetRecords.map(\.id), [selectedSet.id])
        XCTAssertFalse(reader.hasChanges)
        XCTAssertEqual(try persistedFieldSnapshot(in: container), before)
    }

    func testSessionIDCollisionReferencedBySelectedSessionFailsInsteadOfRebindingSet() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let interval = broadInterval()
        let sharedSessionID = uuid("00000000-0000-4000-8000-000000001731")
        let exerciseID = uuid("00000000-0000-4000-8000-000000001732")
        let setID = uuid("00000000-0000-4000-8000-000000001733")
        writer.insert(exercise(id: exerciseID, name: "Squat", measurement: .weightReps))
        let selected = WorkoutSession(
            id: sharedSessionID,
            date: interval.start.addingTimeInterval(100),
            status: .completed
        )
        let unselected = WorkoutSession(
            id: sharedSessionID,
            date: interval.start.addingTimeInterval(200),
            status: .planned
        )
        let set = setLog(
            id: setID,
            exerciseID: exerciseID,
            setIndex: 0,
            weightKg: 30,
            reps: 10,
            session: unselected
        )
        unselected.setLogs = [set]
        writer.insert(selected)
        writer.insert(unselected)
        writer.insert(set)
        try writer.save()
        let reader = ModelContext(container)
        let repository = reportsRepository(in: reader)

        do {
            _ = try await repository.fetchDashboardSource(in: interval)
            XCTFail("Expected a selected-session UUID collision to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? ReportsRepositoryIntegrityError,
                .duplicateWorkoutSessionIDs(id: sharedSessionID, count: 2)
            )
        }
        XCTAssertFalse(reader.hasChanges)
    }

    func testSelectedBodyValidationChoosesLowestIDRegardlessOfInsertionOrder() async throws {
        let lowerID = uuid("00000000-0000-4000-8000-000000001741")
        let higherID = uuid("00000000-0000-4000-8000-000000001742")
        for reverse in [false, true] {
            let container = try ModelContainerFactory.make(for: .inMemory)
            let writer = ModelContext(container)
            let date = Date(timeIntervalSinceReferenceDate: 1_000)
            let models = [
                bodyMetric(id: lowerID, date: date, value: .nan),
                bodyMetric(id: higherID, date: date, value: .infinity),
            ]
            let orderedModels = reverse ? Array(models.reversed()) : models
            for model in orderedModels { writer.insert(model) }
            try writer.save()
            let repository = reportsRepository(in: ModelContext(container))

            do {
                _ = try await repository.fetchDashboardSource(in: broadInterval())
                XCTFail("Expected invalid selected body metrics.")
            } catch {
                XCTAssertEqual(
                    error as? ReportsRepositoryIntegrityError,
                    .invalidBodyMetric(id: lowerID)
                )
            }
        }
    }

    func testSelectedSessionValidationChoosesLowestIDRegardlessOfInsertionOrder() async throws {
        let lowerID = uuid("00000000-0000-4000-8000-000000001751")
        let higherID = uuid("00000000-0000-4000-8000-000000001752")
        for reverse in [false, true] {
            let container = try ModelContainerFactory.make(for: .inMemory)
            let writer = ModelContext(container)
            let date = Date(timeIntervalSinceReferenceDate: 1_000)
            let models = [
                WorkoutSession(
                    id: lowerID,
                    createdAt: Date(timeIntervalSinceReferenceDate: .infinity),
                    date: date,
                    status: .completed
                ),
                WorkoutSession(
                    id: higherID,
                    createdAt: Date(timeIntervalSinceReferenceDate: .infinity),
                    date: date,
                    status: .completed
                ),
            ]
            let orderedModels = reverse ? Array(models.reversed()) : models
            for model in orderedModels { writer.insert(model) }
            try writer.save()
            let reader = ModelContext(container)
            let persistedCandidates = try reader.fetch(FetchDescriptor<WorkoutSession>())
                .filter { $0.id == lowerID || $0.id == higherID }
            XCTAssertEqual(persistedCandidates.count, 2)
            XCTAssertTrue(persistedCandidates.allSatisfy {
                !$0.createdAt.timeIntervalSinceReferenceDate.isFinite
            })
            let repository = reportsRepository(in: reader)

            do {
                _ = try await repository.fetchDashboardSource(in: broadInterval())
                XCTFail("Expected invalid selected sessions.")
            } catch {
                XCTAssertEqual(
                    error as? ReportsRepositoryIntegrityError,
                    .invalidWorkoutSession(id: lowerID)
                )
            }
        }
    }

    func testSelectedSetValidationChoosesLowestIDRegardlessOfInsertionOrder() async throws {
        let lowerID = uuid("00000000-0000-4000-8000-000000001761")
        let higherID = uuid("00000000-0000-4000-8000-000000001762")
        for reverse in [false, true] {
            let container = try ModelContainerFactory.make(for: .inMemory)
            let writer = ModelContext(container)
            let exerciseID = uuid("00000000-0000-4000-8000-000000001763")
            writer.insert(exercise(id: exerciseID, name: "Squat", measurement: .weightReps))
            let session = WorkoutSession(
                id: uuid("00000000-0000-4000-8000-000000001764"),
                date: Date(timeIntervalSinceReferenceDate: 1_000),
                status: .completed
            )
            let models = [
                setLog(
                    id: lowerID,
                    exerciseID: exerciseID,
                    setIndex: -1,
                    weightKg: 30,
                    reps: 10,
                    session: session
                ),
                setLog(
                    id: higherID,
                    exerciseID: exerciseID,
                    setIndex: -2,
                    weightKg: 30,
                    reps: 10,
                    session: session
                ),
            ]
            session.setLogs = models
            writer.insert(session)
            let orderedModels = reverse ? Array(models.reversed()) : models
            for model in orderedModels { writer.insert(model) }
            try writer.save()
            let repository = reportsRepository(in: ModelContext(container))

            do {
                _ = try await repository.fetchDashboardSource(in: broadInterval())
                XCTFail("Expected invalid selected sets.")
            } catch {
                XCTAssertEqual(
                    error as? ReportsRepositoryIntegrityError,
                    .invalidExerciseSet(id: lowerID)
                )
            }
        }
    }

    func testSelectedExerciseValidationChoosesLowestIDRegardlessOfInsertionOrder() async throws {
        let lowerID = uuid("00000000-0000-4000-8000-000000001771")
        let higherID = uuid("00000000-0000-4000-8000-000000001772")
        for reverse in [false, true] {
            let container = try ModelContainerFactory.make(for: .inMemory)
            let writer = ModelContext(container)
            let exercises = [
                exercise(id: lowerID, name: " Lower invalid ", measurement: .weightReps),
                exercise(id: higherID, name: " Higher invalid ", measurement: .weightReps),
            ]
            let orderedExercises = reverse ? Array(exercises.reversed()) : exercises
            for model in orderedExercises { writer.insert(model) }
            let session = WorkoutSession(
                id: uuid("00000000-0000-4000-8000-000000001773"),
                date: Date(timeIntervalSinceReferenceDate: 1_000),
                status: .completed
            )
            let lowerExerciseSet = setLog(
                id: uuid("00000000-0000-4000-8000-000000001779"),
                exerciseID: lowerID,
                setIndex: 0,
                weightKg: 30,
                reps: 10,
                session: session
            )
            let higherExerciseSet = setLog(
                id: uuid("00000000-0000-4000-8000-000000001774"),
                exerciseID: higherID,
                setIndex: 1,
                weightKg: 30,
                reps: 10,
                session: session
            )
            session.setLogs = [higherExerciseSet, lowerExerciseSet]
            writer.insert(session)
            writer.insert(higherExerciseSet)
            writer.insert(lowerExerciseSet)
            try writer.save()
            let repository = reportsRepository(in: ModelContext(container))

            do {
                _ = try await repository.fetchDashboardSource(in: broadInterval())
                XCTFail("Expected invalid selected exercise templates.")
            } catch {
                XCTAssertEqual(
                    error as? ReportsRepositoryIntegrityError,
                    .invalidExerciseTemplate(id: lowerID)
                )
            }
        }
    }

    private func reportsRepository(in context: ModelContext) -> SwiftDataReportsRepository {
        SwiftDataReportsRepository(modelContext: context, calendar: istanbulCalendar())
    }

    private func istanbulCalendar() -> Calendar {
        guard let timeZone = TimeZone(identifier: "Europe/Istanbul") else {
            preconditionFailure("Istanbul timezone must exist in Foundation.")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    private func nutritionLog(id: UUID, date: Date) -> DailyNutritionLog {
        DailyNutritionLog(
            id: id,
            createdAt: date.addingTimeInterval(1),
            updatedAt: date.addingTimeInterval(2),
            date: date
        )
    }

    private func mealEntry(
        id: UUID,
        proteinG: Double,
        loggedAt: Date,
        log: DailyNutritionLog?
    ) -> MealEntry {
        MealEntry(
            id: id,
            createdAt: loggedAt.addingTimeInterval(1),
            updatedAt: loggedAt.addingTimeInterval(2),
            category: .defaultValue,
            adhocName: "Fixture",
            quantity: 1,
            caloriesResolved: 100,
            proteinResolved: proteinG,
            carbResolved: 10,
            fatResolved: 5,
            loggedAt: loggedAt,
            dailyNutritionLog: log
        )
    }

    private func nutritionFieldSnapshot(in container: ModelContainer) throws -> [String] {
        let context = ModelContext(container)
        var rows = try context.fetch(FetchDescriptor<UserProfile>()).map {
            "profile|\($0.id.uuidString)|\($0.proteinTargetG)"
        }
        rows += try context.fetch(FetchDescriptor<DailyNutritionLog>()).map {
            let entryIDs = ($0.mealEntries ?? [])
                .map(\.id.uuidString)
                .sorted()
                .joined(separator: ",")
            return "nutrition-day|\($0.id.uuidString)|\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.date.timeIntervalSinceReferenceDate)|\(entryIDs)"
        }
        rows += try context.fetch(FetchDescriptor<MealEntry>()).map {
            "meal|\($0.id.uuidString)|\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.quantity)|\($0.caloriesResolved)|\($0.proteinResolved)|\($0.carbResolved)|\($0.fatResolved)|\($0.loggedAt.timeIntervalSinceReferenceDate)|\(String(describing: $0.dailyNutritionLog?.id))"
        }
        return rows.sorted()
    }

    private func bodyMetric(id: UUID, date: Date, value: Double) -> BodyMetric {
        BodyMetric(
            id: id,
            createdAt: date,
            updatedAt: date,
            date: date,
            type: .weight,
            customName: nil,
            value: value,
            unit: "kg"
        )
    }

    private func exercise(
        id: UUID,
        name: String,
        measurement: ExerciseMeasurementKind
    ) -> ExerciseTemplate {
        ExerciseTemplate(
            id: id,
            name: name,
            targetSets: 1,
            measurementKind: measurement
        )
    }

    private func setLog(
        id: UUID,
        exerciseID: UUID,
        setIndex: Int,
        weightKg: Double? = nil,
        reps: Int? = nil,
        durationSec: Int? = nil,
        distanceSteps: Int? = nil,
        isWarmup: Bool = false,
        completedAt: Date? = nil,
        session: WorkoutSession?
    ) -> SetLog {
        SetLog(
            id: id,
            createdAt: session?.date ?? Date(timeIntervalSinceReferenceDate: 1_000),
            updatedAt: session?.date ?? Date(timeIntervalSinceReferenceDate: 1_000),
            exerciseTemplateId: exerciseID,
            setIndex: setIndex,
            weightKg: weightKg,
            reps: reps,
            durationSec: durationSec,
            distanceSteps: distanceSteps,
            isWarmupSet: isWarmup,
            completedAt: completedAt ?? session?.date ?? Date(timeIntervalSinceReferenceDate: 1_000),
            workoutSession: session
        )
    }

    private func persistedFieldSnapshot(in container: ModelContainer) throws -> [String] {
        let context = ModelContext(container)
        var rows: [String] = []
        rows += try context.fetch(FetchDescriptor<BodyMetric>()).map {
            "body|\($0.id.uuidString)|\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.date.timeIntervalSinceReferenceDate)|\($0.type)|\(String(describing: $0.customName))|\($0.value)|\($0.unit)"
        }
        rows += try context.fetch(FetchDescriptor<WorkoutSession>()).map {
            let setIDs = ($0.setLogs ?? []).map(\.id).map(\.uuidString).sorted().joined(separator: ",")
            return "session|\($0.id.uuidString)|\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.date.timeIntervalSinceReferenceDate)|\($0.status)|\($0.workoutDayTemplateId.uuidString)|\(String(describing: $0.perceivedRecovery))|\(String(describing: $0.note))|\($0.ohpSymptomResponse)|\(String(describing: $0.ohpSymptomCheckedAt))|\(setIDs)"
        }
        rows += try context.fetch(FetchDescriptor<SetLog>()).map {
            "set|\($0.id.uuidString)|\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.exerciseTemplateId.uuidString)|\($0.setIndex)|\(String(describing: $0.weightKg))|\(String(describing: $0.reps))|\(String(describing: $0.durationSec))|\(String(describing: $0.distanceSteps))|\(String(describing: $0.performedVariant))|\(String(describing: $0.rir))|\($0.isWarmupSet)|\($0.completedAt.timeIntervalSinceReferenceDate)|\(String(describing: $0.workoutSession?.id))"
        }
        rows += try context.fetch(FetchDescriptor<ExerciseTemplate>()).map {
            "exercise|\($0.id.uuidString)|\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.name)|\($0.orderIndex)|\($0.targetSets)|\(String(describing: $0.repLow))|\(String(describing: $0.repHigh))|\($0.rirLow)|\($0.rirHigh)|\($0.category)|\($0.allowFailure)|\($0.cues)|\(String(describing: $0.safetyNote))|\(String(describing: $0.startingWeightKg))|\($0.progressionRule)|\($0.measurementKind)|\(String(describing: $0.supersetGroupId))|\(String(describing: $0.supersetOrder))|\(String(describing: $0.workoutDayTemplate?.id))"
        }
        return rows.sorted()
    }

    private func persistedCounts(
        in container: ModelContainer
    ) throws -> (bodyMetrics: Int, sessions: Int, setLogs: Int, exercises: Int) {
        let context = ModelContext(container)
        return (
            try context.fetchCount(FetchDescriptor<BodyMetric>()),
            try context.fetchCount(FetchDescriptor<WorkoutSession>()),
            try context.fetchCount(FetchDescriptor<SetLog>()),
            try context.fetchCount(FetchDescriptor<ExerciseTemplate>())
        )
    }

    private func broadInterval() -> ReportDateInterval {
        ReportDateInterval(
            start: Date(timeIntervalSinceReferenceDate: 0),
            endExclusive: Date(timeIntervalSinceReferenceDate: 10_000)
        )
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
    }
}
