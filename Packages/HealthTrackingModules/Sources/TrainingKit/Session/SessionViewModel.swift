import CoreModels
import Foundation
import GuidanceKit
import Observation

@MainActor
@Observable
public final class SessionViewModel {
    public private(set) var state: SessionViewState = .idle
    public private(set) var currentSetDraft: SetDraft?
    public private(set) var currentVariantOptions: [SessionVariantOption] = []
    public private(set) var setSaveState: SessionSetSaveState = .idle
    public private(set) var recommendationReason: SessionRecommendationReason = .noPrefill
    public private(set) var ohpSafetyState: SessionOHPSafetyState = .notRequired
    public private(set) var deloadState: SessionDeloadState = .notRequired
    public private(set) var isDeleteConfirmationPresented = false
    public private(set) var summaryRecovery: Int?
    public private(set) var summaryNote = ""

    @ObservationIgnored
    private let repository: any TrainingRepository
    @ObservationIgnored
    private let coordinator: SessionCoordinator
    @ObservationIgnored
    private let calendar: Calendar
    @ObservationIgnored
    private let now: @MainActor () -> Date
    @ObservationIgnored
    private var pendingSetRequest: SetLogSaveRequest?
    @ObservationIgnored
    private var completedHistoryByExerciseID: [UUID: [CompletedExerciseHistorySnapshot]] = [:]
    @ObservationIgnored
    private var weeklyPallofHistory = WeeklyPallofHistorySnapshot(
        eligibleExerciseTemplateIDs: [],
        completions: []
    )
    @ObservationIgnored
    private var ohpDecision: OHPSafetyGate.Decision?
    @ObservationIgnored
    private var ohpTrainingWeekIndex = 1
    @ObservationIgnored
    private var ohpSafeAlternative: SessionExerciseSnapshot?
    @ObservationIgnored
    private var activePhaseOrderIndex = 1
    @ObservationIgnored
    private var activeProgramID: UUID?

    public init(
        repository: any TrainingRepository,
        calendar: Calendar = .current,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.repository = repository
        coordinator = SessionCoordinator(repository: repository)
        self.calendar = calendar
        self.now = now
    }

    public func start(workoutDayID: UUID) async {
        state = .loading
        currentSetDraft = nil
        currentVariantOptions = []
        setSaveState = .idle
        recommendationReason = .noPrefill
        ohpSafetyState = .notRequired
        deloadState = .notRequired
        isDeleteConfirmationPresented = false
        summaryRecovery = nil
        summaryNote = ""
        pendingSetRequest = nil
        completedHistoryByExerciseID = [:]
        weeklyPallofHistory = WeeklyPallofHistorySnapshot(
            eligibleExerciseTemplateIDs: [],
            completions: []
        )
        ohpDecision = nil
        ohpTrainingWeekIndex = 1
        ohpSafeAlternative = nil
        activePhaseOrderIndex = 1
        activeProgramID = nil

        do {
            let existing = try await repository.fetchInProgressWorkoutSession()
            let started = try await coordinator.beginSession(
                WorkoutSessionCreateRequest(
                    date: now(),
                    workoutDayTemplateID: workoutDayID
                )
            )
            guard let plan = try await repository.fetchSessionPlan(
                workoutDayID: started.workoutDayTemplateID
            ) else {
                state = .failed(.load)
                return
            }

            let restored = try await coordinator.restoreInProgressSession()
            let session = restored?.session ?? started
            let progress = restored?.state ?? SessionProgressState(stage: .warmup)
            let source = restored?.source ?? .inferredMissingProgress
            let sets = try await repository.fetchSetLogs(workoutSessionID: session.id)
            var completedHistory: [UUID: [CompletedExerciseHistorySnapshot]] = [:]
            for exercise in plan.exercises {
                completedHistory[exercise.id] = try await repository
                    .fetchCompletedExerciseHistory(exerciseTemplateID: exercise.id)
            }
            completedHistoryByExerciseID = completedHistory
            weeklyPallofHistory = try await repository.fetchWeeklyPallofHistory()
            try await prepareProgramGuidanceContext()
            try await prepareOHPSafety(plan: plan, session: session)
            state = .active(
                SessionPresentation(
                    session: session,
                    plan: plan,
                    progress: progress,
                    setLogs: sets,
                    restoreSource: source
                )
            )
            configureDraft()

            if existing == nil || source != .stored {
                await persistProgress(progress)
            }
        } catch {
            state = .failed(.load)
            currentSetDraft = nil
            currentVariantOptions = []
            ohpSafetyState = .notRequired
            deloadState = .notRequired
        }
    }

    public func toggleWarmupItem(id: UUID) async {
        guard let presentation = activePresentation,
              !isAwaitingPreviousOHPSymptomResponse,
              !isAwaitingDeloadResponse,
              presentation.progress.stage == .warmup,
              presentation.plan.warmupItems.contains(where: { $0.id == id }) else {
            return
        }
        var completed = presentation.progress.completedWarmupItemIDs
        if !completed.insert(id).inserted {
            completed.remove(id)
        }
        await persistProgress(
            SessionProgressState(
                stage: .warmup,
                completedWarmupItemIDs: completed,
                completedCooldownItemIDs: presentation.progress.completedCooldownItemIDs,
                warmupDisposition: .pending,
                cooldownDisposition: presentation.progress.cooldownDisposition
            )
        )
    }

    public func completeWarmup() async {
        await leaveWarmup(disposition: .completed)
    }

    public func skipWarmup() async {
        await leaveWarmup(disposition: .skipped)
    }

    public var displayedExercise: SessionExerciseSnapshot? {
        guard let presentation = activePresentation,
              let currentExercise = presentation.currentExercise else {
            return nil
        }
        guard currentExercise.progressionRule == .gradedEntryOHP,
              case let .stopped(alternative) = ohpSafetyState else {
            return currentExercise
        }
        return alternative
    }

    public var completedWorkingSetsForDisplayedExercise: [SetLogSnapshot] {
        guard let presentation = activePresentation,
              let displayedExercise else {
            return []
        }
        return presentation.setLogs
            .filter {
                !$0.isWarmupSet &&
                    $0.exerciseTemplateID == displayedExercise.id
            }
            .sorted { lhs, rhs in
                if lhs.setIndex != rhs.setIndex {
                    return lhs.setIndex < rhs.setIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    public var canReportCurrentOHPSymptom: Bool {
        guard activePresentation?.currentExercise?.progressionRule == .gradedEntryOHP else {
            return false
        }
        if case .stopped = ohpSafetyState {
            return false
        }
        return true
    }

    public func answerPreviousOHPSymptom(_ response: OHPSymptomResponse) async {
        guard response != .notAsked,
              case let .awaitingPreviousSessionResponse(sessionID, _) = ohpSafetyState,
              let presentation = activePresentation else {
            return
        }
        do {
            let updatedPrevious = try await coordinator.recordOHPSymptomResponse(
                sessionID: sessionID,
                response: response,
                at: now()
            )
            replaceCompletedHistorySession(updatedPrevious)
            resolveOHPSafety(
                currentSession: presentation.session,
                previousSession: updatedPrevious
            )
            configureDraft()
        } catch {
            state = .failed(.ohpSafety)
            currentSetDraft = nil
            currentVariantOptions = []
        }
    }

    public func reportCurrentOHPSymptom() async {
        guard canReportCurrentOHPSymptom,
              let presentation = activePresentation else {
            return
        }
        do {
            let updatedCurrent = try await coordinator.recordOHPSymptomResponse(
                sessionID: presentation.session.id,
                response: .symptomsPresent,
                at: now()
            )
            replaceActiveSession(updatedCurrent)
            let previous = latestCompletedOHPHistory?.session
            resolveOHPSafety(
                currentSession: updatedCurrent,
                previousSession: previous
            )
            configureDraft()
        } catch {
            state = .failed(.ohpSafety)
            currentSetDraft = nil
            currentVariantOptions = []
        }
    }

    public func respondToDeload(_ action: SessionDeloadAction) async {
        guard case let .recommendation(reason, trainingWeekIndex) = deloadState,
              let activeProgramID else {
            return
        }
        do {
            _ = try await repository.applyDeloadAction(
                programID: activeProgramID,
                reason: reason.coreReason,
                action: action.coreAction,
                at: now()
            )
            if action == .accepted {
                deloadState = .active(
                    reason: reason,
                    trainingWeekIndex: trainingWeekIndex
                )
            } else {
                deloadState = .notRequired
            }
            configureDraft()
        } catch {
            state = .failed(.deload)
            currentSetDraft = nil
            currentVariantOptions = []
        }
    }

    public func advanceExercise() async {
        guard let presentation = activePresentation,
              !isAwaitingDeloadResponse,
              presentation.progress.stage == .movement,
              let currentIndex = presentation.currentExerciseIndex else {
            return
        }

        if presentation.plan.exercises.indices.contains(currentIndex + 1) {
            await persistProgress(
                SessionProgressState(
                    stage: .movement,
                    currentExerciseTemplateID: presentation.plan.exercises[currentIndex + 1].id,
                    completedWarmupItemIDs: presentation.progress.completedWarmupItemIDs,
                    completedCooldownItemIDs: presentation.progress.completedCooldownItemIDs,
                    warmupDisposition: presentation.progress.warmupDisposition,
                    cooldownDisposition: presentation.progress.cooldownDisposition
                )
            )
        } else {
            await persistProgress(
                SessionProgressState(
                    stage: .cooldown,
                    completedWarmupItemIDs: presentation.progress.completedWarmupItemIDs,
                    completedCooldownItemIDs: presentation.progress.completedCooldownItemIDs,
                    warmupDisposition: presentation.progress.warmupDisposition,
                    cooldownDisposition: .pending
                )
            )
        }
    }

    public func goBack() async {
        guard let presentation = activePresentation,
              !isAwaitingDeloadResponse else { return }

        switch presentation.progress.stage {
        case .warmup:
            return
        case .movement:
            guard let currentIndex = presentation.currentExerciseIndex else { return }
            if currentIndex > 0 {
                await persistProgress(
                    SessionProgressState(
                        stage: .movement,
                        currentExerciseTemplateID: presentation.plan.exercises[currentIndex - 1].id,
                        completedWarmupItemIDs: presentation.progress.completedWarmupItemIDs,
                        completedCooldownItemIDs: presentation.progress.completedCooldownItemIDs,
                        warmupDisposition: presentation.progress.warmupDisposition,
                        cooldownDisposition: presentation.progress.cooldownDisposition
                    )
                )
            } else {
                await persistProgress(
                    SessionProgressState(
                        stage: .warmup,
                        completedWarmupItemIDs: presentation.progress.completedWarmupItemIDs,
                        completedCooldownItemIDs: presentation.progress.completedCooldownItemIDs,
                        warmupDisposition: presentation.progress.warmupDisposition,
                        cooldownDisposition: presentation.progress.cooldownDisposition
                    )
                )
            }
        case .cooldown:
            guard let lastExercise = presentation.plan.exercises.last else { return }
            await persistProgress(
                SessionProgressState(
                    stage: .movement,
                    currentExerciseTemplateID: lastExercise.id,
                    completedWarmupItemIDs: presentation.progress.completedWarmupItemIDs,
                    completedCooldownItemIDs: presentation.progress.completedCooldownItemIDs,
                    warmupDisposition: presentation.progress.warmupDisposition,
                    cooldownDisposition: presentation.progress.cooldownDisposition
                )
            )
        case .summary:
            return
        }
    }

    public func toggleCooldownItem(id: UUID) async {
        guard let presentation = activePresentation,
              !isAwaitingDeloadResponse,
              presentation.progress.stage == .cooldown,
              presentation.plan.cooldownItems.contains(where: { $0.id == id }) else {
            return
        }
        var completed = presentation.progress.completedCooldownItemIDs
        if !completed.insert(id).inserted {
            completed.remove(id)
        }
        await persistProgress(
            SessionProgressState(
                stage: .cooldown,
                completedWarmupItemIDs: presentation.progress.completedWarmupItemIDs,
                completedCooldownItemIDs: completed,
                warmupDisposition: presentation.progress.warmupDisposition,
                cooldownDisposition: .pending
            )
        )
    }

    public func completeCooldown() async {
        await finishSession(cooldownDisposition: .completed)
    }

    public func skipCooldown() async {
        await finishSession(cooldownDisposition: .skipped)
    }

    public func finishIncomplete() async {
        guard let presentation = activePresentation,
              !isAwaitingDeloadResponse,
              presentation.progress.stage == .movement else {
            return
        }
        await finishSession(cooldownDisposition: presentation.progress.cooldownDisposition)
    }

    public func saveCurrentSet() async {
        guard !isAwaitingDeloadResponse,
              let draft = currentSetDraft else { return }
        do {
            let request = try draft.makeSaveRequest(completedAt: now())
            pendingSetRequest = request
            await performSave(request)
        } catch {
            setSaveState = .validationFailed
        }
    }

    public func retrySetSave() async {
        guard let pendingSetRequest else { return }
        await performSave(pendingSetRequest)
    }

    public func requestDeletion() {
        guard activePresentation != nil else { return }
        isDeleteConfirmationPresented = true
    }

    public func cancelDeletion() {
        isDeleteConfirmationPresented = false
    }

    public func confirmDeletion() async {
        guard let sessionID = activePresentation?.session.id else { return }
        do {
            try await repository.deleteWorkoutSession(id: sessionID)
            isDeleteConfirmationPresented = false
            currentSetDraft = nil
            state = .dismissed
        } catch {
            isDeleteConfirmationPresented = false
            state = .failed(.deletion)
        }
    }

    public func selectRecovery(_ recovery: Int?) {
        if let recovery, !(1...10).contains(recovery) {
            return
        }
        summaryRecovery = recovery
    }

    public func selectPerformedVariant(_ option: SessionVariantOption) {
        guard currentVariantOptions.contains(option) else { return }
        currentSetDraft?.selectPerformedVariant(option.rawValue)
    }

    public func updateSummaryNote(_ note: String) {
        summaryNote = note
    }

    public func saveSummary() async {
        guard let presentation = activePresentation,
              presentation.progress.stage == .summary else {
            return
        }
        let trimmedNote = summaryNote.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await repository.updateWorkoutSessionSummary(
                id: presentation.session.id,
                perceivedRecovery: summaryRecovery,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                at: now()
            )
            currentSetDraft = nil
            state = .dismissed
        } catch {
            state = .failed(.summary)
        }
    }

    private var activePresentation: SessionPresentation? {
        guard case let .active(presentation) = state else { return nil }
        return presentation
    }

    private var isAwaitingPreviousOHPSymptomResponse: Bool {
        if case .awaitingPreviousSessionResponse = ohpSafetyState {
            return true
        }
        return false
    }

    private var isAwaitingDeloadResponse: Bool {
        if case .recommendation = deloadState {
            return true
        }
        return false
    }

    private var latestCompletedOHPHistory: CompletedExerciseHistorySnapshot? {
        guard let exerciseID = activePresentation?.plan.exercises.first(where: {
            $0.progressionRule == .gradedEntryOHP
        })?.id else {
            return nil
        }
        return completedHistoryByExerciseID[exerciseID]?.first
    }

    private func prepareProgramGuidanceContext() async throws {
        guard let program = try await repository.fetchActiveProgram(),
              let programState = try await repository.fetchProgramState(programID: program.id) else {
            return
        }

        activeProgramID = program.id
        ohpTrainingWeekIndex = programState.trainingWeekIndex
        let workoutDays = try await repository.fetchWorkoutDays(programID: program.id)
        for workoutDay in workoutDays {
            let exercises = try await repository.fetchExerciseTemplates(
                workoutDayID: workoutDay.id
            )
            for exercise in exercises where completedHistoryByExerciseID[exercise.id] == nil {
                completedHistoryByExerciseID[exercise.id] = try await repository
                    .fetchCompletedExerciseHistory(exerciseTemplateID: exercise.id)
            }
        }
        let phases = try await repository.fetchProgramPhases(programID: program.id)
        activePhaseOrderIndex = phases.first(where: {
            $0.id == programState.currentPhaseId
        })?.orderIndex ?? 1
        resolveDeload(programState: programState)
    }

    private func resolveDeload(programState: ProgramState) {
        let histories = completedHistoryByExerciseID
            .map { exerciseID, snapshots in
                DeloadGuidance.ExerciseHistory(
                    exerciseID: exerciseID,
                    sessions: snapshots.map { snapshot in
                        DeloadGuidance.CompletedSession(
                            id: snapshot.session.id,
                            completedAt: snapshot.session.date,
                            perceivedRecovery: snapshot.session.perceivedRecovery,
                            sets: snapshot.setLogs.map { setLog in
                                DeloadGuidance.WorkingSet(
                                    setIndex: setLog.setIndex,
                                    weightKg: setLog.measurement.weightKg,
                                    reps: setLog.measurement.reps,
                                    isWarmupSet: setLog.isWarmupSet
                                )
                            }
                        )
                    }
                )
            }
        let reactiveProbe = DeloadGuidance.evaluate(
            DeloadGuidance.Input(
                trainingWeekIndex: nonScheduledWeek(programState.trainingWeekIndex),
                status: .none,
                storedReason: nil,
                histories: histories
            )
        )
        let detectedReactiveExerciseID: UUID?
        if case let .recommended(.reactive(exerciseID: exerciseID)) = reactiveProbe {
            detectedReactiveExerciseID = exerciseID
        } else {
            detectedReactiveExerciseID = nil
        }
        let storedReason = programState.deloadReason.map {
            $0.guidanceReason(reactiveExerciseID: detectedReactiveExerciseID)
        }
        let recommendation = DeloadGuidance.evaluate(
            DeloadGuidance.Input(
                trainingWeekIndex: programState.trainingWeekIndex,
                status: programState.deloadStatus.guidanceStatus,
                storedReason: storedReason,
                histories: histories
            )
        )
        switch recommendation {
        case .none:
            deloadState = .notRequired
        case let .recommended(reason):
            deloadState = .recommendation(
                reason: reason.sessionReason,
                trainingWeekIndex: programState.trainingWeekIndex
            )
        case let .active(reason):
            deloadState = .active(
                reason: reason.sessionReason,
                trainingWeekIndex: programState.trainingWeekIndex
            )
        }
    }

    private func nonScheduledWeek(_ week: Int) -> Int {
        week.isMultiple(of: 5) ? week + 1 : week
    }

    private func prepareOHPSafety(
        plan: SessionWorkoutPlanSnapshot,
        session: WorkoutSessionSnapshot
    ) async throws {
        guard plan.exercises.contains(where: {
            $0.progressionRule == .gradedEntryOHP
        }) else {
            ohpDecision = nil
            ohpSafetyState = .notRequired
            return
        }

        let alternative = try await repository.fetchOHPSafeAlternative()
        ohpSafeAlternative = alternative
        completedHistoryByExerciseID[alternative.id] = try await repository
            .fetchCompletedExerciseHistory(exerciseTemplateID: alternative.id)

        let ohpExerciseID = plan.exercises.first(where: {
            $0.progressionRule == .gradedEntryOHP
        })?.id
        let previousSession = ohpExerciseID
            .flatMap { completedHistoryByExerciseID[$0]?.first?.session }
        resolveOHPSafety(
            currentSession: session,
            previousSession: previousSession
        )
    }

    private func resolveOHPSafety(
        currentSession: WorkoutSessionSnapshot,
        previousSession: WorkoutSessionSnapshot?
    ) {
        let outcome = OHPSafetyGate.resolve(
            OHPSafetyGate.Input(
                trainingWeekIndex: ohpTrainingWeekIndex,
                previousSession: previousSession.map {
                    OHPSafetyGate.PreviousSession(
                        id: $0.id,
                        response: $0.ohpSymptomResponse.guidanceResponse
                    )
                },
                currentSymptomsPresent: currentSession.ohpSymptomResponse == .symptomsPresent
            )
        )
        guard case let .decision(decision) = outcome else {
            ohpDecision = nil
            ohpSafetyState = .notRequired
            return
        }
        ohpDecision = decision
        ohpSafetyState = sessionState(for: decision)
    }

    private func sessionState(
        for decision: OHPSafetyGate.Decision
    ) -> SessionOHPSafetyState {
        if decision.safetyStop != nil, let ohpSafeAlternative {
            return .stopped(alternative: ohpSafeAlternative)
        }
        if let question = decision.priorSessionQuestion {
            return .awaitingPreviousSessionResponse(
                sessionID: question.sessionID,
                entryVariant: decision.entryVariant.sessionVariant
            )
        }
        switch decision.loadIncreasePolicy {
        case .allowed:
            return .ready(
                entryVariant: decision.entryVariant.sessionVariant,
                loadIncreasePolicy: .allowed
            )
        case let .blocked(reason):
            return .ready(
                entryVariant: decision.entryVariant.sessionVariant,
                loadIncreasePolicy: .blocked(reason.sessionBlockReason)
            )
        }
    }

    private func replaceCompletedHistorySession(_ session: WorkoutSessionSnapshot) {
        let matchingExerciseIDs = completedHistoryByExerciseID.compactMap { exerciseID, histories in
            histories.contains(where: { $0.session.id == session.id })
                ? exerciseID
                : nil
        }
        for exerciseID in matchingExerciseIDs {
            let histories = completedHistoryByExerciseID[exerciseID, default: []]
            completedHistoryByExerciseID[exerciseID] = histories.map { history in
                guard history.session.id == session.id else { return history }
                return CompletedExerciseHistorySnapshot(
                    session: session,
                    setLogs: history.setLogs
                )
            }
        }
    }

    private func replaceActiveSession(_ session: WorkoutSessionSnapshot) {
        guard let presentation = activePresentation else { return }
        state = .active(
            SessionPresentation(
                session: session,
                plan: presentation.plan,
                progress: presentation.progress,
                setLogs: presentation.setLogs,
                restoreSource: presentation.restoreSource,
                personalRecords: presentation.personalRecords
            )
        )
    }

    private func leaveWarmup(disposition: WorkoutChecklistDisposition) async {
        guard let presentation = activePresentation,
              !isAwaitingPreviousOHPSymptomResponse,
              !isAwaitingDeloadResponse,
              presentation.progress.stage == .warmup else {
            return
        }
        let nextStage: WorkoutSessionProgressStage = presentation.plan.exercises.isEmpty
            ? .cooldown
            : .movement
        await persistProgress(
            SessionProgressState(
                stage: nextStage,
                currentExerciseTemplateID: presentation.plan.exercises.first?.id,
                completedWarmupItemIDs: presentation.progress.completedWarmupItemIDs,
                completedCooldownItemIDs: presentation.progress.completedCooldownItemIDs,
                warmupDisposition: disposition,
                cooldownDisposition: presentation.progress.cooldownDisposition
            )
        )
    }

    private func finishSession(
        cooldownDisposition: WorkoutChecklistDisposition
    ) async {
        guard let presentation = activePresentation,
              !isAwaitingDeloadResponse,
              presentation.session.status == .inProgress else {
            return
        }
        let summaryProgress = SessionProgressState(
            stage: .summary,
            completedWarmupItemIDs: presentation.progress.completedWarmupItemIDs,
            completedCooldownItemIDs: presentation.progress.completedCooldownItemIDs,
            warmupDisposition: presentation.progress.warmupDisposition,
            cooldownDisposition: cooldownDisposition
        )
        await persistProgress(summaryProgress)
        guard let progressed = activePresentation else { return }
        let personalRecords = PersonalRecordPresentationMapper.make(
            plan: progressed.plan,
            currentSetLogs: progressed.setLogs,
            priorHistoryByExerciseID: completedHistoryByExerciseID
        )

        do {
            let completed = try await repository.transitionWorkoutSession(
                id: progressed.session.id,
                to: .completed,
                at: now()
            )
            state = .active(
                SessionPresentation(
                    session: completed,
                    plan: progressed.plan,
                    progress: progressed.progress,
                    setLogs: progressed.setLogs,
                    restoreSource: progressed.restoreSource,
                    personalRecords: personalRecords
                )
            )
            configureDraft()
        } catch {
            state = .failed(.completion)
            currentSetDraft = nil
        }
    }

    private func persistProgress(_ progress: SessionProgressState) async {
        guard let presentation = activePresentation else { return }
        do {
            let snapshot = try await repository.saveWorkoutSessionProgress(
                WorkoutSessionProgressUpdate(
                    workoutSessionID: presentation.session.id,
                    stage: progress.stage,
                    currentExerciseTemplateID: progress.currentExerciseTemplateID,
                    completedWarmupItemIDs: progress.completedWarmupItemIDs,
                    completedCooldownItemIDs: progress.completedCooldownItemIDs,
                    warmupDisposition: progress.warmupDisposition,
                    cooldownDisposition: progress.cooldownDisposition,
                    updatedAt: now()
                )
            )
            state = .active(
                SessionPresentation(
                    session: presentation.session,
                    plan: presentation.plan,
                    progress: snapshot.state,
                    setLogs: presentation.setLogs,
                    restoreSource: presentation.restoreSource,
                    personalRecords: presentation.personalRecords
                )
            )
            configureDraft()
        } catch {
            state = .failed(.progress)
            currentSetDraft = nil
        }
    }

    private func performSave(_ request: SetLogSaveRequest) async {
        setSaveState = .saving
        do {
            let saved = try await repository.saveSet(request)
            guard let presentation = activePresentation else {
                setSaveState = .repositoryFailed
                return
            }
            let sets = (presentation.setLogs.filter { $0.id != saved.id } + [saved])
                .sorted { lhs, rhs in
                    if lhs.completedAt != rhs.completedAt {
                        return lhs.completedAt < rhs.completedAt
                    }
                    if lhs.setIndex != rhs.setIndex {
                        return lhs.setIndex < rhs.setIndex
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            state = .active(
                SessionPresentation(
                    session: presentation.session,
                    plan: presentation.plan,
                    progress: presentation.progress,
                    setLogs: sets,
                    restoreSource: presentation.restoreSource,
                    personalRecords: presentation.personalRecords
                )
            )
            pendingSetRequest = nil
            configureDraft()
            setSaveState = .saved(setID: saved.id)
        } catch {
            setSaveState = .repositoryFailed
        }
    }

    private func configureDraft() {
        guard let presentation = activePresentation,
              let exercise = displayedExercise else {
            currentSetDraft = nil
            currentVariantOptions = []
            recommendationReason = .noPrefill
            setSaveState = .idle
            return
        }

        let completedSets = completedWorkingSetsForDisplayedExercise
        let nextSetIndex = (completedSets.map(\.setIndex).max() ?? 0) + 1
        let sameSessionPrevious = completedSets.last?.measurement
        let latestHistory = completedHistoryByExerciseID[exercise.id]?.first
        let priorSessionSameIndex = latestHistory?.setLogs.first(where: {
            !$0.isWarmupSet && $0.setIndex == nextSetIndex
        })?.measurement
        let seed = Self.templateSeed(for: exercise)
        let isWeeklyPallofExercise = weeklyPallofHistory
            .eligibleExerciseTemplateIDs
            .contains(exercise.id)
        currentVariantOptions = isWeeklyPallofExercise ? [.pallof, .plank] : []
        let progressionGuidance: (
            measurement: SetMeasurementInput,
            reason: SessionRecommendationReason
        )?
        if sameSessionPrevious != nil,
           exercise.progressionRule == .bodyweightProgression ||
               exercise.progressionRule == .gradedEntryOHP ||
               isWeeklyPallofExercise {
            progressionGuidance = nil
        } else if isWeeklyPallofExercise {
            progressionGuidance = Self.weeklyPallofGuidance(
                history: weeklyPallofHistory,
                baseMeasurement: priorSessionSameIndex ?? seed,
                now: now(),
                calendar: calendar
            )
        } else if exercise.progressionRule == .bodyweightProgression {
            progressionGuidance = Self.bodyweightGuidance(
                for: exercise,
                history: latestHistory
            )
        } else if exercise.progressionRule == .gradedEntryOHP {
            progressionGuidance = Self.ohpGuidance(
                for: exercise,
                history: latestHistory,
                decision: ohpDecision
            )
        } else {
            progressionGuidance = Self.doubleProgressionGuidance(
                for: exercise,
                history: latestHistory
            )
        }
        let composedGuidance = progressionGuidance.map {
            Self.composeEquipmentAndPhaseGuidance(
                $0,
                for: exercise,
                phaseOrderIndex: activePhaseOrderIndex
            )
        }
        let finalGuidance = Self.composeDeloadGuidance(
            composedGuidance,
            sameSessionPrevious: sameSessionPrevious,
            exercise: exercise,
            history: latestHistory,
            state: deloadState
        )
        currentSetDraft = SetDraft(
            workoutSessionID: presentation.session.id,
            exerciseTemplateID: exercise.id,
            setIndex: nextSetIndex,
            measurementKind: exercise.measurementKind,
            isWarmupSet: false,
            guidance: finalGuidance?.measurement,
            sameSessionPrevious: sameSessionPrevious,
            priorSessionSameIndex: priorSessionSameIndex,
            seed: seed
        )
        if let finalGuidance {
            recommendationReason = finalGuidance.reason
        } else if sameSessionPrevious != nil {
            recommendationReason = .sameSessionPrevious
        } else if priorSessionSameIndex != nil {
            recommendationReason = .priorSessionSameIndex
        } else {
            recommendationReason = .templateStartingValues
        }
        if case .saving = setSaveState {
            return
        }
        setSaveState = .idle
    }

    private static func templateSeed(
        for exercise: SessionExerciseSnapshot
    ) -> SetMeasurementInput {
        switch exercise.measurementKind {
        case .weightReps:
            return SetMeasurementInput(
                weightKg: exercise.startingWeightKg,
                reps: exercise.repLow
            )
        case .reps:
            return SetMeasurementInput(
                weightKg: exercise.startingWeightKg,
                reps: exercise.repLow
            )
        case .duration:
            return SetMeasurementInput(durationSec: exercise.repLow)
        case .steps:
            return SetMeasurementInput(
                weightKg: exercise.startingWeightKg,
                distanceSteps: exercise.repLow
            )
        case .quality:
            return SetMeasurementInput()
        }
    }

    private static func composeEquipmentAndPhaseGuidance(
        _ base: (measurement: SetMeasurementInput, reason: SessionRecommendationReason),
        for exercise: SessionExerciseSnapshot,
        phaseOrderIndex: Int
    ) -> (measurement: SetMeasurementInput, reason: SessionRecommendationReason) {
        let phaseDecision = PhaseTrainingFocus.resolve(
            PhaseTrainingFocus.Input(
                phaseOrderIndex: phaseOrderIndex,
                exerciseFocus: exercise.progressionRule == .boneFocusHeavy
                    ? .boneFocusHeavy
                    : .standard,
                templateRepLow: exercise.repLow,
                baseSuggestedReps: base.measurement.reps
            )
        )
        var measurement = base.measurement
        measurement.reps = phaseDecision.suggestedReps

        let ceilingDecision = EquipmentCeiling.apply(
            EquipmentCeiling.Input(
                suggestedWeightKg: measurement.weightKg,
                suggestedReps: measurement.reps
            )
        )
        measurement.weightKg = ceilingDecision.suggestedWeightKg
        measurement.reps = ceilingDecision.suggestedReps

        let phaseFocusApplied = phaseDecision.reason == .boneFocusLowerBound
        if ceilingDecision.reason == .atCeiling {
            let ohpReason: SessionOHPRecommendationReason?
            if case let .ohp(reason) = base.reason {
                ohpReason = reason
            } else {
                ohpReason = nil
            }
            return (
                measurement,
                .equipmentCeiling(
                    SessionEquipmentCeilingReason(
                        weightKg: EquipmentCeiling.maximumWeightKg,
                        phaseFocusApplied: phaseFocusApplied,
                        ohpReason: ohpReason
                    )
                )
            )
        }
        if phaseFocusApplied {
            return (measurement, .phaseTrainingFocus(.boneFocusLowerBound))
        }
        return (measurement, base.reason)
    }

    private static func composeDeloadGuidance(
        _ base: (measurement: SetMeasurementInput, reason: SessionRecommendationReason)?,
        sameSessionPrevious: SetMeasurementInput?,
        exercise: SessionExerciseSnapshot,
        history: CompletedExerciseHistorySnapshot?,
        state: SessionDeloadState
    ) -> (measurement: SetMeasurementInput, reason: SessionRecommendationReason)? {
        guard sameSessionPrevious == nil,
              case let .active(reason, _) = state,
              let history else {
            return base
        }
        let lastWorkingSet = history.setLogs
            .filter { !$0.isWarmupSet }
            .sorted { $0.setIndex < $1.setIndex }
            .last
        guard let lastWorkingSet,
              let load = DeloadGuidance.loadRecommendation(
                  lastWeightKg: lastWorkingSet.measurement.weightKg,
                  equipmentIncrementKg: 2.5
              ) else {
            return base
        }

        var measurement = base?.measurement ?? lastWorkingSet.measurement
        measurement.weightKg = load.defaultWeightKg
        measurement.reps = exercise.repLow ?? measurement.reps
        return (
            measurement,
            .deload(
                SessionDeloadRecommendationReason(
                    reason: reason,
                    defaultFraction: 0.5,
                    allowedFractionRange: load.allowedFractionRange
                )
            )
        )
    }

    private static func doubleProgressionGuidance(
        for exercise: SessionExerciseSnapshot,
        history: CompletedExerciseHistorySnapshot?
    ) -> (measurement: SetMeasurementInput, reason: SessionRecommendationReason)? {
        guard exercise.progressionRule == .doubleProgression ||
                  exercise.progressionRule == .boneFocusHeavy,
              let repLow = exercise.repLow,
              let history else {
            return nil
        }
        let suggestion = DoubleProgression.suggest(
            DoubleProgression.Input(
                repLow: repLow,
                repHigh: exercise.repHigh,
                rirLow: exercise.rirLow,
                sets: history.setLogs.map {
                    DoubleProgression.WorkingSet(
                        setIndex: $0.setIndex,
                        weightKg: $0.measurement.weightKg,
                        reps: $0.measurement.reps,
                        rir: $0.measurement.rir,
                        isWarmupSet: $0.isWarmupSet
                    )
                }
            )
        )
        return (
            SetMeasurementInput(
                weightKg: suggestion.proposedMeasurement.weightKg,
                reps: suggestion.proposedMeasurement.reps
            ),
            recommendationReason(for: suggestion.reason)
        )
    }

    private static func ohpGuidance(
        for exercise: SessionExerciseSnapshot,
        history: CompletedExerciseHistorySnapshot?,
        decision: OHPSafetyGate.Decision?
    ) -> (measurement: SetMeasurementInput, reason: SessionRecommendationReason)? {
        guard exercise.progressionRule == .gradedEntryOHP,
              let decision else {
            return nil
        }
        let variant = decision.entryVariant.rawValue
        guard let history, let repLow = exercise.repLow else {
            return (
                SetMeasurementInput(
                    weightKg: exercise.startingWeightKg,
                    reps: exercise.repLow,
                    performedVariant: variant
                ),
                .ohp(.firstSession)
            )
        }

        let workingSets = history.setLogs.filter { !$0.isWarmupSet }
        let suggestion = DoubleProgression.suggest(
            DoubleProgression.Input(
                repLow: repLow,
                repHigh: exercise.repHigh,
                rirLow: exercise.rirLow,
                sets: workingSets.map {
                    DoubleProgression.WorkingSet(
                        setIndex: $0.setIndex,
                        weightKg: $0.measurement.weightKg,
                        reps: $0.measurement.reps,
                        rir: $0.measurement.rir,
                        isWarmupSet: $0.isWarmupSet
                    )
                }
            )
        )

        switch decision.loadIncreasePolicy {
        case .allowed:
            let reason: SessionOHPRecommendationReason
            switch suggestion.reason {
            case .increase:
                reason = .increaseAllowed
            case let .hold(holdReason):
                reason = .progressionHold(holdReason.sessionReason)
            }
            return (
                SetMeasurementInput(
                    weightKg: suggestion.proposedMeasurement.weightKg,
                    reps: suggestion.proposedMeasurement.reps,
                    performedVariant: variant
                ),
                .ohp(reason)
            )
        case let .blocked(blockReason):
            let proposedMeasurement: DoubleProgression.ProposedMeasurement
            if case .increase = suggestion.reason,
               let lastSet = workingSets.sorted(by: { $0.setIndex < $1.setIndex }).last {
                proposedMeasurement = DoubleProgression.ProposedMeasurement(
                    weightKg: lastSet.measurement.weightKg,
                    reps: exercise.repHigh ?? lastSet.measurement.reps
                )
            } else {
                proposedMeasurement = suggestion.proposedMeasurement
            }
            return (
                SetMeasurementInput(
                    weightKg: proposedMeasurement.weightKg,
                    reps: proposedMeasurement.reps,
                    performedVariant: variant
                ),
                .ohp(blockReason.sessionRecommendationReason)
            )
        }
    }

    private static func bodyweightGuidance(
        for exercise: SessionExerciseSnapshot,
        history: CompletedExerciseHistorySnapshot?
    ) -> (measurement: SetMeasurementInput, reason: SessionRecommendationReason)? {
        guard exercise.progressionRule == .bodyweightProgression,
              let history else {
            return nil
        }
        let suggestion = BodyweightProgression.suggest(
            BodyweightProgression.Input(
                repLow: exercise.repLow ?? 1,
                repHigh: exercise.repHigh,
                definedHarderVariant: nil,
                sets: history.setLogs.map {
                    BodyweightProgression.WorkingSet(
                        setIndex: $0.setIndex,
                        weightKg: $0.measurement.weightKg,
                        reps: $0.measurement.reps,
                        performedVariant: $0.measurement.performedVariant,
                        isWarmupSet: $0.isWarmupSet
                    )
                }
            )
        )
        return (
            SetMeasurementInput(
                weightKg: suggestion.proposedMeasurement.weightKg,
                reps: suggestion.proposedMeasurement.reps,
                performedVariant: suggestion.proposedMeasurement.performedVariant
            ),
            .bodyweight(suggestion.reason.sessionReason)
        )
    }

    private static func weeklyPallofGuidance(
        history: WeeklyPallofHistorySnapshot,
        baseMeasurement: SetMeasurementInput,
        now: Date,
        calendar: Calendar
    ) -> (measurement: SetMeasurementInput, reason: SessionRecommendationReason)? {
        let outcome = WeeklyPallofSelection.resolve(
            input: WeeklyPallofSelection.Input(
                eligibleExerciseTemplateIDs: history.eligibleExerciseTemplateIDs,
                completions: history.completions.map {
                    WeeklyPallofSelection.Completion(
                        id: $0.id,
                        exerciseTemplateID: $0.exerciseTemplateID,
                        completedAt: $0.completedAt,
                        performedVariant: $0.performedVariant.flatMap(
                            WeeklyPallofSelection.Variant.init(rawValue:)
                        )
                    )
                }
            ),
            now: now,
            calendar: calendar
        )
        guard case let .suggestion(suggestion) = outcome else { return nil }
        return (
            SetMeasurementInput(
                weightKg: baseMeasurement.weightKg,
                reps: baseMeasurement.reps,
                durationSec: baseMeasurement.durationSec,
                distanceSteps: baseMeasurement.distanceSteps,
                performedVariant: suggestion.proposedVariant.rawValue,
                rir: baseMeasurement.rir
            ),
            .weeklyPallof(suggestion.reason.sessionReason)
        )
    }

    private static func recommendationReason(
        for reason: DoubleProgression.Reason
    ) -> SessionRecommendationReason {
        switch reason {
        case .increase:
            return .doubleProgressionIncrease
        case let .hold(holdReason):
            return .doubleProgressionHold(holdReason.sessionReason)
        }
    }
}

private extension DoubleProgression.HoldReason {
    var sessionReason: SessionDoubleProgressionHoldReason {
        switch self {
        case .noWorkingSets:
            .noWorkingSets
        case .missingRepCeiling:
            .missingRepCeiling
        case .repetitionsBelowCeiling:
            .repetitionsBelowCeiling
        case .missingRIR:
            .missingRIR
        case .rirAboveThreshold:
            .rirAboveThreshold
        case .missingExternalWeight:
            .missingExternalWeight
        }
    }
}

private extension BodyweightProgression.Reason {
    var sessionReason: SessionBodyweightRecommendationReason {
        switch self {
        case .noWorkingSets:
            .noWorkingSets
        case .missingRepCeiling:
            .missingRepCeiling
        case .inconsistentVariants:
            .inconsistentVariants
        case .buildRepetitions:
            .buildRepetitions
        case .advanceToDefinedVariant:
            .advanceToDefinedVariant
        case .programAdjustmentRequired:
            .programAdjustmentRequired
        }
    }
}

private extension WeeklyPallofSelection.Reason {
    var sessionReason: SessionWeeklyPallofRecommendationReason {
        switch self {
        case .pallofDue:
            .pallofDue
        case .pallofCompletedThisWeek:
            .pallofCompletedThisWeek
        }
    }
}

private extension OHPSymptomResponse {
    var guidanceResponse: OHPSafetyGate.SymptomResponse {
        switch self {
        case .notAsked:
            .notAsked
        case .symptomFree:
            .symptomFree
        case .symptomsPresent:
            .symptomsPresent
        case .uncertain:
            .uncertain
        }
    }
}

private extension OHPSafetyGate.EntryVariant {
    var sessionVariant: SessionOHPEntryVariant {
        switch self {
        case .seatedNeutral:
            .seatedNeutral
        case .standingNeutral:
            .standingNeutral
        case .standingStandard:
            .standingStandard
        }
    }
}

private extension OHPSafetyGate.LoadIncreaseBlockReason {
    var sessionBlockReason: SessionOHPLoadIncreaseBlockReason {
        switch self {
        case .firstSession:
            .firstSession
        case .previousResponseRequired:
            .previousResponseRequired
        case .previousSymptomsPresent:
            .previousSymptomsPresent
        case .previousResponseUncertain:
            .previousResponseUncertain
        case .currentSymptomsPresent:
            .currentSymptomsPresent
        }
    }

    var sessionRecommendationReason: SessionOHPRecommendationReason {
        switch self {
        case .firstSession:
            .firstSession
        case .previousResponseRequired:
            .previousResponseRequired
        case .previousSymptomsPresent:
            .previousSymptomsPresent
        case .previousResponseUncertain:
            .previousResponseUncertain
        case .currentSymptomsPresent:
            .currentSymptomsPresent
        }
    }
}

private extension DeloadStatus {
    var guidanceStatus: DeloadGuidance.Status {
        switch self {
        case .none:
            .none
        case .recommended:
            .recommended
        case .active:
            .active
        case .skipped:
            .skipped
        }
    }
}

private extension DeloadReason {
    func guidanceReason(reactiveExerciseID: UUID?) -> DeloadGuidance.Reason {
        switch self {
        case .scheduled:
            .scheduled
        case .reactive:
            .reactive(
                exerciseID: reactiveExerciseID ?? UUID(
                    uuidString: "00000000-0000-0000-0000-000000000000"
                )!
            )
        }
    }
}

private extension DeloadGuidance.Reason {
    var sessionReason: SessionDeloadReason {
        switch self {
        case .scheduled:
            .scheduled
        case let .reactive(exerciseID):
            .reactive(exerciseID: exerciseID)
        }
    }
}

private extension SessionDeloadReason {
    var coreReason: DeloadReason {
        switch self {
        case .scheduled:
            .scheduled
        case .reactive:
            .reactive
        }
    }
}

private extension SessionDeloadAction {
    var coreAction: DeloadAction {
        switch self {
        case .accepted:
            .accepted
        case .stay:
            .stay
        case .techniqueReview:
            .techniqueReview
        case .skipped:
            .skipped
        }
    }
}
