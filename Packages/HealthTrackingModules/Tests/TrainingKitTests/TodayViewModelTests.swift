import CoreModels
import Foundation
import TrainingKit
import XCTest

@MainActor
final class TodayViewModelTests: XCTestCase {
    private let dayA = UUID(uuidString: "00000000-0000-4000-8000-000000000201")!
    private let dayB = UUID(uuidString: "00000000-0000-4000-8000-000000000202")!
    private let phase1 = UUID(uuidString: "00000000-0000-4000-8000-000000000301")!
    private let phase2 = UUID(uuidString: "00000000-0000-4000-8000-000000000302")!

    func testApplyingPreloadedSnapshotPublishesContentWithoutRepositoryFetch() {
        let repository = TodayRepositorySpy()
        var callbackCount = 0
        let viewModel = makeViewModel(
            repository: repository,
            launchStartedAt: 100,
            uptime: { 100.25 },
            onFirstMeaningfulContent: { _ in callbackCount += 1 }
        )

        viewModel.applyInitialSnapshot(makeSnapshot(), evaluatedAt: now)
        viewModel.applyInitialSnapshot(makeSnapshot(), evaluatedAt: now)

        guard case .content = viewModel.state else {
            return XCTFail("A real preloaded snapshot must publish Today content.")
        }
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(repository.fetchTodaySnapshotCallCount, 0)
    }

    func testInitialLoadingWaitsForExactlyOneCompactRepositorySnapshot() async {
        let gate = TodayAsyncGate()
        let repository = TodayRepositorySpy()
        repository.responses = [.success(makeSnapshot())]
        repository.gates = [gate]
        let viewModel = makeViewModel(repository: repository)

        XCTAssertEqual(viewModel.state, .loading)

        let load = Task { @MainActor in
            await viewModel.load(at: now)
        }
        await gate.waitUntilEntered()

        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertEqual(repository.fetchTodaySnapshotCallCount, 1)

        gate.open()
        await load.value

        guard case .content = viewModel.state else {
            XCTFail("A single resumed snapshot must publish meaningful Today content.")
            return
        }
        XCTAssertEqual(repository.fetchTodaySnapshotCallCount, 1)
    }

    func testScheduledSessionMapsPhaseDirectiveRealActionAndProteinTargetOnly() async {
        let repository = TodayRepositorySpy()
        repository.responses = [.success(makeSnapshot())]
        let viewModel = makeViewModel(
            repository: repository,
            launchStartedAt: 100,
            uptime: { 100.25 }
        )

        await viewModel.load(at: now)

        guard case let .content(content) = viewModel.state else {
            XCTFail("Expected scheduled Today content.")
            return
        }
        XCTAssertEqual(
            content.phase,
            TodayPhasePresentation(name: "Temel", position: 1, count: 2)
        )
        XCTAssertEqual(
            content.directive,
            .train(
                workoutDay: .init(id: dayA, name: "Gün A", focus: "Squat"),
                reason: .scheduled
            )
        )
        XCTAssertEqual(content.mainAction, .start(workoutDayID: dayA))
        XCTAssertNil(content.alert)
        XCTAssertEqual(content.additionalAlertCount, 0)
        XCTAssertEqual(content.proteinTargetG, 120)
        guard let elapsed = content.firstMeaningfulContentElapsed else {
            XCTFail("The injected launch clock must produce raw elapsed evidence.")
            return
        }
        XCTAssertEqual(elapsed, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(repository.fetchTodaySnapshotCallCount, 1)
    }

    func testInProgressSessionWinsAndUsesResumeAction() async {
        let sessionID = uuid(401)
        let repository = TodayRepositorySpy()
        repository.responses = [
            .success(
                makeSnapshot(
                    sessions: [
                        session(
                            id: sessionID,
                            dayID: dayB,
                            status: .inProgress,
                            response: .symptomFree
                        )
                    ]
                )
            )
        ]
        let viewModel = makeViewModel(repository: repository)

        await viewModel.load(at: now)

        guard case let .content(content) = viewModel.state else {
            XCTFail("Expected resume content.")
            return
        }
        XCTAssertEqual(
            content.directive,
            .resume(
                sessionID: sessionID,
                workoutDay: .init(id: dayB, name: "Gün B", focus: "Hinge")
            )
        )
        XCTAssertEqual(
            content.mainAction,
            .resume(sessionID: sessionID, workoutDayID: dayB)
        )
    }

    func testSameDayCompletionProducesRestWithExplicitAuditableOverrideAction() async {
        let repository = TodayRepositorySpy()
        repository.responses = [
            .success(
                makeSnapshot(
                    sessions: [session(id: uuid(402), dayID: dayA, status: .completed)]
                )
            )
        ]
        let viewModel = makeViewModel(repository: repository)

        await viewModel.load(at: now)

        guard case let .content(content) = viewModel.state else {
            XCTFail("Expected rest content.")
            return
        }
        XCTAssertEqual(
            content.directive,
            .rest(
                reason: .completedToday,
                nextWorkoutDay: .init(id: dayB, name: "Gün B", focus: "Hinge")
            )
        )
        XCTAssertEqual(content.mainAction, .overrideRest(workoutDayID: dayB))
    }

    func testAlertPriorityIsSymptomsThenOHPDeloadPhaseBloodworkAndMeasurement() async {
        let bloodwork = TodayRepositorySnapshot.Reminder(
            id: uuid(501),
            title: "Ferritin",
            dueDate: now.addingTimeInterval(-60)
        )
        let measurement = TodayRepositorySnapshot.MeasurementReminder(
            id: uuid(502),
            message: "Bel ölçümünü kaydet"
        )
        let currentSession = session(
            id: uuid(503),
            dayID: dayB,
            status: .inProgress,
            response: .symptomsPresent
        )

        await assertPrimaryAlert(
            snapshot: makeSnapshot(
                programStartDate: dueProgramStart,
                programState: .init(
                    currentPhaseID: phase1,
                    trainingWeekIndex: 5,
                    deloadStatus: .active,
                    deloadReason: .scheduled
                ),
                sessions: [currentSession],
                healthChecks: [bloodwork],
                measurementReminders: [measurement]
            ),
            expected: .activeSymptoms,
            additionalCount: 5
        )

        await assertPrimaryAlert(
            snapshot: makeSnapshot(
                programStartDate: dueProgramStart,
                programState: .init(
                    currentPhaseID: phase1,
                    trainingWeekIndex: 5,
                    deloadStatus: .active,
                    deloadReason: .scheduled
                ),
                sessions: [
                    session(
                        id: uuid(504),
                        dayID: dayB,
                        status: .inProgress,
                        response: .uncertain
                    )
                ],
                healthChecks: [bloodwork],
                measurementReminders: [measurement]
            ),
            expected: .ohp,
            additionalCount: 4
        )

        await assertPrimaryAlert(
            snapshot: makeSnapshot(
                programStartDate: dueProgramStart,
                programState: .init(
                    currentPhaseID: phase1,
                    trainingWeekIndex: 5,
                    deloadStatus: .active,
                    deloadReason: .scheduled
                ),
                healthChecks: [bloodwork],
                measurementReminders: [measurement]
            ),
            expected: .deload(mode: .active, reason: .scheduled, trainingWeekIndex: 5),
            additionalCount: 3
        )

        await assertPrimaryAlert(
            snapshot: makeSnapshot(
                programStartDate: dueProgramStart,
                healthChecks: [bloodwork],
                measurementReminders: [measurement]
            ),
            expected: .phase(nextPhaseName: "İnşa"),
            additionalCount: 2
        )

        await assertPrimaryAlert(
            snapshot: makeSnapshot(
                healthChecks: [bloodwork],
                measurementReminders: [measurement]
            ),
            expected: .bloodwork(title: "Ferritin", dueDate: bloodwork.dueDate),
            additionalCount: 1
        )

        await assertPrimaryAlert(
            snapshot: makeSnapshot(measurementReminders: [measurement]),
            expected: .measurement(message: "Bel ölçümünü kaydet"),
            additionalCount: 0
        )
    }

    func testBloodworkTieBreakUsesDueDateThenStableIdentifierAndReportsRemainingCount() async {
        let later = TodayRepositorySnapshot.Reminder(
            id: uuid(601),
            title: "D vitamini",
            dueDate: now.addingTimeInterval(-60)
        )
        let sameDateHigherID = TodayRepositorySnapshot.Reminder(
            id: uuid(603),
            title: "Genel check-up",
            dueDate: now.addingTimeInterval(-120)
        )
        let sameDateLowerID = TodayRepositorySnapshot.Reminder(
            id: uuid(602),
            title: "Ferritin",
            dueDate: now.addingTimeInterval(-120)
        )

        await assertPrimaryAlert(
            snapshot: makeSnapshot(
                healthChecks: [later, sameDateHigherID, sameDateLowerID]
            ),
            expected: .bloodwork(
                title: sameDateLowerID.title,
                dueDate: sameDateLowerID.dueDate
            ),
            additionalCount: 2
        )
    }

    func testHealthCheckDueLaterTodayUsesTheSameLocalDaySemanticsAsTrackerDetail() async {
        let dueLaterToday = TodayRepositorySnapshot.Reminder(
            id: uuid(604),
            title: "Genel check-up",
            dueDate: calendar.date(
                from: DateComponents(year: 2026, month: 8, day: 20, hour: 17)
            )!
        )
        let dueTomorrow = TodayRepositorySnapshot.Reminder(
            id: uuid(605),
            title: "Ferritin",
            dueDate: calendar.date(
                from: DateComponents(year: 2026, month: 8, day: 21, hour: 0)
            )!
        )

        await assertPrimaryAlert(
            snapshot: makeSnapshot(healthChecks: [dueTomorrow, dueLaterToday]),
            expected: .bloodwork(
                title: dueLaterToday.title,
                dueDate: dueLaterToday.dueDate
            ),
            additionalCount: 0
        )
    }

    func testReactiveDeloadIsRecomputedFromTheSnapshotHistory() async {
        let exerciseID = uuid(701)
        let newerDate = now.addingTimeInterval(-7 * 86_400)
        let olderDate = now.addingTimeInterval(-14 * 86_400)
        let repository = TodayRepositorySpy()
        repository.responses = [
            .success(
                makeSnapshot(
                    programState: .init(
                        currentPhaseID: phase1,
                        trainingWeekIndex: 6,
                        deloadStatus: .none,
                        deloadReason: nil
                    ),
                    exerciseHistories: [
                        .init(
                            exerciseID: exerciseID,
                            sessions: [
                                completedExerciseHistory(
                                    sessionID: uuid(702),
                                    exerciseID: exerciseID,
                                    date: newerDate,
                                    reps: [9, 9, 9]
                                ),
                                completedExerciseHistory(
                                    sessionID: uuid(703),
                                    exerciseID: exerciseID,
                                    date: olderDate,
                                    reps: [10, 10, 10]
                                )
                            ]
                        )
                    ]
                )
            )
        ]
        let viewModel = makeViewModel(repository: repository)

        await viewModel.load(at: now)

        guard case let .content(content) = viewModel.state else {
            XCTFail("Expected Today content with reactive deload.")
            return
        }
        XCTAssertEqual(
            content.alert,
            .deload(mode: .recommended, reason: .reactive, trainingWeekIndex: 6)
        )
    }

    func testMissingProgramIsRecoverableEmptyAndRetryUsesANewSnapshot() async {
        let retryGate = TodayAsyncGate()
        let repository = TodayRepositorySpy()
        repository.responses = [.success(nil), .success(makeSnapshot())]
        repository.gates = [nil, retryGate]
        let viewModel = makeViewModel(repository: repository)

        await viewModel.load(at: now)
        XCTAssertEqual(viewModel.state, .empty)

        let retry = Task { @MainActor in
            await viewModel.retry(at: now)
        }
        await retryGate.waitUntilEntered()

        XCTAssertEqual(viewModel.state, .loading)
        XCTAssertEqual(repository.fetchTodaySnapshotCallCount, 2)

        retryGate.open()
        await retry.value
        guard case .content = viewModel.state else {
            XCTFail("Retry must recover with a fresh snapshot.")
            return
        }
        XCTAssertEqual(repository.fetchTodaySnapshotCallCount, 2)
    }

    func testFirstMeaningfulCallbackSkipsErrorAndEmptyThenPublishesExactlyOnce() async {
        let repository = TodayRepositorySpy()
        repository.responses = [
            .failure(TodayTestError.load),
            .success(nil),
            .success(makeSnapshot()),
            .success(makeSnapshot()),
        ]
        var callbackCount = 0
        let viewModel = makeViewModel(
            repository: repository,
            launchStartedAt: 100,
            uptime: { 100.25 },
            onFirstMeaningfulContent: { _ in callbackCount += 1 }
        )

        await viewModel.load(at: now)
        XCTAssertEqual(callbackCount, 0)
        await viewModel.retry(at: now)
        XCTAssertEqual(callbackCount, 0)
        await viewModel.retry(at: now)
        XCTAssertEqual(callbackCount, 1)
        await viewModel.retry(at: now)

        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(repository.fetchTodaySnapshotCallCount, 4)
    }

    func testRepositoryFailureIsRecoverableErrorAndPreservesNoFabricatedContent() async {
        let repository = TodayRepositorySpy()
        repository.responses = [.failure(TodayTestError.load), .success(makeSnapshot())]
        let viewModel = makeViewModel(repository: repository)

        await viewModel.load(at: now)
        XCTAssertEqual(viewModel.state, .error)

        await viewModel.retry(at: now)
        guard case .content = viewModel.state else {
            XCTFail("Retry must recover from a repository failure.")
            return
        }
        XCTAssertEqual(repository.fetchTodaySnapshotCallCount, 2)
    }

    func testInvalidMultipleInProgressSessionsBecomeRecoverableError() async {
        let repository = TodayRepositorySpy()
        repository.responses = [
            .success(
                makeSnapshot(
                    sessions: [
                        session(id: uuid(801), dayID: dayA, status: .inProgress),
                        session(id: uuid(802), dayID: dayB, status: .inProgress),
                    ]
                )
            )
        ]
        let viewModel = makeViewModel(repository: repository)

        await viewModel.load(at: now)

        XCTAssertEqual(viewModel.state, .error)
        XCTAssertEqual(repository.fetchTodaySnapshotCallCount, 1)
    }

    func testPublicTodayValuesAreEquatableAndSendable() {
        assertEquatableSendable(TodayRepositorySnapshot.self)
        assertEquatableSendable(TodayRepositorySnapshot.Profile.self)
        assertEquatableSendable(TodayRepositorySnapshot.Program.self)
        assertEquatableSendable(TodayRepositorySnapshot.Phase.self)
        assertEquatableSendable(TodayRepositorySnapshot.WorkoutDay.self)
        assertEquatableSendable(TodayRepositorySnapshot.ProgramState.self)
        assertEquatableSendable(TodayRepositorySnapshot.Reminder.self)
        assertEquatableSendable(TodayRepositorySnapshot.MeasurementReminder.self)
        assertEquatableSendable(TodayRepositorySnapshot.ExerciseHistory.self)
        assertEquatableSendable(TodayPhasePresentation.self)
        assertEquatableSendable(TodayWorkoutDayPresentation.self)
        assertEquatableSendable(TodayDirectivePresentation.self)
        assertEquatableSendable(TodayAlertPresentation.self)
        assertEquatableSendable(TodayMainAction.self)
        assertEquatableSendable(TodayPresentation.self)
        assertEquatableSendable(TodayViewState.self)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.firstWeekday = 2
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 12))!
    }

    private var dueProgramStart: Date {
        calendar.date(byAdding: .month, value: -2, to: now)!
    }

    private func makeViewModel(
        repository: TodayRepositorySpy,
        launchStartedAt: TimeInterval? = nil,
        uptime: @escaping @MainActor () -> TimeInterval = { 0 },
        onFirstMeaningfulContent: @escaping @MainActor (TimeInterval) -> Void = { _ in }
    ) -> TodayViewModel {
        TodayViewModel(
            repository: repository,
            calendar: calendar,
            launchStartedAt: launchStartedAt,
            uptime: uptime,
            onFirstMeaningfulContent: onFirstMeaningfulContent
        )
    }

    private func makeSnapshot(
        programStartDate: Date? = nil,
        programState: TodayRepositorySnapshot.ProgramState? = nil,
        sessions: [WorkoutSessionSnapshot] = [],
        healthChecks: [TodayRepositorySnapshot.Reminder] = [],
        measurementReminders: [TodayRepositorySnapshot.MeasurementReminder] = [],
        exerciseHistories: [TodayRepositorySnapshot.ExerciseHistory] = []
    ) -> TodayRepositorySnapshot {
        TodayRepositorySnapshot(
            profile: .init(
                proteinTargetG: 120,
                weeklyWorkoutTarget: 3,
                programStartDate: programStartDate ?? now
            ),
            program: .init(id: uuid(1), name: "Tam Vücut"),
            phases: [
                .init(
                    id: phase2,
                    name: "İnşa",
                    orderIndex: 2,
                    monthStart: 2,
                    monthEnd: 3,
                    entryCriteria: "Temel tamamlandı",
                    milestone: "İnşa başlangıcı"
                ),
                .init(
                    id: phase1,
                    name: "Temel",
                    orderIndex: 1,
                    monthStart: 1,
                    monthEnd: 1,
                    entryCriteria: "",
                    milestone: "Başlangıç"
                ),
            ],
            workoutDays: [
                .init(id: dayB, name: "Gün B", orderIndex: 2, focus: "Hinge", containsOHP: true),
                .init(id: dayA, name: "Gün A", orderIndex: 1, focus: "Squat", containsOHP: false),
            ],
            programState: programState ?? .init(
                currentPhaseID: phase1,
                trainingWeekIndex: 1,
                deloadStatus: .none,
                deloadReason: nil
            ),
            sessions: sessions,
            healthChecks: healthChecks,
            measurementReminders: measurementReminders,
            exerciseHistories: exerciseHistories
        )
    }

    private func session(
        id: UUID,
        dayID: UUID,
        status: WorkoutSessionStatus,
        response: OHPSymptomResponse = .symptomFree
    ) -> WorkoutSessionSnapshot {
        WorkoutSessionSnapshot(
            id: id,
            date: now,
            status: status,
            workoutDayTemplateID: dayID,
            ohpSymptomResponse: response
        )
    }

    private func completedExerciseHistory(
        sessionID: UUID,
        exerciseID: UUID,
        date: Date,
        reps: [Int]
    ) -> CompletedExerciseHistorySnapshot {
        CompletedExerciseHistorySnapshot(
            session: WorkoutSessionSnapshot(
                id: sessionID,
                date: date,
                status: .completed,
                workoutDayTemplateID: dayA
            ),
            setLogs: reps.enumerated().map { offset, repetitions in
                SetLogSnapshot(
                    id: uuid(9_000 + offset),
                    createdAt: date,
                    updatedAt: date,
                    workoutSessionID: sessionID,
                    exerciseTemplateID: exerciseID,
                    setIndex: offset + 1,
                    measurement: .init(weightKg: 10, reps: repetitions, rir: 2),
                    isWarmupSet: false,
                    completedAt: date
                )
            }
        )
    }

    private func assertPrimaryAlert(
        snapshot: TodayRepositorySnapshot,
        expected: TodayAlertPresentation,
        additionalCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let repository = TodayRepositorySpy()
        repository.responses = [.success(snapshot)]
        let viewModel = makeViewModel(repository: repository)

        await viewModel.load(at: now)

        guard case let .content(content) = viewModel.state else {
            XCTFail("Expected content for alert priority.", file: file, line: line)
            return
        }
        XCTAssertEqual(content.alert, expected, file: file, line: line)
        XCTAssertEqual(
            content.additionalAlertCount,
            additionalCount,
            file: file,
            line: line
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value.Type) {}
}

@MainActor
private final class TodayAsyncGate {
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private var hasEntered = false
    private var isOpen = false

    func wait() async {
        hasEntered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        guard !isOpen else { return }
        await withCheckedContinuation { resumeContinuation = $0 }
    }

    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func open() {
        isOpen = true
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

private enum TodayTestError: Error {
    case load
    case unexpectedCall
}

@MainActor
private final class TodayRepositorySpy: TrainingRepository {
    var responses: [Result<TodayRepositorySnapshot?, Error>] = []
    var gates: [TodayAsyncGate?] = []
    private(set) var fetchTodaySnapshotCallCount = 0

    func fetchTodaySnapshot() async throws -> TodayRepositorySnapshot? {
        fetchTodaySnapshotCallCount += 1
        if !gates.isEmpty, let gate = gates.removeFirst() {
            await gate.wait()
        }
        guard !responses.isEmpty else { throw TodayTestError.unexpectedCall }
        return try responses.removeFirst().get()
    }

    func fetchUserProfile() async throws -> UserProfile? { throw TodayTestError.unexpectedCall }
    func fetchActiveProgram() async throws -> Program? { throw TodayTestError.unexpectedCall }
    func fetchProgramPhases(programID _: UUID) async throws -> [ProgramPhase] {
        throw TodayTestError.unexpectedCall
    }
    func fetchWorkoutDays(programID _: UUID) async throws -> [WorkoutDayTemplate] {
        throw TodayTestError.unexpectedCall
    }
    func fetchExerciseTemplates(workoutDayID _: UUID) async throws -> [ExerciseTemplate] {
        throw TodayTestError.unexpectedCall
    }
    func fetchWarmupItems(workoutDayID _: UUID) async throws -> [WarmupItem] {
        throw TodayTestError.unexpectedCall
    }
    func fetchCooldownItems(workoutDayID _: UUID) async throws -> [CooldownItem] {
        throw TodayTestError.unexpectedCall
    }
    func fetchProgramState(programID _: UUID) async throws -> ProgramState? {
        throw TodayTestError.unexpectedCall
    }
    func recalculateProgramStateTrainingWeek(
        programID _: UUID,
        programStartDate _: Date,
        at _: Date
    ) async throws -> ProgramState { throw TodayTestError.unexpectedCall }
    func applyDeloadAction(
        programID _: UUID,
        reason _: DeloadReason,
        action _: DeloadAction,
        at _: Date
    ) async throws -> ProgramState { throw TodayTestError.unexpectedCall }
    func setActiveProgramPhase(
        programID _: UUID,
        phaseID _: UUID,
        at _: Date
    ) async throws -> ProgramState { throw TodayTestError.unexpectedCall }
    func saveSet(_: SetLogSaveRequest) async throws -> SetLogSnapshot {
        throw TodayTestError.unexpectedCall
    }
    func createWorkoutSession(
        _: WorkoutSessionCreateRequest
    ) async throws -> WorkoutSessionSnapshot { throw TodayTestError.unexpectedCall }
    func fetchInProgressWorkoutSession() async throws -> WorkoutSessionSnapshot? {
        throw TodayTestError.unexpectedCall
    }
    func transitionWorkoutSession(
        id _: UUID,
        to _: WorkoutSessionStatus,
        at _: Date
    ) async throws -> WorkoutSessionSnapshot { throw TodayTestError.unexpectedCall }
    func fetchWorkoutSessionProgress(
        sessionID _: UUID
    ) async throws -> WorkoutSessionProgressSnapshot? { throw TodayTestError.unexpectedCall }
    func saveWorkoutSessionProgress(
        _: WorkoutSessionProgressUpdate
    ) async throws -> WorkoutSessionProgressSnapshot { throw TodayTestError.unexpectedCall }
    func fetchSessionExercises(
        workoutDayID _: UUID
    ) async throws -> [SessionExerciseSnapshot] { throw TodayTestError.unexpectedCall }
    func fetchSessionPlan(
        workoutDayID _: UUID
    ) async throws -> SessionWorkoutPlanSnapshot? { throw TodayTestError.unexpectedCall }
    func fetchSetLogs(workoutSessionID _: UUID) async throws -> [SetLogSnapshot] {
        throw TodayTestError.unexpectedCall
    }
    func fetchTrainingHistory() async throws -> [TrainingHistorySessionSnapshot] {
        throw TodayTestError.unexpectedCall
    }
    func updateSet(_: SetLogUpdateRequest) async throws -> SetLogSnapshot {
        throw TodayTestError.unexpectedCall
    }
    func deleteSet(id _: UUID, at _: Date) async throws {
        throw TodayTestError.unexpectedCall
    }
    func fetchCompletedExerciseHistory(
        exerciseTemplateID _: UUID
    ) async throws -> [CompletedExerciseHistorySnapshot] { throw TodayTestError.unexpectedCall }
    func fetchWeeklyPallofHistory() async throws -> WeeklyPallofHistorySnapshot {
        throw TodayTestError.unexpectedCall
    }
    func fetchOHPSafeAlternative() async throws -> SessionExerciseSnapshot {
        throw TodayTestError.unexpectedCall
    }
    func updateWorkoutSessionOHPSymptomResponse(
        id _: UUID,
        response _: OHPSymptomResponse,
        at _: Date
    ) async throws -> WorkoutSessionSnapshot { throw TodayTestError.unexpectedCall }
    func updateWorkoutSessionSummary(
        id _: UUID,
        perceivedRecovery _: Int?,
        note _: String?,
        at _: Date
    ) async throws -> WorkoutSessionSnapshot { throw TodayTestError.unexpectedCall }
    func deleteWorkoutSession(id _: UUID) async throws {
        throw TodayTestError.unexpectedCall
    }
}
