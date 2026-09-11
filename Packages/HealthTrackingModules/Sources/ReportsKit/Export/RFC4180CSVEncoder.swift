import Foundation

public enum RFC4180CSVEncodingError: Error, Equatable, Sendable {
    case nonFiniteDecimal
    case invalidTimestamp
    case invalidUTF8
}

public enum CSVFormulaTextCodecV1 {
    public static func neutralize(_ value: String) -> String {
        guard let first = value.unicodeScalars.first else { return value }
        if first.value == 0x27 { return "'" + value }
        if isFormulaScalar(first) { return "'" + value }
        return value
    }

    public static func restore(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard scalars.first?.value == 0x27 else { return value }
        let remainderIndex = scalars.index(after: scalars.startIndex)
        let remainder = String(scalars[remainderIndex...])
        if remainder.unicodeScalars.first?.value == 0x27 { return remainder }
        if let protected = remainder.unicodeScalars.first, isFormulaScalar(protected) {
            return remainder
        }
        return value
    }

    private static func isFormulaScalar(_ first: Unicode.Scalar) -> Bool {
        [0x3D, 0x2B, 0x2D, 0x40, 0x09, 0x0D].contains(first.value)
    }
}

public enum CanonicalExportScalarV1 {
    public static func timestamp(_ value: Date) throws -> String {
        guard value.timeIntervalSinceReferenceDate.isFinite else {
            throw RFC4180CSVEncodingError.invalidTimestamp
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        return formatter.string(from: value)
    }

    public static func decimal(_ value: Double) throws -> String {
        guard value.isFinite else {
            throw RFC4180CSVEncodingError.nonFiniteDecimal
        }
        return String(value)
    }
}

public struct RFC4180CSVEncoder: Sendable {
    public init() {}

    public func encode(_ table: ExportTableV1) throws -> Data {
        try validateCompleteTable(table)
        let recordSeparator = "\r\n"
        var records = [table.columns.map { escape($0.name) }.joined(separator: ",")]
        records.reserveCapacity(table.rows.count + 1)
        for row in table.rows {
            records.append(try row.cells.map { try encode($0.value) }.joined(separator: ","))
        }
        let output = records.joined(separator: recordSeparator) + recordSeparator
        return Data(output.utf8)
    }

    private func validateCompleteTable(_ table: ExportTableV1) throws {
        for row in table.rows {
            for namedCell in row.cells {
                switch namedCell.value {
                case let .decimal(value):
                    guard value.isFinite else {
                        throw RFC4180CSVEncodingError.nonFiniteDecimal
                    }
                case let .timestamp(value):
                    guard value.timeIntervalSinceReferenceDate.isFinite else {
                        throw RFC4180CSVEncodingError.invalidTimestamp
                    }
                case .null, .text, .integer, .boolean, .uuid:
                    break
                }
            }
        }
    }

    private func encode(_ cell: ExportCellV1) throws -> String {
        switch cell {
        case .null:
            return ""
        case let .text(value):
            let neutralized = CSVFormulaTextCodecV1.neutralize(value)
            return escape(neutralized, forceQuote: value.isEmpty)
        case let .integer(value):
            return String(value)
        case let .decimal(value):
            return try CanonicalExportScalarV1.decimal(value)
        case let .boolean(value):
            return value ? "true" : "false"
        case let .timestamp(value):
            return try CanonicalExportScalarV1.timestamp(value)
        case let .uuid(value):
            return value.uuidString.lowercased()
        }
    }

    private func escape(_ value: String, forceQuote: Bool = false) -> String {
        let requiresQuote = forceQuote || value.contains(",") || value.contains("\"")
            || value.contains("\r") || value.contains("\n")
        guard requiresQuote else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
