import Foundation

public enum RecipeArchiveCodecError: Error, Equatable, Sendable {
    case malformedPayload
    case unexpectedKeys
    case unsupportedSchemaVersion(Int)
    case invalidRecipeID(String)
    case duplicateRecipeID(UUID)
    case nonCanonicalRecipeIDOrder
    case encodingFailed
}

public enum RecipeArchiveCodec {
    public static let settingKey = "nutrition.recipe.archive"
    private static let schemaVersion = 1

    private struct Envelope: Codable {
        let recipeIDs: [String]
        let schemaVersion: Int
    }

    public static func encode(_ recipeIDs: Set<UUID>) throws -> String {
        let envelope = Envelope(
            recipeIDs: recipeIDs.map(\.uuidString).sorted(),
            schemaVersion: schemaVersion
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(envelope)
            guard let result = String(data: data, encoding: .utf8) else {
                throw RecipeArchiveCodecError.encodingFailed
            }
            return result
        } catch let error as RecipeArchiveCodecError {
            throw error
        } catch {
            throw RecipeArchiveCodecError.encodingFailed
        }
    }

    public static func decode(_ json: String) throws -> Set<UUID> {
        guard let data = json.data(using: .utf8) else {
            throw RecipeArchiveCodecError.malformedPayload
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw RecipeArchiveCodecError.malformedPayload
        }
        guard let dictionary = object as? [String: Any] else {
            throw RecipeArchiveCodecError.malformedPayload
        }
        guard Set(dictionary.keys) == Set(["recipeIDs", "schemaVersion"]) else {
            throw RecipeArchiveCodecError.unexpectedKeys
        }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw RecipeArchiveCodecError.malformedPayload
        }
        guard envelope.schemaVersion == schemaVersion else {
            throw RecipeArchiveCodecError.unsupportedSchemaVersion(
                envelope.schemaVersion
            )
        }

        var result = Set<UUID>()
        for rawID in envelope.recipeIDs {
            guard let id = UUID(uuidString: rawID), rawID == id.uuidString else {
                throw RecipeArchiveCodecError.invalidRecipeID(rawID)
            }
            guard result.insert(id).inserted else {
                throw RecipeArchiveCodecError.duplicateRecipeID(id)
            }
        }
        guard envelope.recipeIDs == envelope.recipeIDs.sorted() else {
            throw RecipeArchiveCodecError.nonCanonicalRecipeIDOrder
        }
        return result
    }
}
