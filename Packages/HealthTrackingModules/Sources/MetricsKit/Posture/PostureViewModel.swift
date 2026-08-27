import DesignSystem
import Foundation
import HealthSafetyKit
import Observation

public enum PostureLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

public enum PostureSavePhase: Equatable, Sendable {
    case idle
    case saving(requestID: UUID)
    case failed(requestID: UUID)
    case saved(id: UUID)
}

public enum PostureEditPhase: Equatable, Sendable {
    case idle
    case saving
    case saved
    case failed
}

@MainActor
@Observable
public final class PostureViewModel {
    public var wallTestPass: Bool?
    public var symptomScore: Int? {
        didSet { refreshSafetyPresentation() }
    }
    public var region = ""
    public var note = ""
    public private(set) var snapshots: [PostureMetricSnapshot] = []
    public private(set) var loadPhase: PostureLoadPhase = .idle
    public private(set) var savePhase: PostureSavePhase = .idle
    public private(set) var editPhase: PostureEditPhase = .idle
    public private(set) var validationIssue: QuickEntryValidationIssue?
    public private(set) var previousExplicitSymptomScore: Int?
    public private(set) var safetyPresentation = MedicalSafetyPresentation.resolve(
        triggers: []
    )

    @ObservationIgnored
    private let repository: any MetricsRepository
    @ObservationIgnored
    private let makeRequestID: @MainActor () -> UUID
    @ObservationIgnored
    private var pendingInput: PostureMetricInput?
    @ObservationIgnored
    private var loadGeneration: UInt64 = 0
    @ObservationIgnored
    private var editGeneration: UInt64 = 0

    public init(
        repository: any MetricsRepository,
        makeRequestID: @escaping @MainActor () -> UUID = { UUID() }
    ) {
        self.repository = repository
        self.makeRequestID = makeRequestID
    }

    public func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        loadPhase = .loading
        do {
            let loaded = try await repository.fetchPostureMetrics()
            guard generation == loadGeneration else { return }
            snapshots = loaded.sorted(by: PostureMetricOrdering.newestFirst)
            refreshPreviousExplicitScore()
            refreshSafetyPresentation()
            loadPhase = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            loadPhase = .failed
        }
    }

    public func save(date: Date) async {
        guard !isSaving else { return }
        let input: PostureMetricInput
        do {
            input = try PostureMetricInput(
                date: date,
                wallTestPass: wallTestPass,
                symptomScore: symptomScore,
                region: region,
                note: note
            )
        } catch let error as PostureMetricInputError {
            validationIssue = Self.validationIssue(for: error)
            return
        } catch {
            validationIssue = Self.validationIssue(for: .empty)
            return
        }

        validationIssue = nil
        let requestID = makeRequestID()
        pendingInput = input
        savePhase = .saving(requestID: requestID)
        await performCreate(input, requestID: requestID)
    }

    public func retrySave() async {
        guard case let .failed(requestID) = savePhase,
              let pendingInput else { return }
        savePhase = .saving(requestID: requestID)
        await performCreate(pendingInput, requestID: requestID)
    }

    public func update(
        _ snapshot: PostureMetricSnapshot,
        with input: PostureMetricInput
    ) async {
        editGeneration &+= 1
        let generation = editGeneration
        editPhase = .saving
        do {
            let updated = try await repository.updatePostureMetric(
                id: snapshot.id,
                expectedUpdatedAt: snapshot.updatedAt,
                input: input
            )
            guard generation == editGeneration else { return }
            replaceSnapshot(updated)
            refreshPreviousExplicitScore()
            refreshSafetyPresentation()
            editPhase = .saved
        } catch {
            guard generation == editGeneration else { return }
            editPhase = .failed
        }
    }

    public func delete(_ snapshot: PostureMetricSnapshot) async {
        editGeneration &+= 1
        let generation = editGeneration
        editPhase = .saving
        do {
            try await repository.deletePostureMetric(
                id: snapshot.id,
                expectedUpdatedAt: snapshot.updatedAt
            )
            guard generation == editGeneration else { return }
            snapshots.removeAll { $0.id == snapshot.id }
            refreshPreviousExplicitScore()
            refreshSafetyPresentation()
            editPhase = .saved
        } catch {
            guard generation == editGeneration else { return }
            editPhase = .failed
        }
    }

    public func refreshSafetyPresentation() {
        let trigger = PostureSymptomTrend.compare(
            current: symptomScore,
            previous: previousExplicitSymptomScore
        )?.safetyTrigger
        safetyPresentation = MedicalSafetyPresentation.resolve(
            triggers: Set(trigger.map { [$0] } ?? [])
        )
    }

    public func prepareForCreation() {
        guard !isSaving else { return }
        wallTestPass = nil
        symptomScore = nil
        region = ""
        note = ""
        pendingInput = nil
        validationIssue = nil
        savePhase = .idle
        refreshSafetyPresentation()
    }

    private var isSaving: Bool {
        if case .saving = savePhase { return true }
        return false
    }

    private func performCreate(
        _ input: PostureMetricInput,
        requestID: UUID
    ) async {
        do {
            let saved = try await repository.createPostureMetric(input)
            guard savePhase == .saving(requestID: requestID) else { return }
            replaceSnapshot(saved)
            savePhase = .saved(id: saved.id)
        } catch {
            guard savePhase == .saving(requestID: requestID) else { return }
            savePhase = .failed(requestID: requestID)
        }
    }

    private func replaceSnapshot(_ snapshot: PostureMetricSnapshot) {
        snapshots = (snapshots.filter { $0.id != snapshot.id } + [snapshot])
            .sorted(by: PostureMetricOrdering.newestFirst)
    }

    private func refreshPreviousExplicitScore() {
        previousExplicitSymptomScore = snapshots.lazy.compactMap(\.symptomScore).first
    }

    private static func validationIssue(
        for error: PostureMetricInputError
    ) -> QuickEntryValidationIssue {
        let key: String
        let field: String?
        switch error {
        case .empty:
            key = "posture.validation.empty"
            field = nil
        case .invalidSymptomScore:
            key = "posture.validation.symptom"
            field = "posture.entry.symptom"
        }
        let message = String(localized: String.LocalizationValue(key), bundle: .module)
        return QuickEntryValidationIssue(
            id: key,
            fieldIdentifier: field,
            localizedMessage: message,
            accessibilityAnnouncement: message
        )
    }
}
