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
        isDeleteConfirmationPresented = false
        summaryRecovery = nil
        summaryNote = ""
        pendingSetRequest = nil
        completedHistoryByExerciseID = [:]
        weeklyPallofHistory = WeeklyPallofHistorySnapshot(
            eligibleExerciseTemplateIDs: [],
            completions: []
        )

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
        }
    }

    public func toggleWarmupItem(id: UUID) async {
        guard let presentation = activePresentation,
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

    public func advanceExercise() async {
        guard let presentation = activePresentation,
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
        guard let presentation = activePresentation else { return }

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
              presentation.progress.stage == .movement else {
            return
        }
        await finishSession(cooldownDisposition: presentation.progress.cooldownDisposition)
    }

    public func saveCurrentSet() async {
        guard let draft = currentSetDraft else { return }
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

    private func leaveWarmup(disposition: WorkoutChecklistDisposition) async {
        guard let presentation = activePresentation,
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
                    restoreSource: progressed.restoreSource
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
                    restoreSource: presentation.restoreSource
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
                    restoreSource: presentation.restoreSource
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
              let exercise = presentation.currentExercise else {
            currentSetDraft = nil
            currentVariantOptions = []
            recommendationReason = .noPrefill
            setSaveState = .idle
            return
        }

        let completedSets = presentation.completedWorkingSetsForCurrentExercise
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
        currentVariantOptions = isWeeklyPallofExercise ? SessionVariantOption.allCases : []
        let progressionGuidance: (
            measurement: SetMeasurementInput,
            reason: SessionRecommendationReason
        )?
        if sameSessionPrevious != nil,
           exercise.progressionRule == .bodyweightProgression || isWeeklyPallofExercise {
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
        } else {
            progressionGuidance = Self.doubleProgressionGuidance(
                for: exercise,
                history: latestHistory
            )
        }
        currentSetDraft = SetDraft(
            workoutSessionID: presentation.session.id,
            exerciseTemplateID: exercise.id,
            setIndex: nextSetIndex,
            measurementKind: exercise.measurementKind,
            isWarmupSet: false,
            guidance: progressionGuidance?.measurement,
            sameSessionPrevious: sameSessionPrevious,
            priorSessionSameIndex: priorSessionSameIndex,
            seed: seed
        )
        if let progressionGuidance {
            recommendationReason = progressionGuidance.reason
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

    private static func doubleProgressionGuidance(
        for exercise: SessionExerciseSnapshot,
        history: CompletedExerciseHistorySnapshot?
    ) -> (measurement: SetMeasurementInput, reason: SessionRecommendationReason)? {
        guard exercise.progressionRule == .doubleProgression,
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
