import CoreModels
import Foundation
import GuidanceKit
import SwiftData
import TrainingKit

public enum TrainingRepositoryIntegrityError: Error, Equatable, Sendable {
    case duplicateUserProfiles(count: Int)
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
    case transactionDidNotProduceSetSnapshot
    case transactionDidNotProduceSessionSnapshot
    case transactionDidNotProduceProgressSnapshot
    case missingProgramState(programID: UUID)
}

public enum TrainingRepositoryMutationError: Error, Equatable, Sendable {
    case workoutSessionNotFound(id: UUID)
    case invalidPerceivedRecovery(Int)
    case summaryRequiresCompletedSession(id: UUID, status: WorkoutSessionStatus)
    case illegalWorkoutSessionTransition(
        id: UUID,
        from: WorkoutSessionStatus,
        to: WorkoutSessionStatus
    )
    case phaseNotFound(programID: UUID, phaseID: UUID)
}

@MainActor
public final class SwiftDataTrainingRepository: TrainingRepository {
    private let modelContext: ModelContext
    private let calendar: Calendar

    public init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
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

    public func fetchHealthCheckReminders() async throws -> [HealthCheckReminder] {
        let reminders = try modelContext.fetch(FetchDescriptor<HealthCheckReminder>())

        return reminders.sorted { lhs, rhs in
            if lhs.dueDate != rhs.dueDate {
                return lhs.dueDate < rhs.dueDate
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
        var updatedState: ProgramState?
        try modelContext.transaction {
            let state = try requiredProgramState(programID: programID)
            let matchingPhases = try modelContext.fetch(FetchDescriptor<ProgramPhase>())
                .filter { $0.id == phaseID && $0.program?.id == programID }
            guard matchingPhases.count == 1 else {
                throw TrainingRepositoryMutationError.phaseNotFound(
                    programID: programID,
                    phaseID: phaseID
                )
            }

            state.currentPhaseId = phaseID
            state.phaseStartedAt = date
            state.updatedAt = date
            try modelContext.save()
            updatedState = state
        }
        guard let updatedState else {
            throw TrainingRepositoryIntegrityError.missingProgramState(programID: programID)
        }
        return updatedState
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
