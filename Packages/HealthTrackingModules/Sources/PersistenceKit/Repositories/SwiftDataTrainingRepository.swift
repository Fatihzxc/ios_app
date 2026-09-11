import CoreModels
import Foundation
import GuidanceKit
import SwiftData
import TrainingKit

public enum TrainingRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateUserProfiles(count: Int)
    case missingUserProfile
    case duplicateActivePrograms(count: Int)
    case duplicateProgramStates(programID: UUID, count: Int)
    case missingWorkoutSession(id: UUID)
    case duplicateWorkoutSessions(id: UUID, count: Int)
    case duplicateWorkoutDayTemplates(id: UUID, count: Int)
    case missingExerciseTemplate(id: UUID)
    case duplicateExerciseTemplates(id: UUID, count: Int)
    case inProgressSessionAlreadyExists(existingID: UUID)
    case duplicateInProgressWorkoutSessions(count: Int)
    case duplicateWorkoutSessionProgress(workoutSessionID: UUID, count: Int)
    case duplicateSetIndex(
        workoutSessionID: UUID,
        exerciseTemplateID: UUID,
        setIndex: Int
    )
    case duplicateSetLogs(id: UUID, count: Int)
    case transactionDidNotProduceSetSnapshot
    case transactionDidNotProduceSessionSnapshot
    case transactionDidNotProduceProgressSnapshot
    case missingProgramState(programID: UUID)
    case duplicateProgramPhases(programID: UUID, phaseID: UUID, count: Int)
    case currentPhaseNotFound(programID: UUID, phaseID: UUID)
    case duplicatePhaseTransitionSettings(programID: UUID, count: Int)
    case phaseTransitionSettingIDCollision(id: UUID)
    case phaseTransitionRecordIDCollision(id: UUID)
    case invalidPhaseTransitionLedger(programID: UUID, PhaseTransitionLedgerError)
}

public enum TrainingRepositoryMutationError: Error, Equatable, Sendable {
    case workoutSessionNotFound(id: UUID)
    case setLogNotFound(id: UUID)
    case setLogMissingSession(id: UUID)
    case historyMutationRequiresCompletedSession(id: UUID, status: WorkoutSessionStatus)
    case invalidPerceivedRecovery(Int)
    case summaryRequiresCompletedSession(id: UUID, status: WorkoutSessionStatus)
    case illegalWorkoutSessionTransition(
        id: UUID,
        from: WorkoutSessionStatus,
        to: WorkoutSessionStatus
    )
    case phaseNotFound(programID: UUID, phaseID: UUID)
    case invalidPhaseTransitionDate(
        programID: UUID,
        currentPhaseStartedAt: Date,
        transitionedAt: Date
    )
}

public enum TrainingRepositoryOperationError: Error, Equatable, Sendable {
    case phaseTransitionSaveFailed
    case pendingContextChanges
}

@MainActor
public final class SwiftDataTrainingRepository: TrainingRepository,
    SynchronousTodaySnapshotRepository {
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let phaseTransitionRecordID: @MainActor () -> UUID
    private let phaseTransitionSettingID: @MainActor () -> UUID
    private let saveOperation: @MainActor () throws -> Void
    private let rollbackOperation: @MainActor () -> Void

    public init(
        modelContext: ModelContext,
        calendar: Calendar = .current,
        phaseTransitionRecordID: @escaping @MainActor () -> UUID = { UUID() },
        phaseTransitionSettingID: @escaping @MainActor () -> UUID = { UUID() },
        save: (@MainActor () throws -> Void)? = nil,
        rollback: (@MainActor () -> Void)? = nil
    ) {
        self.modelContext = modelContext
        self.calendar = calendar
        self.phaseTransitionRecordID = phaseTransitionRecordID
        self.phaseTransitionSettingID = phaseTransitionSettingID
        saveOperation = save ?? { try modelContext.save() }
        rollbackOperation = rollback ?? { modelContext.rollback() }
    }

    public func fetchTodaySnapshot() async throws -> TodayRepositorySnapshot? {
        try fetchTodaySnapshotSynchronously()
    }

    public func fetchTodaySnapshotSynchronously() throws -> TodayRepositorySnapshot? {
        var profileDescriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\UserProfile.updatedAt, order: .reverse)]
        )
        profileDescriptor.fetchLimit = 2
        let profiles = try modelContext.fetch(profileDescriptor)
        if profiles.count > 1 {
            profileDescriptor.fetchLimit = nil
            throw TrainingRepositoryIntegrityError.duplicateUserProfiles(
                count: try modelContext.fetchCount(profileDescriptor)
            )
        }

        var activeProgramDescriptor = FetchDescriptor<Program>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\Program.updatedAt, order: .reverse)]
        )
        activeProgramDescriptor.fetchLimit = 2
        let programs = Self.sortActivePrograms(
            try modelContext.fetch(activeProgramDescriptor)
        )
        if programs.count > 1 {
            activeProgramDescriptor.fetchLimit = nil
            throw TrainingRepositoryIntegrityError.duplicateActivePrograms(
                count: try modelContext.fetchCount(activeProgramDescriptor)
            )
        }
        guard let program = programs.first else { return nil }
        guard let profile = profiles.first else {
            throw TrainingRepositoryIntegrityError.missingUserProfile
        }

        let phases = (program.programPhases ?? [])
            .sorted(by: Self.phaseOrderedBefore)
        let workoutDays = (program.workoutDayTemplates ?? [])
            .sorted(by: Self.workoutDayOrderedBefore)
        let workoutDayIDs = Set(workoutDays.map(\.id))

        let programID = program.id
        var programStateDescriptor = FetchDescriptor<ProgramState>(
            predicate: #Predicate { $0.programId == programID }
        )
        programStateDescriptor.fetchLimit = 2
        let programStates = try modelContext.fetch(programStateDescriptor)
        if programStates.count > 1 {
            programStateDescriptor.fetchLimit = nil
            throw TrainingRepositoryIntegrityError.duplicateProgramStates(
                programID: programID,
                count: try modelContext.fetchCount(programStateDescriptor)
            )
        }
        guard let programState = programStates.first else {
            throw TrainingRepositoryIntegrityError.missingProgramState(programID: programID)
        }

        // Fetch once instead of faulting each workout day's to-many relationship separately.
        // The inverse day objects are already registered in this context, so resolving their IDs
        // does not require another catalog-wide fetch.
        let exercises = try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())
            .filter { exercise in
                guard let workoutDayID = exercise.workoutDayTemplate?.id else { return false }
                return workoutDayIDs.contains(workoutDayID)
            }
        let ohpDayIDs = Set(
            exercises.compactMap { exercise -> UUID? in
                guard exercise.progressionRule == .gradedEntryOHP else { return nil }
                return exercise.workoutDayTemplate?.id
            }
        )

        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
            .filter {
                workoutDayIDs.contains($0.workoutDayTemplateId)
                    || $0.status == .inProgress
            }
            .sorted(by: Self.workoutSessionOrderedBefore)
        let completedSessions = sessions.filter {
            $0.status == .completed && workoutDayIDs.contains($0.workoutDayTemplateId)
        }
        let exerciseHistories: [TodayRepositorySnapshot.ExerciseHistory]
        if completedSessions.isEmpty {
            exerciseHistories = []
        } else {
            let exerciseIDs = Set(exercises.map(\.id))
            let setLogs = completedSessions
                .flatMap { $0.setLogs ?? [] }
                .filter { exerciseIDs.contains($0.exerciseTemplateId) }
            let setLogsByExerciseID = Dictionary(grouping: setLogs, by: \.exerciseTemplateId)

            exerciseHistories = exercises
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .compactMap { exercise -> TodayRepositorySnapshot.ExerciseHistory? in
                    let exerciseSets = setLogsByExerciseID[exercise.id, default: []]
                    var setsBySessionID: [UUID: [SetLog]] = [:]
                    for setLog in exerciseSets {
                        guard let sessionID = setLog.workoutSession?.id else { continue }
                        setsBySessionID[sessionID, default: []].append(setLog)
                    }
                    let history = completedSessions.compactMap {
                        session -> CompletedExerciseHistorySnapshot? in
                        guard let logs = setsBySessionID[session.id], !logs.isEmpty else {
                            return nil
                        }
                        let snapshots = logs
                            .sorted(by: Self.setLogOrderedBefore)
                            .map { Self.snapshot($0, workoutSessionID: session.id) }
                        return CompletedExerciseHistorySnapshot(
                            session: Self.sessionSnapshot(session),
                            setLogs: snapshots
                        )
                    }
                    guard !history.isEmpty else { return nil }
                    return .init(exerciseID: exercise.id, sessions: history)
                }
        }

        let healthChecks = try modelContext.fetch(FetchDescriptor<HealthCheckReminder>())
            .filter { $0.status == .pending }
            .sorted(by: Self.healthCheckOrderedBefore)
            .map {
                TodayRepositorySnapshot.Reminder(
                    id: $0.id,
                    title: $0.name,
                    dueDate: $0.dueDate
                )
            }
        let measurementReminders = try modelContext.fetch(
            FetchDescriptor<AppReminder>(predicate: #Predicate { $0.isEnabled })
        )
            .filter { $0.type == .measurement }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                TodayRepositorySnapshot.MeasurementReminder(
                    id: $0.id,
                    message: $0.message
                )
            }

        return TodayRepositorySnapshot(
            profile: .init(
                proteinTargetG: profile.proteinTargetG,
                weeklyWorkoutTarget: profile.weeklyWorkoutTarget,
                programStartDate: profile.programStartDate
            ),
            program: .init(id: program.id, name: program.name),
            phases: phases.map {
                .init(
                    id: $0.id,
                    name: $0.name,
                    orderIndex: $0.orderIndex,
                    monthStart: $0.monthStart,
                    monthEnd: $0.monthEnd,
                    entryCriteria: $0.entryCriteria,
                    milestone: $0.milestone
                )
            },
            workoutDays: workoutDays.map {
                .init(
                    id: $0.id,
                    name: $0.name,
                    orderIndex: $0.orderIndex,
                    focus: $0.focus,
                    containsOHP: ohpDayIDs.contains($0.id)
                )
            },
            programState: .init(
                currentPhaseID: programState.currentPhaseId,
                trainingWeekIndex: programState.trainingWeekIndex,
                deloadStatus: programState.deloadStatus,
                deloadReason: programState.deloadReason
            ),
            sessions: sessions.map(Self.sessionSnapshot),
            healthChecks: healthChecks,
            measurementReminders: measurementReminders,
            exerciseHistories: exerciseHistories
        )
    }

    public func fetchUserProfile() async throws -> UserProfile? {
        let profiles = try modelContext.fetch(
            FetchDescriptor<UserProfile>(
                sortBy: [SortDescriptor(\UserProfile.updatedAt, order: .reverse)]
            )
        )

        guard profiles.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateUserProfiles(count: profiles.count)
        }
        return profiles.first
    }

    public func fetchActiveProgram() async throws -> Program? {
        let programs = Self.sortActivePrograms(
            try modelContext.fetch(
                FetchDescriptor<Program>(
                    predicate: #Predicate { $0.isActive },
                    sortBy: [SortDescriptor(\Program.updatedAt, order: .reverse)]
                )
            )
        )

        guard programs.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateActivePrograms(count: programs.count)
        }
        return programs.first
    }

    static func sortActivePrograms(_ programs: [Program]) -> [Program] {
        programs.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func fetchProgramPhases(programID: UUID) async throws -> [ProgramPhase] {
        let phases = try modelContext.fetch(
            FetchDescriptor<ProgramPhase>(
                sortBy: [SortDescriptor(\ProgramPhase.orderIndex, order: .forward)]
            )
        )

        return phases
            .filter { $0.program?.id == programID }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func fetchWorkoutDays(programID: UUID) async throws -> [WorkoutDayTemplate] {
        let days = try modelContext.fetch(
            FetchDescriptor<WorkoutDayTemplate>(
                sortBy: [SortDescriptor(\WorkoutDayTemplate.orderIndex, order: .forward)]
            )
        )

        return days
            .filter { $0.program?.id == programID }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func fetchExerciseTemplates(workoutDayID: UUID) async throws -> [ExerciseTemplate] {
        let exercises = try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())

        return exercises
            .filter { $0.workoutDayTemplate?.id == workoutDayID }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func fetchWarmupItems(workoutDayID: UUID) async throws -> [WarmupItem] {
        let warmups = try modelContext.fetch(FetchDescriptor<WarmupItem>())

        return warmups
            .filter { $0.workoutDayTemplate?.id == workoutDayID }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func fetchCooldownItems(workoutDayID: UUID) async throws -> [CooldownItem] {
        let cooldowns = try modelContext.fetch(FetchDescriptor<CooldownItem>())

        return cooldowns
            .filter { $0.workoutDayTemplate?.id == workoutDayID }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public func fetchProgramState(programID: UUID) async throws -> ProgramState? {
        let states = try modelContext.fetch(FetchDescriptor<ProgramState>())
            .filter { $0.programId == programID }

        guard states.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateProgramStates(
                programID: programID,
                count: states.count
            )
        }
        return states.first
    }

    public func recalculateProgramStateTrainingWeek(
        programID: UUID,
        programStartDate: Date,
        at date: Date
    ) async throws -> ProgramState {
        var updatedState: ProgramState?
        try modelContext.transaction {
            let state = try requiredProgramState(programID: programID)
            let dayIDs = Set(
                try modelContext.fetch(FetchDescriptor<WorkoutDayTemplate>())
                    .filter { $0.program?.id == programID }
                    .map(\.id)
            )
            let completedDates = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
                .filter {
                    $0.status == .completed && dayIDs.contains($0.workoutDayTemplateId)
                }
                .map(\.date)
            let decision = TrainingWeek.resolve(
                TrainingWeek.Input(
                    programStartDate: programStartDate,
                    completedSessionDates: completedDates
                ),
                calendar: calendar
            )

            state.trainingWeekIndex = decision.trainingWeekIndex
            if state.deloadStatus == .active || state.deloadStatus == .skipped,
               let deloadUpdatedAt = state.deloadUpdatedAt,
               let latestWeekStart = decision.countedWeekStarts.last,
               let deloadWeekStart = calendar.dateInterval(
                   of: .weekOfYear,
                   for: deloadUpdatedAt
               )?.start,
               latestWeekStart > deloadWeekStart {
                state.deloadStatus = .none
                state.deloadReason = nil
            }
            state.updatedAt = date
            try modelContext.save()
            updatedState = state
        }
        guard let updatedState else {
            throw TrainingRepositoryIntegrityError.missingProgramState(programID: programID)
        }
        return updatedState
    }

    public func applyDeloadAction(
        programID: UUID,
        reason: DeloadReason,
        action: DeloadAction,
        at date: Date
    ) async throws -> ProgramState {
        var updatedState: ProgramState?
        try modelContext.transaction {
            let state = try requiredProgramState(programID: programID)
            state.deloadStatus = action == .accepted ? .active : .skipped
            state.deloadReason = reason
            state.deloadUpdatedAt = date
            state.lastDeloadSkippedAt = action == .accepted ? nil : date
            state.lastDeloadAction = action
            state.updatedAt = date
            try modelContext.save()
            updatedState = state
        }
        guard let updatedState else {
            throw TrainingRepositoryIntegrityError.missingProgramState(programID: programID)
        }
        return updatedState
    }

    public func setActiveProgramPhase(
        programID: UUID,
        phaseID: UUID,
        at date: Date
    ) async throws -> ProgramState {
        let state = try requiredProgramState(programID: programID)
        _ = try requiredProgramPhase(programID: programID, phaseID: phaseID)
        guard state.currentPhaseId != phaseID else { return state }
        guard !modelContext.hasChanges else {
            throw TrainingRepositoryOperationError.pendingContextChanges
        }
        guard date.timeIntervalSinceReferenceDate.isFinite,
              date > state.phaseStartedAt else {
            throw TrainingRepositoryMutationError.invalidPhaseTransitionDate(
                programID: programID,
                currentPhaseStartedAt: state.phaseStartedAt,
                transitionedAt: date
            )
        }
        let originalPhaseID = state.currentPhaseId
        let originalPhaseStartedAt = state.phaseStartedAt
        let originalStateUpdatedAt = state.updatedAt
        var originalSetting: (model: AppSetting, value: String, updatedAt: Date)?
        var updatedState: ProgramState?
        do {
            try modelContext.transaction {
                let state = try requiredProgramState(programID: programID)
                _ = try requiredProgramPhase(programID: programID, phaseID: phaseID)
                do {
                    _ = try requiredCurrentProgramPhase(
                        programID: programID,
                        phaseID: state.currentPhaseId
                    )
                    let key = PhaseTransitionLedgerV1.key(for: programID)
                    let settings = try modelContext.fetch(FetchDescriptor<AppSetting>())
                    let matchingSettings = settings.filter { $0.key == key }
                    guard matchingSettings.count <= 1 else {
                        throw TrainingRepositoryIntegrityError.duplicatePhaseTransitionSettings(
                            programID: programID,
                            count: matchingSettings.count
                        )
                    }
                    let setting: AppSetting
                    var ledger: PhaseTransitionLedgerV1
                    if let existing = matchingSettings.first {
                        setting = existing
                        originalSetting = (existing, existing.value, existing.updatedAt)
                        ledger = try PhaseTransitionLedgerV1.decode(existing.value, for: programID)
                    } else {
                        let settingID = phaseTransitionSettingID()
                        guard !settings.contains(where: { $0.id == settingID }) else {
                            throw TrainingRepositoryIntegrityError.phaseTransitionSettingIDCollision(
                                id: settingID
                            )
                        }
                        setting = AppSetting(
                            id: settingID,
                            createdAt: date,
                            updatedAt: date,
                            key: key,
                            value: ""
                        )
                        ledger = PhaseTransitionLedgerV1(records: [])
                        modelContext.insert(setting)
                    }

                    let recordID = phaseTransitionRecordID()
                    guard !ledger.records.contains(where: { $0.id == recordID }) else {
                        throw TrainingRepositoryIntegrityError.phaseTransitionRecordIDCollision(
                            id: recordID
                        )
                    }
                    ledger.records.append(PhaseTransitionRecord(
                        id: recordID,
                        programID: programID,
                        fromPhaseID: state.currentPhaseId,
                        toPhaseID: phaseID,
                        fromStartedAt: state.phaseStartedAt,
                        transitionedAt: date
                    ))
                    setting.value = try ledger.encoded(for: programID)
                    setting.updatedAt = date
                } catch let error as PhaseTransitionLedgerError {
                    throw TrainingRepositoryIntegrityError.invalidPhaseTransitionLedger(
                        programID: programID,
                        error
                    )
                }

                state.currentPhaseId = phaseID
                state.phaseStartedAt = date
                state.updatedAt = date
                try saveOperation()
                updatedState = state
            }
        } catch {
            state.currentPhaseId = originalPhaseID
            state.phaseStartedAt = originalPhaseStartedAt
            state.updatedAt = originalStateUpdatedAt
            if let originalSetting {
                originalSetting.model.value = originalSetting.value
                originalSetting.model.updatedAt = originalSetting.updatedAt
            }
            rollbackOperation()
            if let error = error as? TrainingRepositoryIntegrityError { throw error }
            if let error = error as? TrainingRepositoryMutationError { throw error }
            throw TrainingRepositoryOperationError.phaseTransitionSaveFailed
        }
        guard let updatedState else {
            throw TrainingRepositoryIntegrityError.missingProgramState(programID: programID)
        }
        return updatedState
    }

    private func requiredProgramPhase(
        programID: UUID,
        phaseID: UUID
    ) throws -> ProgramPhase {
        let matching = try modelContext.fetch(FetchDescriptor<ProgramPhase>())
            .filter { $0.id == phaseID && $0.program?.id == programID }
        guard matching.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateProgramPhases(
                programID: programID,
                phaseID: phaseID,
                count: matching.count
            )
        }
        guard let phase = matching.first else {
            throw TrainingRepositoryMutationError.phaseNotFound(
                programID: programID,
                phaseID: phaseID
            )
        }
        return phase
    }

    private func requiredCurrentProgramPhase(
        programID: UUID,
        phaseID: UUID
    ) throws -> ProgramPhase {
        do {
            return try requiredProgramPhase(programID: programID, phaseID: phaseID)
        } catch is TrainingRepositoryMutationError {
            throw TrainingRepositoryIntegrityError.currentPhaseNotFound(
                programID: programID,
                phaseID: phaseID
            )
        }
    }

    private func requiredProgramState(programID: UUID) throws -> ProgramState {
        let states = try modelContext.fetch(FetchDescriptor<ProgramState>())
            .filter { $0.programId == programID }
        guard states.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateProgramStates(
                programID: programID,
                count: states.count
            )
        }
        guard let state = states.first else {
            throw TrainingRepositoryIntegrityError.missingProgramState(programID: programID)
        }
        return state
    }

    public func createWorkoutSession(
        _ request: WorkoutSessionCreateRequest
    ) async throws -> WorkoutSessionSnapshot {
        var savedSnapshot: WorkoutSessionSnapshot?
        try modelContext.transaction {
            let duplicates = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
                .filter { $0.id == request.id }
            guard duplicates.isEmpty else {
                throw TrainingRepositoryIntegrityError.duplicateWorkoutSessions(
                    id: request.id,
                    count: duplicates.count
                )
            }

            let session = WorkoutSession(
                id: request.id,
                createdAt: request.date,
                updatedAt: request.date,
                date: request.date,
                status: .planned,
                workoutDayTemplateId: request.workoutDayTemplateID
            )
            modelContext.insert(session)
            try modelContext.save()
            savedSnapshot = Self.sessionSnapshot(session)
        }
        guard let savedSnapshot else {
            throw TrainingRepositoryIntegrityError.transactionDidNotProduceSessionSnapshot
        }
        return savedSnapshot
    }

    public func fetchInProgressWorkoutSession() async throws -> WorkoutSessionSnapshot? {
        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.status == .inProgress }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date < rhs.date
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        guard sessions.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateInProgressWorkoutSessions(
                count: sessions.count
            )
        }
        return sessions.first.map(Self.sessionSnapshot)
    }

    public func transitionWorkoutSession(
        id: UUID,
        to status: WorkoutSessionStatus,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        var savedSnapshot: WorkoutSessionSnapshot?
        try modelContext.transaction {
            let matches = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
                .filter { $0.id == id }
            guard let session = matches.first else {
                throw TrainingRepositoryMutationError.workoutSessionNotFound(id: id)
            }
            guard matches.count == 1 else {
                throw TrainingRepositoryIntegrityError.duplicateWorkoutSessions(
                    id: id,
                    count: matches.count
                )
            }

            let currentStatus = session.status
            switch (currentStatus, status) {
            case (.planned, .inProgress), (.inProgress, .completed), (.planned, .skipped):
                break
            default:
                throw TrainingRepositoryMutationError.illegalWorkoutSessionTransition(
                    id: id,
                    from: currentStatus,
                    to: status
                )
            }

            if status == .inProgress {
                let existing = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
                    .filter { $0.status == .inProgress && $0.id != id }
                    .sorted { $0.id.uuidString < $1.id.uuidString }
                guard existing.isEmpty else {
                    throw TrainingRepositoryIntegrityError.inProgressSessionAlreadyExists(
                        existingID: existing[0].id
                    )
                }
            }

            session.status = status
            session.updatedAt = date
            if status == .completed {
                try synchronizeTrainingWeekAfterCompletion(
                    workoutDayTemplateID: session.workoutDayTemplateId,
                    completionDate: session.date,
                    at: date
                )
            }
            try modelContext.save()
            savedSnapshot = Self.sessionSnapshot(session)
        }
        guard let savedSnapshot else {
            throw TrainingRepositoryIntegrityError.transactionDidNotProduceSessionSnapshot
        }
        return savedSnapshot
    }

    private func synchronizeTrainingWeekAfterCompletion(
        workoutDayTemplateID: UUID,
        completionDate: Date,
        at date: Date
    ) throws {
        let matchingDays = try modelContext.fetch(FetchDescriptor<WorkoutDayTemplate>())
            .filter { $0.id == workoutDayTemplateID }
        guard matchingDays.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateWorkoutDayTemplates(
                id: workoutDayTemplateID,
                count: matchingDays.count
            )
        }
        guard let programID = matchingDays.first?.program?.id else { return }

        let profiles = try modelContext.fetch(FetchDescriptor<UserProfile>())
        guard profiles.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateUserProfiles(count: profiles.count)
        }
        guard let programStartDate = profiles.first?.programStartDate else { return }

        let states = try modelContext.fetch(FetchDescriptor<ProgramState>())
            .filter { $0.programId == programID }
        guard states.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateProgramStates(
                programID: programID,
                count: states.count
            )
        }
        guard let state = states.first else { return }

        let programDayIDs = Set(
            try modelContext.fetch(FetchDescriptor<WorkoutDayTemplate>())
                .filter { $0.program?.id == programID }
                .map(\.id)
        )
        var completedDates = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
            .filter {
                $0.status == .completed && programDayIDs.contains($0.workoutDayTemplateId)
            }
            .map(\.date)
        completedDates.append(completionDate)
        let decision = TrainingWeek.resolve(
            .init(
                programStartDate: programStartDate,
                completedSessionDates: completedDates
            ),
            calendar: calendar
        )
        state.trainingWeekIndex = decision.trainingWeekIndex
        if state.deloadStatus == .active || state.deloadStatus == .skipped,
           let deloadUpdatedAt = state.deloadUpdatedAt,
           let newestCompletedWeek = decision.countedWeekStarts.last,
           let deloadWeek = calendar.dateInterval(
               of: .weekOfYear,
               for: deloadUpdatedAt
           )?.start,
           newestCompletedWeek > deloadWeek {
            state.deloadStatus = .none
            state.deloadReason = nil
        }
        state.updatedAt = date
    }

    public func fetchWorkoutSessionProgress(
        sessionID: UUID
    ) async throws -> WorkoutSessionProgressSnapshot? {
        let matches = try modelContext.fetch(FetchDescriptor<WorkoutSessionProgress>())
            .filter { $0.workoutSessionId == sessionID }
        guard matches.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateWorkoutSessionProgress(
                workoutSessionID: sessionID,
                count: matches.count
            )
        }
        guard let progress = matches.first else {
            return nil
        }
        return try Self.progressSnapshot(progress)
    }

    public func saveWorkoutSessionProgress(
        _ update: WorkoutSessionProgressUpdate
    ) async throws -> WorkoutSessionProgressSnapshot {
        var savedSnapshot: WorkoutSessionProgressSnapshot?
        try modelContext.transaction {
            let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
                .filter { $0.id == update.workoutSessionID }
            guard !sessions.isEmpty else {
                throw TrainingRepositoryMutationError.workoutSessionNotFound(
                    id: update.workoutSessionID
                )
            }
            guard sessions.count == 1 else {
                throw TrainingRepositoryIntegrityError.duplicateWorkoutSessions(
                    id: update.workoutSessionID,
                    count: sessions.count
                )
            }

            let matchingProgress = try modelContext.fetch(
                FetchDescriptor<WorkoutSessionProgress>()
            ).filter { $0.workoutSessionId == update.workoutSessionID }
            guard matchingProgress.count <= 1 else {
                throw TrainingRepositoryIntegrityError.duplicateWorkoutSessionProgress(
                    workoutSessionID: update.workoutSessionID,
                    count: matchingProgress.count
                )
            }

            let warmupData = try WorkoutSessionProgressCodec.encode(
                update.state.completedWarmupItemIDs
            )
            let cooldownData = try WorkoutSessionProgressCodec.encode(
                update.state.completedCooldownItemIDs
            )
            let progress: WorkoutSessionProgress
            if let existing = matchingProgress.first {
                progress = existing
                progress.updatedAt = update.updatedAt
                progress.stage = update.state.stage
                progress.currentExerciseTemplateId = update.state.currentExerciseTemplateID
                progress.completedWarmupItemIdsData = warmupData
                progress.completedCooldownItemIdsData = cooldownData
                progress.warmupDisposition = update.state.warmupDisposition
                progress.cooldownDisposition = update.state.cooldownDisposition
            } else {
                progress = WorkoutSessionProgress(
                    id: update.id,
                    createdAt: update.updatedAt,
                    updatedAt: update.updatedAt,
                    workoutSessionId: update.workoutSessionID,
                    stage: update.state.stage,
                    currentExerciseTemplateId: update.state.currentExerciseTemplateID,
                    completedWarmupItemIdsData: warmupData,
                    completedCooldownItemIdsData: cooldownData,
                    warmupDisposition: update.state.warmupDisposition,
                    cooldownDisposition: update.state.cooldownDisposition
                )
                modelContext.insert(progress)
            }
            try modelContext.save()
            savedSnapshot = try Self.progressSnapshot(progress)
        }
        guard let savedSnapshot else {
            throw TrainingRepositoryIntegrityError.transactionDidNotProduceProgressSnapshot
        }
        return savedSnapshot
    }

    public func fetchSessionExercises(
        workoutDayID: UUID
    ) async throws -> [SessionExerciseSnapshot] {
        try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())
            .filter { $0.workoutDayTemplate?.id == workoutDayID }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map(Self.exerciseSnapshot)
    }

    public func fetchSessionPlan(
        workoutDayID: UUID
    ) async throws -> SessionWorkoutPlanSnapshot? {
        let matchingDays = try modelContext.fetch(FetchDescriptor<WorkoutDayTemplate>())
            .filter { $0.id == workoutDayID }
        guard matchingDays.count <= 1 else {
            throw TrainingRepositoryIntegrityError.duplicateWorkoutDayTemplates(
                id: workoutDayID,
                count: matchingDays.count
            )
        }
        guard let day = matchingDays.first else {
            return nil
        }

        let warmups = try modelContext.fetch(FetchDescriptor<WarmupItem>())
            .filter { $0.workoutDayTemplate?.id == workoutDayID }
            .sorted(by: Self.orderChecklistItems)
            .map {
                SessionChecklistItemSnapshot(
                    id: $0.id,
                    title: $0.movement,
                    detail: $0.dose,
                    orderIndex: $0.orderIndex
                )
            }
        let exercises = try await fetchSessionExercises(workoutDayID: workoutDayID)
        let cooldowns = try modelContext.fetch(FetchDescriptor<CooldownItem>())
            .filter { $0.workoutDayTemplate?.id == workoutDayID }
            .sorted(by: Self.orderChecklistItems)
            .map {
                SessionChecklistItemSnapshot(
                    id: $0.id,
                    title: $0.movement,
                    detail: $0.dose,
                    note: $0.note,
                    orderIndex: $0.orderIndex
                )
            }

        return SessionWorkoutPlanSnapshot(
            workoutDayID: day.id,
            name: day.name,
            focus: day.focus,
            warmupItems: warmups,
            exercises: exercises,
            cooldownItems: cooldowns
        )
    }

    public func fetchSetLogs(workoutSessionID: UUID) async throws -> [SetLogSnapshot] {
        try modelContext.fetch(FetchDescriptor<SetLog>())
            .filter { $0.workoutSession?.id == workoutSessionID }
            .sorted { lhs, rhs in
                if lhs.completedAt != rhs.completedAt {
                    return lhs.completedAt < rhs.completedAt
                }
                if lhs.setIndex != rhs.setIndex {
                    return lhs.setIndex < rhs.setIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { Self.snapshot($0, workoutSessionID: workoutSessionID) }
    }

    public func fetchTrainingHistory() async throws -> [TrainingHistorySessionSnapshot] {
        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.status == .completed }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        let sessionIDs = Set(sessions.map(\.id))
        let daysByID = Dictionary(
            grouping: try modelContext.fetch(FetchDescriptor<WorkoutDayTemplate>()),
            by: \.id
        )
        let exercisesByID = Dictionary(
            grouping: try modelContext.fetch(FetchDescriptor<ExerciseTemplate>()),
            by: \.id
        )
        var setsBySessionID: [UUID: [SetLog]] = [:]
        for setLog in try modelContext.fetch(FetchDescriptor<SetLog>()) {
            guard let sessionID = setLog.workoutSession?.id,
                  sessionIDs.contains(sessionID) else {
                continue
            }
            setsBySessionID[sessionID, default: []].append(setLog)
        }

        var history: [TrainingHistorySessionSnapshot] = []
        for session in sessions {
            let dayMatches = daysByID[session.workoutDayTemplateId, default: []]
            guard dayMatches.count <= 1 else {
                throw TrainingRepositoryIntegrityError.duplicateWorkoutDayTemplates(
                    id: session.workoutDayTemplateId,
                    count: dayMatches.count
                )
            }
            let day = dayMatches.first
            let groupedSets = Dictionary(
                grouping: setsBySessionID[session.id, default: []],
                by: \.exerciseTemplateId
            )
            var exerciseHistory: [TrainingHistoryExerciseSnapshot] = []
            for (exerciseID, setLogs) in groupedSets {
                let exerciseMatches = exercisesByID[exerciseID, default: []]
                guard exerciseMatches.count <= 1 else {
                    throw TrainingRepositoryIntegrityError.duplicateExerciseTemplates(
                        id: exerciseID,
                        count: exerciseMatches.count
                    )
                }
                let sortedLogs = setLogs.sorted { lhs, rhs in
                    if lhs.setIndex != rhs.setIndex {
                        return lhs.setIndex < rhs.setIndex
                    }
                    if lhs.completedAt != rhs.completedAt {
                        return lhs.completedAt < rhs.completedAt
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                exerciseHistory.append(
                    TrainingHistoryExerciseSnapshot(
                        exerciseTemplateID: exerciseID,
                        exercise: exerciseMatches.first.map(Self.exerciseSnapshot),
                        setLogs: sortedLogs.map {
                            Self.snapshot($0, workoutSessionID: session.id)
                        }
                    )
                )
            }
            exerciseHistory.sort { lhs, rhs in
                let lhsOrder = lhs.exercise?.orderIndex ?? .max
                let rhsOrder = rhs.exercise?.orderIndex ?? .max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.exerciseTemplateID.uuidString < rhs.exerciseTemplateID.uuidString
            }
            history.append(
                TrainingHistorySessionSnapshot(
                    session: Self.sessionSnapshot(session),
                    workoutDayName: day?.name,
                    workoutDayFocus: day?.focus,
                    exercises: exerciseHistory
                )
            )
        }
        return history
    }

    public func updateSet(_ request: SetLogUpdateRequest) async throws -> SetLogSnapshot {
        var savedSnapshot: SetLogSnapshot?
        try modelContext.transaction {
            let matches = try modelContext.fetch(FetchDescriptor<SetLog>())
                .filter { $0.id == request.id }
            guard let setLog = matches.first else {
                throw TrainingRepositoryMutationError.setLogNotFound(id: request.id)
            }
            guard matches.count == 1 else {
                throw TrainingRepositoryIntegrityError.duplicateSetLogs(
                    id: request.id,
                    count: matches.count
                )
            }
            guard let session = setLog.workoutSession else {
                throw TrainingRepositoryMutationError.setLogMissingSession(id: request.id)
            }
            guard session.status == .completed else {
                throw TrainingRepositoryMutationError.historyMutationRequiresCompletedSession(
                    id: session.id,
                    status: session.status
                )
            }
            let exercises = try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())
                .filter { $0.id == setLog.exerciseTemplateId }
            guard let exercise = exercises.first else {
                throw TrainingRepositoryIntegrityError.missingExerciseTemplate(
                    id: setLog.exerciseTemplateId
                )
            }
            guard exercises.count == 1 else {
                throw TrainingRepositoryIntegrityError.duplicateExerciseTemplates(
                    id: setLog.exerciseTemplateId,
                    count: exercises.count
                )
            }
            try SetMeasurementValidator.validate(
                request.measurement,
                for: exercise.measurementKind
            )

            setLog.weightKg = request.measurement.weightKg
            setLog.reps = request.measurement.reps
            setLog.durationSec = request.measurement.durationSec
            setLog.distanceSteps = request.measurement.distanceSteps
            setLog.performedVariant = request.measurement.performedVariant
            setLog.rir = request.measurement.rir
            setLog.updatedAt = request.updatedAt
            session.updatedAt = request.updatedAt
            try modelContext.save()
            savedSnapshot = Self.snapshot(setLog, workoutSessionID: session.id)
        }
        guard let savedSnapshot else {
            throw TrainingRepositoryIntegrityError.transactionDidNotProduceSetSnapshot
        }
        return savedSnapshot
    }

    public func deleteSet(id: UUID, at date: Date) async throws {
        try modelContext.transaction {
            let matches = try modelContext.fetch(FetchDescriptor<SetLog>())
                .filter { $0.id == id }
            guard !matches.isEmpty else { return }
            guard matches.count == 1, let setLog = matches.first else {
                throw TrainingRepositoryIntegrityError.duplicateSetLogs(
                    id: id,
                    count: matches.count
                )
            }
            guard let session = setLog.workoutSession else {
                throw TrainingRepositoryMutationError.setLogMissingSession(id: id)
            }
            guard session.status == .completed else {
                throw TrainingRepositoryMutationError.historyMutationRequiresCompletedSession(
                    id: session.id,
                    status: session.status
                )
            }
            session.updatedAt = date
            modelContext.delete(setLog)
            try modelContext.save()
        }
    }

    public func fetchCompletedExerciseHistory(
        exerciseTemplateID: UUID
    ) async throws -> [CompletedExerciseHistorySnapshot] {
        let completedSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.status == .completed }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        let matchingSets = try modelContext.fetch(FetchDescriptor<SetLog>())
            .filter { $0.exerciseTemplateId == exerciseTemplateID }
        var setsBySessionID: [UUID: [SetLog]] = [:]
        for setLog in matchingSets {
            guard let sessionID = setLog.workoutSession?.id else { continue }
            setsBySessionID[sessionID, default: []].append(setLog)
        }

        return completedSessions.compactMap { session in
            guard let sessionSets = setsBySessionID[session.id], !sessionSets.isEmpty else {
                return nil
            }
            let snapshots = sessionSets
                .sorted { lhs, rhs in
                    if lhs.setIndex != rhs.setIndex {
                        return lhs.setIndex < rhs.setIndex
                    }
                    if lhs.completedAt != rhs.completedAt {
                        return lhs.completedAt < rhs.completedAt
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .map { Self.snapshot($0, workoutSessionID: session.id) }
            return CompletedExerciseHistorySnapshot(
                session: Self.sessionSnapshot(session),
                setLogs: snapshots
            )
        }
    }

    public func fetchWeeklyPallofHistory() async throws -> WeeklyPallofHistorySnapshot {
        let eligibleExerciseTemplateIDs: Set<UUID> = [
            SeedIdentifiers.plankPallof,
            SeedIdentifiers.sidePlankPallof,
        ]
        let completions = try modelContext.fetch(FetchDescriptor<SetLog>())
            .filter {
                eligibleExerciseTemplateIDs.contains($0.exerciseTemplateId)
                    && !$0.isWarmupSet
                    && $0.workoutSession?.status == .completed
            }
            .sorted { lhs, rhs in
                if lhs.completedAt != rhs.completedAt {
                    return lhs.completedAt > rhs.completedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map {
                WeeklyPallofCompletionSnapshot(
                    id: $0.id,
                    exerciseTemplateID: $0.exerciseTemplateId,
                    completedAt: $0.completedAt,
                    performedVariant: $0.performedVariant
                )
            }
        return WeeklyPallofHistorySnapshot(
            eligibleExerciseTemplateIDs: eligibleExerciseTemplateIDs,
            completions: completions
        )
    }

    public func fetchOHPSafeAlternative() async throws -> SessionExerciseSnapshot {
        let matches = try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())
            .filter { $0.id == SeedIdentifiers.halfKneelingDBPress }
        guard !matches.isEmpty else {
            throw TrainingRepositoryIntegrityError.missingExerciseTemplate(
                id: SeedIdentifiers.halfKneelingDBPress
            )
        }
        guard matches.count == 1, let alternative = matches.first else {
            throw TrainingRepositoryIntegrityError.duplicateExerciseTemplates(
                id: SeedIdentifiers.halfKneelingDBPress,
                count: matches.count
            )
        }
        return Self.exerciseSnapshot(alternative)
    }

    public func updateWorkoutSessionOHPSymptomResponse(
        id: UUID,
        response: OHPSymptomResponse,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        var savedSnapshot: WorkoutSessionSnapshot?
        try modelContext.transaction {
            let matches = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
                .filter { $0.id == id }
            guard let session = matches.first else {
                throw TrainingRepositoryMutationError.workoutSessionNotFound(id: id)
            }
            guard matches.count == 1 else {
                throw TrainingRepositoryIntegrityError.duplicateWorkoutSessions(
                    id: id,
                    count: matches.count
                )
            }
            session.ohpSymptomResponse = response
            session.ohpSymptomCheckedAt = date
            session.updatedAt = date
            try modelContext.save()
            savedSnapshot = Self.sessionSnapshot(session)
        }
        guard let savedSnapshot else {
            throw TrainingRepositoryIntegrityError.transactionDidNotProduceSessionSnapshot
        }
        return savedSnapshot
    }

    public func updateWorkoutSessionSummary(
        id: UUID,
        perceivedRecovery: Int?,
        note: String?,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        if let perceivedRecovery, !(1...10).contains(perceivedRecovery) {
            throw TrainingRepositoryMutationError.invalidPerceivedRecovery(perceivedRecovery)
        }

        var savedSnapshot: WorkoutSessionSnapshot?
        try modelContext.transaction {
            let matches = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
                .filter { $0.id == id }
            guard let session = matches.first else {
                throw TrainingRepositoryMutationError.workoutSessionNotFound(id: id)
            }
            guard matches.count == 1 else {
                throw TrainingRepositoryIntegrityError.duplicateWorkoutSessions(
                    id: id,
                    count: matches.count
                )
            }
            guard session.status == .completed else {
                throw TrainingRepositoryMutationError.summaryRequiresCompletedSession(
                    id: id,
                    status: session.status
                )
            }

            session.perceivedRecovery = perceivedRecovery
            session.note = note
            session.updatedAt = date
            try modelContext.save()
            savedSnapshot = Self.sessionSnapshot(session)
        }
        guard let savedSnapshot else {
            throw TrainingRepositoryIntegrityError.transactionDidNotProduceSessionSnapshot
        }
        return savedSnapshot
    }

    public func deleteWorkoutSession(id: UUID) async throws {
        try modelContext.transaction {
            let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
                .filter { $0.id == id }
            guard sessions.count <= 1 else {
                throw TrainingRepositoryIntegrityError.duplicateWorkoutSessions(
                    id: id,
                    count: sessions.count
                )
            }
            let sets = try modelContext.fetch(FetchDescriptor<SetLog>())
                .filter { $0.workoutSession?.id == id }
            let progress = try modelContext.fetch(FetchDescriptor<WorkoutSessionProgress>())
                .filter { $0.workoutSessionId == id }
            sets.forEach { modelContext.delete($0) }
            progress.forEach { modelContext.delete($0) }
            sessions.forEach { modelContext.delete($0) }
            try modelContext.save()
        }
    }

    public func saveSet(_ request: SetLogSaveRequest) async throws -> SetLogSnapshot {
        var savedSnapshot: SetLogSnapshot?

        try modelContext.transaction {
            let matchingSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
                .filter { $0.id == request.workoutSessionID }
            guard !matchingSessions.isEmpty else {
                throw TrainingRepositoryIntegrityError.missingWorkoutSession(
                    id: request.workoutSessionID
                )
            }
            guard matchingSessions.count == 1, let session = matchingSessions.first else {
                throw TrainingRepositoryIntegrityError.duplicateWorkoutSessions(
                    id: request.workoutSessionID,
                    count: matchingSessions.count
                )
            }

            let matchingExercises = try modelContext.fetch(FetchDescriptor<ExerciseTemplate>())
                .filter { $0.id == request.exerciseTemplateID }
            guard !matchingExercises.isEmpty else {
                throw TrainingRepositoryIntegrityError.missingExerciseTemplate(
                    id: request.exerciseTemplateID
                )
            }
            guard matchingExercises.count == 1, let exercise = matchingExercises.first else {
                throw TrainingRepositoryIntegrityError.duplicateExerciseTemplates(
                    id: request.exerciseTemplateID,
                    count: matchingExercises.count
                )
            }

            try SetMeasurementValidator.validate(
                request.measurement,
                for: exercise.measurementKind
            )

            let duplicateCount = try modelContext.fetch(FetchDescriptor<SetLog>())
                .filter {
                    $0.workoutSession?.id == request.workoutSessionID &&
                        $0.exerciseTemplateId == request.exerciseTemplateID &&
                        $0.setIndex == request.setIndex
                }
                .count
            guard duplicateCount == 0 else {
                throw TrainingRepositoryIntegrityError.duplicateSetIndex(
                    workoutSessionID: request.workoutSessionID,
                    exerciseTemplateID: request.exerciseTemplateID,
                    setIndex: request.setIndex
                )
            }

            let setLog = SetLog(
                id: request.id,
                createdAt: request.completedAt,
                updatedAt: request.completedAt,
                exerciseTemplateId: request.exerciseTemplateID,
                setIndex: request.setIndex,
                weightKg: request.measurement.weightKg,
                reps: request.measurement.reps,
                durationSec: request.measurement.durationSec,
                distanceSteps: request.measurement.distanceSteps,
                performedVariant: request.measurement.performedVariant,
                rir: request.measurement.rir,
                isWarmupSet: request.isWarmupSet,
                completedAt: request.completedAt,
                workoutSession: session
            )
            modelContext.insert(setLog)
            try modelContext.save()
            savedSnapshot = Self.snapshot(setLog, workoutSessionID: request.workoutSessionID)
        }

        guard let savedSnapshot else {
            throw TrainingRepositoryIntegrityError.transactionDidNotProduceSetSnapshot
        }
        return savedSnapshot
    }

    private static func snapshot(
        _ setLog: SetLog,
        workoutSessionID: UUID
    ) -> SetLogSnapshot {
        SetLogSnapshot(
            id: setLog.id,
            createdAt: setLog.createdAt,
            updatedAt: setLog.updatedAt,
            workoutSessionID: workoutSessionID,
            exerciseTemplateID: setLog.exerciseTemplateId,
            setIndex: setLog.setIndex,
            measurement: setLog.measurementInput,
            isWarmupSet: setLog.isWarmupSet,
            completedAt: setLog.completedAt
        )
    }

    private static func sessionSnapshot(
        _ session: WorkoutSession
    ) -> WorkoutSessionSnapshot {
        WorkoutSessionSnapshot(
            id: session.id,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            date: session.date,
            status: session.status,
            workoutDayTemplateID: session.workoutDayTemplateId,
            perceivedRecovery: session.perceivedRecovery,
            note: session.note,
            ohpSymptomResponse: session.ohpSymptomResponse,
            ohpSymptomCheckedAt: session.ohpSymptomCheckedAt
        )
    }

    private static func exerciseSnapshot(
        _ exercise: ExerciseTemplate
    ) -> SessionExerciseSnapshot {
        SessionExerciseSnapshot(
            id: exercise.id,
            name: exercise.name,
            orderIndex: exercise.orderIndex,
            targetSets: exercise.targetSets,
            repLow: exercise.repLow,
            repHigh: exercise.repHigh,
            rirLow: exercise.rirLow,
            rirHigh: exercise.rirHigh,
            allowFailure: exercise.allowFailure,
            cues: exercise.cues,
            safetyNote: exercise.safetyNote,
            startingWeightKg: exercise.startingWeightKg,
            progressionRule: exercise.progressionRule,
            measurementKind: exercise.measurementKind
        )
    }

    private static func orderChecklistItems(
        _ lhs: WarmupItem,
        _ rhs: WarmupItem
    ) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func phaseOrderedBefore(_ lhs: ProgramPhase, _ rhs: ProgramPhase) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func workoutDayOrderedBefore(
        _ lhs: WorkoutDayTemplate,
        _ rhs: WorkoutDayTemplate
    ) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func workoutSessionOrderedBefore(
        _ lhs: WorkoutSession,
        _ rhs: WorkoutSession
    ) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func setLogOrderedBefore(_ lhs: SetLog, _ rhs: SetLog) -> Bool {
        if lhs.setIndex != rhs.setIndex {
            return lhs.setIndex < rhs.setIndex
        }
        if lhs.completedAt != rhs.completedAt {
            return lhs.completedAt < rhs.completedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func healthCheckOrderedBefore(
        _ lhs: HealthCheckReminder,
        _ rhs: HealthCheckReminder
    ) -> Bool {
        if lhs.dueDate != rhs.dueDate {
            return lhs.dueDate < rhs.dueDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func orderChecklistItems(
        _ lhs: CooldownItem,
        _ rhs: CooldownItem
    ) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func progressSnapshot(
        _ progress: WorkoutSessionProgress
    ) throws -> WorkoutSessionProgressSnapshot {
        WorkoutSessionProgressSnapshot(
            id: progress.id,
            createdAt: progress.createdAt,
            updatedAt: progress.updatedAt,
            workoutSessionID: progress.workoutSessionId,
            stage: progress.stage,
            currentExerciseTemplateID: progress.currentExerciseTemplateId,
            completedWarmupItemIDs: try WorkoutSessionProgressCodec.decode(
                progress.completedWarmupItemIdsData
            ),
            completedCooldownItemIDs: try WorkoutSessionProgressCodec.decode(
                progress.completedCooldownItemIdsData
            ),
            warmupDisposition: progress.warmupDisposition,
            cooldownDisposition: progress.cooldownDisposition
        )
    }
}
