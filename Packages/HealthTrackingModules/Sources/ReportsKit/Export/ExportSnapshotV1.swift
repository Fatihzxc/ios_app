import Foundation

public struct ExportSnapshotV1: Equatable, Sendable {
    public let schemaVersion: Int
    public let interval: ReportDateInterval
    public let selectedModules: [ExportModuleV1]
    public let tables: [ExportTableV1]

    public init(
        interval: ReportDateInterval,
        selectedModules: Set<ExportModuleV1>,
        tables: [ExportTableV1]
    ) throws {
        guard interval.start < interval.endExclusive,
              interval.start.timeIntervalSinceReferenceDate.isFinite,
              interval.endExclusive.timeIntervalSinceReferenceDate.isFinite else {
            throw ExportSchemaV1Error.invalidInterval
        }

        let moduleOrder = Dictionary(
            uniqueKeysWithValues: ExportModuleV1.allCases.enumerated().map { index, module in
                (module, index)
            }
        )
        let orderedSelection = selectedModules.sorted {
            moduleOrder[$0, default: .max] < moduleOrder[$1, default: .max]
        }
        var tablesByModule: [ExportModuleV1: ExportTableV1] = [:]
        for table in tables {
            guard tablesByModule.updateValue(table, forKey: table.module) == nil else {
                throw ExportSchemaV1Error.duplicateTable(table.module)
            }
            guard table.columns == ExportSchemaV1.columns(for: table.module) else {
                throw ExportSchemaV1Error.unexpectedTableSchema(table.module)
            }
        }
        for module in orderedSelection where tablesByModule[module] == nil {
            throw ExportSchemaV1Error.missingSelectedModule(module)
        }

        for table in tables {
            let isSelected = selectedModules.contains(table.module)
            if !isSelected && table.rows.isEmpty {
                throw ExportSchemaV1Error.unselectedTableContainsNonReferencedRows(table.module)
            }
            for row in table.rows {
                guard case let .text(rawType) = row.cells[0].value,
                      let recordType = ExportRecordTypeV1(rawValue: rawType),
                      recordType.module == table.module else {
                    throw ExportSchemaV1Error.unknownRecordType
                }
                let configScope = row.cells.first { $0.columnName == "config_scope" }?.value
                if recordType.isConfiguration {
                    let expectedScope: ExportCellV1 = .text(
                        isSelected
                            ? ExportConfigScopeV1.selected.rawValue
                            : ExportConfigScopeV1.referenced.rawValue
                    )
                    guard configScope == expectedScope else {
                        throw ExportSchemaV1Error.unselectedTableContainsNonReferencedRows(
                            table.module
                        )
                    }
                } else {
                    guard isSelected, configScope == .null else {
                        throw ExportSchemaV1Error.unselectedTableContainsNonReferencedRows(
                            table.module
                        )
                    }
                }
            }
        }

        self.schemaVersion = 1
        self.interval = interval
        self.selectedModules = orderedSelection
        self.tables = tables.sorted {
            moduleOrder[$0.module, default: .max] < moduleOrder[$1.module, default: .max]
        }
    }
}

public protocol ReportsExportRepository: Sendable {
    @MainActor
    func fetchExportSnapshot(
        in interval: ReportDateInterval,
        modules: Set<ExportModuleV1>
    ) async throws -> ExportSnapshotV1
}
