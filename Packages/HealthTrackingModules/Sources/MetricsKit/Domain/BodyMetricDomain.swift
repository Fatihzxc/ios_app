import CoreModels
import Foundation

public enum BodyMetricInputError: Error, Equatable, Sendable {
    case invalidValue(type: BodyMetricType)
    case invalidCanonicalUnit(type: BodyMetricType, expected: String)
    case unexpectedCustomName(type: BodyMetricType)
    case missingCustomName
    case missingCustomUnit
    case emptyBatch
    case unexpectedBatchMetricType(BodyMetricType)
}

public struct BodyMetricValueInput: Equatable, Sendable {
    public let type: BodyMetricType
    public let customName: String?
    public let value: Double
    public let unit: String

    public init(
        type: BodyMetricType,
        customName: String?,
        value: Double,
        unit: String
    ) throws {
        guard value.isFinite, value > 0 else {
            throw BodyMetricInputError.invalidValue(type: type)
        }

        switch type {
        case .weight:
            guard customName == nil else {
                throw BodyMetricInputError.unexpectedCustomName(type: type)
            }
            guard unit == "kg" else {
                throw BodyMetricInputError.invalidCanonicalUnit(
                    type: type,
                    expected: "kg"
                )
            }
            self.customName = nil
            self.unit = "kg"
        case .waist:
            guard customName == nil else {
                throw BodyMetricInputError.unexpectedCustomName(type: type)
            }
            guard unit == "cm" else {
                throw BodyMetricInputError.invalidCanonicalUnit(
                    type: type,
                    expected: "cm"
                )
            }
            self.customName = nil
            self.unit = "cm"
        case .custom:
            let normalizedName = customName?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let normalizedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedName.isEmpty else {
                throw BodyMetricInputError.missingCustomName
            }
            guard !normalizedUnit.isEmpty else {
                throw BodyMetricInputError.missingCustomUnit
            }
            self.customName = normalizedName
            self.unit = normalizedUnit
        }

        self.type = type
        self.value = value
    }

    public static func weight(kilograms: Double) throws -> Self {
        try Self(type: .weight, customName: nil, value: kilograms, unit: "kg")
    }

    public static func waist(centimeters: Double) throws -> Self {
        try Self(type: .waist, customName: nil, value: centimeters, unit: "cm")
    }

    public static func custom(
        name: String,
        value: Double,
        unit: String
    ) throws -> Self {
        try Self(type: .custom, customName: name, value: value, unit: unit)
    }
}

public struct BodyMetricBatchInput: Equatable, Sendable {
    public let date: Date
    public let values: [BodyMetricValueInput]

    public init(
        date: Date,
        weightKilograms: Double?,
        waistCentimeters: Double?,
        customMetrics: [BodyMetricValueInput]
    ) throws {
        var values: [BodyMetricValueInput] = []
        if let weightKilograms {
            values.append(try .weight(kilograms: weightKilograms))
        }
        if let waistCentimeters {
            values.append(try .waist(centimeters: waistCentimeters))
        }
        for metric in customMetrics {
            guard metric.type == .custom else {
                throw BodyMetricInputError.unexpectedBatchMetricType(metric.type)
            }
            values.append(metric)
        }
        guard !values.isEmpty else {
            throw BodyMetricInputError.emptyBatch
        }

        self.date = date
        self.values = values
    }
}

public struct BodyMetricSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let updatedAt: Date
    public let date: Date
    public let type: BodyMetricType
    public let customName: String?
    public let value: Double
    public let unit: String

    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        date: Date,
        type: BodyMetricType,
        customName: String?,
        value: Double,
        unit: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.date = date
        self.type = type
        self.customName = customName
        self.value = value
        self.unit = unit
    }
}

public enum BodyMetricOrdering {
    public static func newestFirst(
        _ lhs: BodyMetricSnapshot,
        _ rhs: BodyMetricSnapshot
    ) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public enum BodyMetricUnitConverter {
    private static let poundsPerKilogram = 2.204_622_621_848_775_7
    private static let centimetersPerInch = 2.54

    public static func pounds(fromKilograms value: Double) -> Double {
        value * poundsPerKilogram
    }

    public static func kilograms(fromPounds value: Double) -> Double {
        value / poundsPerKilogram
    }

    public static func inches(fromCentimeters value: Double) -> Double {
        value / centimetersPerInch
    }

    public static func centimeters(fromInches value: Double) -> Double {
        value * centimetersPerInch
    }
}

public struct BodyMetricCreationUndoToken: Equatable, Sendable {
    public let ids: [UUID]

    public init(ids: [UUID]) {
        self.ids = ids
    }
}

public struct BodyMetricCreationMutation: Equatable, Sendable {
    public let snapshots: [BodyMetricSnapshot]
    public let undoToken: BodyMetricCreationUndoToken

    public init(
        snapshots: [BodyMetricSnapshot],
        undoToken: BodyMetricCreationUndoToken
    ) {
        self.snapshots = snapshots
        self.undoToken = undoToken
    }
}
