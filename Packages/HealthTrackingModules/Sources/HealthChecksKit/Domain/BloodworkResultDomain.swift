import Foundation

public enum BloodworkResultInputError: Error, Equatable, Sendable {
    case missingMarker
    case nonFiniteValue
    case missingUnit
}

public struct BloodworkResultInput: Equatable, Sendable {
    public let date: Date
    public let marker: String
    public let value: Double
    public let unit: String
    public let note: String?

    public init(
        date: Date,
        marker: String,
        value: Double,
        unit: String,
        note: String? = nil
    ) throws {
        let trimmedMarker = marker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMarker.isEmpty else {
            throw BloodworkResultInputError.missingMarker
        }
        guard value.isFinite else {
            throw BloodworkResultInputError.nonFiniteValue
        }
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUnit.isEmpty else {
            throw BloodworkResultInputError.missingUnit
        }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.date = date
        self.marker = trimmedMarker
        self.value = value
        self.unit = trimmedUnit
        self.note = trimmedNote?.isEmpty == false ? trimmedNote : nil
    }
}

public struct BloodworkResultSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let date: Date
    public let marker: String
    public let value: Double
    public let unit: String
    public let note: String?

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        date: Date,
        marker: String,
        value: Double,
        unit: String,
        note: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.marker = marker
        self.value = value
        self.unit = unit
        self.note = note
    }
}

public enum BloodworkResultOrdering {
    public static func newestFirst(
        _ lhs: BloodworkResultSnapshot,
        _ rhs: BloodworkResultSnapshot
    ) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
    }
}

public struct BloodworkCreationUndoToken: Equatable, Sendable {
    public let id: UUID
    public let expectedUpdatedAt: Date

    public init(id: UUID, expectedUpdatedAt: Date) {
        self.id = id
        self.expectedUpdatedAt = expectedUpdatedAt
    }
}

public struct BloodworkCreationMutation: Equatable, Sendable {
    public let snapshot: BloodworkResultSnapshot
    public let undoToken: BloodworkCreationUndoToken

    public init(
        snapshot: BloodworkResultSnapshot,
        undoToken: BloodworkCreationUndoToken
    ) {
        self.snapshot = snapshot
        self.undoToken = undoToken
    }
}
