import Foundation
@testable import SleepMoodKit
import XCTest

@MainActor
final class LifestyleViewModelTests: XCTestCase {
    private enum FixtureFailure: Error {
        case save
    }

    func testLoadPopulatesBothSectionsFromTheSameDaySnapshot() async throws {
        let loaded = daySnapshot(
            sleep: sleepSnapshot(durationHours: 7.5, quality: 8, note: "Uyku"),
            mood: moodSnapshot(score: 7, tags: ["Sakin", "Odak"], energy: 6, note: "Ruh")
        )
        let repository = LifestyleRepositoryStub(fetched: loaded)
        let viewModel = LifestyleViewModel(repository: repository)

        await viewModel.load(date: loaded.dayStart.addingTimeInterval(3_600))

        XCTAssertEqual(viewModel.loadPhase, .loaded)
        XCTAssertEqual(viewModel.day, loaded)
        XCTAssertEqual(viewModel.sleepDurationHours, 7.5)
        XCTAssertEqual(viewModel.sleepQuality, 8)
        XCTAssertEqual(viewModel.sleepNote, "Uyku")
        XCTAssertEqual(viewModel.moodScore, 7)
        XCTAssertEqual(viewModel.moodTagsText, "Sakin, Odak")
        XCTAssertEqual(viewModel.moodEnergy, 6)
        XCTAssertEqual(viewModel.moodNote, "Ruh")
    }

    func testFailedCombinedSavePreservesEveryInputAndRetryUsesIdenticalRequest() async throws {
        let empty = daySnapshot(sleep: nil, mood: nil)
        let saved = daySnapshot(
            sleep: sleepSnapshot(durationHours: 8, quality: 9, note: "Kesintisiz"),
            mood: moodSnapshot(score: 8, tags: ["Sakin", "Odak"], energy: 7, note: "İyi")
        )
        let repository = LifestyleRepositoryStub(
            fetched: empty,
            upsertResults: [.failure(FixtureFailure.save), .success(saved)]
        )
        let requestID = uuid("00000000-0000-4000-8000-000000000461")
        let viewModel = LifestyleViewModel(
            repository: repository,
            makeRequestID: { requestID }
        )
        let entryDate = empty.dayStart.addingTimeInterval(10_000)
        await viewModel.load(date: entryDate)
        viewModel.sleepDurationHours = 8
        viewModel.sleepQuality = 9
        viewModel.sleepNote = "  Kesintisiz  "
        viewModel.moodScore = 8
        viewModel.moodTagsText = " Sakin, Odak, sakin "
        viewModel.moodEnergy = 7
        viewModel.moodNote = "  İyi  "

        await viewModel.save(date: entryDate)

        XCTAssertEqual(viewModel.savePhase, .saveFailed(requestID: requestID))
        XCTAssertEqual(viewModel.sleepDurationHours, 8)
        XCTAssertEqual(viewModel.sleepQuality, 9)
        XCTAssertEqual(viewModel.sleepNote, "  Kesintisiz  ")
        XCTAssertEqual(viewModel.moodScore, 8)
        XCTAssertEqual(viewModel.moodTagsText, " Sakin, Odak, sakin ")
        XCTAssertEqual(viewModel.moodEnergy, 7)
        XCTAssertEqual(viewModel.moodNote, "  İyi  ")
        XCTAssertEqual(repository.upserts.count, 1)
        XCTAssertEqual(repository.upserts.first?.expected, empty)

        await viewModel.retrySave()

        XCTAssertEqual(repository.upserts.count, 2)
        XCTAssertEqual(repository.upserts[0], repository.upserts[1])
        XCTAssertEqual(repository.upserts[0].input.sleep?.note, "Kesintisiz")
        XCTAssertEqual(repository.upserts[0].input.mood?.tags, ["Sakin", "Odak"])
        XCTAssertEqual(repository.upserts[0].input.mood?.note, "İyi")
        XCTAssertEqual(viewModel.day, saved)
        XCTAssertEqual(viewModel.savePhase, .saved(requestID: requestID))
    }

    func testDuplicateSaveWhileInFlightCannotReplaceThePendingCombinedRetry() async throws {
        let empty = daySnapshot(sleep: nil, mood: nil)
        let saved = daySnapshot(
            sleep: sleepSnapshot(durationHours: 7, quality: 8, note: "İlk"),
            mood: nil
        )
        let repository = LifestyleRepositoryStub(
            fetched: empty,
            upsertResults: [.success(saved)],
            suspendsFirstUpsert: true
        )
        let viewModel = LifestyleViewModel(repository: repository)
        let originalDate = empty.dayStart.addingTimeInterval(2_000)
        await viewModel.load(date: originalDate)
        viewModel.sleepDurationHours = 7
        viewModel.sleepQuality = 8
        viewModel.sleepNote = "  İlk  "

        let originalSave = Task {
            await viewModel.save(date: originalDate)
        }
        for _ in 0..<20 {
            if repository.hasSuspendedUpsert { break }
            await Task.yield()
        }
        XCTAssertTrue(repository.hasSuspendedUpsert)

        viewModel.sleepDurationHours = 9
        viewModel.sleepQuality = 10
        viewModel.moodScore = 9
        await viewModel.save(date: originalDate.addingTimeInterval(60))

        XCTAssertEqual(repository.upserts.count, 1)
        repository.completeSuspendedUpsert(with: .failure(FixtureFailure.save))
        await originalSave.value
        await viewModel.retrySave()

        XCTAssertEqual(repository.upserts.count, 2)
        XCTAssertEqual(repository.upserts[0], repository.upserts[1])
        XCTAssertEqual(repository.upserts[1].input.date, originalDate)
        XCTAssertEqual(repository.upserts[1].input.sleep?.durationHours, 7)
        XCTAssertNil(repository.upserts[1].input.mood)
    }

    func testSaveCanSubmitOnlyOneNonEmptySectionAndRejectsAnEmptyForm() async throws {
        let empty = daySnapshot(sleep: nil, mood: nil)
        let sleepOnly = daySnapshot(
            sleep: sleepSnapshot(durationHours: 7, quality: 8, note: nil),
            mood: nil
        )
        let repository = LifestyleRepositoryStub(
            fetched: empty,
            upsertResults: [.success(sleepOnly)]
        )
        let viewModel = LifestyleViewModel(repository: repository)
        let entryDate = empty.dayStart.addingTimeInterval(1_000)
        await viewModel.load(date: entryDate)

        await viewModel.save(date: entryDate)
        XCTAssertEqual(viewModel.validationIssue?.id, "lifestyle.validation.empty")
        XCTAssertTrue(repository.upserts.isEmpty)

        viewModel.sleepDurationHours = 7
        viewModel.sleepQuality = 8
        await viewModel.save(date: entryDate)

        XCTAssertEqual(repository.upserts.count, 1)
        XCTAssertNotNil(repository.upserts.first?.input.sleep)
        XCTAssertNil(repository.upserts.first?.input.mood)
        XCTAssertNil(viewModel.validationIssue)
    }

    private func daySnapshot(
        sleep: SleepLogSnapshot?,
        mood: MoodLogSnapshot?
    ) -> LifestyleDaySnapshot {
        let dayStart = Date(timeIntervalSinceReferenceDate: 50_000)
        return LifestyleDaySnapshot(
            dayStart: dayStart,
            dayEnd: dayStart.addingTimeInterval(86_400),
            sleep: sleep,
            mood: mood
        )
    }

    private func sleepSnapshot(
        durationHours: Double,
        quality: Int,
        note: String?
    ) -> SleepLogSnapshot {
        let timestamp = Date(timeIntervalSinceReferenceDate: 50_000)
        return SleepLogSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000462"),
            createdAt: timestamp,
            updatedAt: timestamp,
            date: timestamp,
            durationHours: durationHours,
            quality: quality,
            note: note
        )
    }

    private func moodSnapshot(
        score: Int?,
        tags: [String],
        energy: Int?,
        note: String?
    ) -> MoodLogSnapshot {
        let timestamp = Date(timeIntervalSinceReferenceDate: 50_000)
        return MoodLogSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000463"),
            createdAt: timestamp,
            updatedAt: timestamp,
            date: timestamp,
            score: score,
            tags: tags,
            energy: energy,
            note: note
        )
    }

    private func uuid(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID: \(value)")
        }
        return id
    }
}

@MainActor
private final class LifestyleRepositoryStub: LifestyleRepository {
    struct Upsert: Equatable {
        let input: LifestyleDayInput
        let expected: LifestyleDaySnapshot
    }

    var fetched: LifestyleDaySnapshot
    var upsertResults: [Result<LifestyleDaySnapshot, Error>]
    private(set) var requestedDates: [Date] = []
    private(set) var upserts: [Upsert] = []
    private(set) var hasSuspendedUpsert = false
    private var suspendsFirstUpsert: Bool
    private var upsertContinuation: CheckedContinuation<LifestyleDaySnapshot, Error>?

    init(
        fetched: LifestyleDaySnapshot,
        upsertResults: [Result<LifestyleDaySnapshot, Error>] = [],
        suspendsFirstUpsert: Bool = false
    ) {
        self.fetched = fetched
        self.upsertResults = upsertResults
        self.suspendsFirstUpsert = suspendsFirstUpsert
    }

    func fetchLifestyleDay(containing date: Date) async throws -> LifestyleDaySnapshot {
        requestedDates.append(date)
        return fetched
    }

    func upsertLifestyleDay(
        _ input: LifestyleDayInput,
        expected: LifestyleDaySnapshot
    ) async throws -> LifestyleDaySnapshot {
        upserts.append(.init(input: input, expected: expected))
        if suspendsFirstUpsert {
            suspendsFirstUpsert = false
            return try await withCheckedThrowingContinuation { continuation in
                hasSuspendedUpsert = true
                upsertContinuation = continuation
            }
        }
        guard !upsertResults.isEmpty else {
            throw StubFailure.missingUpsertResult
        }
        let result = try upsertResults.removeFirst().get()
        fetched = result
        return result
    }

    func completeSuspendedUpsert(
        with result: Result<LifestyleDaySnapshot, Error>
    ) {
        guard let upsertContinuation else {
            preconditionFailure("No suspended lifestyle upsert to complete.")
        }
        self.upsertContinuation = nil
        upsertContinuation.resume(with: result)
    }

    private enum StubFailure: Error {
        case missingUpsertResult
    }
}
