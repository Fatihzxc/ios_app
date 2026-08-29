import CoreModels
import Foundation
@testable import PersistenceKit
import ReportsKit
import SwiftData
import XCTest

@MainActor
final class PhaseTransitionLedgerRepositoryTests: XCTestCase {
    private enum FixtureFailure: Error { case save }

    func testActualPhaseChangeAppendsExplicitRecordAndPersistsStateAndLedgerTogether() async throws {
        let fixture = try makeProgramFixture()
        let recordID = uuid(101)
        let settingID = uuid(102)
        let transitionedAt = date(500)
        var saveCount = 0
        let repository = SwiftDataTrainingRepository(
            modelContext: fixture.context,
            phaseTransitionRecordID: { recordID },
            phaseTransitionSettingID: { settingID },
            save: {
                saveCount += 1
                try fixture.context.save()
            },
            rollback: { fixture.context.rollback() }
        )

        let updated = try await repository.setActiveProgramPhase(
            programID: fixture.program.id,
            phaseID: fixture.next.id,
            at: transitionedAt
        )

        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(updated.currentPhaseId, fixture.next.id)
        XCTAssertEqual(updated.phaseStartedAt, transitionedAt)
        XCTAssertEqual(updated.updatedAt, transitionedAt)
        let settings = try fixture.context.fetch(FetchDescriptor<AppSetting>())
        let setting = try XCTUnwrap(settings.only)
        XCTAssertEqual(setting.id, settingID)
        XCTAssertEqual(setting.key, PhaseTransitionLedgerV1.key(for: fixture.program.id))
        XCTAssertEqual(setting.createdAt, transitionedAt)
        XCTAssertEqual(setting.updatedAt, transitionedAt)
        let ledger = try PhaseTransitionLedgerV1.decode(setting.value, for: fixture.program.id)
        XCTAssertEqual(ledger.records, [
            PhaseTransitionRecord(
                id: recordID,
                programID: fixture.program.id,
                fromPhaseID: fixture.current.id,
                toPhaseID: fixture.next.id,
                fromStartedAt: fixture.startedAt,
                transitionedAt: transitionedAt
            )
        ])

        let reopened = ModelContext(fixture.container)
        let state = try XCTUnwrap(reopened.fetch(FetchDescriptor<ProgramState>()).only)
        let persistedSetting = try XCTUnwrap(reopened.fetch(FetchDescriptor<AppSetting>()).only)
        XCTAssertEqual(state.currentPhaseId, fixture.next.id)
        XCTAssertEqual(
            try PhaseTransitionLedgerV1.decode(persistedSetting.value, for: fixture.program.id),
            ledger
        )
    }

    func testSamePhaseIsTrueNoOpWithoutLedgerIDsTimestampChangeOrSave() async throws {
        let fixture = try makeProgramFixture()
        var recordIDCount = 0
        var settingIDCount = 0
        var saveCount = 0
        let repository = SwiftDataTrainingRepository(
            modelContext: fixture.context,
            phaseTransitionRecordID: {
                recordIDCount += 1
                return self.uuid(201)
            },
            phaseTransitionSettingID: {
                settingIDCount += 1
                return self.uuid(202)
            },
            save: { saveCount += 1 },
            rollback: { fixture.context.rollback() }
        )

        let result = try await repository.setActiveProgramPhase(
            programID: fixture.program.id,
            phaseID: fixture.current.id,
            at: date(999)
        )

        XCTAssertTrue(result === fixture.state)
        XCTAssertEqual(result.phaseStartedAt, fixture.startedAt)
        XCTAssertEqual(result.updatedAt, fixture.stateUpdatedAt)
        XCTAssertEqual(recordIDCount, 0)
        XCTAssertEqual(settingIDCount, 0)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AppSetting>()), 0)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testSamePhaseWithUnrelatedPendingMutationSucceedsWithoutAnySideEffect() async throws {
        let fixture = try makeProgramFixture()
        let unrelated = UserProfile(id: uuid(251), displayName: "Kaydedilmemiş")
        fixture.context.insert(unrelated)
        var recordIDCount = 0
        var settingIDCount = 0
        var saveCount = 0
        var rollbackCount = 0
        let repository = SwiftDataTrainingRepository(
            modelContext: fixture.context,
            phaseTransitionRecordID: {
                recordIDCount += 1
                return self.uuid(252)
            },
            phaseTransitionSettingID: {
                settingIDCount += 1
                return self.uuid(253)
            },
            save: { saveCount += 1 },
            rollback: {
                rollbackCount += 1
                fixture.context.rollback()
            }
        )

        let result = try await repository.setActiveProgramPhase(
            programID: fixture.program.id,
            phaseID: fixture.current.id,
            at: date(999)
        )

        XCTAssertTrue(result === fixture.state)
        XCTAssertEqual(result.currentPhaseId, fixture.current.id)
        XCTAssertEqual(result.phaseStartedAt, fixture.startedAt)
        XCTAssertEqual(result.updatedAt, fixture.stateUpdatedAt)
        XCTAssertEqual(recordIDCount, 0)
        XCTAssertEqual(settingIDCount, 0)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(rollbackCount, 0)
        XCTAssertTrue(fixture.context.hasChanges)
        XCTAssertEqual(unrelated.displayName, "Kaydedilmemiş")
        XCTAssertEqual(try ModelContext(fixture.container).fetchCount(FetchDescriptor<UserProfile>()), 0)
    }

    func testZeroDurationFirstTransitionFailsBeforeIDsMutationSaveOrRollback() async throws {
        let fixture = try makeProgramFixture()
        var recordIDCount = 0
        var settingIDCount = 0
        var saveCount = 0
        var rollbackCount = 0
        let repository = SwiftDataTrainingRepository(
            modelContext: fixture.context,
            phaseTransitionRecordID: {
                recordIDCount += 1
                return self.uuid(261)
            },
            phaseTransitionSettingID: {
                settingIDCount += 1
                return self.uuid(262)
            },
            save: { saveCount += 1 },
            rollback: { rollbackCount += 1 }
        )

        do {
            _ = try await repository.setActiveProgramPhase(
                programID: fixture.program.id,
                phaseID: fixture.next.id,
                at: fixture.startedAt
            )
            XCTFail("Expected strict transition timestamp failure")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryMutationError,
                .invalidPhaseTransitionDate(
                    programID: fixture.program.id,
                    currentPhaseStartedAt: fixture.startedAt,
                    transitionedAt: fixture.startedAt
                )
            )
        }

        XCTAssertEqual(recordIDCount, 0)
        XCTAssertEqual(settingIDCount, 0)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(rollbackCount, 0)
        XCTAssertEqual(fixture.state.currentPhaseId, fixture.current.id)
        XCTAssertEqual(fixture.state.phaseStartedAt, fixture.startedAt)
        XCTAssertEqual(fixture.state.updatedAt, fixture.stateUpdatedAt)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AppSetting>()), 0)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testSequentialTransitionsAtSameTimestampRejectSecondWithoutPartialMutation() async throws {
        let fixture = try makeProgramFixture()
        let transitionedAt = date(500)
        var recordIDCount = 0
        var settingIDCount = 0
        var saveCount = 0
        var rollbackCount = 0
        let repository = SwiftDataTrainingRepository(
            modelContext: fixture.context,
            phaseTransitionRecordID: {
                recordIDCount += 1
                return self.uuid(270 + recordIDCount)
            },
            phaseTransitionSettingID: {
                settingIDCount += 1
                return self.uuid(280 + settingIDCount)
            },
            save: {
                saveCount += 1
                try fixture.context.save()
            },
            rollback: {
                rollbackCount += 1
                fixture.context.rollback()
            }
        )
        _ = try await repository.setActiveProgramPhase(
            programID: fixture.program.id,
            phaseID: fixture.next.id,
            at: transitionedAt
        )
        let setting = try XCTUnwrap(fixture.context.fetch(FetchDescriptor<AppSetting>()).only)
        let savedLedgerValue = setting.value
        let savedSettingUpdatedAt = setting.updatedAt

        do {
            _ = try await repository.setActiveProgramPhase(
                programID: fixture.program.id,
                phaseID: fixture.current.id,
                at: transitionedAt
            )
            XCTFail("Expected duplicate transition timestamp rejection")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryMutationError,
                .invalidPhaseTransitionDate(
                    programID: fixture.program.id,
                    currentPhaseStartedAt: transitionedAt,
                    transitionedAt: transitionedAt
                )
            )
        }

        XCTAssertEqual(recordIDCount, 1)
        XCTAssertEqual(settingIDCount, 1)
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(rollbackCount, 0)
        XCTAssertEqual(fixture.state.currentPhaseId, fixture.next.id)
        XCTAssertEqual(fixture.state.phaseStartedAt, transitionedAt)
        XCTAssertEqual(fixture.state.updatedAt, transitionedAt)
        XCTAssertEqual(setting.value, savedLedgerValue)
        XCTAssertEqual(setting.updatedAt, savedSettingUpdatedAt)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testMalformedAndUnknownLedgerFailBeforeAnyStateMutation() async throws {
        for value in ["{", #"{"records":[],"schemaVersion":2}"#] {
            let fixture = try makeProgramFixture()
            fixture.context.insert(AppSetting(
                id: uuid(301),
                createdAt: date(250),
                updatedAt: date(250),
                key: PhaseTransitionLedgerV1.key(for: fixture.program.id),
                value: value
            ))
            try fixture.context.save()
            let repository = SwiftDataTrainingRepository(
                modelContext: fixture.context,
                phaseTransitionRecordID: { self.uuid(302) },
                phaseTransitionSettingID: { self.uuid(303) }
            )

            do {
                _ = try await repository.setActiveProgramPhase(
                    programID: fixture.program.id,
                    phaseID: fixture.next.id,
                    at: date(500)
                )
                XCTFail("Expected typed ledger integrity failure")
            } catch {
                guard let typed = error as? TrainingRepositoryIntegrityError,
                      case let .invalidPhaseTransitionLedger(programID, _) = typed else {
                    XCTFail("Expected typed ledger integrity failure, got \(error)")
                    continue
                }
                XCTAssertEqual(programID, fixture.program.id)
            }
            XCTAssertEqual(fixture.state.currentPhaseId, fixture.current.id)
            XCTAssertEqual(fixture.state.phaseStartedAt, fixture.startedAt)
            XCTAssertEqual(fixture.state.updatedAt, fixture.stateUpdatedAt)
            XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<AppSetting>()).only?.value, value)
            XCTAssertFalse(fixture.context.hasChanges)
        }
    }

    func testInjectedSaveFailureRollsBackNewSettingAndEveryStateFieldExactly() async throws {
        let fixture = try makeProgramFixture()
        let repository = SwiftDataTrainingRepository(
            modelContext: fixture.context,
            phaseTransitionRecordID: { self.uuid(401) },
            phaseTransitionSettingID: { self.uuid(402) },
            save: { throw FixtureFailure.save },
            rollback: { fixture.context.rollback() }
        )

        do {
            _ = try await repository.setActiveProgramPhase(
                programID: fixture.program.id,
                phaseID: fixture.next.id,
                at: date(500)
            )
            XCTFail("Expected save failure")
        } catch {
            XCTAssertEqual(error as? TrainingRepositoryOperationError, .phaseTransitionSaveFailed)
        }

        XCTAssertEqual(fixture.state.currentPhaseId, fixture.current.id)
        XCTAssertEqual(fixture.state.phaseStartedAt, fixture.startedAt)
        XCTAssertEqual(fixture.state.updatedAt, fixture.stateUpdatedAt)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AppSetting>()), 0)
        XCTAssertFalse(fixture.context.hasChanges)
        let reopened = ModelContext(fixture.container)
        let state = try XCTUnwrap(reopened.fetch(FetchDescriptor<ProgramState>()).only)
        XCTAssertEqual(state.currentPhaseId, fixture.current.id)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<AppSetting>()), 0)
    }

    func testInjectedSaveFailureRestoresExistingSettingFieldsExactly() async throws {
        let fixture = try makeProgramFixture()
        let originalUpdatedAt = date(250)
        let originalValue = emptyLedger()
        let setting = AppSetting(
            id: uuid(451),
            createdAt: date(200),
            updatedAt: originalUpdatedAt,
            key: PhaseTransitionLedgerV1.key(for: fixture.program.id),
            value: originalValue
        )
        fixture.context.insert(setting)
        try fixture.context.save()
        let repository = SwiftDataTrainingRepository(
            modelContext: fixture.context,
            phaseTransitionRecordID: { self.uuid(452) },
            phaseTransitionSettingID: { self.uuid(453) },
            save: { throw FixtureFailure.save },
            rollback: { fixture.context.rollback() }
        )

        do {
            _ = try await repository.setActiveProgramPhase(
                programID: fixture.program.id,
                phaseID: fixture.next.id,
                at: date(500)
            )
            XCTFail("Expected save failure")
        } catch {
            XCTAssertEqual(error as? TrainingRepositoryOperationError, .phaseTransitionSaveFailed)
        }

        XCTAssertEqual(fixture.state.currentPhaseId, fixture.current.id)
        XCTAssertEqual(fixture.state.phaseStartedAt, fixture.startedAt)
        XCTAssertEqual(fixture.state.updatedAt, fixture.stateUpdatedAt)
        XCTAssertEqual(setting.value, originalValue)
        XCTAssertEqual(setting.updatedAt, originalUpdatedAt)
        XCTAssertFalse(fixture.context.hasChanges)
        let reopened = ModelContext(fixture.container)
        let persistedSetting = try XCTUnwrap(reopened.fetch(FetchDescriptor<AppSetting>()).only)
        XCTAssertEqual(persistedSetting.value, originalValue)
        XCTAssertEqual(persistedSetting.updatedAt, originalUpdatedAt)
    }

    func testUnrelatedPendingMutationIsNeitherSavedNorDiscarded() async throws {
        let fixture = try makeProgramFixture()
        let unrelated = UserProfile(displayName: "Önce")
        fixture.context.insert(unrelated)
        unrelated.displayName = "Kaydedilmemiş"
        let repository = SwiftDataTrainingRepository(
            modelContext: fixture.context,
            phaseTransitionRecordID: { self.uuid(501) },
            phaseTransitionSettingID: { self.uuid(502) }
        )

        do {
            _ = try await repository.setActiveProgramPhase(
                programID: fixture.program.id,
                phaseID: fixture.next.id,
                at: date(500)
            )
            XCTFail("Expected pending context failure")
        } catch {
            XCTAssertEqual(error as? TrainingRepositoryOperationError, .pendingContextChanges)
        }

        XCTAssertTrue(fixture.context.hasChanges)
        XCTAssertEqual(unrelated.displayName, "Kaydedilmemiş")
        XCTAssertEqual(fixture.state.currentPhaseId, fixture.current.id)
        XCTAssertEqual(try ModelContext(fixture.container).fetchCount(FetchDescriptor<UserProfile>()), 0)
    }

    func testDuplicateSettingStateAndPhaseIdentitiesFailDeterministically() async throws {
        let settingFixture = try makeProgramFixture()
        let key = PhaseTransitionLedgerV1.key(for: settingFixture.program.id)
        settingFixture.context.insert(AppSetting(id: uuid(601), key: key, value: emptyLedger()))
        settingFixture.context.insert(AppSetting(id: uuid(602), key: key, value: emptyLedger()))
        try settingFixture.context.save()
        await assertTransitionError(
            in: settingFixture,
            expected: .duplicatePhaseTransitionSettings(programID: settingFixture.program.id, count: 2)
        )

        let stateFixture = try makeProgramFixture()
        stateFixture.context.insert(ProgramState(
            programId: stateFixture.program.id,
            currentPhaseId: stateFixture.current.id,
            phaseStartedAt: stateFixture.startedAt
        ))
        try stateFixture.context.save()
        await assertTransitionError(
            in: stateFixture,
            expected: .duplicateProgramStates(programID: stateFixture.program.id, count: 2)
        )

        let phaseFixture = try makeProgramFixture()
        phaseFixture.context.insert(ProgramPhase(
            id: phaseFixture.next.id,
            name: "Kimlik çakışması",
            orderIndex: 3,
            program: phaseFixture.program
        ))
        try phaseFixture.context.save()
        await assertTransitionError(
            in: phaseFixture,
            expected: .duplicateProgramPhases(
                programID: phaseFixture.program.id,
                phaseID: phaseFixture.next.id,
                count: 2
            )
        )
    }

    func testCrossProgramTargetFailsWithoutCreatingLedger() async throws {
        let fixture = try makeProgramFixture()
        let otherProgram = Program(id: uuid(701), name: "Başka")
        let otherPhase = ProgramPhase(id: uuid(702), name: "Başka faz", program: otherProgram)
        fixture.context.insert(otherProgram)
        fixture.context.insert(otherPhase)
        try fixture.context.save()

        do {
            _ = try await fixture.repository.setActiveProgramPhase(
                programID: fixture.program.id,
                phaseID: otherPhase.id,
                at: date(500)
            )
            XCTFail("Expected cross-program phase rejection")
        } catch {
            XCTAssertEqual(
                error as? TrainingRepositoryMutationError,
                .phaseNotFound(programID: fixture.program.id, phaseID: otherPhase.id)
            )
        }
        XCTAssertEqual(fixture.state.currentPhaseId, fixture.current.id)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AppSetting>()), 0)
    }

    func testReportsRepositoryProjectsLifestyleCurrentProgramAndActualLedgerReadOnly() async throws {
        let fixture = try makeProgramFixture()
        let transitionDate = date(500)
        _ = try await SwiftDataTrainingRepository(
            modelContext: fixture.context,
            phaseTransitionRecordID: { self.uuid(801) },
            phaseTransitionSettingID: { self.uuid(802) }
        ).setActiveProgramPhase(
            programID: fixture.program.id,
            phaseID: fixture.next.id,
            at: transitionDate
        )
        fixture.context.insert(SleepLog(
            id: uuid(811), createdAt: date(310), updatedAt: date(310), date: date(300),
            durationHours: 7.5, quality: 8
        ))
        fixture.context.insert(MoodLog(
            id: uuid(812), createdAt: date(320), updatedAt: date(320), date: date(300),
            moodScore: 0, moodTags: [], energy: nil
        ))
        fixture.context.insert(PostureMetric(
            id: uuid(813), createdAt: date(330), updatedAt: date(330), date: date(300),
            wallTestPass: nil, symptomScore: 0
        ))
        try fixture.context.save()
        let reader = ModelContext(fixture.container)
        let before = try persistenceSnapshot(reader)
        let repository = SwiftDataReportsRepository(modelContext: reader, calendar: utcCalendar())

        let first = try await repository.fetchDashboardSource(
            in: ReportDateInterval(start: date(0), endExclusive: date(1_000))
        )
        let second = try await repository.fetchDashboardSource(
            in: ReportDateInterval(start: date(0), endExclusive: date(1_000))
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.sleepRecords.map(\.id), [uuid(811)])
        XCTAssertEqual(first.moodRecords.map(\.score), [0])
        XCTAssertEqual(first.postureRecords.map(\.symptomScore), [0])
        XCTAssertEqual(first.programPhases.map(\.id), [fixture.current.id, fixture.next.id])
        XCTAssertEqual(first.currentPhaseState?.phaseID, fixture.next.id)
        XCTAssertEqual(first.phaseTransitions.map(\.id), [uuid(801)])
        XCTAssertEqual(first.coverage.observedCount, 3)
        XCTAssertFalse(reader.hasChanges)
        XCTAssertEqual(try persistenceSnapshot(reader), before)
    }

    func testLoneCurrentStateProjectsPartialEvidenceAndNeverInfersFromMonthFields() async throws {
        let fixture = try makeProgramFixture()
        fixture.current.monthStart = 1
        fixture.current.monthEnd = 99
        fixture.next.monthStart = 100
        fixture.next.monthEnd = 200
        try fixture.context.save()

        let source = try await SwiftDataReportsRepository(
            modelContext: ModelContext(fixture.container),
            calendar: utcCalendar()
        ).fetchDashboardSource(in: ReportDateInterval(start: date(0), endExclusive: date(1_000)))
        let report = try LifestylePhaseDatasetBuilder.build(source: source, interval: ReportDateInterval(
            start: date(0), endExclusive: date(1_000)
        ), calendar: utcCalendar())

        XCTAssertTrue(source.phaseTransitions.isEmpty)
        XCTAssertEqual(report.phaseTimelineProvenance, .partialCurrentState)
        XCTAssertEqual(report.phaseSegments.count, 1)
        XCTAssertEqual(report.phaseSegments.only?.phaseID, fixture.current.id)
    }

    func testNoProgramStateAndNoLedgerProjectsHonestUnavailableEvidence() async throws {
        let fixture = try makeProgramFixture()
        fixture.context.delete(fixture.state)
        try fixture.context.save()

        let source = try await SwiftDataReportsRepository(
            modelContext: ModelContext(fixture.container),
            calendar: utcCalendar()
        ).fetchDashboardSource(in: ReportDateInterval(start: date(0), endExclusive: date(1_000)))
        let report = try LifestylePhaseDatasetBuilder.build(
            source: source,
            interval: ReportDateInterval(start: date(0), endExclusive: date(1_000)),
            calendar: utcCalendar()
        )

        XCTAssertNil(source.currentPhaseState)
        XCTAssertTrue(source.phaseTransitions.isEmpty)
        XCTAssertEqual(report.phaseTimelineProvenance, .unavailable)
        XCTAssertTrue(report.phaseSegments.isEmpty)
    }

    func testNoProgramStateWithValidNonemptyLedgerFailsStateLedgerMismatch() async throws {
        let fixture = try makeProgramFixture()
        fixture.context.delete(fixture.state)
        let record = PhaseTransitionRecord(
            id: uuid(851),
            programID: fixture.program.id,
            fromPhaseID: fixture.current.id,
            toPhaseID: fixture.next.id,
            fromStartedAt: fixture.startedAt,
            transitionedAt: date(500)
        )
        fixture.context.insert(AppSetting(
            id: uuid(852),
            key: PhaseTransitionLedgerV1.key(for: fixture.program.id),
            value: try PhaseTransitionLedgerV1(records: [record]).encoded(for: fixture.program.id)
        ))
        try fixture.context.save()

        await assertReportsError(
            in: fixture,
            expected: .phaseTransitionStateMismatch(programID: fixture.program.id)
        )
    }

    func testNoProgramStateWithValidEmptyLedgerSettingFailsStateLedgerMismatch() async throws {
        let fixture = try makeProgramFixture()
        fixture.context.delete(fixture.state)
        fixture.context.insert(AppSetting(
            id: uuid(861),
            key: PhaseTransitionLedgerV1.key(for: fixture.program.id),
            value: emptyLedger()
        ))
        try fixture.context.save()

        await assertReportsError(
            in: fixture,
            expected: .phaseTransitionStateMismatch(programID: fixture.program.id)
        )
    }

    func testNoProgramStateStillDecodesMalformedUnknownCrossProgramAndBrokenLedgers() async throws {
        let programID = uuid(1)
        let crossProgram = PhaseTransitionRecord(
            id: uuid(871),
            programID: uuid(999),
            fromPhaseID: uuid(2),
            toPhaseID: uuid(3),
            fromStartedAt: date(100),
            transitionedAt: date(200)
        )
        let first = PhaseTransitionRecord(
            id: uuid(872),
            programID: programID,
            fromPhaseID: uuid(2),
            toPhaseID: uuid(3),
            fromStartedAt: date(100),
            transitionedAt: date(200)
        )
        let broken = PhaseTransitionRecord(
            id: uuid(873),
            programID: programID,
            fromPhaseID: uuid(998),
            toPhaseID: uuid(2),
            fromStartedAt: date(200),
            transitionedAt: date(300)
        )
        let cases: [(String, PhaseTransitionLedgerError)] = [
            ("{", .malformedPayload),
            (#"{"records":[],"schemaVersion":2}"#, .unsupportedSchemaVersion(2)),
            (
                try uncheckedLedger([crossProgram]),
                .crossProgramRecord(
                    recordID: crossProgram.id,
                    expectedProgramID: programID,
                    actualProgramID: crossProgram.programID
                )
            ),
            (
                try uncheckedLedger([broken, first]),
                .brokenTransitionChain(previousRecordID: first.id, recordID: broken.id)
            ),
        ]

        for (index, testCase) in cases.enumerated() {
            let fixture = try makeProgramFixture()
            fixture.context.delete(fixture.state)
            fixture.context.insert(AppSetting(
                id: uuid(880 + index),
                key: PhaseTransitionLedgerV1.key(for: fixture.program.id),
                value: testCase.0
            ))
            try fixture.context.save()

            await assertReportsError(
                in: fixture,
                expected: .invalidPhaseTransitionLedger(
                    programID: fixture.program.id,
                    testCase.1
                )
            )
        }
    }

    func testOutOfIntervalAndOtherProgramCorruptionDoesNotPoisonSelectedProjection() async throws {
        let fixture = try makeProgramFixture()
        fixture.context.insert(SleepLog(
            id: uuid(901), createdAt: date(20_000), updatedAt: date(20_000), date: date(20_000),
            durationHours: .nan, quality: 99
        ))
        let otherProgram = Program(id: uuid(902), name: "Pasif", isActive: false)
        fixture.context.insert(otherProgram)
        fixture.context.insert(ProgramState(
            id: uuid(903), programId: otherProgram.id, currentPhaseId: uuid(999),
            phaseStartedAt: Date(timeIntervalSinceReferenceDate: .nan)
        ))
        try fixture.context.save()

        let source = try await SwiftDataReportsRepository(
            modelContext: ModelContext(fixture.container),
            calendar: utcCalendar()
        ).fetchDashboardSource(in: ReportDateInterval(start: date(0), endExclusive: date(1_000)))

        XCTAssertTrue(source.sleepRecords.isEmpty)
        XCTAssertEqual(source.currentPhaseState?.programID, fixture.program.id)
    }

    private struct ProgramFixture {
        let container: ModelContainer
        let context: ModelContext
        let repository: SwiftDataTrainingRepository
        let program: Program
        let current: ProgramPhase
        let next: ProgramPhase
        let state: ProgramState
        let startedAt: Date
        let stateUpdatedAt: Date
    }

    private func makeProgramFixture() throws -> ProgramFixture {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let program = Program(id: uuid(1), name: "Program", isActive: true)
        let current = ProgramPhase(
            id: uuid(2), name: "Temel", orderIndex: 1, monthStart: 1, monthEnd: 2,
            program: program
        )
        let next = ProgramPhase(
            id: uuid(3), name: "İnşa", orderIndex: 2, monthStart: 3, monthEnd: 6,
            program: program
        )
        let startedAt = date(100)
        let stateUpdatedAt = date(150)
        let state = ProgramState(
            id: uuid(4), createdAt: date(90), updatedAt: stateUpdatedAt,
            programId: program.id, currentPhaseId: current.id, phaseStartedAt: startedAt
        )
        context.insert(program)
        context.insert(current)
        context.insert(next)
        context.insert(state)
        try context.save()
        return ProgramFixture(
            container: container,
            context: context,
            repository: SwiftDataTrainingRepository(modelContext: context),
            program: program,
            current: current,
            next: next,
            state: state,
            startedAt: startedAt,
            stateUpdatedAt: stateUpdatedAt
        )
    }

    private func assertTransitionError(
        in fixture: ProgramFixture,
        expected: TrainingRepositoryIntegrityError
    ) async {
        do {
            _ = try await fixture.repository.setActiveProgramPhase(
                programID: fixture.program.id,
                phaseID: fixture.next.id,
                at: date(500)
            )
            XCTFail("Expected transition integrity error")
        } catch {
            XCTAssertEqual(error as? TrainingRepositoryIntegrityError, expected)
        }
        XCTAssertEqual(fixture.state.currentPhaseId, fixture.current.id)
        XCTAssertEqual(fixture.state.phaseStartedAt, fixture.startedAt)
    }

    private func assertReportsError(
        in fixture: ProgramFixture,
        expected: ReportsRepositoryIntegrityError
    ) async {
        do {
            _ = try await SwiftDataReportsRepository(
                modelContext: ModelContext(fixture.container),
                calendar: utcCalendar()
            ).fetchDashboardSource(
                in: ReportDateInterval(start: date(0), endExclusive: date(1_000))
            )
            XCTFail("Expected reports integrity failure")
        } catch {
            XCTAssertEqual(error as? ReportsRepositoryIntegrityError, expected)
        }
    }

    private func emptyLedger() -> String {
        try! PhaseTransitionLedgerV1(records: []).encoded(for: uuid(1))
    }

    private func uncheckedLedger(_ records: [PhaseTransitionRecord]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(PhaseTransitionLedgerV1(records: records)), as: UTF8.self)
    }

    private func persistenceSnapshot(_ context: ModelContext) throws -> [String] {
        let sleep = try context.fetch(FetchDescriptor<SleepLog>()).map {
            "sleep:\($0.id.uuidString):\($0.durationHours):\($0.quality)"
        }
        let mood = try context.fetch(FetchDescriptor<MoodLog>()).map {
            "mood:\($0.id.uuidString):\(String(describing: $0.moodScore))"
        }
        let posture = try context.fetch(FetchDescriptor<PostureMetric>()).map {
            "posture:\($0.id.uuidString):\(String(describing: $0.symptomScore))"
        }
        let state = try context.fetch(FetchDescriptor<ProgramState>()).map {
            "state:\($0.id.uuidString):\($0.currentPhaseId.uuidString):\($0.phaseStartedAt.timeIntervalSinceReferenceDate)"
        }
        let settings = try context.fetch(FetchDescriptor<AppSetting>()).map {
            "setting:\($0.id.uuidString):\($0.key):\($0.value)"
        }
        return (sleep + mood + posture + state + settings).sorted()
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: value)
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
