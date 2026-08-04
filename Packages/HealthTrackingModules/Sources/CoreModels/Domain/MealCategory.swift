import Foundation

public struct MealCategory: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case breakfast
        case lunch
        case dinner
        case snack
        case custom
    }

    public let kind: Kind
    public let customName: String?

    public static let defaultValue = MealCategory(uncheckedKind: .breakfast, customName: nil)

    private init(uncheckedKind kind: Kind, customName: String?) {
        self.kind = kind
        self.customName = customName
    }

    public init(kind: Kind, customName: String? = nil) throws {
        switch kind {
        case .custom:
            guard let customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MealCategoryValidationError.customNameRequired
            }
        case .breakfast, .lunch, .dinner, .snack:
            guard customName == nil else {
                throw MealCategoryValidationError.customNameNotAllowed
            }
        }

        self.kind = kind
        self.customName = customName
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case customName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(Kind.self, forKey: .kind),
            customName: container.decodeIfPresent(String.self, forKey: .customName)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(customName, forKey: .customName)
    }
}

private enum MealCategoryValidationError: Error {
    case customNameRequired
    case customNameNotAllowed
}
