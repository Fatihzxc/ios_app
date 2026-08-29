import Foundation

public enum ExportModuleV1: String, CaseIterable, Codable, Hashable, Sendable {
    case profileProgram = "profile_program"
    case training = "training"
    case nutrition = "nutrition"
    case metrics = "metrics"
    case lifestyle = "lifestyle"
    case health = "health"
    case photos = "photos"
    case system = "system"
}

public enum ExportRecordTypeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case userProfile = "user_profile"
    case program = "program"
    case programPhase = "program_phase"
    case programState = "program_state"
    case workoutDayTemplate = "workout_day_template"
    case exerciseTemplate = "exercise_template"
    case warmupItem = "warmup_item"
    case cooldownItem = "cooldown_item"
    case workoutSession = "workout_session"
    case setLog = "set_log"
    case workoutSessionProgress = "workout_session_progress"
    case food = "food"
    case recipe = "recipe"
    case dailyNutritionLog = "daily_nutrition_log"
    case mealEntry = "meal_entry"
    case bodyMetric = "body_metric"
    case postureMetric = "posture_metric"
    case sleepLog = "sleep_log"
    case moodLog = "mood_log"
    case healthCheckReminder = "health_check_reminder"
    case bloodworkResult = "bloodwork_result"
    case progressPhoto = "progress_photo"
    case appReminder = "app_reminder"
    case appSetting = "app_setting"

    public var module: ExportModuleV1 {
        switch self {
        case .userProfile, .program, .programPhase, .programState,
             .workoutDayTemplate, .exerciseTemplate, .warmupItem, .cooldownItem:
            .profileProgram
        case .workoutSession, .setLog, .workoutSessionProgress:
            .training
        case .food, .recipe, .dailyNutritionLog, .mealEntry:
            .nutrition
        case .bodyMetric, .postureMetric:
            .metrics
        case .sleepLog, .moodLog:
            .lifestyle
        case .healthCheckReminder, .bloodworkResult:
            .health
        case .progressPhoto:
            .photos
        case .appReminder, .appSetting:
            .system
        }
    }

    public var isConfiguration: Bool {
        switch self {
        case .userProfile, .program, .programPhase, .programState,
             .workoutDayTemplate, .exerciseTemplate, .warmupItem, .cooldownItem,
             .food, .recipe, .appReminder, .appSetting:
            true
        case .workoutSession, .setLog, .workoutSessionProgress, .dailyNutritionLog,
             .mealEntry, .bodyMetric, .postureMetric, .sleepLog, .moodLog,
             .healthCheckReminder, .bloodworkResult, .progressPhoto:
            false
        }
    }
}

public enum ExportColumnTypeV1: String, Codable, Equatable, Sendable {
    case text
    case integer
    case decimal
    case boolean
    case timestamp
    case uuid
}

public enum ExportCellV1: Equatable, Sendable {
    case null
    case text(String)
    case integer(Int64)
    case decimal(Double)
    case boolean(Bool)
    case timestamp(Date)
    case uuid(UUID)

    public var type: ExportColumnTypeV1? {
        switch self {
        case .null: nil
        case .text: .text
        case .integer: .integer
        case .decimal: .decimal
        case .boolean: .boolean
        case .timestamp: .timestamp
        case .uuid: .uuid
        }
    }
}

public enum ExportConfigScopeV1: String, Codable, Equatable, Sendable {
    case selected
    case referenced
}

public struct ExportColumnV1: Equatable, Sendable {
    public let name: String
    public let type: ExportColumnTypeV1
    public let isNullable: Bool

    public init(name: String, type: ExportColumnTypeV1, isNullable: Bool) throws {
        guard Self.isSnakeCase(name) else {
            throw ExportSchemaV1Error.invalidColumnName(name)
        }
        self.name = name
        self.type = type
        self.isNullable = isNullable
    }

    fileprivate init(schemaName: String, type: ExportColumnTypeV1, isNullable: Bool) {
        precondition(Self.isSnakeCase(schemaName))
        name = schemaName
        self.type = type
        self.isNullable = isNullable
    }

    private static func isSnakeCase(_ value: String) -> Bool {
        guard let first = value.utf8.first, (97...122).contains(first) else { return false }
        return value.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || $0 == 95
        }
    }
}

public struct ExportNamedCellV1: Equatable, Sendable {
    public let columnName: String
    public let value: ExportCellV1

    public init(columnName: String, value: ExportCellV1) {
        self.columnName = columnName
        self.value = value
    }
}

public struct ExportRowV1: Equatable, Sendable {
    public let primaryTimestamp: Date
    public let cells: [ExportNamedCellV1]

    public init(primaryTimestamp: Date, cells: [ExportNamedCellV1]) throws {
        var names = Set<String>()
        for cell in cells where !names.insert(cell.columnName).inserted {
            throw ExportSchemaV1Error.duplicateCell(cell.columnName)
        }
        guard primaryTimestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw ExportSchemaV1Error.invalidPrimaryTimestamp
        }
        self.primaryTimestamp = primaryTimestamp
        self.cells = cells
    }
}

public struct ExportTableV1: Equatable, Sendable {
    public let module: ExportModuleV1
    public let columns: [ExportColumnV1]
    public let rows: [ExportRowV1]

    public init(
        module: ExportModuleV1,
        columns: [ExportColumnV1],
        rows: [ExportRowV1]
    ) throws {
        var columnNames = Set<String>()
        for column in columns where !columnNames.insert(column.name).inserted {
            throw ExportSchemaV1Error.duplicateColumn(column.name)
        }
        let requiredLeading: [(String, ExportColumnTypeV1)] = [
            ("record_type", .text),
            ("id", .uuid),
            ("created_at", .timestamp),
            ("updated_at", .timestamp),
        ]
        guard columns.count >= requiredLeading.count,
              zip(columns.prefix(4), requiredLeading).allSatisfy({ column, required in
                  column.name == required.0 && column.type == required.1 && !column.isNullable
              }) else {
            throw ExportSchemaV1Error.invalidLeadingColumns
        }

        let columnByName = Dictionary(uniqueKeysWithValues: columns.map { ($0.name, $0) })
        for row in rows {
            guard row.cells.count == columns.count else {
                throw ExportSchemaV1Error.rowWidthMismatch(
                    expected: columns.count,
                    actual: row.cells.count
                )
            }
            for cell in row.cells where columnByName[cell.columnName] == nil {
                throw ExportSchemaV1Error.unknownCell(cell.columnName)
            }
            for (index, cell) in row.cells.enumerated() {
                let column = columns[index]
                guard cell.columnName == column.name else {
                    throw ExportSchemaV1Error.cellOrderMismatch(
                        expected: column.name,
                        actual: cell.columnName
                    )
                }
                if case .null = cell.value {
                    guard column.isNullable else {
                        throw ExportSchemaV1Error.nullInRequiredColumn(column.name)
                    }
                } else if cell.value.type != column.type {
                    throw ExportSchemaV1Error.cellTypeMismatch(
                        column: column.name,
                        expected: column.type,
                        actual: cell.value.type!
                    )
                }
            }
        }

        if columns == ExportSchemaV1.columns(for: module) {
            for row in rows {
                guard case let .text(rawRecordType) = row.cells[0].value,
                      let recordType = ExportRecordTypeV1(rawValue: rawRecordType) else {
                    throw ExportSchemaV1Error.unknownRecordType
                }
                guard recordType.module == module else {
                    throw ExportSchemaV1Error.recordTypeModuleMismatch(recordType, module)
                }
                let definition = ExportSchemaV1.definition(for: recordType)
                guard let primaryTimestampCell = row.cells.first(where: {
                    $0.columnName == definition.primaryTimestampColumn
                }),
                    case let .timestamp(canonicalPrimaryTimestamp) = primaryTimestampCell.value,
                    canonicalPrimaryTimestamp == row.primaryTimestamp else {
                    throw ExportSchemaV1Error.primaryTimestampMismatch(
                        recordType: recordType,
                        column: definition.primaryTimestampColumn
                    )
                }
                let ownedFields = Dictionary(
                    uniqueKeysWithValues: definition.fields.map { ($0.name, $0) }
                )
                for cell in row.cells.dropFirst(4) {
                    if let owned = ownedFields[cell.columnName] {
                        if case .null = cell.value, !owned.isNullable {
                            throw ExportSchemaV1Error.nullInRequiredColumn(cell.columnName)
                        }
                    } else if case .null = cell.value {
                        continue
                    } else {
                        throw ExportSchemaV1Error.nonNullSparseCell(
                            recordType: recordType,
                            column: cell.columnName
                        )
                    }
                }
            }
        }

        self.module = module
        self.columns = columns
        self.rows = rows.sorted(by: Self.rowOrderedBefore)
    }

    private static func rowOrderedBefore(_ lhs: ExportRowV1, _ rhs: ExportRowV1) -> Bool {
        let lhsRecordType = textCell("record_type", in: lhs) ?? ""
        let rhsRecordType = textCell("record_type", in: rhs) ?? ""
        if lhsRecordType != rhsRecordType { return lhsRecordType < rhsRecordType }
        if lhs.primaryTimestamp != rhs.primaryTimestamp {
            return lhs.primaryTimestamp < rhs.primaryTimestamp
        }
        let lhsID = uuidCell("id", in: lhs)?.uuidString.lowercased() ?? ""
        let rhsID = uuidCell("id", in: rhs)?.uuidString.lowercased() ?? ""
        if lhsID != rhsID { return lhsID < rhsID }
        return stableTieBreak(lhs) < stableTieBreak(rhs)
    }

    private static func textCell(_ name: String, in row: ExportRowV1) -> String? {
        guard case let .text(value)? = row.cells.first(where: { $0.columnName == name })?.value else {
            return nil
        }
        return value
    }

    private static func uuidCell(_ name: String, in row: ExportRowV1) -> UUID? {
        guard case let .uuid(value)? = row.cells.first(where: { $0.columnName == name })?.value else {
            return nil
        }
        return value
    }

    private static func stableTieBreak(_ row: ExportRowV1) -> String {
        row.cells.map { cell in
            let value: String
            switch cell.value {
            case .null:
                value = "n"
            case let .text(text):
                value = "s\(text.utf8.count):\(text)"
            case let .integer(integer):
                value = "i\(integer)"
            case let .decimal(decimal):
                value = "d\(String(decimal))"
            case let .boolean(boolean):
                value = boolean ? "b1" : "b0"
            case let .timestamp(timestamp):
                value = "t\(timestamp.timeIntervalSinceReferenceDate.bitPattern)"
            case let .uuid(uuid):
                value = "u\(uuid.uuidString.lowercased())"
            }
            return "\(cell.columnName.utf8.count):\(cell.columnName)=\(value)"
        }.joined(separator: "|")
    }
}

public struct ExportRecordDefinitionV1: Equatable, Sendable {
    public let recordType: ExportRecordTypeV1
    public let module: ExportModuleV1
    public let primaryTimestampColumn: String
    public let fields: [ExportColumnV1]

    fileprivate init(
        _ recordType: ExportRecordTypeV1,
        primaryTimestampColumn: String,
        fields: [ExportColumnV1]
    ) {
        self.recordType = recordType
        module = recordType.module
        self.primaryTimestampColumn = primaryTimestampColumn
        self.fields = [ExportSchemaV1.configScopeColumn] + fields
    }
}

public enum ExportSchemaV1Error: Error, Equatable, Sendable {
    case invalidColumnName(String)
    case duplicateColumn(String)
    case duplicateCell(String)
    case unknownCell(String)
    case rowWidthMismatch(expected: Int, actual: Int)
    case cellOrderMismatch(expected: String, actual: String)
    case cellTypeMismatch(
        column: String,
        expected: ExportColumnTypeV1,
        actual: ExportColumnTypeV1
    )
    case nullInRequiredColumn(String)
    case invalidLeadingColumns
    case invalidPrimaryTimestamp
    case unknownRecordType
    case recordTypeModuleMismatch(ExportRecordTypeV1, ExportModuleV1)
    case primaryTimestampMismatch(recordType: ExportRecordTypeV1, column: String)
    case nonNullSparseCell(recordType: ExportRecordTypeV1, column: String)
    case duplicateTable(ExportModuleV1)
    case unexpectedTableSchema(ExportModuleV1)
    case missingSelectedModule(ExportModuleV1)
    case unselectedTableContainsNonReferencedRows(ExportModuleV1)
    case invalidInterval
}

public enum ExportSchemaV1 {
    fileprivate static let configScopeColumn = column("config_scope", .text, true)
    private static let leadingColumns = [
        column("record_type", .text, false),
        column("id", .uuid, false),
        column("created_at", .timestamp, false),
        column("updated_at", .timestamp, false),
    ]

    public static let records: [ExportRecordDefinitionV1] = [
        definition(.userProfile, "user_profile_program_start_date", [
            field(.userProfile, "display_name", .text),
            field(.userProfile, "height_cm", .decimal),
            field(.userProfile, "start_weight_kg", .decimal),
            field(.userProfile, "target_weight_kg", .decimal),
            field(.userProfile, "birth_year", .integer, true),
            field(.userProfile, "units_system", .text),
            field(.userProfile, "protein_target_g", .decimal),
            field(.userProfile, "calorie_target", .decimal, true),
            field(.userProfile, "carb_target_g", .decimal, true),
            field(.userProfile, "fat_target_g", .decimal, true),
            field(.userProfile, "program_start_date", .timestamp),
            field(.userProfile, "weekly_workout_target", .integer),
        ]),
        definition(.program, "created_at", [
            field(.program, "name", .text),
            field(.program, "description_text", .text),
            field(.program, "is_active", .boolean),
        ]),
        definition(.programPhase, "created_at", [
            field(.programPhase, "name", .text),
            field(.programPhase, "order_index", .integer),
            field(.programPhase, "month_start", .integer),
            field(.programPhase, "month_end", .integer),
            field(.programPhase, "training_focus", .text),
            field(.programPhase, "nutrition_focus", .text),
            field(.programPhase, "milestone", .text),
            field(.programPhase, "entry_criteria", .text),
            field(.programPhase, "program_id", .uuid, true),
        ]),
        definition(.programState, "program_state_phase_started_at", [
            field(.programState, "program_id", .uuid),
            field(.programState, "current_phase_id", .uuid),
            field(.programState, "phase_started_at", .timestamp),
            field(.programState, "training_week_index", .integer),
            field(.programState, "deload_status", .text),
            field(.programState, "deload_reason", .text, true),
            field(.programState, "deload_updated_at", .timestamp, true),
            field(.programState, "last_deload_skipped_at", .timestamp, true),
            field(.programState, "last_deload_action", .text, true),
        ]),
        definition(.workoutDayTemplate, "created_at", [
            field(.workoutDayTemplate, "name", .text),
            field(.workoutDayTemplate, "order_index", .integer),
            field(.workoutDayTemplate, "focus", .text),
            field(.workoutDayTemplate, "program_id", .uuid, true),
        ]),
        definition(.exerciseTemplate, "created_at", [
            field(.exerciseTemplate, "name", .text),
            field(.exerciseTemplate, "order_index", .integer),
            field(.exerciseTemplate, "target_sets", .integer),
            field(.exerciseTemplate, "rep_low", .integer, true),
            field(.exerciseTemplate, "rep_high", .integer, true),
            field(.exerciseTemplate, "rir_low", .integer),
            field(.exerciseTemplate, "rir_high", .integer),
            field(.exerciseTemplate, "category", .text),
            field(.exerciseTemplate, "allow_failure", .boolean),
            field(.exerciseTemplate, "cues", .text),
            field(.exerciseTemplate, "safety_note", .text, true),
            field(.exerciseTemplate, "starting_weight_kg", .decimal, true),
            field(.exerciseTemplate, "progression_rule", .text),
            field(.exerciseTemplate, "measurement_kind", .text),
            field(.exerciseTemplate, "superset_group_id", .uuid, true),
            field(.exerciseTemplate, "superset_order", .integer, true),
            field(.exerciseTemplate, "workout_day_template_id", .uuid, true),
        ]),
        definition(.warmupItem, "created_at", [
            field(.warmupItem, "phase", .text),
            field(.warmupItem, "movement", .text),
            field(.warmupItem, "dose", .text),
            field(.warmupItem, "order_index", .integer),
            field(.warmupItem, "workout_day_template_id", .uuid, true),
        ]),
        definition(.cooldownItem, "created_at", [
            field(.cooldownItem, "movement", .text),
            field(.cooldownItem, "dose", .text),
            field(.cooldownItem, "note", .text, true),
            field(.cooldownItem, "order_index", .integer),
            field(.cooldownItem, "workout_day_template_id", .uuid, true),
        ]),
        definition(.workoutSession, "workout_session_date", [
            field(.workoutSession, "date", .timestamp),
            field(.workoutSession, "status", .text),
            field(.workoutSession, "workout_day_template_id", .uuid),
            field(.workoutSession, "perceived_recovery", .integer, true),
            field(.workoutSession, "note", .text, true),
            field(.workoutSession, "ohp_symptom_response", .text),
            field(.workoutSession, "ohp_symptom_checked_at", .timestamp, true),
        ]),
        definition(.setLog, "set_log_completed_at", [
            field(.setLog, "exercise_template_id", .uuid),
            field(.setLog, "set_index", .integer),
            field(.setLog, "weight_kg", .decimal, true),
            field(.setLog, "reps", .integer, true),
            field(.setLog, "duration_sec", .integer, true),
            field(.setLog, "distance_steps", .integer, true),
            field(.setLog, "performed_variant", .text, true),
            field(.setLog, "rir", .integer, true),
            field(.setLog, "is_warmup_set", .boolean),
            field(.setLog, "completed_at", .timestamp),
            field(.setLog, "workout_session_id", .uuid, true),
        ]),
        definition(.workoutSessionProgress, "updated_at", [
            field(.workoutSessionProgress, "workout_session_id", .uuid),
            field(.workoutSessionProgress, "stage", .text),
            field(.workoutSessionProgress, "current_exercise_template_id", .uuid, true),
            field(.workoutSessionProgress, "completed_warmup_item_ids_json", .text),
            field(.workoutSessionProgress, "completed_cooldown_item_ids_json", .text),
            field(.workoutSessionProgress, "warmup_disposition", .text),
            field(.workoutSessionProgress, "cooldown_disposition", .text),
        ]),
        definition(.food, "created_at", [
            field(.food, "name", .text), field(.food, "brand", .text, true),
            field(.food, "serving_size", .decimal), field(.food, "serving_unit", .text),
            field(.food, "calories_per_serving", .decimal), field(.food, "protein_g", .decimal),
            field(.food, "carb_g", .decimal), field(.food, "fat_g", .decimal),
            field(.food, "fiber_g", .decimal, true), field(.food, "source", .text),
        ]),
        definition(.recipe, "created_at", [
            field(.recipe, "name", .text), field(.recipe, "category", .text),
            field(.recipe, "category_custom_name", .text, true),
            field(.recipe, "servings", .decimal), field(.recipe, "is_direct_macros", .boolean),
            field(.recipe, "calories_total", .decimal), field(.recipe, "protein_total_g", .decimal),
            field(.recipe, "carb_total_g", .decimal), field(.recipe, "fat_total_g", .decimal),
            field(.recipe, "note", .text, true),
        ]),
        definition(.dailyNutritionLog, "daily_nutrition_log_date", [
            field(.dailyNutritionLog, "date", .timestamp),
        ]),
        definition(.mealEntry, "meal_entry_logged_at", [
            field(.mealEntry, "category", .text),
            field(.mealEntry, "category_custom_name", .text, true),
            field(.mealEntry, "recipe_id", .uuid, true), field(.mealEntry, "food_id", .uuid, true),
            field(.mealEntry, "adhoc_name", .text, true), field(.mealEntry, "quantity", .decimal),
            field(.mealEntry, "calories_resolved", .decimal),
            field(.mealEntry, "protein_resolved", .decimal),
            field(.mealEntry, "carb_resolved", .decimal), field(.mealEntry, "fat_resolved", .decimal),
            field(.mealEntry, "logged_at", .timestamp),
            field(.mealEntry, "daily_nutrition_log_id", .uuid, true),
        ]),
        definition(.bodyMetric, "body_metric_date", [
            field(.bodyMetric, "date", .timestamp), field(.bodyMetric, "type", .text),
            field(.bodyMetric, "custom_name", .text, true), field(.bodyMetric, "value", .decimal),
            field(.bodyMetric, "unit", .text),
        ]),
        definition(.postureMetric, "posture_metric_date", [
            field(.postureMetric, "date", .timestamp),
            field(.postureMetric, "wall_test_pass", .boolean, true),
            field(.postureMetric, "symptom_score", .integer, true),
            field(.postureMetric, "region", .text, true), field(.postureMetric, "note", .text, true),
        ]),
        definition(.sleepLog, "sleep_log_date", [
            field(.sleepLog, "date", .timestamp), field(.sleepLog, "duration_hours", .decimal),
            field(.sleepLog, "quality", .integer), field(.sleepLog, "note", .text, true),
        ]),
        definition(.moodLog, "mood_log_date", [
            field(.moodLog, "date", .timestamp), field(.moodLog, "mood_score", .integer, true),
            field(.moodLog, "mood_tags_json", .text), field(.moodLog, "energy", .integer, true),
            field(.moodLog, "note", .text, true),
        ]),
        definition(.healthCheckReminder, "health_check_reminder_due_date", [
            field(.healthCheckReminder, "name", .text),
            field(.healthCheckReminder, "due_date", .timestamp),
            field(.healthCheckReminder, "recurrence", .text),
            field(.healthCheckReminder, "status", .text),
        ]),
        definition(.bloodworkResult, "bloodwork_result_date", [
            field(.bloodworkResult, "date", .timestamp), field(.bloodworkResult, "marker", .text),
            field(.bloodworkResult, "value", .decimal), field(.bloodworkResult, "unit", .text),
            field(.bloodworkResult, "note", .text, true),
        ]),
        definition(.progressPhoto, "progress_photo_date", [
            field(.progressPhoto, "date", .timestamp),
            field(.progressPhoto, "image_available", .boolean),
            field(.progressPhoto, "pose", .text), field(.progressPhoto, "note", .text, true),
        ]),
        definition(.appReminder, "created_at", [
            field(.appReminder, "type", .text), field(.appReminder, "schedule", .text),
            field(.appReminder, "message", .text), field(.appReminder, "is_enabled", .boolean),
        ]),
        definition(.appSetting, "created_at", [
            field(.appSetting, "key", .text), field(.appSetting, "value", .text),
        ]),
    ]

    public static func columns(for module: ExportModuleV1) -> [ExportColumnV1] {
        var result = leadingColumns
        var names = Set(result.map(\.name))
        for definition in records where definition.module == module {
            for field in definition.fields where names.insert(field.name).inserted {
                result.append(ExportColumnV1(
                    schemaName: field.name,
                    type: field.type,
                    isNullable: true
                ))
            }
        }
        return result
    }

    public static func definition(
        for recordType: ExportRecordTypeV1
    ) -> ExportRecordDefinitionV1 {
        records.first { $0.recordType == recordType }!
    }

    private static func definition(
        _ recordType: ExportRecordTypeV1,
        _ primaryTimestampColumn: String,
        _ fields: [ExportColumnV1]
    ) -> ExportRecordDefinitionV1 {
        ExportRecordDefinitionV1(
            recordType,
            primaryTimestampColumn: primaryTimestampColumn,
            fields: fields
        )
    }

    private static func field(
        _ recordType: ExportRecordTypeV1,
        _ name: String,
        _ type: ExportColumnTypeV1,
        _ nullable: Bool = false
    ) -> ExportColumnV1 {
        column("\(recordType.rawValue)_\(name)", type, nullable)
    }

    private static func column(
        _ name: String,
        _ type: ExportColumnTypeV1,
        _ nullable: Bool
    ) -> ExportColumnV1 {
        ExportColumnV1(schemaName: name, type: type, isNullable: nullable)
    }
}
