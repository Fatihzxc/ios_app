import CoreModels
import Foundation
import GuidanceKit
import Observation

public enum FoundationUnitDisplayMode: Equatable, Sendable {
    case metric
    case imperial
}

public struct FoundationProfileSummary: Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let usesFallbackDisplayName: Bool
    public let unitDisplayMode: FoundationUnitDisplayMode
    public let heightCm: Double
    public let startWeightKg: Double
    public let targetWeightKg: Double
    public let proteinTargetG: Double
    public let weeklyWorkoutTarget: Int

    public init(
        id: UUID,
        displayName: String,
        usesFallbackDisplayName: Bool,
        unitDisplayMode: FoundationUnitDisplayMode,
        heightCm: Double,
        startWeightKg: Double,
        targetWeightKg: Double,
        proteinTargetG: Double,
        weeklyWorkoutTarget: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.usesFallbackDisplayName = usesFallbackDisplayName
        self.unitDisplayMode = unitDisplayMode
        self.heightCm = heightCm
        self.startWeightKg = startWeightKg
        self.targetWeightKg = targetWeightKg
        self.proteinTargetG = proteinTargetG
        self.weeklyWorkoutTarget = weeklyWorkoutTarget
    }
}

public struct FoundationProgramSummary: Equatable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct FoundationPhaseSummary: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let orderIndex: Int
    public let monthStart: Int
    public let monthEnd: Int
    public let trainingFocus: String
    public let nutritionFocus: String
    public let milestone: String
    public let entryCriteria: String

    public init(
        id: UUID,
        name: String,
        orderIndex: Int,
        monthStart: Int,
        monthEnd: Int,
        trainingFocus: String,
        nutritionFocus: String,
        milestone: String,
        entryCriteria: String
    ) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.monthStart = monthStart
        self.monthEnd = monthEnd
        self.trainingFocus = trainingFocus
        self.nutritionFocus = nutritionFocus
        self.milestone = milestone
        self.entryCriteria = entryCriteria
    }
}

public struct FoundationWorkoutDaySummary: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let orderIndex: Int
    public let focus: String

    public init(id: UUID, name: String, orderIndex: Int, focus: String) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.focus = focus
    }
}

public enum FoundationDeloadReason: Equatable, Sendable {
    case scheduled
    case reactive
}

public enum FoundationDeloadMode: Equatable, Sendable {
    case recommended
    case active
}

public struct FoundationDeloadSummary: Equatable, Sendable {
    public let mode: FoundationDeloadMode
    public let reason: FoundationDeloadReason
    public let trainingWeekIndex: Int

    public init(
        mode: FoundationDeloadMode,
        reason: FoundationDeloadReason,
        trainingWeekIndex: Int
    ) {
        self.mode = mode
        self.reason = reason
        self.trainingWeekIndex = trainingWeekIndex
    }
}

public struct FoundationProgramSnapshot: Equatable, Sendable {
    public let profile: FoundationProfileSummary
    public let program: FoundationProgramSummary
    public let phases: [FoundationPhaseSummary]
    public let workoutDays: [FoundationWorkoutDaySummary]
    public let deload: FoundationDeloadSummary?

    public init(
        profile: FoundationProfileSummary,
        program: FoundationProgramSummary,
        phases: [FoundationPhaseSummary],
        workoutDays: [FoundationWorkoutDaySummary],
        deload: FoundationDeloadSummary? = nil
    ) {
        self.profile = profile
        self.program = program
        self.phases = phases
        self.workoutDays = workoutDays
        self.deload = deload
    }
}

public enum FoundationProgramState: Equatable, Sendable {
    case loading
    case content(FoundationProgramSnapshot)
    case empty
    case error
}

@MainActor
@Observable
public final class FoundationProgramViewModel {
    public private(set) var state: FoundationProgramState

    @ObservationIgnored
    private let repository: any TrainingRepository

    public init(repository: any TrainingRepository) {
        self.repository = repository
        state = .loading
    }

    public func load() async {
        state = .loading

        do {
            let profile = try await repository.fetchUserProfile()
            let program = try await repository.fetchActiveProgram()

            guard let program else {
                state = .empty
                return
            }
            guard let profile else {
                state = .error
                return
            }

            let phases = try await repository.fetchProgramPhases(programID: program.id)
            let workoutDays = try await repository.fetchWorkoutDays(programID: program.id)
            let deload = await makeDeloadSummary(
                programID: program.id,
                workoutDays: workoutDays
            )
            state = .content(
                FoundationProgramSnapshot(
                    profile: Self.makeProfileSummary(profile),
                    program: FoundationProgramSummary(id: program.id, name: program.name),
                    phases: Self.makePhaseSummaries(phases),
                    workoutDays: Self.makeWorkoutDaySummaries(workoutDays),
                    deload: deload
                )
            )
        } catch {
            state = .error
        }
    }

    private func makeDeloadSummary(
        programID: UUID,
        workoutDays: [WorkoutDayTemplate]
    ) async -> FoundationDeloadSummary? {
        guard let state = try? await repository.fetchProgramState(programID: programID) else {
            return nil
        }
        switch state.deloadStatus {
        case .skipped:
            return nil
        case .active:
            guard let reason = state.deloadReason?.foundationReason else { return nil }
            return .init(
                mode: .active,
                reason: reason,
                trainingWeekIndex: state.trainingWeekIndex
            )
        case .recommended:
            guard let reason = state.deloadReason?.foundationReason else { return nil }
            return .init(
                mode: .recommended,
                reason: reason,
                trainingWeekIndex: state.trainingWeekIndex
            )
        case .none:
            break
        }

        if state.trainingWeekIndex >= 1,
           state.trainingWeekIndex.isMultiple(of: 5) {
            return .init(
                mode: .recommended,
                reason: .scheduled,
                trainingWeekIndex: state.trainingWeekIndex
            )
        }

        var histories: [DeloadGuidance.ExerciseHistory] = []
        for workoutDay in workoutDays {
            guard let exercises = try? await repository.fetchExerciseTemplates(
                workoutDayID: workoutDay.id
            ) else {
                return nil
            }
            for exercise in exercises {
                guard let snapshots = try? await repository.fetchCompletedExerciseHistory(
                    exerciseTemplateID: exercise.id
                ) else {
                    return nil
                }
                histories.append(
                    DeloadGuidance.ExerciseHistory(
                        exerciseID: exercise.id,
                        sessions: snapshots.map(Self.makeDeloadSession)
                    )
                )
            }
        }

        guard case .recommended(.reactive(exerciseID: _)) = DeloadGuidance.evaluate(
            .init(
                trainingWeekIndex: state.trainingWeekIndex,
                status: .none,
                storedReason: nil,
                histories: histories
            )
        ) else {
            return nil
        }
        return .init(
            mode: .recommended,
            reason: .reactive,
            trainingWeekIndex: state.trainingWeekIndex
        )
    }

    private static func makeDeloadSession(
        _ snapshot: CompletedExerciseHistorySnapshot
    ) -> DeloadGuidance.CompletedSession {
        .init(
            id: snapshot.session.id,
            completedAt: snapshot.session.date,
            perceivedRecovery: snapshot.session.perceivedRecovery,
            sets: snapshot.setLogs.map {
                .init(
                    setIndex: $0.setIndex,
                    weightKg: $0.measurement.weightKg,
                    reps: $0.measurement.reps,
                    isWarmupSet: $0.isWarmupSet
                )
            }
        )
    }

    private static func makeProfileSummary(_ profile: UserProfile) -> FoundationProfileSummary {
        let trimmedDisplayName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesFallbackDisplayName = trimmedDisplayName.isEmpty
        let displayName = usesFallbackDisplayName
            ? String(
                localized: "foundation.profile.fallback",
                defaultValue: "Profilim",
                bundle: .module
            )
            : trimmedDisplayName

        return FoundationProfileSummary(
            id: profile.id,
            displayName: displayName,
            usesFallbackDisplayName: usesFallbackDisplayName,
            unitDisplayMode: makeUnitDisplayMode(profile.unitsSystem),
            heightCm: profile.heightCm,
            startWeightKg: profile.startWeightKg,
            targetWeightKg: profile.targetWeightKg,
            proteinTargetG: profile.proteinTargetG,
            weeklyWorkoutTarget: profile.weeklyWorkoutTarget
        )
    }

    private static func makeUnitDisplayMode(_ unitsSystem: UnitsSystem) -> FoundationUnitDisplayMode {
        switch unitsSystem {
        case .metric:
            .metric
        case .imperial:
            .imperial
        }
    }

    private static func makePhaseSummaries(_ phases: [ProgramPhase]) -> [FoundationPhaseSummary] {
        phases
            .sorted(by: orderedBefore)
            .map {
                FoundationPhaseSummary(
                    id: $0.id,
                    name: $0.name,
                    orderIndex: $0.orderIndex,
                    monthStart: $0.monthStart,
                    monthEnd: $0.monthEnd,
                    trainingFocus: $0.trainingFocus,
                    nutritionFocus: $0.nutritionFocus,
                    milestone: $0.milestone,
                    entryCriteria: $0.entryCriteria
                )
            }
    }

    private static func makeWorkoutDaySummaries(
        _ workoutDays: [WorkoutDayTemplate]
    ) -> [FoundationWorkoutDaySummary] {
        workoutDays
            .sorted(by: orderedBefore)
            .map {
                FoundationWorkoutDaySummary(
                    id: $0.id,
                    name: $0.name,
                    orderIndex: $0.orderIndex,
                    focus: $0.focus
                )
            }
    }

    private static func orderedBefore(_ lhs: ProgramPhase, _ rhs: ProgramPhase) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func orderedBefore(
        _ lhs: WorkoutDayTemplate,
        _ rhs: WorkoutDayTemplate
    ) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private extension DeloadReason {
    var foundationReason: FoundationDeloadReason {
        switch self {
        case .scheduled:
            .scheduled
        case .reactive:
            .reactive
        }
    }
}
