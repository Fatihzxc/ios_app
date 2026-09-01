import DesignSystem
import Foundation
import Observation

public enum BodyMetricLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

public enum BodyMetricEditPhase: Equatable, Sendable {
    case idle
    case saving
    case saved
    case failed
}

@MainActor
@Observable
public final class BodyMetricViewModel {
    public var weightKilograms: Double?
    public var waistCentimeters: Double?
    public private(set) var customMetric: BodyMetricValueInput?
    public private(set) var snapshots: [BodyMetricSnapshot] = []
    public private(set) var loadPhase: BodyMetricLoadPhase = .idle
    public private(set) var editPhase: BodyMetricEditPhase = .idle
    public private(set) var mutationPhase:
        QuickEntryMutationPhase<BodyMetricCreationUndoToken> = .idle
    public private(set) var validationIssue: QuickEntryValidationIssue?

    @ObservationIgnored
    private let repository: any MetricsRepository
    @ObservationIgnored
    private let makeRequestID: @MainActor () -> UUID
    @ObservationIgnored
    private let onCommittedEdit: @MainActor () async -> Void
    @ObservationIgnored
    private var mutationMachine =
        QuickEntryMutationStateMachine<BodyMetricCreationUndoToken>()
    @ObservationIgnored
    private var pendingBatch: BodyMetricBatchInput?
    @ObservationIgnored
    private var loadGeneration: UInt64 = 0
    @ObservationIgnored
    private var editGeneration: UInt64 = 0

    public init(
        repository: any MetricsRepository,
        makeRequestID: @escaping @MainActor () -> UUID = { UUID() },
        onCommittedEdit: @escaping @MainActor () async -> Void = {}
    ) {
        self.repository = repository
        self.makeRequestID = makeRequestID
        self.onCommittedEdit = onCommittedEdit
    }

    public func setCustomMetric(_ metric: BodyMetricValueInput?) {
        customMetric = metric
        validationIssue = nil
    }

    public func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        loadPhase = .loading
        do {
            let loaded = try await repository.fetchBodyMetrics()
            guard generation == loadGeneration else { return }
            snapshots = loaded.sorted(by: BodyMetricOrdering.newestFirst)
            loadPhase = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            loadPhase = .failed
        }
    }

    public func save(date: Date) async {
        let batch: BodyMetricBatchInput
        do {
            batch = try BodyMetricBatchInput(
                date: date,
                weightKilograms: weightKilograms,
                waistCentimeters: waistCentimeters,
                customMetrics: customMetric.map { [$0] } ?? []
            )
        } catch let error as BodyMetricInputError {
            validationIssue = Self.validationIssue(for: error)
            return
        } catch {
            validationIssue = Self.validationIssue(for: .emptyBatch)
            return
        }

        validationIssue = nil
        guard let attempt = mutationMachine.beginSave(requestID: makeRequestID()) else {
            return
        }
        pendingBatch = batch
        publishMutationPhase()
        await performCreate(batch, attempt: attempt)
    }

    public func retrySave() async {
        guard let pendingBatch,
              let attempt = mutationMachine.retrySave() else { return }
        publishMutationPhase()
        await performCreate(pendingBatch, attempt: attempt)
    }

    public func retryFailedMutation() async {
        switch mutationMachine.phase {
        case .saveFailed:
            await retrySave()
        case .undoFailed:
            await retryUndo()
        case .idle, .saving, .saved, .undoing:
            return
        }
    }

    public func prepareForCreation() {
        guard mutationMachine.expireUndo() else { return }
        weightKilograms = nil
        waistCentimeters = nil
        customMetric = nil
        pendingBatch = nil
        validationIssue = nil
        publishMutationPhase()
    }

    public func undoLastSave() async {
        guard case let .saved(undoToken) = mutationMachine.phase,
              let attempt = mutationMachine.beginUndo(requestID: makeRequestID()) else {
            return
        }
        publishMutationPhase()
        do {
            try await repository.undoBodyMetricCreation(undoToken)
            guard mutationMachine.completeUndo(attempt) else { return }
            let ids = Set(undoToken.ids)
            snapshots.removeAll { ids.contains($0.id) }
            pendingBatch = nil
            publishMutationPhase()
        } catch {
            guard mutationMachine.failUndo(attempt) else { return }
            publishMutationPhase()
        }
    }

    public func retryUndo() async {
        guard case let .undoFailed(_, undoToken) = mutationMachine.phase,
              let attempt = mutationMachine.retryUndo() else { return }
        publishMutationPhase()
        do {
            try await repository.undoBodyMetricCreation(undoToken)
            guard mutationMachine.completeUndo(attempt) else { return }
            let ids = Set(undoToken.ids)
            snapshots.removeAll { ids.contains($0.id) }
            pendingBatch = nil
            publishMutationPhase()
        } catch {
            guard mutationMachine.failUndo(attempt) else { return }
            publishMutationPhase()
        }
    }

    public func update(
        _ snapshot: BodyMetricSnapshot,
        date: Date,
        value: BodyMetricValueInput
    ) async {
        editGeneration &+= 1
        let generation = editGeneration
        editPhase = .saving
        do {
            let updated = try await repository.updateBodyMetric(
                id: snapshot.id,
                expectedUpdatedAt: snapshot.updatedAt,
                date: date,
                value: value
            )
            guard generation == editGeneration else { return }
            replaceSnapshot(updated)
            editPhase = .saved
            await onCommittedEdit()
        } catch {
            guard generation == editGeneration else { return }
            editPhase = .failed
        }
    }

    public func delete(_ snapshot: BodyMetricSnapshot) async {
        editGeneration &+= 1
        let generation = editGeneration
        editPhase = .saving
        do {
            try await repository.deleteBodyMetric(
                id: snapshot.id,
                expectedUpdatedAt: snapshot.updatedAt
            )
            guard generation == editGeneration else { return }
            snapshots.removeAll { $0.id == snapshot.id }
            editPhase = .saved
            await onCommittedEdit()
        } catch {
            guard generation == editGeneration else { return }
            editPhase = .failed
        }
    }

    public func prepareForEditing() {
        editGeneration &+= 1
        editPhase = .idle
        validationIssue = nil
    }

    private func performCreate(
        _ batch: BodyMetricBatchInput,
        attempt: QuickEntryMutationAttempt
    ) async {
        do {
            let mutation = try await repository.createBodyMetrics(batch)
            guard mutationMachine.completeSave(
                attempt,
                undoToken: mutation.undoToken
            ) else { return }
            let createdIDs = Set(mutation.snapshots.map(\.id))
            snapshots = (snapshots.filter { !createdIDs.contains($0.id) }
                + mutation.snapshots)
                .sorted(by: BodyMetricOrdering.newestFirst)
            publishMutationPhase()
        } catch {
            guard mutationMachine.failSave(attempt) else { return }
            publishMutationPhase()
        }
    }

    private func replaceSnapshot(_ snapshot: BodyMetricSnapshot) {
        snapshots = (snapshots.filter { $0.id != snapshot.id } + [snapshot])
            .sorted(by: BodyMetricOrdering.newestFirst)
    }

    private func publishMutationPhase() {
        mutationPhase = mutationMachine.phase
    }

    private static func validationIssue(
        for error: BodyMetricInputError
    ) -> QuickEntryValidationIssue {
        let key: String
        let field: String?
        let message: String
        switch error {
        case .invalidValue(.weight):
            key = "metrics.validation.weight"
            field = "metrics.entry.weight"
            message = String(localized: "metrics.validation.weight", bundle: .module)
        case .invalidValue(.waist):
            key = "metrics.validation.waist"
            field = "metrics.entry.waist"
            message = String(localized: "metrics.validation.waist", bundle: .module)
        case .invalidValue(.custom), .missingCustomName, .missingCustomUnit,
             .unexpectedBatchMetricType:
            key = "metrics.validation.custom"
            field = "metrics.entry.custom.value"
            message = String(localized: "metrics.validation.custom", bundle: .module)
        case .emptyBatch:
            key = "metrics.validation.empty"
            field = nil
            message = String(localized: "metrics.validation.empty", bundle: .module)
        case .invalidCanonicalUnit, .unexpectedCustomName:
            key = "metrics.validation.invalid"
            field = nil
            message = String(localized: "metrics.validation.invalid", bundle: .module)
        }
        return QuickEntryValidationIssue(
            id: key,
            fieldIdentifier: field,
            localizedMessage: message,
            accessibilityAnnouncement: message
        )
    }
}
