import Foundation

public struct PhaseTransitionRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let programID: UUID
    public let fromPhaseID: UUID
    public let toPhaseID: UUID
    public let fromStartedAt: Date
    public let transitionedAt: Date

    public init(
        id: UUID,
        programID: UUID,
        fromPhaseID: UUID,
        toPhaseID: UUID,
        fromStartedAt: Date,
        transitionedAt: Date
    ) {
        self.id = id
        self.programID = programID
        self.fromPhaseID = fromPhaseID
        self.toPhaseID = toPhaseID
        self.fromStartedAt = fromStartedAt
        self.transitionedAt = transitionedAt
    }
}

public enum PhaseTransitionLedgerError: Error, Equatable, Sendable {
    case malformedPayload
    case unsupportedSchemaVersion(Int)
    case duplicateRecordID(UUID)
    case duplicateLogicalTransition(recordIDs: [UUID])
    case duplicateTransitionTimestamp(transitionedAt: Date, recordIDs: [UUID])
    case invalidRecord(id: UUID)
    case crossProgramRecord(recordID: UUID, expectedProgramID: UUID, actualProgramID: UUID)
    case brokenTransitionChain(previousRecordID: UUID, recordID: UUID)
}

public struct PhaseTransitionLedgerV1: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var records: [PhaseTransitionRecord]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        records: [PhaseTransitionRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    public static func key(for programID: UUID) -> String {
        "phase-transition-ledger.v1." + programID.uuidString.lowercased()
    }

    public static func decode(
        _ value: String,
        for programID: UUID
    ) throws -> PhaseTransitionLedgerV1 {
        let data = Data(value.utf8)
        let version: Int
        do {
            version = try JSONDecoder().decode(SchemaProbe.self, from: data).schemaVersion
        } catch {
            throw PhaseTransitionLedgerError.malformedPayload
        }
        guard version == currentSchemaVersion else {
            throw PhaseTransitionLedgerError.unsupportedSchemaVersion(version)
        }
        do {
            let decoded = try JSONDecoder().decode(Self.self, from: data)
            return try decoded.validated(for: programID)
        } catch let error as PhaseTransitionLedgerError {
            throw error
        } catch {
            throw PhaseTransitionLedgerError.malformedPayload
        }
    }

    public func encoded(for programID: UUID) throws -> String {
        let canonical = try validated(for: programID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return String(decoding: try encoder.encode(canonical), as: UTF8.self)
        } catch {
            throw PhaseTransitionLedgerError.malformedPayload
        }
    }

    public func validated(for programID: UUID) throws -> PhaseTransitionLedgerV1 {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PhaseTransitionLedgerError.unsupportedSchemaVersion(schemaVersion)
        }
        let ordered = records.sorted(by: Self.recordOrderedBefore)

        let ids = Dictionary(grouping: ordered, by: \.id)
        if let duplicate = ids
            .filter({ $0.value.count > 1 })
            .sorted(by: { Self.uuidOrderedBefore($0.key, $1.key) })
            .first {
            throw PhaseTransitionLedgerError.duplicateRecordID(duplicate.key)
        }

        let logical = Dictionary(grouping: ordered, by: LogicalTransitionKey.init)
        if let duplicate = logical
            .filter({ $0.value.count > 1 })
            .sorted(by: { Self.logicalKeyOrderedBefore($0.key, $1.key) })
            .first {
            throw PhaseTransitionLedgerError.duplicateLogicalTransition(
                recordIDs: duplicate.value.map(\.id).sorted(by: Self.uuidOrderedBefore)
            )
        }

        let timestamps = Dictionary(grouping: ordered, by: \.transitionedAt)
        if let duplicate = timestamps
            .filter({ $0.value.count > 1 })
            .sorted(by: { $0.key < $1.key })
            .first {
            throw PhaseTransitionLedgerError.duplicateTransitionTimestamp(
                transitionedAt: duplicate.key,
                recordIDs: duplicate.value.map(\.id).sorted(by: Self.uuidOrderedBefore)
            )
        }

        if let foreign = ordered
            .filter({ $0.programID != programID })
            .min(by: { Self.uuidOrderedBefore($0.id, $1.id) }) {
            throw PhaseTransitionLedgerError.crossProgramRecord(
                recordID: foreign.id,
                expectedProgramID: programID,
                actualProgramID: foreign.programID
            )
        }
        if let invalid = ordered
            .filter({
                !Self.validDate($0.fromStartedAt)
                    || !Self.validDate($0.transitionedAt)
                    || $0.fromStartedAt >= $0.transitionedAt
                    || $0.fromPhaseID == $0.toPhaseID
            })
            .min(by: { Self.uuidOrderedBefore($0.id, $1.id) }) {
            throw PhaseTransitionLedgerError.invalidRecord(id: invalid.id)
        }

        for index in ordered.indices.dropFirst() {
            let previous = ordered[index - 1]
            let record = ordered[index]
            guard record.fromPhaseID == previous.toPhaseID,
                  record.fromStartedAt == previous.transitionedAt else {
                throw PhaseTransitionLedgerError.brokenTransitionChain(
                    previousRecordID: previous.id,
                    recordID: record.id
                )
            }
        }
        return PhaseTransitionLedgerV1(schemaVersion: schemaVersion, records: ordered)
    }

    private static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    private static func recordOrderedBefore(
        _ lhs: PhaseTransitionRecord,
        _ rhs: PhaseTransitionRecord
    ) -> Bool {
        if lhs.transitionedAt != rhs.transitionedAt {
            return lhs.transitionedAt < rhs.transitionedAt
        }
        return uuidOrderedBefore(lhs.id, rhs.id)
    }

    private static func uuidOrderedBefore(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }

    private static func logicalKeyOrderedBefore(
        _ lhs: LogicalTransitionKey,
        _ rhs: LogicalTransitionKey
    ) -> Bool {
        if lhs.programID != rhs.programID {
            return uuidOrderedBefore(lhs.programID, rhs.programID)
        }
        if lhs.transitionedAt != rhs.transitionedAt { return lhs.transitionedAt < rhs.transitionedAt }
        if lhs.fromStartedAt != rhs.fromStartedAt { return lhs.fromStartedAt < rhs.fromStartedAt }
        if lhs.fromPhaseID != rhs.fromPhaseID {
            return uuidOrderedBefore(lhs.fromPhaseID, rhs.fromPhaseID)
        }
        return uuidOrderedBefore(lhs.toPhaseID, rhs.toPhaseID)
    }
}

private struct SchemaProbe: Decodable {
    let schemaVersion: Int
}

private struct LogicalTransitionKey: Hashable {
    let programID: UUID
    let fromPhaseID: UUID
    let toPhaseID: UUID
    let fromStartedAt: Date
    let transitionedAt: Date

    init(_ record: PhaseTransitionRecord) {
        programID = record.programID
        fromPhaseID = record.fromPhaseID
        toPhaseID = record.toPhaseID
        fromStartedAt = record.fromStartedAt
        transitionedAt = record.transitionedAt
    }
}
