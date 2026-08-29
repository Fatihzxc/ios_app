import Foundation
@testable import ReportsKit
import XCTest

final class ExportSchemaInventoryTests: XCTestCase {
    func testInventoryEnumeratesExactlyTwentyFourRecordsInFixedModuleOrder() {
        let expected: [(ExportModuleV1, [String])] = [
            (.profileProgram, [
                "user_profile", "program", "program_phase", "program_state",
                "workout_day_template", "exercise_template", "warmup_item", "cooldown_item",
            ]),
            (.training, ["workout_session", "set_log", "workout_session_progress"]),
            (.nutrition, ["food", "recipe", "daily_nutrition_log", "meal_entry"]),
            (.metrics, ["body_metric", "posture_metric"]),
            (.lifestyle, ["sleep_log", "mood_log"]),
            (.health, ["health_check_reminder", "bloodwork_result"]),
            (.photos, ["progress_photo"]),
            (.system, ["app_reminder", "app_setting"]),
        ]

        XCTAssertEqual(ExportModuleV1.allCases, expected.map(\.0))
        XCTAssertEqual(
            ExportSchemaV1.records.map(\.recordType.rawValue),
            expected.flatMap(\.1)
        )
        XCTAssertEqual(ExportSchemaV1.records.count, 24)
        for (module, recordTypes) in expected {
            XCTAssertEqual(
                ExportSchemaV1.records.filter { $0.module == module }.map(\.recordType.rawValue),
                recordTypes
            )
        }
    }

    func testEveryModuleUsesOneFixedTypedUnionWithCanonicalLeadingColumns() throws {
        let expectedLeading = ["record_type", "id", "created_at", "updated_at"]
        let snakeCase = try NSRegularExpression(pattern: "^[a-z][a-z0-9_]*$")

        for module in ExportModuleV1.allCases {
            let columns = ExportSchemaV1.columns(for: module)
            XCTAssertEqual(Array(columns.prefix(4).map(\.name)), expectedLeading)
            XCTAssertEqual(Set(columns.map(\.name)).count, columns.count)
            XCTAssertTrue(columns.contains {
                $0.name == "config_scope" && $0.type == .text && $0.isNullable
            })
            for column in columns {
                let range = NSRange(column.name.startIndex..., in: column.name)
                XCTAssertNotNil(snakeCase.firstMatch(in: column.name, range: range), column.name)
            }

            for record in ExportSchemaV1.records where record.module == module {
                XCTAssertEqual(record.fields.first?.name, "config_scope")
                XCTAssertTrue(Set(record.fields.map(\.name)).isSubset(of: Set(columns.map(\.name))))
                XCTAssertFalse(record.primaryTimestampColumn.isEmpty)
            }
        }
    }

    func testEveryRecordDeclaresExactPersistentProjectionAndDocumentedPrivacyTransform() {
        let expected: [ExportRecordTypeV1: String] = [
            .userProfile: "config_scope:text? user_profile_display_name:text! user_profile_height_cm:decimal! user_profile_start_weight_kg:decimal! user_profile_target_weight_kg:decimal! user_profile_birth_year:integer? user_profile_units_system:text! user_profile_protein_target_g:decimal! user_profile_calorie_target:decimal? user_profile_carb_target_g:decimal? user_profile_fat_target_g:decimal? user_profile_program_start_date:timestamp! user_profile_weekly_workout_target:integer!",
            .program: "config_scope:text? program_name:text! program_description_text:text! program_is_active:boolean!",
            .programPhase: "config_scope:text? program_phase_name:text! program_phase_order_index:integer! program_phase_month_start:integer! program_phase_month_end:integer! program_phase_training_focus:text! program_phase_nutrition_focus:text! program_phase_milestone:text! program_phase_entry_criteria:text! program_phase_program_id:uuid?",
            .programState: "config_scope:text? program_state_program_id:uuid! program_state_current_phase_id:uuid! program_state_phase_started_at:timestamp! program_state_training_week_index:integer! program_state_deload_status:text! program_state_deload_reason:text? program_state_deload_updated_at:timestamp? program_state_last_deload_skipped_at:timestamp? program_state_last_deload_action:text?",
            .workoutDayTemplate: "config_scope:text? workout_day_template_name:text! workout_day_template_order_index:integer! workout_day_template_focus:text! workout_day_template_program_id:uuid?",
            .exerciseTemplate: "config_scope:text? exercise_template_name:text! exercise_template_order_index:integer! exercise_template_target_sets:integer! exercise_template_rep_low:integer? exercise_template_rep_high:integer? exercise_template_rir_low:integer! exercise_template_rir_high:integer! exercise_template_category:text! exercise_template_allow_failure:boolean! exercise_template_cues:text! exercise_template_safety_note:text? exercise_template_starting_weight_kg:decimal? exercise_template_progression_rule:text! exercise_template_measurement_kind:text! exercise_template_superset_group_id:uuid? exercise_template_superset_order:integer? exercise_template_workout_day_template_id:uuid?",
            .warmupItem: "config_scope:text? warmup_item_phase:text! warmup_item_movement:text! warmup_item_dose:text! warmup_item_order_index:integer! warmup_item_workout_day_template_id:uuid?",
            .cooldownItem: "config_scope:text? cooldown_item_movement:text! cooldown_item_dose:text! cooldown_item_note:text? cooldown_item_order_index:integer! cooldown_item_workout_day_template_id:uuid?",
            .workoutSession: "config_scope:text? workout_session_date:timestamp! workout_session_status:text! workout_session_workout_day_template_id:uuid! workout_session_perceived_recovery:integer? workout_session_note:text? workout_session_ohp_symptom_response:text! workout_session_ohp_symptom_checked_at:timestamp?",
            .setLog: "config_scope:text? set_log_exercise_template_id:uuid! set_log_set_index:integer! set_log_weight_kg:decimal? set_log_reps:integer? set_log_duration_sec:integer? set_log_distance_steps:integer? set_log_performed_variant:text? set_log_rir:integer? set_log_is_warmup_set:boolean! set_log_completed_at:timestamp! set_log_workout_session_id:uuid?",
            .workoutSessionProgress: "config_scope:text? workout_session_progress_workout_session_id:uuid! workout_session_progress_stage:text! workout_session_progress_current_exercise_template_id:uuid? workout_session_progress_completed_warmup_item_ids_json:text! workout_session_progress_completed_cooldown_item_ids_json:text! workout_session_progress_warmup_disposition:text! workout_session_progress_cooldown_disposition:text!",
            .food: "config_scope:text? food_name:text! food_brand:text? food_serving_size:decimal! food_serving_unit:text! food_calories_per_serving:decimal! food_protein_g:decimal! food_carb_g:decimal! food_fat_g:decimal! food_fiber_g:decimal? food_source:text!",
            .recipe: "config_scope:text? recipe_name:text! recipe_category:text! recipe_category_custom_name:text? recipe_servings:decimal! recipe_is_direct_macros:boolean! recipe_calories_total:decimal! recipe_protein_total_g:decimal! recipe_carb_total_g:decimal! recipe_fat_total_g:decimal! recipe_note:text?",
            .dailyNutritionLog: "config_scope:text? daily_nutrition_log_date:timestamp!",
            .mealEntry: "config_scope:text? meal_entry_category:text! meal_entry_category_custom_name:text? meal_entry_recipe_id:uuid? meal_entry_food_id:uuid? meal_entry_adhoc_name:text? meal_entry_quantity:decimal! meal_entry_calories_resolved:decimal! meal_entry_protein_resolved:decimal! meal_entry_carb_resolved:decimal! meal_entry_fat_resolved:decimal! meal_entry_logged_at:timestamp! meal_entry_daily_nutrition_log_id:uuid?",
            .bodyMetric: "config_scope:text? body_metric_date:timestamp! body_metric_type:text! body_metric_custom_name:text? body_metric_value:decimal! body_metric_unit:text!",
            .postureMetric: "config_scope:text? posture_metric_date:timestamp! posture_metric_wall_test_pass:boolean? posture_metric_symptom_score:integer? posture_metric_region:text? posture_metric_note:text?",
            .sleepLog: "config_scope:text? sleep_log_date:timestamp! sleep_log_duration_hours:decimal! sleep_log_quality:integer! sleep_log_note:text?",
            .moodLog: "config_scope:text? mood_log_date:timestamp! mood_log_mood_score:integer? mood_log_mood_tags_json:text! mood_log_energy:integer? mood_log_note:text?",
            .healthCheckReminder: "config_scope:text? health_check_reminder_name:text! health_check_reminder_due_date:timestamp! health_check_reminder_recurrence:text! health_check_reminder_status:text!",
            .bloodworkResult: "config_scope:text? bloodwork_result_date:timestamp! bloodwork_result_marker:text! bloodwork_result_value:decimal! bloodwork_result_unit:text! bloodwork_result_note:text?",
            .progressPhoto: "config_scope:text? progress_photo_date:timestamp! progress_photo_image_available:boolean! progress_photo_pose:text! progress_photo_note:text?",
            .appReminder: "config_scope:text? app_reminder_type:text! app_reminder_schedule:text! app_reminder_message:text! app_reminder_is_enabled:boolean!",
            .appSetting: "config_scope:text? app_setting_key:text! app_setting_value:text!",
        ]

        XCTAssertEqual(Set(expected.keys), Set(ExportRecordTypeV1.allCases))
        for recordType in ExportRecordTypeV1.allCases {
            let actual = ExportSchemaV1.definition(for: recordType).fields.map {
                "\($0.name):\($0.type.rawValue)\($0.isNullable ? "?" : "!")"
            }
            XCTAssertEqual(actual, expected[recordType]!.split(separator: " ").map(String.init), recordType.rawValue)
        }

        let allNames = Set(ExportSchemaV1.records.flatMap(\.fields).map(\.name))
        for omittedInverse in [
            "program_workout_day_templates", "program_program_phases",
            "workout_day_template_exercise_templates", "workout_day_template_warmup_items",
            "workout_day_template_cooldown_items", "workout_session_set_logs",
            "daily_nutrition_log_meal_entries",
        ] {
            XCTAssertFalse(allNames.contains(omittedInverse))
        }
        XCTAssertFalse(allNames.contains { $0.contains("image_ref") || $0.hasSuffix("_data") })
        XCTAssertTrue(allNames.contains("progress_photo_image_available"))
        XCTAssertTrue(allNames.contains("workout_session_progress_completed_warmup_item_ids_json"))
        XCTAssertTrue(allNames.contains("workout_session_progress_completed_cooldown_item_ids_json"))
    }

    func testTableRejectsDuplicateUnknownMissingAndWrongTypedCells() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let columns = try canonicalColumns(extra: [
            ExportColumnV1(name: "optional_note", type: .text, isNullable: true),
        ])
        let validCells = canonicalCells(date: date, id: id) + [
            ExportNamedCellV1(columnName: "optional_note", value: .text("ok")),
        ]
        let validRow = try ExportRowV1(primaryTimestamp: date, cells: validCells)

        XCTAssertNoThrow(try ExportTableV1(module: .metrics, columns: columns, rows: [validRow]))

        XCTAssertThrowsError(try ExportTableV1(
            module: .metrics,
            columns: columns + [columns.last!],
            rows: [validRow]
        )) { error in
            XCTAssertEqual(error as? ExportSchemaV1Error, .duplicateColumn("optional_note"))
        }

        XCTAssertThrowsError(try ExportRowV1(
            primaryTimestamp: date,
            cells: validCells + [validCells.last!]
        )) { error in
            XCTAssertEqual(error as? ExportSchemaV1Error, .duplicateCell("optional_note"))
        }

        let unknown = try ExportRowV1(
            primaryTimestamp: date,
            cells: Array(validCells.dropLast()) + [
                ExportNamedCellV1(columnName: "unknown", value: .text("no")),
            ]
        )
        XCTAssertThrowsError(try ExportTableV1(
            module: .metrics,
            columns: columns,
            rows: [unknown]
        )) { error in
            XCTAssertEqual(error as? ExportSchemaV1Error, .unknownCell("unknown"))
        }

        let short = try ExportRowV1(
            primaryTimestamp: date,
            cells: Array(validCells.dropLast())
        )
        XCTAssertThrowsError(try ExportTableV1(
            module: .metrics,
            columns: columns,
            rows: [short]
        )) { error in
            XCTAssertEqual(
                error as? ExportSchemaV1Error,
                .rowWidthMismatch(expected: columns.count, actual: columns.count - 1)
            )
        }

        let wrongType = try ExportRowV1(
            primaryTimestamp: date,
            cells: Array(validCells.dropLast()) + [
                ExportNamedCellV1(columnName: "optional_note", value: .integer(1)),
            ]
        )
        XCTAssertThrowsError(try ExportTableV1(
            module: .metrics,
            columns: columns,
            rows: [wrongType]
        )) { error in
            XCTAssertEqual(
                error as? ExportSchemaV1Error,
                .cellTypeMismatch(column: "optional_note", expected: .text, actual: .integer)
            )
        }

        var nullRequiredCells = validCells
        nullRequiredCells[1] = ExportNamedCellV1(columnName: "id", value: .null)
        let nullRequired = try ExportRowV1(primaryTimestamp: date, cells: nullRequiredCells)
        XCTAssertThrowsError(try ExportTableV1(
            module: .metrics,
            columns: columns,
            rows: [nullRequired]
        )) { error in
            XCTAssertEqual(error as? ExportSchemaV1Error, .nullInRequiredColumn("id"))
        }
    }

    func testCanonicalTableRejectsPrimaryTimestampThatDisagreesWithTypedRecordCell() throws {
        let cellTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let fakeSortTimestamp = cellTimestamp.addingTimeInterval(-60)
        let row = try canonicalSchemaRow(
            recordType: .bodyMetric,
            id: UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!,
            timestamp: cellTimestamp,
            primaryTimestamp: fakeSortTimestamp,
            configScope: nil
        )

        XCTAssertThrowsError(try ExportTableV1(
            module: .metrics,
            columns: ExportSchemaV1.columns(for: .metrics),
            rows: [row]
        )) { error in
            XCTAssertEqual(
                error as? ExportSchemaV1Error,
                .primaryTimestampMismatch(
                    recordType: .bodyMetric,
                    column: "body_metric_date"
                )
            )
        }

        let valid = try canonicalSchemaRow(
            recordType: .bodyMetric,
            id: UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!,
            timestamp: cellTimestamp,
            configScope: nil
        )
        XCTAssertNoThrow(try ExportTableV1(
            module: .metrics,
            columns: ExportSchemaV1.columns(for: .metrics),
            rows: [valid]
        ))
    }

    func testSnapshotPreservesExactRequestAndOrdersTablesWithoutInventingAllModules() throws {
        let interval = ReportDateInterval(
            start: Date(timeIntervalSince1970: 100),
            endExclusive: Date(timeIntervalSince1970: 200)
        )
        let metrics = try ExportTableV1(
            module: .metrics,
            columns: ExportSchemaV1.columns(for: .metrics),
            rows: []
        )
        let nutrition = try ExportTableV1(
            module: .nutrition,
            columns: ExportSchemaV1.columns(for: .nutrition),
            rows: []
        )
        let snapshot = try ExportSnapshotV1(
            interval: interval,
            selectedModules: [.metrics, .nutrition],
            tables: [metrics, nutrition]
        )

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.interval, interval)
        XCTAssertEqual(snapshot.selectedModules, [.nutrition, .metrics])
        XCTAssertEqual(snapshot.tables.map(\.module), [.nutrition, .metrics])

        let empty = try ExportSnapshotV1(
            interval: interval,
            selectedModules: [],
            tables: []
        )
        XCTAssertEqual(empty.selectedModules, [])
        XCTAssertEqual(empty.tables, [])

        XCTAssertThrowsError(try ExportSnapshotV1(
            interval: interval,
            selectedModules: [.metrics],
            tables: []
        )) { error in
            XCTAssertEqual(error as? ExportSchemaV1Error, .missingSelectedModule(.metrics))
        }
    }

    func testSnapshotRejectsUnselectedOrMalformedExtraTablesUnlessRowsAreReferencedConfig() throws {
        let interval = ReportDateInterval(
            start: Date(timeIntervalSince1970: 100),
            endExclusive: Date(timeIntervalSince1970: 200)
        )
        let metrics = try ExportTableV1(
            module: .metrics,
            columns: ExportSchemaV1.columns(for: .metrics),
            rows: []
        )
        let emptyExtra = try ExportTableV1(
            module: .profileProgram,
            columns: ExportSchemaV1.columns(for: .profileProgram),
            rows: []
        )
        XCTAssertThrowsError(try ExportSnapshotV1(
            interval: interval,
            selectedModules: [.metrics],
            tables: [metrics, emptyExtra]
        )) { error in
            XCTAssertEqual(
                error as? ExportSchemaV1Error,
                .unselectedTableContainsNonReferencedRows(.profileProgram)
            )
        }

        let wrongSchema = try ExportTableV1(
            module: .metrics,
            columns: try canonicalColumns(extra: []),
            rows: []
        )
        XCTAssertThrowsError(try ExportSnapshotV1(
            interval: interval,
            selectedModules: [.metrics],
            tables: [wrongSchema]
        )) { error in
            XCTAssertEqual(error as? ExportSchemaV1Error, .unexpectedTableSchema(.metrics))
        }


        let referencedProfileRow = try canonicalSchemaRow(
            recordType: .userProfile,
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            timestamp: interval.start,
            configScope: .referenced
        )
        let referencedProfile = try ExportTableV1(
            module: .profileProgram,
            columns: ExportSchemaV1.columns(for: .profileProgram),
            rows: [referencedProfileRow]
        )
        let accepted = try ExportSnapshotV1(
            interval: interval,
            selectedModules: [.metrics],
            tables: [metrics, referencedProfile]
        )
        XCTAssertEqual(accepted.tables.map(\.module), [.profileProgram, .metrics])
        XCTAssertEqual(accepted.tables.first?.rows, [referencedProfileRow])

        let selectedScopeProfile = try ExportTableV1(
            module: .profileProgram,
            columns: ExportSchemaV1.columns(for: .profileProgram),
            rows: [try canonicalSchemaRow(
                recordType: .userProfile,
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
                timestamp: interval.start,
                configScope: .selected
            )]
        )
        XCTAssertThrowsError(try ExportSnapshotV1(
            interval: interval,
            selectedModules: [.metrics],
            tables: [metrics, selectedScopeProfile]
        )) { error in
            XCTAssertEqual(
                error as? ExportSchemaV1Error,
                .unselectedTableContainsNonReferencedRows(.profileProgram)
            )
        }

        let unselectedEvent = try ExportTableV1(
            module: .training,
            columns: ExportSchemaV1.columns(for: .training),
            rows: [try canonicalSchemaRow(
                recordType: .workoutSession,
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
                timestamp: interval.start,
                configScope: nil
            )]
        )
        XCTAssertThrowsError(try ExportSnapshotV1(
            interval: interval,
            selectedModules: [.metrics],
            tables: [metrics, unselectedEvent]
        )) { error in
            XCTAssertEqual(
                error as? ExportSchemaV1Error,
                .unselectedTableContainsNonReferencedRows(.training)
            )
        }
    }

    private func canonicalColumns(extra: [ExportColumnV1]) throws -> [ExportColumnV1] {
        try [
            ExportColumnV1(name: "record_type", type: .text, isNullable: false),
            ExportColumnV1(name: "id", type: .uuid, isNullable: false),
            ExportColumnV1(name: "created_at", type: .timestamp, isNullable: false),
            ExportColumnV1(name: "updated_at", type: .timestamp, isNullable: false),
        ] + extra
    }

    private func canonicalCells(date: Date, id: UUID) -> [ExportNamedCellV1] {
        [
            ExportNamedCellV1(columnName: "record_type", value: .text("body_metric")),
            ExportNamedCellV1(columnName: "id", value: .uuid(id)),
            ExportNamedCellV1(columnName: "created_at", value: .timestamp(date)),
            ExportNamedCellV1(columnName: "updated_at", value: .timestamp(date)),
        ]
    }

    private func canonicalSchemaRow(
        recordType: ExportRecordTypeV1,
        id: UUID,
        timestamp: Date,
        primaryTimestamp: Date? = nil,
        configScope: ExportConfigScopeV1?
    ) throws -> ExportRowV1 {
        let definition = ExportSchemaV1.definition(for: recordType)
        let ownedFields = Dictionary(
            uniqueKeysWithValues: definition.fields.map { ($0.name, $0) }
        )
        let cells = ExportSchemaV1.columns(for: recordType.module).map { column in
            let value: ExportCellV1
            switch column.name {
            case "record_type": value = .text(recordType.rawValue)
            case "id": value = .uuid(id)
            case "created_at", "updated_at": value = .timestamp(timestamp)
            case "config_scope":
                value = configScope.map { .text($0.rawValue) } ?? .null
            default:
                guard let field = ownedFields[column.name] else {
                    return ExportNamedCellV1(columnName: column.name, value: .null)
                }
                value = field.isNullable ? .null : placeholder(field.type, id, timestamp)
            }
            return ExportNamedCellV1(columnName: column.name, value: value)
        }
        return try ExportRowV1(
            primaryTimestamp: primaryTimestamp ?? timestamp,
            cells: cells
        )
    }

    private func placeholder(
        _ type: ExportColumnTypeV1,
        _ id: UUID,
        _ timestamp: Date
    ) -> ExportCellV1 {
        switch type {
        case .text: .text("value")
        case .integer: .integer(1)
        case .decimal: .decimal(1)
        case .boolean: .boolean(true)
        case .timestamp: .timestamp(timestamp)
        case .uuid: .uuid(id)
        }
    }
}
