import DesignSystem
import Foundation
import Observation

public enum LifestyleLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
}

public enum LifestyleSavePhase: Equatable, Sendable {
    case idle
    case saving(requestID: UUID)
    case saved(requestID: UUID)
    case saveFailed(requestID: UUID)
}

@MainActor
@Observable
public final class LifestyleViewModel {
    public var sleepDurationHours: Double?
    public var sleepQuality: Int?
    public var sleepNote = ""
    public var moodScore: Int?
    public var moodTagsText = ""
    public var moodEnergy: Int?
    public var moodNote = ""

    public private(set) var day: LifestyleDaySnapshot?
    public private(set) var loadPhase: LifestyleLoadPhase = .idle
    public private(set) var savePhase: LifestyleSavePhase = .idle
    public private(set) var validationIssue: QuickEntryValidationIssue?

    @ObservationIgnored
    private let repository: any LifestyleRepository
    @ObservationIgnored
    private let makeRequestID: @MainActor () -> UUID
    @ObservationIgnored
    private var mutationMachine = QuickEntryMutationStateMachine<UUID>()
    @ObservationIgnored
    private var pendingSave: PendingSave?
    @ObservationIgnored
    private var loadGeneration: UInt64 = 0

    private struct PendingSave: Equatable, Sendable {
        let input: LifestyleDayInput
        let expected: LifestyleDaySnapshot
    }

    public init(
        repository: any LifestyleRepository,
        makeRequestID: @escaping @MainActor () -> UUID = { UUID() }
    ) {
        self.repository = repository
        self.makeRequestID = makeRequestID
    }

    public func load(date: Date) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        loadPhase = .loading
        do {
            let loaded = try await repository.fetchLifestyleDay(containing: date)
            guard generation == loadGeneration else { return }
            day = loaded
            apply(loaded)
            loadPhase = .loaded
        } catch {
            guard generation == loadGeneration else { return }
            loadPhase = .failed
        }
    }

    public func save(date: Date) async {
        let input: LifestyleDayInput
        do {
            input = try makeInput(date: date)
        } catch let error as LifestyleInputError {
            validationIssue = Self.validationIssue(for: error)
            return
        } catch {
            validationIssue = Self.validationIssue(for: .emptyDay)
            return
        }

        guard let expected = day else {
            validationIssue = Self.loadValidationIssue()
            return
        }
        validationIssue = nil
        guard let attempt = mutationMachine.beginSave(requestID: makeRequestID()) else {
            return
        }
        pendingSave = PendingSave(input: input, expected: expected)
        publishSavePhase()
        await performSave(input: input, expected: expected, attempt: attempt)
    }

    public func retrySave() async {
        guard let pendingSave,
              let attempt = mutationMachine.retrySave() else { return }
        publishSavePhase()
        await performSave(
            input: pendingSave.input,
            expected: pendingSave.expected,
            attempt: attempt
        )
    }

    public func prepareForEntry() {
        if mutationMachine.expireUndo() {
            pendingSave = nil
            publishSavePhase()
        }
        validationIssue = nil
    }

    private func performSave(
        input: LifestyleDayInput,
        expected: LifestyleDaySnapshot,
        attempt: QuickEntryMutationAttempt
    ) async {
        do {
            let saved = try await repository.upsertLifestyleDay(
                input,
                expected: expected
            )
            guard mutationMachine.completeSave(
                attempt,
                undoToken: attempt.requestID
            ) else { return }
            day = saved
            apply(saved)
            pendingSave = nil
            publishSavePhase()
        } catch {
            guard mutationMachine.failSave(attempt) else { return }
            publishSavePhase()
        }
    }

    private func makeInput(date: Date) throws -> LifestyleDayInput {
        let hasSleepInput = sleepDurationHours != nil
            || sleepQuality != nil
            || !sleepNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let sleep: SleepEntryInput?
        if hasSleepInput {
            guard let sleepDurationHours else {
                throw LifestyleInputError.invalidSleepDuration
            }
            guard let sleepQuality else {
                throw LifestyleInputError.invalidSleepQuality
            }
            sleep = try SleepEntryInput(
                durationHours: sleepDurationHours,
                quality: sleepQuality,
                note: sleepNote
            )
        } else {
            sleep = nil
        }

        let rawTags = moodTagsText.components(separatedBy: ",")
        let hasMoodInput = moodScore != nil
            || moodEnergy != nil
            || rawTags.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            || !moodNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let mood: MoodEntryInput?
        if hasMoodInput {
            mood = try MoodEntryInput(
                score: moodScore,
                tags: rawTags,
                energy: moodEnergy,
                note: moodNote
            )
        } else {
            mood = nil
        }

        return try LifestyleDayInput(date: date, sleep: sleep, mood: mood)
    }

    private func apply(_ snapshot: LifestyleDaySnapshot) {
        sleepDurationHours = snapshot.sleep?.durationHours
        sleepQuality = snapshot.sleep?.quality
        sleepNote = snapshot.sleep?.note ?? ""
        moodScore = snapshot.mood?.score
        moodTagsText = snapshot.mood?.tags.joined(separator: ", ") ?? ""
        moodEnergy = snapshot.mood?.energy
        moodNote = snapshot.mood?.note ?? ""
    }

    private func publishSavePhase() {
        switch mutationMachine.phase {
        case .idle:
            savePhase = .idle
        case let .saving(attempt):
            savePhase = .saving(requestID: attempt.requestID)
        case let .saved(requestID):
            savePhase = .saved(requestID: requestID)
        case let .saveFailed(requestID):
            savePhase = .saveFailed(requestID: requestID)
        case .undoing, .undoFailed:
            savePhase = .idle
        }
    }

    private static func validationIssue(
        for error: LifestyleInputError
    ) -> QuickEntryValidationIssue {
        let key: String
        let field: String?
        switch error {
        case .invalidSleepDuration:
            key = "lifestyle.validation.sleep.duration"
            field = "lifestyle.sleep.duration"
        case .invalidSleepQuality:
            key = "lifestyle.validation.sleep.quality"
            field = "lifestyle.sleep.quality"
        case .missingMoodSignal:
            key = "lifestyle.validation.mood.signal"
            field = "lifestyle.mood.score"
        case .invalidMoodScore:
            key = "lifestyle.validation.mood.score"
            field = "lifestyle.mood.score"
        case .invalidMoodEnergy:
            key = "lifestyle.validation.mood.energy"
            field = "lifestyle.mood.energy"
        case .emptyDay:
            key = "lifestyle.validation.empty"
            field = nil
        }
        let message = String(localized: String.LocalizationValue(key), bundle: .module)
        return QuickEntryValidationIssue(
            id: key,
            fieldIdentifier: field,
            localizedMessage: message,
            accessibilityAnnouncement: message
        )
    }

    private static func loadValidationIssue() -> QuickEntryValidationIssue {
        let key = "lifestyle.validation.load"
        let message = String(localized: String.LocalizationValue(key), bundle: .module)
        return QuickEntryValidationIssue(
            id: key,
            fieldIdentifier: nil,
            localizedMessage: message,
            accessibilityAnnouncement: message
        )
    }
}
