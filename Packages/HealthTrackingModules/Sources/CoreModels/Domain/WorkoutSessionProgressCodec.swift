import Foundation

public enum WorkoutSessionProgressCodecError: Error, Equatable, Sendable {
    case malformedPayload
    case unsupportedSchemaVersion(Int)
    case duplicateIdentifier(UUID)
}

public enum WorkoutSessionProgressCodec {
    public static let schemaVersion = 1
    public static let emptyPayload = Data(#"{"ids":[],"schemaVersion":1}"#.utf8)

    public static func encode(_ identifiers: Set<UUID>) throws -> Data {
        let envelope = Envelope(
            ids: identifiers.map { $0.uuidString.lowercased() }.sorted(),
            schemaVersion: schemaVersion
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(envelope)
        } catch {
            throw WorkoutSessionProgressCodecError.malformedPayload
        }
    }

    public static func decode(_ data: Data) throws -> Set<UUID> {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw WorkoutSessionProgressCodecError.malformedPayload
        }

        guard envelope.schemaVersion == schemaVersion else {
            throw WorkoutSessionProgressCodecError.unsupportedSchemaVersion(
                envelope.schemaVersion
            )
        }

        var identifiers: Set<UUID> = []
        for encodedIdentifier in envelope.ids {
            guard let identifier = UUID(uuidString: encodedIdentifier) else {
                throw WorkoutSessionProgressCodecError.malformedPayload
            }
            guard identifiers.insert(identifier).inserted else {
                throw WorkoutSessionProgressCodecError.duplicateIdentifier(identifier)
            }
        }
        return identifiers
    }
}

private struct Envelope: Codable {
    let ids: [String]
    let schemaVersion: Int
}
