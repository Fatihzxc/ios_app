import CoreModels
import Foundation
import GuidanceKit
import Observation

@MainActor
@Observable
public final class TodayViewModel {
    private struct AlertCandidate {
        let priority: TodayAlertPriority.Candidate
        let presentation: TodayAlertPresentation
    }

    public private(set) var state: TodayViewState = .loading

    @ObservationIgnored
    private let repository: any TrainingRepository
    @ObservationIgnored
    private let calendar: Calendar
    @ObservationIgnored
    private let launchStartedAt: TimeInterval?
    @ObservationIgnored
    private let uptime: @MainActor () -> TimeInterval
    @ObservationIgnored
    private let onFirstMeaningfulContent: @MainActor (TimeInterval) -> Void
    @ObservationIgnored
    private var firstMeaningfulContentElapsed: TimeInterval?

    public init(
        repository: any TrainingRepository,
        calendar: Calendar = .current,
        launchStartedAt: TimeInterval? = nil,
        uptime: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        onFirstMeaningfulContent: @escaping @MainActor (TimeInterval) -> Void = { _ in }
    ) {
        self.repository = repository
        self.calendar = calendar
        self.launchStartedAt = launchStartedAt
        self.uptime = uptime
        self.onFirstMeaningfulContent = onFirstMeaningfulContent
    }

    public func load(at date: Date = .now) async {
        await performLoad(at: date, yieldAfterPublishingLoading: false)
    }

    public func retry(at date: Date = .now) async {
        await performLoad(at: date, yieldAfterPublishingLoading: true)
    }

    private func performLoad(
        at date: Date,
        yieldAfterPublishingLoading: Bool
    ) async {
        state = .loading
        if yieldAfterPublishingLoading {
            await Task.yield()
        }
        do {
            guard let snapshot = try await repository.fetchTodaySnapshot() else {
                state = .empty
                return
            }
            guard let semanticPresentation = makePresentation(
                from: snapshot,
                evaluatedAt: date
            ) else {
                state = .error
                return
            }
            state = .content(attachLaunchEvidence(to: semanticPresentation))
        } catch {
            state = .error
        }
    }

    private func makePresentation(
        from snapshot: TodayRepositorySnapshot,
        evaluatedAt date: Date
    ) -> TodayPresentation? {
        let phases = snapshot.phases.sorted(by: phaseOrder)
        guard let currentPhaseIndex = phases.firstIndex(where: {
            $0.id == snapshot.programState.currentPhaseID
        }),
        snapshot.profile.proteinTargetG.isFinite,
        snapshot.profile.proteinTargetG >= 0 else {
            return nil
        }
        let workoutDays = snapshot.workoutDays.sorted(by: workoutDayOrder)
        guard !workoutDays.isEmpty,
              Set(workoutDays.map(\.id)).count == workoutDays.count else {
            return nil
        }

        let outcome = TodayDirective.resolve(
            input: TodayDirective.Input(
                templates: workoutDays.map {
                    WorkoutRotation.Template(id: $0.id, orderIndex: $0.orderIndex)
                },
                sessions: snapshot.sessions.map(makeDirectiveSession),
                weeklyWorkoutTarget: snapshot.profile.weeklyWorkoutTarget,
                overrideRest: false
            ),
            now: date,
            calendar: calendar
        )
        guard let directiveResult = makeDirectivePresentation(
            outcome,
            workoutDays: workoutDays
        ) else {
            return nil
        }

        let phaseRecommendation = PhaseTransition.evaluate(
            .init(
                programStartDate: snapshot.profile.programStartDate,
                currentPhaseID: snapshot.programState.currentPhaseID,
                phases: phases.map {
                    .init(
                        id: $0.id,
                        orderIndex: $0.orderIndex,
                        monthStart: $0.monthStart,
                        monthEnd: $0.monthEnd,
                        entryCriteria: $0.entryCriteria,
                        milestone: $0.milestone
                    )
                },
                evaluatedAt: date
            ),
            calendar: calendar
        )
        let alerts = makeAlerts(
            snapshot: snapshot,
            workoutDays: workoutDays,
            phaseRecommendation: phaseRecommendation,
            phases: phases,
            evaluatedAt: date
        )
        let selection = TodayAlertPriority.select(alerts.map(\.priority))
        let selectedAlert = selection.flatMap { selected in
            alerts.first(where: { $0.priority == selected.primary })?.presentation
        }

        return TodayPresentation(
            phase: TodayPhasePresentation(
                name: phases[currentPhaseIndex].name,
                position: currentPhaseIndex + 1,
                count: phases.count
            ),
            directive: directiveResult.directive,
            alert: selectedAlert,
            additionalAlertCount: selection?.additionalCount ?? 0,
            mainAction: directiveResult.action,
            proteinTargetG: snapshot.profile.proteinTargetG,
            firstMeaningfulContentElapsed: nil
        )
    }

    private func makeDirectivePresentation(
        _ outcome: TodayDirective.Outcome,
        workoutDays: [TodayRepositorySnapshot.WorkoutDay]
    ) -> (directive: TodayDirectivePresentation, action: TodayMainAction)? {
        func day(id: UUID) -> TodayWorkoutDayPresentation? {
            workoutDays.first(where: { $0.id == id }).map {
                TodayWorkoutDayPresentation(id: $0.id, name: $0.name, focus: $0.focus)
            }
        }

        switch outcome {
        case let .train(templateID, reason):
            guard let workoutDay = day(id: templateID), reason == .scheduled else { return nil }
            return (
                .train(workoutDay: workoutDay, reason: .scheduled),
                .start(workoutDayID: templateID)
            )
        case let .resume(sessionID, templateID):
            guard let workoutDay = day(id: templateID) else { return nil }
            return (
                .resume(sessionID: sessionID, workoutDay: workoutDay),
                .resume(sessionID: sessionID, workoutDayID: templateID)
            )
        case let .rest(reason, nextTemplateID):
            guard let workoutDay = day(id: nextTemplateID) else { return nil }
            let presentationReason: TodayRestReason
            switch reason {
            case .completedToday:
                presentationReason = .completedToday
            case .completedPreviousCalendarDay:
                presentationReason = .completedPreviousCalendarDay
            case let .weeklyTargetReached(completed, target):
                presentationReason = .weeklyTargetReached(
                    completed: completed,
                    target: target
                )
            }
            return (
                .rest(reason: presentationReason, nextWorkoutDay: workoutDay),
                .overrideRest(workoutDayID: nextTemplateID)
            )
        case .invalid:
            return nil
        }
    }

    private func makeAlerts(
        snapshot: TodayRepositorySnapshot,
        workoutDays: [TodayRepositorySnapshot.WorkoutDay],
        phaseRecommendation: PhaseTransition.Recommendation,
        phases: [TodayRepositorySnapshot.Phase],
        evaluatedAt date: Date
    ) -> [AlertCandidate] {
        let daysByID = Dictionary(uniqueKeysWithValues: workoutDays.map { ($0.id, $0) })
        var alerts: [AlertCandidate] = []

        for session in snapshot.sessions where session.status == .inProgress {
            if session.ohpSymptomResponse == .symptomsPresent {
                alerts.append(
                    AlertCandidate(
                        priority: .init(sourceID: session.id, kind: .activeSymptoms),
                        presentation: .activeSymptoms
                    )
                )
            }
            if daysByID[session.workoutDayTemplateID]?.containsOHP == true,
               session.ohpSymptomResponse != .symptomFree {
                alerts.append(
                    AlertCandidate(
                        priority: .init(sourceID: session.id, kind: .ohp),
                        presentation: .ohp
                    )
                )
            }
        }

        if let deload = makeDeloadAlert(snapshot) {
            alerts.append(
                AlertCandidate(
                    priority: .init(sourceID: snapshot.program.id, kind: .deload),
                    presentation: deload
                )
            )
        }

        if case let .review(review) = phaseRecommendation,
           let nextPhaseName = phases.first(where: { $0.id == review.nextPhaseID })?.name {
            alerts.append(
                AlertCandidate(
                    priority: .init(sourceID: review.nextPhaseID, kind: .phase),
                    presentation: .phase(nextPhaseName: nextPhaseName)
                )
            )
        }

        for reminder in snapshot.healthChecks where reminder.dueDate <= date {
            alerts.append(
                AlertCandidate(
                    priority: .init(
                        sourceID: reminder.id,
                        kind: .bloodwork,
                        date: reminder.dueDate
                    ),
                    presentation: .bloodwork(
                        title: reminder.title,
                        dueDate: reminder.dueDate
                    )
                )
            )
        }

        for reminder in snapshot.measurementReminders {
            let message = reminder.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { continue }
            alerts.append(
                AlertCandidate(
                    priority: .init(sourceID: reminder.id, kind: .measurement),
                    presentation: .measurement(message: message)
                )
            )
        }
        return alerts
    }

    private func makeDeloadAlert(
        _ snapshot: TodayRepositorySnapshot
    ) -> TodayAlertPresentation? {
        let recommendation = DeloadGuidance.evaluate(
            .init(
                trainingWeekIndex: snapshot.programState.trainingWeekIndex,
                status: guidanceStatus(snapshot.programState.deloadStatus),
                storedReason: guidanceReason(snapshot.programState.deloadReason),
                histories: snapshot.exerciseHistories.map { history in
                    .init(
                        exerciseID: history.exerciseID,
                        sessions: history.sessions.map { session in
                            .init(
                                id: session.session.id,
                                completedAt: session.session.date,
                                perceivedRecovery: session.session.perceivedRecovery,
                                sets: session.setLogs.map {
                                    .init(
                                        setIndex: $0.setIndex,
                                        weightKg: $0.measurement.weightKg,
                                        reps: $0.measurement.reps,
                                        isWarmupSet: $0.isWarmupSet
                                    )
                                }
                            )
                        }
                    )
                }
            )
        )
        let mode: TodayDeloadMode
        let reason: DeloadGuidance.Reason
        switch recommendation {
        case let .recommended(value):
            mode = .recommended
            reason = value
        case let .active(value):
            mode = .active
            reason = value
        case .none:
            return nil
        }
        let presentationReason: TodayDeloadReason
        switch reason {
        case .scheduled:
            presentationReason = .scheduled
        case .reactive:
            presentationReason = .reactive
        }
        return .deload(
            mode: mode,
            reason: presentationReason,
            trainingWeekIndex: snapshot.programState.trainingWeekIndex
        )
    }

    private func attachLaunchEvidence(
        to presentation: TodayPresentation
    ) -> TodayPresentation {
        if firstMeaningfulContentElapsed == nil, let launchStartedAt {
            let elapsed = max(0, uptime() - launchStartedAt)
            firstMeaningfulContentElapsed = elapsed
            onFirstMeaningfulContent(elapsed)
        }
        return TodayPresentation(
            phase: presentation.phase,
            directive: presentation.directive,
            alert: presentation.alert,
            additionalAlertCount: presentation.additionalAlertCount,
            mainAction: presentation.mainAction,
            proteinTargetG: presentation.proteinTargetG,
            firstMeaningfulContentElapsed: firstMeaningfulContentElapsed
        )
    }

    private func makeDirectiveSession(
        _ session: WorkoutSessionSnapshot
    ) -> TodayDirective.Session {
        let status: TodayDirective.Session.Status
        switch session.status {
        case .planned: status = .planned
        case .inProgress: status = .inProgress
        case .completed: status = .completed
        case .skipped: status = .skipped
        }
        return .init(
            id: session.id,
            templateID: session.workoutDayTemplateID,
            date: session.date,
            status: status
        )
    }

    private func guidanceStatus(_ status: DeloadStatus) -> DeloadGuidance.Status {
        switch status {
        case .none: .none
        case .recommended: .recommended
        case .active: .active
        case .skipped: .skipped
        }
    }

    private func guidanceReason(_ reason: DeloadReason?) -> DeloadGuidance.Reason? {
        switch reason {
        case .scheduled: .scheduled
        case .reactive: .reactive(exerciseID: snapshotlessReactiveID)
        case nil: nil
        }
    }

    private var snapshotlessReactiveID: UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }

    private func phaseOrder(
        _ lhs: TodayRepositorySnapshot.Phase,
        _ rhs: TodayRepositorySnapshot.Phase
    ) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func workoutDayOrder(
        _ lhs: TodayRepositorySnapshot.WorkoutDay,
        _ rhs: TodayRepositorySnapshot.WorkoutDay
    ) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
