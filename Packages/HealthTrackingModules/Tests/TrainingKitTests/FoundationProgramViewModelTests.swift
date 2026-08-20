import CoreModels
import Foundation
import TrainingKit
import XCTest

@MainActor
final class FoundationProgramViewModelTests: XCTestCase {
    func testInitialLoadingRemainsVisibleUntilRepositoryResumesThenBecomesContent() async {
        let gate = AsyncGate()
        let repository = FakeTrainingRepository()
        repository.userProfileResponses = [.success(makeProfile(displayName: "Ada"), gate: gate)]
        repository.activeProgramResponses = [.success(makeProgram())]
        repository.programPhaseResponses = [.success([])]
        repository.workoutDayResponses = [.success([])]
        let viewModel = FoundationProgramViewModel(repository: repository)

        XCTAssertEqual(viewModel.state, .loading)

        let loadTask = Task { @MainActor in
            await viewModel.load()
        }
        await gate.waitUntilEntered()

        XCTAssertEqual(viewModel.state, .loading)

        gate.open()
        await loadTask.value

        guard case let .content(snapshot) = viewModel.state else {
            XCTFail("Expected content after the repository resumes")
            return
        }
        XCTAssertEqual(snapshot.profile.displayName, "Ada")
        XCTAssertEqual(snapshot.program.name, "Foundation Program")
        XCTAssertTrue(snapshot.phases.isEmpty)
        XCTAssertTrue(snapshot.workoutDays.isEmpty)
        assertCallCounts(repository, profile: 1, program: 1, phases: 1, days: 1)
    }

    func testContentCopiesExactFallbackProfileProgramPhaseAndDayScalarsInDefensiveOrder() async {
        let profileID = uuid("00000000-0000-4000-8000-000000000001")
        let programID = uuid("00000000-0000-4000-8000-000000000100")
        let phase1ID = uuid("00000000-0000-4000-8000-000000000111")
        let phase2ID = uuid("00000000-0000-4000-8000-000000000112")
        let phase3ID = uuid("00000000-0000-4000-8000-000000000113")
        let phase4ID = uuid("00000000-0000-4000-8000-000000000114")
        let dayAID = uuid("00000000-0000-4000-8000-000000000201")
        let dayBID = uuid("00000000-0000-4000-8000-000000000202")
        let dayCID = uuid("00000000-0000-4000-8000-000000000203")
        let profile = UserProfile(
            id: profileID,
            displayName: " \n\t ",
            heightCm: 185.5,
            startWeightKg: 98.25,
            targetWeightKg: 90.75,
            unitsSystem: .metric,
            proteinTargetG: 120.5,
            weeklyWorkoutTarget: 4
        )
        let program = Program(
            id: programID,
            name: "Tam Vücut v3 (Postür → Recomp)",
            isActive: true
        )
        let phase1 = ProgramPhase(
            id: phase1ID,
            name: "Temel",
            orderIndex: 1,
            monthStart: 1,
            monthEnd: 2,
            trainingFocus: "Teknik + alışkanlık",
            nutritionFocus: "Ölçülü açık",
            milestone: "Başlangıç",
            entryCriteria: ""
        )
        let phase2 = ProgramPhase(
            id: phase2ID,
            name: "İnşa",
            orderIndex: 2,
            monthStart: 3,
            monthEnd: 6,
            trainingFocus: "Çift progresyon",
            nutritionFocus: "Açığı sürdür",
            milestone: "Bel ve güç",
            entryCriteria: "Temel tamamlandı"
        )
        let phase3 = ProgramPhase(
            id: phase3ID,
            name: "İlerleme",
            orderIndex: 3,
            monthStart: 7,
            monthEnd: 9,
            trainingFocus: "Ağır dumbbell",
            nutritionFocus: "Açığı yeniden kalibre et",
            milestone: "Güç sıçraması",
            entryCriteria: "İnşa tamamlandı"
        )
        let phase4 = ProgramPhase(
            id: phase4ID,
            name: "Konsolidasyon",
            orderIndex: 4,
            monthStart: 10,
            monthEnd: 12,
            trainingFocus: "Kaliteyi koru",
            nutritionFocus: "Sürdürülebilir bakım",
            milestone: "İkinci yıl kararı",
            entryCriteria: "İlerleme tamamlandı"
        )
        let dayA = WorkoutDayTemplate(
            id: dayAID,
            name: "Gün A",
            orderIndex: 1,
            focus: "Squat Ağırlıklı"
        )
        let dayB = WorkoutDayTemplate(
            id: dayBID,
            name: "Gün B",
            orderIndex: 2,
            focus: "Hinge Ağırlıklı"
        )
        let dayC = WorkoutDayTemplate(
            id: dayCID,
            name: "Gün C",
            orderIndex: 3,
            focus: "Unilateral + Taşıma"
        )
        let repository = FakeTrainingRepository()
        repository.userProfileResponses = [.success(profile)]
        repository.activeProgramResponses = [.success(program)]
        repository.programPhaseResponses = [.success([phase4, phase2, phase1, phase3])]
        repository.workoutDayResponses = [.success([dayC, dayA, dayB])]
        let viewModel = FoundationProgramViewModel(repository: repository)

        await viewModel.load()

        let expected = FoundationProgramSnapshot(
            profile: FoundationProfileSummary(
                id: profileID,
                displayName: "Profilim",
                usesFallbackDisplayName: true,
                unitDisplayMode: .metric,
                heightCm: 185.5,
                startWeightKg: 98.25,
                targetWeightKg: 90.75,
                proteinTargetG: 120.5,
                weeklyWorkoutTarget: 4
            ),
            program: FoundationProgramSummary(
                id: programID,
                name: "Tam Vücut v3 (Postür → Recomp)"
            ),
            phases: [
                FoundationPhaseSummary(
                    id: phase1ID,
                    name: "Temel",
                    orderIndex: 1,
                    monthStart: 1,
                    monthEnd: 2,
                    trainingFocus: "Teknik + alışkanlık",
                    nutritionFocus: "Ölçülü açık",
                    milestone: "Başlangıç",
                    entryCriteria: ""
                ),
                FoundationPhaseSummary(
                    id: phase2ID,
                    name: "İnşa",
                    orderIndex: 2,
                    monthStart: 3,
                    monthEnd: 6,
                    trainingFocus: "Çift progresyon",
                    nutritionFocus: "Açığı sürdür",
                    milestone: "Bel ve güç",
                    entryCriteria: "Temel tamamlandı"
                ),
                FoundationPhaseSummary(
                    id: phase3ID,
                    name: "İlerleme",
                    orderIndex: 3,
                    monthStart: 7,
                    monthEnd: 9,
                    trainingFocus: "Ağır dumbbell",
                    nutritionFocus: "Açığı yeniden kalibre et",
                    milestone: "Güç sıçraması",
                    entryCriteria: "İnşa tamamlandı"
                ),
                FoundationPhaseSummary(
                    id: phase4ID,
                    name: "Konsolidasyon",
                    orderIndex: 4,
                    monthStart: 10,
                    monthEnd: 12,
                    trainingFocus: "Kaliteyi koru",
                    nutritionFocus: "Sürdürülebilir bakım",
                    milestone: "İkinci yıl kararı",
                    entryCriteria: "İlerleme tamamlandı"
                )
            ],
            workoutDays: [
                FoundationWorkoutDaySummary(
                    id: dayAID,
                    name: "Gün A",
                    orderIndex: 1,
                    focus: "Squat Ağırlıklı"
                ),
                FoundationWorkoutDaySummary(
                    id: dayBID,
                    name: "Gün B",
                    orderIndex: 2,
                    focus: "Hinge Ağırlıklı"
                ),
                FoundationWorkoutDaySummary(
                    id: dayCID,
                    name: "Gün C",
                    orderIndex: 3,
                    focus: "Unilateral + Taşıma"
                )
            ]
        )
        assertEquatableSendable(expected)
        assertEquatableSendable(FoundationProgramState.content(expected))
        XCTAssertEqual(viewModel.state, .content(expected))
        assertCallCounts(repository, profile: 1, program: 1, phases: 1, days: 1)
        XCTAssertEqual(repository.fetchProgramPhasesProgramIDs, [programID])
        XCTAssertEqual(repository.fetchWorkoutDaysProgramIDs, [programID])

        profile.displayName = "Kaynak profil değişti"
        profile.heightCm = 999
        program.name = "Kaynak program değişti"
        phase1.name = "Kaynak faz değişti"
        dayA.name = "Kaynak gün değişti"

        XCTAssertEqual(viewModel.state, .content(expected))
    }

    func testGenuineTrimmedProfilimNameDoesNotReportFallbackAndCopiesImperialMode() async {
        let profile = UserProfile(
            id: uuid("00000000-0000-4000-8000-000000000903"),
            displayName: " \tProfilim\n ",
            heightCm: 72,
            startWeightKg: 220,
            targetWeightKg: 198,
            unitsSystem: .imperial,
            proteinTargetG: 130,
            weeklyWorkoutTarget: 5
        )
        let repository = FakeTrainingRepository()
        repository.userProfileResponses = [.success(profile)]
        repository.activeProgramResponses = [.success(makeProgram())]
        repository.programPhaseResponses = [.success([])]
        repository.workoutDayResponses = [.success([])]
        let viewModel = FoundationProgramViewModel(repository: repository)

        await viewModel.load()

        guard case let .content(snapshot) = viewModel.state else {
            XCTFail("Expected content state")
            return
        }
        let expectedUnitMode: FoundationUnitDisplayMode = .imperial
        assertEquatableSendable(expectedUnitMode)
        XCTAssertEqual(snapshot.profile.displayName, "Profilim")
        XCTAssertFalse(snapshot.profile.usesFallbackDisplayName)
        XCTAssertEqual(snapshot.profile.unitDisplayMode, expectedUnitMode)
        assertCallCounts(repository, profile: 1, program: 1, phases: 1, days: 1)
    }

    func testContentUsesUUIDAsDefensiveTieBreakForPhasesAndWorkoutDays() async {
        let lowerPhaseID = uuid("00000000-0000-4000-8000-000000000301")
        let higherPhaseID = uuid("00000000-0000-4000-8000-000000000302")
        let lowerDayID = uuid("00000000-0000-4000-8000-000000000401")
        let higherDayID = uuid("00000000-0000-4000-8000-000000000402")
        let repository = FakeTrainingRepository()
        repository.userProfileResponses = [.success(makeProfile())]
        repository.activeProgramResponses = [.success(makeProgram())]
        repository.programPhaseResponses = [
            .success([
                ProgramPhase(id: higherPhaseID, name: "Higher", orderIndex: 2),
                ProgramPhase(id: lowerPhaseID, name: "Lower", orderIndex: 2)
            ])
        ]
        repository.workoutDayResponses = [
            .success([
                WorkoutDayTemplate(id: higherDayID, name: "Higher", orderIndex: 1),
                WorkoutDayTemplate(id: lowerDayID, name: "Lower", orderIndex: 1)
            ])
        ]
        let viewModel = FoundationProgramViewModel(repository: repository)

        await viewModel.load()

        guard case let .content(snapshot) = viewModel.state else {
            XCTFail("Expected content state")
            return
        }
        XCTAssertEqual(snapshot.phases.map(\.id), [lowerPhaseID, higherPhaseID])
        XCTAssertEqual(snapshot.workoutDays.map(\.id), [lowerDayID, higherDayID])
    }

    func testMissingActiveProgramBecomesGenuineEmptyWithoutPhaseOrDayFetches() async {
        let repository = FakeTrainingRepository()
        repository.userProfileResponses = [.success(makeProfile())]
        repository.activeProgramResponses = [.success(nil)]
        let viewModel = FoundationProgramViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
        assertCallCounts(repository, profile: 1, program: 1, phases: 0, days: 0)
    }

    func testProgramWithoutProfileBecomesStableErrorWithoutPhaseOrDayFetches() async {
        let repository = FakeTrainingRepository()
        repository.userProfileResponses = [.success(nil)]
        repository.activeProgramResponses = [.success(makeProgram())]
        let viewModel = FoundationProgramViewModel(repository: repository)

        await viewModel.load()
        await Task.yield()

        XCTAssertEqual(viewModel.state, .error)
        assertCallCounts(repository, profile: 1, program: 1, phases: 0, days: 0)
    }

    func testProfileFailureBecomesStableErrorAndShortCircuitsEveryLaterFetch() async {
        let repository = FakeTrainingRepository()
        repository.userProfileResponses = [.failure(sensitiveFailure("profile.localizedDescription"))]
        let viewModel = FoundationProgramViewModel(repository: repository)

        await viewModel.load()
        await Task.yield()

        XCTAssertEqual(viewModel.state, .error)
        assertCallCounts(repository, profile: 1, program: 0, phases: 0, days: 0)
    }

    func testActiveProgramFailureBecomesStableErrorAndShortCircuitsPhaseAndDayFetches() async {
        let repository = FakeTrainingRepository()
        repository.userProfileResponses = [.success(makeProfile())]
        repository.activeProgramResponses = [.failure(sensitiveFailure("program.localizedDescription"))]
        let viewModel = FoundationProgramViewModel(repository: repository)

        await viewModel.load()
        await Task.yield()

        XCTAssertEqual(viewModel.state, .error)
        assertCallCounts(repository, profile: 1, program: 1, phases: 0, days: 0)
    }

    func testPhaseFailureBecomesStableErrorAndShortCircuitsWorkoutDayFetch() async {
        let repository = FakeTrainingRepository()
        repository.userProfileResponses = [.success(makeProfile())]
        repository.activeProgramResponses = [.success(makeProgram())]
        repository.programPhaseResponses = [.failure(sensitiveFailure("phases.localizedDescription"))]
        let viewModel = FoundationProgramViewModel(repository: repository)

        await viewModel.load()
        await Task.yield()

        XCTAssertEqual(viewModel.state, .error)
        assertCallCounts(repository, profile: 1, program: 1, phases: 1, days: 0)
    }

    func testWorkoutDayFailureBecomesStableErrorAfterEveryRequiredFetch() async {
        let repository = FakeTrainingRepository()
        repository.userProfileResponses = [.success(makeProfile())]
        repository.activeProgramResponses = [.success(makeProgram())]
        repository.programPhaseResponses = [.success([])]
        repository.workoutDayResponses = [.failure(sensitiveFailure("days.localizedDescription"))]
        let viewModel = FoundationProgramViewModel(repository: repository)

        await viewModel.load()
        await Task.yield()

        XCTAssertEqual(viewModel.state, .error)
        assertCallCounts(repository, profile: 1, program: 1, phases: 1, days: 1)
    }

    func testRetryReentersVisibleLoadingThenReplacesErrorWithRealContent() async {
        let retryGate = AsyncGate()
        let repository = FakeTrainingRepository()
        repository.userProfileResponses = [
            .failure(sensitiveFailure("first-attempt.localizedDescription")),
            .success(makeProfile(displayName: "Ada"), gate: retryGate)
        ]
        repository.activeProgramResponses = [.success(makeProgram())]
        repository.programPhaseResponses = [.success([])]
        repository.workoutDayResponses = [.success([])]
        let viewModel = FoundationProgramViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .error)
        assertCallCounts(repository, profile: 1, program: 0, phases: 0, days: 0)

        let retryTask = Task { @MainActor in
            await viewModel.load()
        }
        await retryGate.waitUntilEntered()

        XCTAssertEqual(viewModel.state, .loading)

        retryGate.open()
        await retryTask.value

        guard case let .content(snapshot) = viewModel.state else {
            XCTFail("Expected retry to replace error with content")
            return
        }
        XCTAssertEqual(snapshot.profile.displayName, "Ada")
        XCTAssertEqual(snapshot.program.name, "Foundation Program")
        assertCallCounts(repository, profile: 2, program: 1, phases: 1, days: 1)
    }

    private func makeProfile(displayName: String = "Ada") -> UserProfile {
        UserProfile(
            id: uuid("00000000-0000-4000-8000-000000000901"),
            displayName: displayName,
            heightCm: 180,
            startWeightKg: 100,
            targetWeightKg: 90,
            proteinTargetG: 110,
            weeklyWorkoutTarget: 3
        )
    }

    private func makeProgram() -> Program {
        Program(
            id: uuid("00000000-0000-4000-8000-000000000902"),
            name: "Foundation Program",
            isActive: true
        )
    }

    private func sensitiveFailure(_ detail: String) -> SensitiveRepositoryError {
        SensitiveRepositoryError(detail: detail)
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func assertEquatableSendable<Value: Equatable & Sendable>(_: Value) {}

    private func assertCallCounts(
        _ repository: FakeTrainingRepository,
        profile: Int,
        program: Int,
        phases: Int,
        days: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(repository.fetchUserProfileCallCount, profile, file: file, line: line)
        XCTAssertEqual(repository.fetchActiveProgramCallCount, program, file: file, line: line)
        XCTAssertEqual(repository.fetchProgramPhasesCallCount, phases, file: file, line: line)
        XCTAssertEqual(repository.fetchWorkoutDaysCallCount, days, file: file, line: line)
    }
}

@MainActor
private final class FakeTrainingRepository: TrainingRepository {
    var userProfileResponses: [QueuedResponse<UserProfile?>] = []
    var activeProgramResponses: [QueuedResponse<Program?>] = []
    var programPhaseResponses: [QueuedResponse<[ProgramPhase]>] = []
    var workoutDayResponses: [QueuedResponse<[WorkoutDayTemplate]>] = []

    private(set) var fetchUserProfileCallCount = 0
    private(set) var fetchActiveProgramCallCount = 0
    private(set) var fetchProgramPhasesCallCount = 0
    private(set) var fetchWorkoutDaysCallCount = 0
    private(set) var fetchProgramPhasesProgramIDs: [UUID] = []
    private(set) var fetchWorkoutDaysProgramIDs: [UUID] = []

    func fetchUserProfile() async throws -> UserProfile? {
        fetchUserProfileCallCount += 1
        let response = try Self.dequeue(&userProfileResponses, method: "fetchUserProfile")
        if let gate = response.gate {
            await gate.wait()
        }
        return try response.result.get()
    }

    func fetchActiveProgram() async throws -> Program? {
        fetchActiveProgramCallCount += 1
        let response = try Self.dequeue(&activeProgramResponses, method: "fetchActiveProgram")
        if let gate = response.gate {
            await gate.wait()
        }
        return try response.result.get()
    }

    func fetchProgramPhases(programID: UUID) async throws -> [ProgramPhase] {
        fetchProgramPhasesCallCount += 1
        fetchProgramPhasesProgramIDs.append(programID)
        let response = try Self.dequeue(&programPhaseResponses, method: "fetchProgramPhases")
        if let gate = response.gate {
            await gate.wait()
        }
        return try response.result.get()
    }

    func fetchWorkoutDays(programID: UUID) async throws -> [WorkoutDayTemplate] {
        fetchWorkoutDaysCallCount += 1
        fetchWorkoutDaysProgramIDs.append(programID)
        let response = try Self.dequeue(&workoutDayResponses, method: "fetchWorkoutDays")
        if let gate = response.gate {
            await gate.wait()
        }
        return try response.result.get()
    }

    func fetchExerciseTemplates(workoutDayID: UUID) async throws -> [ExerciseTemplate] {
        throw FakeRepositoryError.unexpectedCall("fetchExerciseTemplates")
    }

    func fetchWarmupItems(workoutDayID: UUID) async throws -> [WarmupItem] {
        throw FakeRepositoryError.unexpectedCall("fetchWarmupItems")
    }

    func fetchCooldownItems(workoutDayID: UUID) async throws -> [CooldownItem] {
        throw FakeRepositoryError.unexpectedCall("fetchCooldownItems")
    }

    func fetchHealthCheckReminders() async throws -> [HealthCheckReminder] {
        throw FakeRepositoryError.unexpectedCall("fetchHealthCheckReminders")
    }

    func fetchProgramState(programID: UUID) async throws -> ProgramState? {
        throw FakeRepositoryError.unexpectedCall("fetchProgramState")
    }

    func saveSet(_ request: SetLogSaveRequest) async throws -> SetLogSnapshot {
        throw FakeRepositoryError.unexpectedCall("saveSet")
    }

    func createWorkoutSession(
        _ request: WorkoutSessionCreateRequest
    ) async throws -> WorkoutSessionSnapshot {
        throw FakeRepositoryError.unexpectedCall("createWorkoutSession")
    }

    func fetchInProgressWorkoutSession() async throws -> WorkoutSessionSnapshot? {
        throw FakeRepositoryError.unexpectedCall("fetchInProgressWorkoutSession")
    }

    func transitionWorkoutSession(
        id: UUID,
        to status: WorkoutSessionStatus,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        throw FakeRepositoryError.unexpectedCall("transitionWorkoutSession")
    }

    func fetchWorkoutSessionProgress(
        sessionID: UUID
    ) async throws -> WorkoutSessionProgressSnapshot? {
        throw FakeRepositoryError.unexpectedCall("fetchWorkoutSessionProgress")
    }

    func saveWorkoutSessionProgress(
        _ update: WorkoutSessionProgressUpdate
    ) async throws -> WorkoutSessionProgressSnapshot {
        throw FakeRepositoryError.unexpectedCall("saveWorkoutSessionProgress")
    }

    func fetchSessionExercises(
        workoutDayID: UUID
    ) async throws -> [SessionExerciseSnapshot] {
        throw FakeRepositoryError.unexpectedCall("fetchSessionExercises")
    }

    func fetchSessionPlan(
        workoutDayID: UUID
    ) async throws -> SessionWorkoutPlanSnapshot? {
        throw FakeRepositoryError.unexpectedCall("fetchSessionPlan")
    }

    func fetchSetLogs(workoutSessionID: UUID) async throws -> [SetLogSnapshot] {
        throw FakeRepositoryError.unexpectedCall("fetchSetLogs")
    }

    func updateWorkoutSessionSummary(
        id: UUID,
        perceivedRecovery: Int?,
        note: String?,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        throw FakeRepositoryError.unexpectedCall("updateWorkoutSessionSummary")
    }

    func deleteWorkoutSession(id: UUID) async throws {
        throw FakeRepositoryError.unexpectedCall("deleteWorkoutSession")
    }

    private static func dequeue<Value>(
        _ responses: inout [QueuedResponse<Value>],
        method: String
    ) throws -> QueuedResponse<Value> {
        guard !responses.isEmpty else {
            throw FakeRepositoryError.unexpectedCall(method)
        }
        return responses.removeFirst()
    }
}

private struct QueuedResponse<Value> {
    let result: Result<Value, Error>
    let gate: AsyncGate?

    static func success(_ value: Value, gate: AsyncGate? = nil) -> Self {
        Self(result: .success(value), gate: gate)
    }

    static func failure(_ error: Error, gate: AsyncGate? = nil) -> Self {
        Self(result: .failure(error), gate: gate)
    }
}

@MainActor
private final class AsyncGate {
    private var hasEntered = false
    private var isOpen = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        hasEntered = true
        let waitingForEntry = entryWaiters
        entryWaiters.removeAll()
        waitingForEntry.forEach { $0.resume() }

        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            openWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !hasEntered else {
            return
        }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waitingForOpen = openWaiters
        openWaiters.removeAll()
        waitingForOpen.forEach { $0.resume() }
    }
}

private enum FakeRepositoryError: Error {
    case unexpectedCall(String)
}

private struct SensitiveRepositoryError: LocalizedError {
    let detail: String

    var errorDescription: String? {
        "Teknik ayrıntı gösterilmemeli: \(detail)"
    }
}
