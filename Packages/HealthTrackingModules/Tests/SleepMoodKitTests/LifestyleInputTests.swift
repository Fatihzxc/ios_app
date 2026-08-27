import Foundation
@testable import SleepMoodKit
import XCTest

final class LifestyleInputTests: XCTestCase {
    func testSleepRequiresFiniteDurationWithinDayAndQualityOneThroughTen() throws {
        let input = try SleepEntryInput(
            durationHours: 7.5,
            quality: 8,
            note: "  Kesintisiz  "
        )
        XCTAssertEqual(input.durationHours, 7.5)
        XCTAssertEqual(input.quality, 8)
        XCTAssertEqual(input.note, "Kesintisiz")

        let invalidDurations: [Double] = [0, -1, 24.01, .nan, .infinity]
        for duration in invalidDurations {
            XCTAssertThrowsError(
                try SleepEntryInput(durationHours: duration, quality: 8, note: nil)
            ) {
                XCTAssertEqual($0 as? LifestyleInputError, .invalidSleepDuration)
            }
        }
        for quality in [0, 11] {
            XCTAssertThrowsError(
                try SleepEntryInput(durationHours: 7, quality: quality, note: nil)
            ) {
                XCTAssertEqual($0 as? LifestyleInputError, .invalidSleepQuality)
            }
        }
        let boundary = try SleepEntryInput(durationHours: 24, quality: 1, note: " \n ")
        XCTAssertNil(boundary.note)
    }

    func testMoodRequiresScoreOrNormalizedTagAndValidOptionalEnergy() throws {
        let input = try MoodEntryInput(
            score: nil,
            tags: ["  Sakin ", "odak", "sakin", " ODAK ", "\n"],
            energy: 7,
            note: "  İyi bir gün  "
        )
        XCTAssertNil(input.score)
        XCTAssertEqual(input.tags, ["Sakin", "odak"])
        XCTAssertEqual(input.energy, 7)
        XCTAssertEqual(input.note, "İyi bir gün")
        let blankNote = try MoodEntryInput(
            score: 5,
            tags: [],
            energy: nil,
            note: " \n "
        )
        XCTAssertNil(blankNote.note)

        let turkishCasePairs = try MoodEntryInput(
            score: nil,
            tags: ["  İyi ", "iyi", " IŞIK ", "ışık"],
            energy: nil,
            note: nil
        )
        XCTAssertEqual(turkishCasePairs.tags, ["İyi", "IŞIK"])

        XCTAssertThrowsError(
            try MoodEntryInput(score: nil, tags: ["  "], energy: 5, note: nil)
        ) {
            XCTAssertEqual($0 as? LifestyleInputError, .missingMoodSignal)
        }
        for score in [0, 11] {
            XCTAssertThrowsError(
                try MoodEntryInput(score: score, tags: [], energy: nil, note: nil)
            ) {
                XCTAssertEqual($0 as? LifestyleInputError, .invalidMoodScore)
            }
        }
        for energy in [0, 11] {
            XCTAssertThrowsError(
                try MoodEntryInput(score: 5, tags: [], energy: energy, note: nil)
            ) {
                XCTAssertEqual($0 as? LifestyleInputError, .invalidMoodEnergy)
            }
        }
    }

    func testDayInputRequiresAtLeastOneSectionAndPreservesEntryDate() throws {
        let date = Date(timeIntervalSinceReferenceDate: 10_000)
        let sleep = try SleepEntryInput(durationHours: 8, quality: 9, note: nil)
        let mood = try MoodEntryInput(score: 8, tags: ["Dengeli"], energy: 7, note: nil)

        let combined = try LifestyleDayInput(date: date, sleep: sleep, mood: mood)
        XCTAssertEqual(combined.date, date)
        XCTAssertEqual(combined.sleep, sleep)
        XCTAssertEqual(combined.mood, mood)

        XCTAssertThrowsError(try LifestyleDayInput(date: date, sleep: nil, mood: nil)) {
            XCTAssertEqual($0 as? LifestyleInputError, .emptyDay)
        }
    }

    func testSnapshotsAreImmutableEquatableSendableValues() {
        let timestamp = Date(timeIntervalSinceReferenceDate: 11_000)
        let sleep = SleepLogSnapshot(
            id: UUID(),
            createdAt: timestamp,
            updatedAt: timestamp,
            date: timestamp,
            durationHours: 7,
            quality: 8,
            note: nil
        )
        let mood = MoodLogSnapshot(
            id: UUID(),
            createdAt: timestamp,
            updatedAt: timestamp,
            date: timestamp,
            score: 7,
            tags: ["Sakin"],
            energy: 6,
            note: nil
        )
        let day = LifestyleDaySnapshot(
            dayStart: timestamp,
            dayEnd: timestamp.addingTimeInterval(60),
            sleep: sleep,
            mood: mood
        )

        assertEquatableSendable(day)
        XCTAssertEqual(day.sleep, sleep)
        XCTAssertEqual(day.mood, mood)
    }

    private func assertEquatableSendable<T: Equatable & Sendable>(_ value: T) {
        XCTAssertEqual(value, value)
    }
}
