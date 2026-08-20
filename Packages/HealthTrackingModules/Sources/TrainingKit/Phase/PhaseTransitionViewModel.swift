import CoreModels
import Foundation
import GuidanceKit
import Observation

public enum PhaseChecklistKind: Equatable, Sendable {
    case entryCriteria
    case milestone
}

public struct PhaseChecklistItemSnapshot: Equatable, Sendable {
    public let kind: PhaseChecklistKind
    public let text: String

    public init(kind: PhaseChecklistKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public struct PhaseTransitionReviewSnapshot: Equatable, Sendable {
    public let currentPhaseID: UUID
    public let nextPhaseID: UUID
    public let nextPhaseName: String
    public let estimatedStart: Date
    public let checklist: [PhaseChecklistItemSnapshot]
    public let isDue: Bool

    public init(
        currentPhaseID: UUID,
        nextPhaseID: UUID,
        nextPhaseName: String,
        estimatedStart: Date,
        checklist: [PhaseChecklistItemSnapshot],
        isDue: Bool
    ) {
        self.currentPhaseID = currentPhaseID
        self.nextPhaseID = nextPhaseID
        self.nextPhaseName = nextPhaseName
        self.estimatedStart = estimatedStart
        self.checklist = checklist
        self.isDue = isDue
    }
}

public struct PhaseSelectionOption: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let orderIndex: Int
    public let isCurrent: Bool

    public init(id: UUID, name: String, orderIndex: Int, isCurrent: Bool) {
        self.id = id
        self.name = name
        self.orderIndex = orderIndex
        self.isCurrent = isCurrent
    }
}

public struct PhaseTransitionSnapshot: Equatable, Sendable {
    public let programID: UUID
    public let currentPhaseID: UUID
    public let currentPhaseName: String
    public let options: [PhaseSelectionOption]
    public let review: PhaseTransitionReviewSnapshot?
    public let isPriority: Bool
    public let isFinalPhase: Bool

    public init(
        programID: UUID,
        currentPhaseID: UUID,
        currentPhaseName: String,
        options: [PhaseSelectionOption],
        review: PhaseTransitionReviewSnapshot?,
        isPriority: Bool,
        isFinalPhase: Bool
    ) {
        self.programID = programID
        self.currentPhaseID = currentPhaseID
        self.currentPhaseName = currentPhaseName
        self.options = options
        self.review = review
        self.isPriority = isPriority
        self.isFinalPhase = isFinalPhase
    }
}

public enum PhaseTransitionViewState: Equatable, Sendable {
    case loading
    case content(PhaseTransitionSnapshot)
    case empty
    case error
}

@MainActor
@Observable
public final class PhaseTransitionViewModel {
    private struct PhaseRecord {
        let id: UUID
        let name: String
        let orderIndex: Int
        let guidance: PhaseTransition.Phase
    }

    public private(set) var state: PhaseTransitionViewState = .loading

    @ObservationIgnored
    private let repository: any TrainingRepository
    @ObservationIgnored
    private let calendar: Calendar
    @ObservationIgnored
    private var programID: UUID?
    @ObservationIgnored
    private var programStartDate: Date?
    @ObservationIgnored
    private var phases: [PhaseRecord] = []
    @ObservationIgnored
    private var programState: ProgramState?

    public init(
        repository: any TrainingRepository,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.calendar = calendar
    }

    public func load(at date: Date = .now) async {
        state = .loading
        do {
            guard let profile = try await repository.fetchUserProfile(),
                  let program = try await repository.fetchActiveProgram() else {
                state = .empty
                return
            }
            let sourcePhases = try await repository.fetchProgramPhases(programID: program.id)
            guard let storedState = try await repository.fetchProgramState(
                programID: program.id
            ) else {
                state = .empty
                return
            }

            programID = program.id
            programStartDate = profile.programStartDate
            phases = sourcePhases.map(Self.makePhaseRecord).sorted(by: Self.phaseOrder)
            programState = storedState
            state = makeState(currentPhaseID: storedState.currentPhaseId, evaluatedAt: date)
        } catch {
            state = .error
        }
    }

    public func stayInCurrentPhase() {
        guard case let .content(snapshot) = state,
              snapshot.review != nil else {
            return
        }
        state = .content(
            PhaseTransitionSnapshot(
                programID: snapshot.programID,
                currentPhaseID: snapshot.currentPhaseID,
                currentPhaseName: snapshot.currentPhaseName,
                options: snapshot.options,
                review: snapshot.review,
                isPriority: false,
                isFinalPhase: snapshot.isFinalPhase
            )
        )
    }

    public func confirmTransition(at date: Date = .now) async {
        guard case let .content(snapshot) = state,
              let review = snapshot.review,
              review.isDue else {
            return
        }
        await selectPhase(id: review.nextPhaseID, at: date)
    }

    public func selectPhaseManually(id phaseID: UUID, at date: Date = .now) async {
        guard phases.contains(where: { $0.id == phaseID }) else {
            return
        }
        await selectPhase(id: phaseID, at: date)
    }

    private func selectPhase(id phaseID: UUID, at date: Date) async {
        guard let programID else { return }
        do {
            programState = try await repository.setActiveProgramPhase(
                programID: programID,
                phaseID: phaseID,
                at: date
            )
            state = makeState(currentPhaseID: phaseID, evaluatedAt: date)
        } catch {
            state = .error
        }
    }

    private func makeState(
        currentPhaseID: UUID,
        evaluatedAt date: Date
    ) -> PhaseTransitionViewState {
        guard let programID,
              let programStartDate,
              let current = phases.first(where: { $0.id == currentPhaseID }) else {
            return .empty
        }
        let recommendation = PhaseTransition.evaluate(
            .init(
                programStartDate: programStartDate,
                currentPhaseID: currentPhaseID,
                phases: phases.map(\.guidance),
                evaluatedAt: date
            ),
            calendar: calendar
        )
        let options = phases.map {
            PhaseSelectionOption(
                id: $0.id,
                name: $0.name,
                orderIndex: $0.orderIndex,
                isCurrent: $0.id == currentPhaseID
            )
        }

        switch recommendation {
        case let .upcoming(review):
            return .content(
                snapshot(
                    programID: programID,
                    current: current,
                    options: options,
                    review: review,
                    isDue: false,
                    isPriority: false
                )
            )
        case let .review(review):
            return .content(
                snapshot(
                    programID: programID,
                    current: current,
                    options: options,
                    review: review,
                    isDue: true,
                    isPriority: true
                )
            )
        case .finalPhase:
            return .content(
                PhaseTransitionSnapshot(
                    programID: programID,
                    currentPhaseID: current.id,
                    currentPhaseName: current.name,
                    options: options,
                    review: nil,
                    isPriority: false,
                    isFinalPhase: true
                )
            )
        case .unavailable:
            return .empty
        }
    }

    private func snapshot(
        programID: UUID,
        current: PhaseRecord,
        options: [PhaseSelectionOption],
        review: PhaseTransition.Review,
        isDue: Bool,
        isPriority: Bool
    ) -> PhaseTransitionSnapshot {
        let nextName = phases.first(where: { $0.id == review.nextPhaseID })?.name ?? ""
        return PhaseTransitionSnapshot(
            programID: programID,
            currentPhaseID: current.id,
            currentPhaseName: current.name,
            options: options,
            review: PhaseTransitionReviewSnapshot(
                currentPhaseID: review.currentPhaseID,
                nextPhaseID: review.nextPhaseID,
                nextPhaseName: nextName,
                estimatedStart: review.estimatedStart,
                checklist: review.checklist.map {
                    PhaseChecklistItemSnapshot(
                        kind: $0.kind == .entryCriteria ? .entryCriteria : .milestone,
                        text: $0.text
                    )
                },
                isDue: isDue
            ),
            isPriority: isPriority,
            isFinalPhase: false
        )
    }

    private static func makePhaseRecord(_ phase: ProgramPhase) -> PhaseRecord {
        PhaseRecord(
            id: phase.id,
            name: phase.name,
            orderIndex: phase.orderIndex,
            guidance: PhaseTransition.Phase(
                id: phase.id,
                orderIndex: phase.orderIndex,
                monthStart: phase.monthStart,
                monthEnd: phase.monthEnd,
                entryCriteria: phase.entryCriteria,
                milestone: phase.milestone
            )
        )
    }

    private static func phaseOrder(_ lhs: PhaseRecord, _ rhs: PhaseRecord) -> Bool {
        if lhs.orderIndex != rhs.orderIndex {
            return lhs.orderIndex < rhs.orderIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
