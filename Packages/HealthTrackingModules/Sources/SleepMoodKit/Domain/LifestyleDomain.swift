import Foundation

public enum LifestyleInputError: Error, Equatable, Sendable {
    case invalidSleepDuration
    case invalidSleepQuality
    case missingMoodSignal
    case invalidMoodScore
    case invalidMoodEnergy
    case emptyDay
}

public struct SleepEntryInput: Equatable, Sendable {
    public let durationHours: Double
    public let quality: Int
    public let note: String?

    public init(
        durationHours: Double,
        quality: Int,
        note: String?
    ) throws {
        guard durationHours.isFinite,
              durationHours > 0,
              durationHours <= 24 else {
            throw LifestyleInputError.invalidSleepDuration
        }
        guard (1...10).contains(quality) else {
            throw LifestyleInputError.invalidSleepQuality
        }

        self.durationHours = durationHours
        self.quality = quality
        self.note = Self.normalizedOptionalText(note)
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }
}

public struct MoodEntryInput: Equatable, Sendable {
    public let score: Int?
    public let tags: [String]
    public let energy: Int?
    public let note: String?

    public init(
        score: Int?,
        tags: [String],
        energy: Int?,
        note: String?
    ) throws {
        if let score, !(1...10).contains(score) {
            throw LifestyleInputError.invalidMoodScore
        }
        if let energy, !(1...10).contains(energy) {
            throw LifestyleInputError.invalidMoodEnergy
        }

        let normalizedTags = Self.normalizedTags(tags)
        guard score != nil || !normalizedTags.isEmpty else {
            throw LifestyleInputError.missingMoodSignal
        }

        self.score = score
        self.tags = normalizedTags
        self.energy = energy
        self.note = Self.normalizedOptionalText(note)
    }

    private static func normalizedTags(_ values: [String]) -> [String] {
        let locale = Locale(identifier: "tr_TR")
        var seen = Set<String>()
        var normalized: [String] = []
        normalized.reserveCapacity(values.count)

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let comparisonKey = trimmed.lowercased(with: locale)
            guard seen.insert(comparisonKey).inserted else { continue }
            normalized.append(trimmed)
        }
        return normalized
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }
}

public struct LifestyleDayInput: Equatable, Sendable {
    public let date: Date
    public let sleep: SleepEntryInput?
    public let mood: MoodEntryInput?

    public init(
        date: Date,
        sleep: SleepEntryInput?,
        mood: MoodEntryInput?
    ) throws {
        guard sleep != nil || mood != nil else {
            throw LifestyleInputError.emptyDay
        }
        self.date = date
        self.sleep = sleep
        self.mood = mood
    }
}

public struct SleepLogSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let date: Date
    public let durationHours: Double
    public let quality: Int
    public let note: String?

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        date: Date,
        durationHours: Double,
        quality: Int,
        note: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.durationHours = durationHours
        self.quality = quality
        self.note = note
    }
}

public struct MoodLogSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let date: Date
    public let score: Int?
    public let tags: [String]
    public let energy: Int?
    public let note: String?

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        date: Date,
        score: Int?,
        tags: [String],
        energy: Int?,
        note: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.score = score
        self.tags = tags
        self.energy = energy
        self.note = note
    }
}

public struct LifestyleDaySnapshot: Equatable, Sendable {
    public let dayStart: Date
    public let dayEnd: Date
    public let sleep: SleepLogSnapshot?
    public let mood: MoodLogSnapshot?

    public init(
        dayStart: Date,
        dayEnd: Date,
        sleep: SleepLogSnapshot?,
        mood: MoodLogSnapshot?
    ) {
        self.dayStart = dayStart
        self.dayEnd = dayEnd
        self.sleep = sleep
        self.mood = mood
    }
}
