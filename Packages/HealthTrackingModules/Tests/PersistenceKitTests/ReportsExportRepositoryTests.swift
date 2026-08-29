import CoreModels
@testable import PersistenceKit
import ReportsKit
import SwiftData
import XCTest

@MainActor
final class ReportsExportRepositoryTests: XCTestCase {
    func testInventoryUsesAllTwentyFourRealModelTypesAndProjectsEveryRecord() async throws {
        let expectedTypes: [any PersistentModel.Type] = [
            UserProfile.self, Program.self, ProgramPhase.self, ProgramState.self,
            WorkoutDayTemplate.self, ExerciseTemplate.self, WarmupItem.self, CooldownItem.self,
            WorkoutSession.self, SetLog.self, WorkoutSessionProgress.self,
            Food.self, Recipe.self, DailyNutritionLog.self, MealEntry.self,
            BodyMetric.self, PostureMetric.self, SleepLog.self, MoodLog.self,
            HealthCheckReminder.self, BloodworkResult.self, ProgressPhoto.self,
            AppReminder.self, AppSetting.self,
        ]
        XCTAssertEqual(ReportsExportModelInventoryV1.modelTypes.count, 24)
        XCTAssertEqual(
            ReportsExportModelInventoryV1.modelTypes.map { ObjectIdentifier($0) },
            expectedTypes.map { ObjectIdentifier($0) }
        )

        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let instant = try date("2024-06-01T12:00:00Z")
        let graph = try completeGraph(at: instant)
        insert(graph, into: writer)
        try writer.save()

        let reader = ModelContext(container)
        let before = graphSnapshot(graph)
        let repository = SwiftDataReportsRepository(modelContext: reader, calendar: utcCalendar())
        let request = ReportDateInterval(
            start: instant.addingTimeInterval(-1),
            endExclusive: instant.addingTimeInterval(1)
        )

        let first = try await repository.fetchExportSnapshot(
            in: request,
            modules: Set(ExportModuleV1.allCases)
        )
        let second = try await repository.fetchExportSnapshot(
            in: request,
            modules: Set(ExportModuleV1.allCases)
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.tables.map(\.module), ExportModuleV1.allCases)
        XCTAssertEqual(first.tables.flatMap(\.rows).count, 24)
        XCTAssertEqual(
            first.tables.flatMap(\.rows).compactMap(recordType),
            ExportModuleV1.allCases.flatMap { module in
                ExportRecordTypeV1.allCases
                    .filter { $0.module == module }
                    .map(\.rawValue)
                    .sorted()
            }
        )
        for definition in ExportSchemaV1.records {
            XCTAssertEqual(rows(definition.recordType, in: first).count, 1)
        }

        let progress = try XCTUnwrap(rows(.workoutSessionProgress, in: first).first)
        XCTAssertEqual(
            cell("workout_session_progress_completed_warmup_item_ids_json", in: progress),
            .text("[\"00000000-0000-4000-8000-000000000007\"]")
        )
        XCTAssertEqual(
            cell("workout_session_progress_completed_cooldown_item_ids_json", in: progress),
            .text("[\"00000000-0000-4000-8000-000000000008\"]")
        )
        XCTAssertFalse(progress.cells.contains { $0.columnName.contains("data") })

        let photo = try XCTUnwrap(rows(.progressPhoto, in: first).first)
        XCTAssertEqual(cell("progress_photo_image_available", in: photo), .boolean(true))
        XCTAssertEqual(cell("progress_photo_note", in: photo), .text("özel not"))
        XCTAssertFalse(first.tables.flatMap(\.columns).contains {
            $0.name.contains("image_ref") || $0.name.contains("image_path")
        })

        let nutrition = try XCTUnwrap(rows(.mealEntry, in: first).first)
        XCTAssertEqual(cell("meal_entry_category", in: nutrition), .text("custom"))
        XCTAssertEqual(cell("meal_entry_category_custom_name", in: nutrition), .text("Gece"))
        let mood = try XCTUnwrap(rows(.moodLog, in: first).first)
        XCTAssertEqual(cell("mood_log_mood_tags_json", in: mood), .text("[\"odak\",\"iyi\"]"))

        let intentionallyOmittedInverseRelationships = [
            "program_workout_day_templates", "program_program_phases",
            "workout_day_template_exercise_templates", "workout_day_template_warmup_items",
            "workout_day_template_cooldown_items", "workout_session_set_logs",
            "daily_nutrition_log_meal_entries",
        ]
        let allColumnNames = Set(first.tables.flatMap(\.columns).map(\.name))
        for omitted in intentionallyOmittedInverseRelationships {
            XCTAssertFalse(allColumnNames.contains(omitted), omitted)
        }
        XCTAssertFalse(reader.hasChanges)
        XCTAssertEqual(graphSnapshot(graph), before)
    }

    func testHalfOpenRangeIncludesExactStartAndJustBeforeEndOnly() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let start = try date("2024-03-31T21:00:00Z")
        let end = try date("2024-04-01T21:00:00Z")
        let values: [(Int, Date)] = [
            (101, start.addingTimeInterval(-0.001)),
            (102, start),
            (103, end.addingTimeInterval(-0.001)),
            (104, end),
        ]
        for (identifier, timestamp) in values {
            writer.insert(BodyMetric(
                id: id(identifier), createdAt: timestamp, updatedAt: timestamp,
                date: timestamp, type: .weight, value: Double(identifier), unit: "kg"
            ))
        }
        try writer.save()
        let reader = ModelContext(container)

        let snapshot = try await SwiftDataReportsRepository(
            modelContext: reader,
            calendar: istanbulCalendar()
        ).fetchExportSnapshot(
            in: ReportDateInterval(start: start, endExclusive: end),
            modules: [.metrics]
        )

        XCTAssertEqual(rows(.bodyMetric, in: snapshot).compactMap(rowID), [id(102), id(103)])
        XCTAssertEqual(snapshot.tables.map(\.module), [.metrics])
        XCTAssertTrue(try XCTUnwrap(snapshot.tables.first).rows.allSatisfy {
            cell("config_scope", in: $0) == .null
        })
        XCTAssertFalse(reader.hasChanges)
    }

    func testSelectedTrainingAddsOnlyTransitiveReferencedConfiguration() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let instant = try date("2024-06-01T12:00:00Z")
        let graph = try completeGraph(at: instant)
        insertTrainingAndReferencedConfiguration(graph, into: writer)

        let unrelatedProgram = Program(
            id: id(901), createdAt: instant, updatedAt: instant,
            name: "Unrelated", descriptionText: "exclude", isActive: false
        )
        let unrelatedDay = WorkoutDayTemplate(
            id: id(902), createdAt: instant, updatedAt: instant,
            name: "Unrelated day", orderIndex: 9, focus: "exclude", program: unrelatedProgram
        )
        unrelatedProgram.workoutDayTemplates = [unrelatedDay]
        writer.insert(unrelatedProgram)
        writer.insert(unrelatedDay)
        writer.insert(AppSetting(
            id: id(903), createdAt: instant, updatedAt: instant,
            key: "unrelated", value: "must-not-leak"
        ))
        try writer.save()
        let reader = ModelContext(container)
        let before = graphSnapshot(graph)

        let snapshot = try await SwiftDataReportsRepository(
            modelContext: reader,
            calendar: utcCalendar()
        ).fetchExportSnapshot(
            in: ReportDateInterval(
                start: instant.addingTimeInterval(-1),
                endExclusive: instant.addingTimeInterval(1)
            ),
            modules: [.training]
        )

        XCTAssertEqual(snapshot.selectedModules, [.training])
        XCTAssertEqual(snapshot.tables.map(\.module), [.profileProgram, .training])
        XCTAssertEqual(snapshot.tables.flatMap(\.rows).compactMap(recordType), [
            "cooldown_item", "exercise_template", "program", "program_phase",
            "program_state", "user_profile", "warmup_item", "workout_day_template",
            "set_log", "workout_session", "workout_session_progress",
        ])
        let referenced = try XCTUnwrap(snapshot.tables.first)
        XCTAssertTrue(referenced.rows.allSatisfy { cell("config_scope", in: $0) == .text("referenced") })
        XCTAssertFalse(snapshot.tables.flatMap(\.rows).compactMap(rowID).contains(id(901)))
        XCTAssertFalse(snapshot.tables.flatMap(\.rows).compactMap(rowID).contains(id(902)))
        XCTAssertFalse(snapshot.tables.contains { $0.module == .system })
        XCTAssertFalse(reader.hasChanges)
        XCTAssertEqual(graphSnapshot(graph), before)
    }

    func testSelectedTrainingFailsClosedOnProgressChecklistReferenceTypeAndDay() async throws {
        let instant = try date("2024-06-01T12:00:00Z")

        let missingID = id(930)
        let missingOptional = try await trainingExportError(
            at: instant
        ) { graph, _ in
            graph.progress.completedWarmupItemIdsData = try WorkoutSessionProgressCodec.encode(
                [missingID]
            )
        }
        let missing = try XCTUnwrap(missingOptional)
        XCTAssertEqual(
            missing,
            .invalidWorkoutSessionProgressReference(
                id: id(11), field: .completedWarmupItemIDs, targetID: missingID,
                reason: .missing
            )
        )

        let missingDayRelationshipOptional = try await trainingExportError(
            at: instant
        ) { graph, _ in
            graph.day.warmupItems = []
            graph.warmup.workoutDayTemplate = nil
        }
        let missingDayRelationship = try XCTUnwrap(missingDayRelationshipOptional)
        XCTAssertEqual(
            missingDayRelationship,
            .invalidWorkoutSessionProgressReference(
                id: id(11), field: .completedWarmupItemIDs, targetID: id(7),
                reason: .missingWorkoutDay
            )
        )

        let warmupUsesCooldownOptional = try await trainingExportError(
            at: instant
        ) { graph, _ in
            graph.progress.completedWarmupItemIdsData = try WorkoutSessionProgressCodec.encode(
                [graph.cooldown.id]
            )
        }
        let warmupUsesCooldown = try XCTUnwrap(warmupUsesCooldownOptional)
        XCTAssertEqual(
            warmupUsesCooldown,
            .invalidWorkoutSessionProgressReference(
                id: id(11), field: .completedWarmupItemIDs, targetID: id(8),
                reason: .wrongRecordType(.cooldownItem)
            )
        )

        let cooldownUsesWarmupOptional = try await trainingExportError(
            at: instant
        ) { graph, _ in
            graph.progress.completedCooldownItemIdsData = try WorkoutSessionProgressCodec.encode(
                [graph.warmup.id]
            )
        }
        let cooldownUsesWarmup = try XCTUnwrap(cooldownUsesWarmupOptional)
        XCTAssertEqual(
            cooldownUsesWarmup,
            .invalidWorkoutSessionProgressReference(
                id: id(11), field: .completedCooldownItemIDs, targetID: id(7),
                reason: .wrongRecordType(.warmupItem)
            )
        )

        let otherDayID = id(931)
        let otherWarmupID = id(932)
        let wrongDayOptional = try await trainingExportError(
            at: instant
        ) { graph, writer in
            let otherDay = WorkoutDayTemplate(
                id: otherDayID, createdAt: instant, updatedAt: instant,
                name: "Other day", orderIndex: 2, focus: "other",
                program: graph.program
            )
            let otherWarmup = WarmupItem(
                id: otherWarmupID, createdAt: instant, updatedAt: instant,
                movement: "Other warmup", dose: "1", orderIndex: 1,
                workoutDayTemplate: otherDay
            )
            otherDay.warmupItems = [otherWarmup]
            graph.program.workoutDayTemplates = [graph.day, otherDay]
            graph.progress.completedWarmupItemIdsData = try WorkoutSessionProgressCodec.encode(
                [otherWarmup.id]
            )
            writer.insert(otherDay)
            writer.insert(otherWarmup)
        }
        let wrongDay = try XCTUnwrap(wrongDayOptional)
        XCTAssertEqual(
            wrongDay,
            .invalidWorkoutSessionProgressReference(
                id: id(11), field: .completedWarmupItemIDs, targetID: otherWarmupID,
                reason: .wrongWorkoutDay(expected: id(5), actual: otherDayID)
            )
        )
    }

    func testSelectedTrainingExerciseReferencesMatchSessionDayAndIgnoreOutOfRangeRows() async throws {
        let instant = try date("2024-06-01T12:00:00Z")

        let setMissingDayOptional = try await trainingExportError(
            at: instant
        ) { graph, _ in
            graph.progress.currentExerciseTemplateId = nil
            graph.day.exerciseTemplates = []
            graph.exercise.workoutDayTemplate = nil
        }
        let setMissingDay = try XCTUnwrap(setMissingDayOptional)
        XCTAssertEqual(
            setMissingDay,
            .invalidTrainingExerciseReference(
                sourceType: .setLog,
                sourceID: id(10),
                exerciseTemplateID: id(6),
                reason: .missingWorkoutDay
            )
        )

        let otherDayID = id(960)
        let setWrongDayOptional = try await trainingExportError(
            at: instant
        ) { graph, writer in
            let otherDay = WorkoutDayTemplate(
                id: otherDayID, createdAt: instant, updatedAt: instant,
                name: "Other set day", orderIndex: 2, focus: "other",
                program: graph.program
            )
            graph.progress.currentExerciseTemplateId = nil
            graph.day.exerciseTemplates = []
            graph.exercise.workoutDayTemplate = otherDay
            otherDay.exerciseTemplates = [graph.exercise]
            graph.program.workoutDayTemplates = [graph.day, otherDay]
            writer.insert(otherDay)
        }
        let setWrongDay = try XCTUnwrap(setWrongDayOptional)
        XCTAssertEqual(
            setWrongDay,
            .invalidTrainingExerciseReference(
                sourceType: .setLog,
                sourceID: id(10),
                exerciseTemplateID: id(6),
                reason: .wrongWorkoutDay(expected: id(5), actual: otherDayID)
            )
        )

        let progressMissingDayOptional = try await trainingExportError(
            at: instant
        ) { graph, _ in
            graph.set.completedAt = instant.addingTimeInterval(10)
            graph.day.exerciseTemplates = []
            graph.exercise.workoutDayTemplate = nil
        }
        let progressMissingDay = try XCTUnwrap(progressMissingDayOptional)
        XCTAssertEqual(
            progressMissingDay,
            .invalidTrainingExerciseReference(
                sourceType: .workoutSessionProgress,
                sourceID: id(11),
                exerciseTemplateID: id(6),
                reason: .missingWorkoutDay
            )
        )

        let progressWrongDayOptional = try await trainingExportError(
            at: instant
        ) { graph, writer in
            let otherDay = WorkoutDayTemplate(
                id: otherDayID, createdAt: instant, updatedAt: instant,
                name: "Other progress day", orderIndex: 2, focus: "other",
                program: graph.program
            )
            graph.set.completedAt = instant.addingTimeInterval(10)
            graph.day.exerciseTemplates = []
            graph.exercise.workoutDayTemplate = otherDay
            otherDay.exerciseTemplates = [graph.exercise]
            graph.program.workoutDayTemplates = [graph.day, otherDay]
            writer.insert(otherDay)
        }
        let progressWrongDay = try XCTUnwrap(progressWrongDayOptional)
        XCTAssertEqual(
            progressWrongDay,
            .invalidTrainingExerciseReference(
                sourceType: .workoutSessionProgress,
                sourceID: id(11),
                exerciseTemplateID: id(6),
                reason: .wrongWorkoutDay(expected: id(5), actual: otherDayID)
            )
        )

        let ignored = try await trainingExportError(at: instant) { graph, writer in
            let corruptExercise = ExerciseTemplate(
                id: id(970), createdAt: instant, updatedAt: instant,
                name: "Out of range", orderIndex: 99, targetSets: 1,
                workoutDayTemplate: nil
            )
            let outsideSet = SetLog(
                id: id(971), createdAt: instant, updatedAt: instant,
                exerciseTemplateId: corruptExercise.id,
                setIndex: 99,
                completedAt: instant.addingTimeInterval(10),
                workoutSession: graph.session
            )
            writer.insert(corruptExercise)
            writer.insert(outsideSet)
        }
        XCTAssertNil(ignored)
    }

    func testSelectedTrainingMissingReferencesPreserveActualSourceProvenance() async throws {
        let instant = try date("2024-06-01T12:00:00Z")
        let missingDayID = id(950)
        let missingDayOptional = try await trainingExportError(
            at: instant
        ) { graph, _ in
            graph.session.workoutDayTemplateId = missingDayID
        }
        let missingDay = try XCTUnwrap(missingDayOptional)
        XCTAssertEqual(
            missingDay,
            .missingReference(
                sourceType: .workoutSession, sourceID: id(9),
                targetType: .workoutDayTemplate, targetID: missingDayID
            )
        )

        let missingSetExerciseID = id(951)
        let missingSetExerciseOptional = try await trainingExportError(
            at: instant
        ) { graph, _ in
            graph.set.exerciseTemplateId = missingSetExerciseID
        }
        let missingSetExercise = try XCTUnwrap(missingSetExerciseOptional)
        XCTAssertEqual(
            missingSetExercise,
            .missingReference(
                sourceType: .setLog, sourceID: id(10),
                targetType: .exerciseTemplate, targetID: missingSetExerciseID
            )
        )

        let missingProgressExerciseID = id(952)
        let missingProgressExerciseOptional = try await trainingExportError(
            at: instant
        ) { graph, _ in
            graph.progress.currentExerciseTemplateId = missingProgressExerciseID
        }
        let missingProgressExercise = try XCTUnwrap(missingProgressExerciseOptional)
        XCTAssertEqual(
            missingProgressExercise,
            .missingReference(
                sourceType: .workoutSessionProgress, sourceID: id(11),
                targetType: .exerciseTemplate, targetID: missingProgressExerciseID
            )
        )
    }

    func testRelevantCorruptionFailsInCanonicalUUIDOrderAcrossInsertionOrders() async throws {
        let instant = try date("2024-06-01T12:00:00Z")
        let interval = ReportDateInterval(
            start: instant.addingTimeInterval(-1),
            endExclusive: instant.addingTimeInterval(1)
        )
        let lowerProgressID = id(980)
        let higherProgressID = id(981)
        let lowerMissingSessionID = id(982)
        let higherMissingSessionID = id(983)
        let expectedReferenceError = ReportsExportRepositoryError.missingReference(
            sourceType: .workoutSessionProgress,
            sourceID: lowerProgressID,
            targetType: .workoutSession,
            targetID: lowerMissingSessionID
        )
        let lowerMetricID = id(984)
        let higherMetricID = id(985)
        let expectedProjectionError = ReportsExportRepositoryError.nonFiniteValue(
            recordType: .bodyMetric,
            id: lowerMetricID,
            column: "body_metric_value"
        )

        for reverseInsertion in [false, true] {
            let referenceContainer = try ModelContainerFactory.make(for: .inMemory)
            let referenceWriter = ModelContext(referenceContainer)
            let progressRecords = [
                WorkoutSessionProgress(
                    id: lowerProgressID,
                    createdAt: instant,
                    updatedAt: instant,
                    workoutSessionId: lowerMissingSessionID
                ),
                WorkoutSessionProgress(
                    id: higherProgressID,
                    createdAt: instant,
                    updatedAt: instant,
                    workoutSessionId: higherMissingSessionID
                ),
            ]
            let orderedProgress = reverseInsertion
                ? Array(progressRecords.reversed())
                : progressRecords
            for progress in orderedProgress { referenceWriter.insert(progress) }
            try referenceWriter.save()
            let referenceReader = ModelContext(referenceContainer)

            do {
                _ = try await SwiftDataReportsRepository(
                    modelContext: referenceReader,
                    calendar: utcCalendar()
                ).fetchExportSnapshot(in: interval, modules: [.training])
                XCTFail("Expected canonical missing-session failure.")
            } catch let error as ReportsExportRepositoryError {
                XCTAssertEqual(error, expectedReferenceError)
            }
            XCTAssertFalse(referenceReader.hasChanges)

            let projectionContainer = try ModelContainerFactory.make(for: .inMemory)
            let projectionWriter = ModelContext(projectionContainer)
            let metrics = [
                BodyMetric(
                    id: lowerMetricID,
                    createdAt: instant,
                    updatedAt: instant,
                    date: instant,
                    type: .weight,
                    value: .infinity,
                    unit: "kg"
                ),
                BodyMetric(
                    id: higherMetricID,
                    createdAt: instant,
                    updatedAt: instant,
                    date: instant,
                    type: .weight,
                    value: .infinity,
                    unit: "kg"
                ),
            ]
            let orderedMetrics = reverseInsertion ? Array(metrics.reversed()) : metrics
            for metric in orderedMetrics { projectionWriter.insert(metric) }
            try projectionWriter.save()
            let projectionReader = ModelContext(projectionContainer)

            do {
                _ = try await SwiftDataReportsRepository(
                    modelContext: projectionReader,
                    calendar: utcCalendar()
                ).fetchExportSnapshot(in: interval, modules: [.metrics])
                XCTFail("Expected canonical non-finite projection failure.")
            } catch let error as ReportsExportRepositoryError {
                XCTAssertEqual(error, expectedProjectionError)
            }
            XCTAssertFalse(projectionReader.hasChanges)
        }
    }

    func testSelectedNutritionExportsAllSelectedFoodAndRecipeConfiguration() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let instant = try date("2024-06-01T12:00:00Z")
        let graph = try completeGraph(at: instant)
        writer.insert(graph.profile)
        writer.insert(graph.food)
        writer.insert(graph.recipe)
        writer.insert(graph.nutritionDay)
        writer.insert(graph.meal)
        let unrelatedFood = Food(
            id: id(910), createdAt: instant, updatedAt: instant,
            name: "Unrelated food", servingSize: 1, servingUnit: "g",
            caloriesPerServing: 1, proteinG: 1, carbG: 1, fatG: 1
        )
        let unrelatedRecipe = Recipe(
            id: id(911), createdAt: instant, updatedAt: instant,
            name: "Unrelated recipe", servings: 1
        )
        writer.insert(unrelatedFood)
        writer.insert(unrelatedRecipe)
        try writer.save()
        let reader = ModelContext(container)

        let snapshot = try await SwiftDataReportsRepository(
            modelContext: reader,
            calendar: utcCalendar()
        ).fetchExportSnapshot(
            in: ReportDateInterval(
                start: instant.addingTimeInterval(-1),
                endExclusive: instant.addingTimeInterval(1)
            ),
            modules: [.nutrition]
        )

        XCTAssertEqual(snapshot.tables.map(\.module), [.profileProgram, .nutrition])
        XCTAssertEqual(snapshot.tables.flatMap(\.rows).compactMap(recordType), [
            "user_profile", "daily_nutrition_log", "food", "food", "meal_entry",
            "recipe", "recipe",
        ])
        XCTAssertEqual(cell("config_scope", in: try XCTUnwrap(rows(.userProfile, in: snapshot).first)), .text("referenced"))
        XCTAssertEqual(rows(.food, in: snapshot).compactMap(rowID), [graph.food.id, id(910)])
        XCTAssertEqual(rows(.recipe, in: snapshot).compactMap(rowID), [graph.recipe.id, id(911)])
        XCTAssertTrue(rows(.food, in: snapshot).allSatisfy {
            cell("config_scope", in: $0) == .text("selected")
        })
        XCTAssertTrue(rows(.recipe, in: snapshot).allSatisfy {
            cell("config_scope", in: $0) == .text("selected")
        })
        XCTAssertFalse(reader.hasChanges)
    }

    func testSelectedNutritionFailsClosedOnMealReferencesAndDuplicateConfiguration() async throws {
        let instant = try date("2024-06-01T12:00:00Z")
        let interval = ReportDateInterval(
            start: instant.addingTimeInterval(-1),
            endExclusive: instant.addingTimeInterval(1)
        )

        let missingContainer = try ModelContainerFactory.make(for: .inMemory)
        let missingWriter = ModelContext(missingContainer)
        let day = DailyNutritionLog(
            id: id(920), createdAt: instant, updatedAt: instant, date: instant
        )
        let missingFoodID = id(921)
        let meal = MealEntry(
            id: id(922), createdAt: instant, updatedAt: instant,
            foodId: missingFoodID, quantity: 1, loggedAt: instant,
            dailyNutritionLog: day
        )
        day.mealEntries = [meal]
        missingWriter.insert(day)
        missingWriter.insert(meal)
        try missingWriter.save()
        let missingReader = ModelContext(missingContainer)

        do {
            _ = try await SwiftDataReportsRepository(
                modelContext: missingReader,
                calendar: utcCalendar()
            ).fetchExportSnapshot(in: interval, modules: [.nutrition])
            XCTFail("Expected the selected meal's missing food reference to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? ReportsExportRepositoryError,
                .missingReference(
                    sourceType: .mealEntry,
                    sourceID: meal.id,
                    targetType: .food,
                    targetID: missingFoodID
                )
            )
        }
        XCTAssertFalse(missingReader.hasChanges)

        let duplicateContainer = try ModelContainerFactory.make(for: .inMemory)
        let duplicateWriter = ModelContext(duplicateContainer)
        let duplicateID = id(923)
        duplicateWriter.insert(Food(
            id: duplicateID, createdAt: instant, updatedAt: instant,
            name: "First", servingSize: 1, servingUnit: "g"
        ))
        duplicateWriter.insert(Food(
            id: duplicateID, createdAt: instant, updatedAt: instant,
            name: "Second", servingSize: 1, servingUnit: "g"
        ))
        try duplicateWriter.save()
        let duplicateReader = ModelContext(duplicateContainer)

        do {
            _ = try await SwiftDataReportsRepository(
                modelContext: duplicateReader,
                calendar: utcCalendar()
            ).fetchExportSnapshot(in: interval, modules: [.nutrition])
            XCTFail("Expected duplicate selected Food configuration to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? ReportsExportRepositoryError,
                .duplicateRecord(recordType: .food, id: duplicateID, count: 2)
            )
        }
        XCTAssertFalse(duplicateReader.hasChanges)
    }

    func testExplicitProfileAndSystemConfigurationUsesSelectedScope() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let instant = try date("2024-06-01T12:00:00Z")
        let graph = try completeGraph(at: instant)
        insertTrainingAndReferencedConfiguration(graph, into: writer)
        writer.insert(graph.appReminder)
        writer.insert(graph.setting)
        try writer.save()
        let reader = ModelContext(container)

        let snapshot = try await SwiftDataReportsRepository(
            modelContext: reader,
            calendar: utcCalendar()
        ).fetchExportSnapshot(
            in: ReportDateInterval(
                start: instant.addingTimeInterval(10),
                endExclusive: instant.addingTimeInterval(20)
            ),
            modules: [.profileProgram, .system]
        )

        XCTAssertEqual(snapshot.tables.map(\.module), [.profileProgram, .system])
        XCTAssertEqual(snapshot.tables.flatMap(\.rows).compactMap(recordType), [
            "cooldown_item", "exercise_template", "program", "program_phase",
            "program_state", "user_profile", "warmup_item", "workout_day_template",
            "app_reminder", "app_setting",
        ])
        XCTAssertTrue(snapshot.tables.flatMap(\.rows).allSatisfy {
            cell("config_scope", in: $0) == .text("selected")
        })
        XCTAssertFalse(reader.hasChanges)
    }

    func testProgramStateRequiredReferencesFailClosedWhenSelectedOrTransitivelyReferenced() async throws {
        let instant = try date("2024-06-01T12:00:00Z")
        let missingProgramID = id(940)
        let selectedMissingProgramOptional = try await programStateReferenceError(
            at: instant,
            modules: [.profileProgram]
        ) { graph, _ in
            graph.state.programId = missingProgramID
        }
        let selectedMissingProgram = try XCTUnwrap(selectedMissingProgramOptional)
        XCTAssertEqual(
            selectedMissingProgram,
            .missingReference(
                sourceType: .programState, sourceID: id(4), targetType: .program,
                targetID: missingProgramID
            )
        )

        let missingPhaseID = id(941)
        let selectedMissingPhaseOptional = try await programStateReferenceError(
            at: instant,
            modules: [.profileProgram]
        ) { graph, _ in
            graph.state.currentPhaseId = missingPhaseID
        }
        let selectedMissingPhase = try XCTUnwrap(selectedMissingPhaseOptional)
        XCTAssertEqual(
            selectedMissingPhase,
            .missingReference(
                sourceType: .programState, sourceID: id(4), targetType: .programPhase,
                targetID: missingPhaseID
            )
        )

        let otherProgramID = id(942)
        let otherPhaseID = id(943)
        let selectedMismatchOptional = try await programStateReferenceError(
            at: instant,
            modules: [.profileProgram]
        ) { graph, writer in
            let otherProgram = Program(
                id: otherProgramID, createdAt: instant, updatedAt: instant,
                name: "Other", descriptionText: "other"
            )
            let otherPhase = ProgramPhase(
                id: otherPhaseID, createdAt: instant, updatedAt: instant,
                name: "Other phase", program: otherProgram
            )
            otherProgram.programPhases = [otherPhase]
            graph.state.currentPhaseId = otherPhase.id
            writer.insert(otherProgram)
            writer.insert(otherPhase)
        }
        let selectedMismatch = try XCTUnwrap(selectedMismatchOptional)
        XCTAssertEqual(
            selectedMismatch,
            .programStatePhaseProgramMismatch(
                stateID: id(4), programID: id(2), phaseID: otherPhaseID,
                phaseProgramID: otherProgramID
            )
        )

        let referencedMissingPhaseOptional = try await programStateReferenceError(
            at: instant,
            modules: [.training]
        ) { graph, _ in
            graph.state.currentPhaseId = missingPhaseID
        }
        let referencedMissingPhase = try XCTUnwrap(referencedMissingPhaseOptional)
        XCTAssertEqual(referencedMissingPhase, selectedMissingPhase)

        let referencedMismatchOptional = try await programStateReferenceError(
            at: instant,
            modules: [.training]
        ) { graph, writer in
            let otherProgram = Program(
                id: otherProgramID, createdAt: instant, updatedAt: instant,
                name: "Other", descriptionText: "other"
            )
            let otherPhase = ProgramPhase(
                id: otherPhaseID, createdAt: instant, updatedAt: instant,
                name: "Other phase", program: otherProgram
            )
            otherProgram.programPhases = [otherPhase]
            graph.state.currentPhaseId = otherPhase.id
            writer.insert(otherProgram)
            writer.insert(otherPhase)
        }
        let referencedMismatch = try XCTUnwrap(referencedMismatchOptional)
        XCTAssertEqual(referencedMismatch, selectedMismatch)
    }

    func testIrrelevantCorruptProgressPayloadDoesNotPoisonButSelectedPayloadFailsTyped() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let start = try date("2024-06-01T00:00:00Z")
        let end = try date("2024-06-02T00:00:00Z")
        let corruptID = id(801)
        writer.insert(WorkoutSessionProgress(
            id: corruptID,
            createdAt: start,
            updatedAt: start.addingTimeInterval(1),
            workoutSessionId: id(802),
            completedWarmupItemIdsData: Data("not-json".utf8),
            completedCooldownItemIdsData: WorkoutSessionProgressCodec.emptyPayload
        ))
        writer.insert(WorkoutSessionProgress(
            id: id(803),
            createdAt: end,
            updatedAt: end,
            workoutSessionId: id(804),
            completedWarmupItemIdsData: Data("also-not-json".utf8),
            completedCooldownItemIdsData: WorkoutSessionProgressCodec.emptyPayload
        ))
        writer.insert(BodyMetric(
            id: id(805), createdAt: start, updatedAt: start,
            date: start, type: .weight, value: 80, unit: "kg"
        ))
        try writer.save()
        let reader = ModelContext(container)
        let repository = SwiftDataReportsRepository(modelContext: reader, calendar: utcCalendar())
        let interval = ReportDateInterval(start: start, endExclusive: end)

        let metrics = try await repository.fetchExportSnapshot(in: interval, modules: [.metrics])
        XCTAssertEqual(rows(.bodyMetric, in: metrics).count, 1)

        do {
            _ = try await repository.fetchExportSnapshot(in: interval, modules: [.training])
            XCTFail("Expected selected progress payload to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? ReportsExportRepositoryError,
                .invalidWorkoutSessionProgress(
                    id: corruptID,
                    field: .completedWarmupItemIDs,
                    reason: .malformedPayload
                )
            )
        }
        XCTAssertFalse(reader.hasChanges)
    }

    func testEmptySelectionAndSelectedEmptyModuleRemainDistinct() async throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let reader = ModelContext(container)
        let repository = SwiftDataReportsRepository(modelContext: reader, calendar: utcCalendar())
        let interval = ReportDateInterval(
            start: Date(timeIntervalSince1970: 0),
            endExclusive: Date(timeIntervalSince1970: 1)
        )

        let none = try await repository.fetchExportSnapshot(in: interval, modules: [])
        let health = try await repository.fetchExportSnapshot(in: interval, modules: [.health])

        XCTAssertEqual(none.tables, [])
        XCTAssertEqual(none.selectedModules, [])
        XCTAssertEqual(health.tables.map(\.module), [.health])
        XCTAssertEqual(health.tables.first?.columns, ExportSchemaV1.columns(for: .health))
        XCTAssertEqual(health.tables.first?.rows, [])
        XCTAssertFalse(reader.hasChanges)
    }

    private struct CompleteGraph {
        let profile: UserProfile
        let program: Program
        let phase: ProgramPhase
        let state: ProgramState
        let day: WorkoutDayTemplate
        let exercise: ExerciseTemplate
        let warmup: WarmupItem
        let cooldown: CooldownItem
        let session: WorkoutSession
        let set: SetLog
        let progress: WorkoutSessionProgress
        let food: Food
        let recipe: Recipe
        let nutritionDay: DailyNutritionLog
        let meal: MealEntry
        let body: BodyMetric
        let posture: PostureMetric
        let sleep: SleepLog
        let mood: MoodLog
        let healthReminder: HealthCheckReminder
        let bloodwork: BloodworkResult
        let photo: ProgressPhoto
        let appReminder: AppReminder
        let setting: AppSetting
    }

    private func completeGraph(at instant: Date) throws -> CompleteGraph {
        let profile = UserProfile(
            id: id(1), createdAt: instant, updatedAt: instant,
            displayName: "Fatih", heightCm: 180, startWeightKg: 90,
            targetWeightKg: 82, birthYear: 1990, unitsSystem: .metric,
            proteinTargetG: 160, calorieTarget: 2_400, carbTargetG: 250,
            fatTargetG: 70, programStartDate: instant, weeklyWorkoutTarget: 4
        )
        let program = Program(
            id: id(2), createdAt: instant, updatedAt: instant,
            name: "Temel", descriptionText: "Açıklama", isActive: true
        )
        let phase = ProgramPhase(
            id: id(3), createdAt: instant, updatedAt: instant,
            name: "Faz 1", orderIndex: 1, monthStart: 1, monthEnd: 3,
            trainingFocus: "güç", nutritionFocus: "protein", milestone: "başlangıç",
            entryCriteria: "hazır", program: program
        )
        let state = ProgramState(
            id: id(4), createdAt: instant, updatedAt: instant,
            programId: program.id, currentPhaseId: phase.id, phaseStartedAt: instant,
            trainingWeekIndex: 2, deloadStatus: .recommended, deloadReason: .scheduled,
            deloadUpdatedAt: instant, lastDeloadSkippedAt: instant,
            lastDeloadAction: .stay
        )
        let day = WorkoutDayTemplate(
            id: id(5), createdAt: instant, updatedAt: instant,
            name: "Gün A", orderIndex: 1, focus: "tam vücut", program: program
        )
        let exercise = ExerciseTemplate(
            id: id(6), createdAt: instant, updatedAt: instant,
            name: "Squat", orderIndex: 1, targetSets: 3, repLow: 5, repHigh: 8,
            rirLow: 1, rirHigh: 3, category: .compound, allowFailure: false,
            cues: "dizleri izle", safetyNote: "ağrıda dur", startingWeightKg: 40,
            progressionRule: .doubleProgression, measurementKind: .weightReps,
            supersetGroupId: id(600), supersetOrder: 1, workoutDayTemplate: day
        )
        let warmup = WarmupItem(
            id: id(7), createdAt: instant, updatedAt: instant,
            phase: .raise, movement: "yürü", dose: "5 dk", orderIndex: 1,
            workoutDayTemplate: day
        )
        let cooldown = CooldownItem(
            id: id(8), createdAt: instant, updatedAt: instant,
            movement: "nefes", dose: "2 dk", note: "yavaş", orderIndex: 1,
            workoutDayTemplate: day
        )
        program.workoutDayTemplates = [day]
        program.programPhases = [phase]
        day.exerciseTemplates = [exercise]
        day.warmupItems = [warmup]
        day.cooldownItems = [cooldown]

        let session = WorkoutSession(
            id: id(9), createdAt: instant, updatedAt: instant, date: instant,
            status: .completed, workoutDayTemplateId: day.id, perceivedRecovery: 8,
            note: "iyi", ohpSymptomResponse: .symptomFree, ohpSymptomCheckedAt: instant
        )
        let set = SetLog(
            id: id(10), createdAt: instant, updatedAt: instant,
            exerciseTemplateId: exercise.id, setIndex: 1, weightKg: 50,
            reps: 8, durationSec: 30, distanceSteps: 12,
            performedVariant: "tempo", rir: 2, isWarmupSet: false,
            completedAt: instant, workoutSession: session
        )
        session.setLogs = [set]
        let progress = WorkoutSessionProgress(
            id: id(11), createdAt: instant, updatedAt: instant,
            workoutSessionId: session.id, stage: .movement,
            currentExerciseTemplateId: exercise.id,
            completedWarmupItemIdsData: try WorkoutSessionProgressCodec.encode([warmup.id]),
            completedCooldownItemIdsData: try WorkoutSessionProgressCodec.encode([cooldown.id]),
            warmupDisposition: .completed, cooldownDisposition: .skipped
        )
        let food = Food(
            id: id(12), createdAt: instant, updatedAt: instant,
            name: "Yoğurt", brand: "Marka", servingSize: 200, servingUnit: "g",
            caloriesPerServing: 120, proteinG: 20, carbG: 8, fatG: 2,
            fiberG: 1, source: .userCreated
        )
        let category = try MealCategory(kind: .custom, customName: "Gece")
        let recipe = Recipe(
            id: id(13), createdAt: instant, updatedAt: instant,
            name: "Kase", category: category, servings: 2, isDirectMacros: true,
            caloriesTotal: 400, proteinTotalG: 40, carbTotalG: 30,
            fatTotalG: 10, note: "ev yapımı"
        )
        let nutritionDay = DailyNutritionLog(
            id: id(14), createdAt: instant, updatedAt: instant, date: instant
        )
        let meal = MealEntry(
            id: id(15), createdAt: instant, updatedAt: instant,
            category: category, recipeId: recipe.id, foodId: food.id,
            adhocName: "ek", quantity: 1.5, caloriesResolved: 300,
            proteinResolved: 30, carbResolved: 20, fatResolved: 8,
            loggedAt: instant, dailyNutritionLog: nutritionDay
        )
        nutritionDay.mealEntries = [meal]
        return CompleteGraph(
            profile: profile, program: program, phase: phase, state: state,
            day: day, exercise: exercise, warmup: warmup, cooldown: cooldown,
            session: session, set: set, progress: progress,
            food: food, recipe: recipe, nutritionDay: nutritionDay, meal: meal,
            body: BodyMetric(
                id: id(16), createdAt: instant, updatedAt: instant, date: instant,
                type: .custom, customName: "Boyun", value: 38, unit: "cm"
            ),
            posture: PostureMetric(
                id: id(17), createdAt: instant, updatedAt: instant, date: instant,
                wallTestPass: true, symptomScore: 2, region: "omuz", note: "iyi"
            ),
            sleep: SleepLog(
                id: id(18), createdAt: instant, updatedAt: instant, date: instant,
                durationHours: 7.5, quality: 4, note: "dinç"
            ),
            mood: MoodLog(
                id: id(19), createdAt: instant, updatedAt: instant, date: instant,
                moodScore: 4, moodTags: ["odak", "iyi"], energy: 5, note: "iyi"
            ),
            healthReminder: HealthCheckReminder(
                id: id(20), createdAt: instant, updatedAt: instant,
                name: "Kontrol", dueDate: instant, recurrence: .yearly, status: .pending
            ),
            bloodwork: BloodworkResult(
                id: id(21), createdAt: instant, updatedAt: instant, date: instant,
                marker: "D", value: 42, unit: "ng/mL", note: "takip"
            ),
            photo: ProgressPhoto(
                id: id(22), createdAt: instant, updatedAt: instant, date: instant,
                imageRef: "/private/secret.jpg", pose: .front, note: "özel not"
            ),
            appReminder: AppReminder(
                id: id(23), createdAt: instant, updatedAt: instant,
                type: .workout, schedule: "{\"hour\":9}", message: "Antrenman",
                isEnabled: true
            ),
            setting: AppSetting(
                id: id(24), createdAt: instant, updatedAt: instant,
                key: "theme", value: "dark"
            )
        )
    }

    private func insert(_ graph: CompleteGraph, into context: ModelContext) {
        insertTrainingAndReferencedConfiguration(graph, into: context)
        context.insert(graph.food)
        context.insert(graph.recipe)
        context.insert(graph.nutritionDay)
        context.insert(graph.meal)
        context.insert(graph.body)
        context.insert(graph.posture)
        context.insert(graph.sleep)
        context.insert(graph.mood)
        context.insert(graph.healthReminder)
        context.insert(graph.bloodwork)
        context.insert(graph.photo)
        context.insert(graph.appReminder)
        context.insert(graph.setting)
    }

    private func insertTrainingAndReferencedConfiguration(
        _ graph: CompleteGraph,
        into context: ModelContext
    ) {
        context.insert(graph.profile)
        context.insert(graph.program)
        context.insert(graph.phase)
        context.insert(graph.state)
        context.insert(graph.day)
        context.insert(graph.exercise)
        context.insert(graph.warmup)
        context.insert(graph.cooldown)
        context.insert(graph.session)
        context.insert(graph.set)
        context.insert(graph.progress)
    }

    private func trainingExportError(
        at instant: Date,
        configure: (CompleteGraph, ModelContext) throws -> Void
    ) async throws -> ReportsExportRepositoryError? {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let graph = try completeGraph(at: instant)
        try configure(graph, writer)
        insertTrainingAndReferencedConfiguration(graph, into: writer)
        try writer.save()
        let reader = ModelContext(container)

        do {
            _ = try await SwiftDataReportsRepository(
                modelContext: reader,
                calendar: utcCalendar()
            ).fetchExportSnapshot(
                in: ReportDateInterval(
                    start: instant.addingTimeInterval(-1),
                    endExclusive: instant.addingTimeInterval(1)
                ),
                modules: [.training]
            )
            return nil
        } catch let error as ReportsExportRepositoryError {
            return error
        }
    }

    private func programStateReferenceError(
        at instant: Date,
        modules: Set<ExportModuleV1>,
        configure: (CompleteGraph, ModelContext) throws -> Void
    ) async throws -> ReportsExportRepositoryError? {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let writer = ModelContext(container)
        let graph = try completeGraph(at: instant)
        try configure(graph, writer)
        insertTrainingAndReferencedConfiguration(graph, into: writer)
        try writer.save()
        let reader = ModelContext(container)

        do {
            _ = try await SwiftDataReportsRepository(
                modelContext: reader,
                calendar: utcCalendar()
            ).fetchExportSnapshot(
                in: ReportDateInterval(
                    start: instant.addingTimeInterval(-1),
                    endExclusive: instant.addingTimeInterval(1)
                ),
                modules: modules
            )
            return nil
        } catch let error as ReportsExportRepositoryError {
            return error
        }
    }

    private func rows(
        _ type: ExportRecordTypeV1,
        in snapshot: ExportSnapshotV1
    ) -> [ExportRowV1] {
        snapshot.tables.flatMap(\.rows).filter { recordType($0) == type.rawValue }
    }

    private func recordType(_ row: ExportRowV1) -> String? {
        guard case let .text(value)? = cell("record_type", in: row) else { return nil }
        return value
    }

    private func rowID(_ row: ExportRowV1) -> UUID? {
        guard case let .uuid(value)? = cell("id", in: row) else { return nil }
        return value
    }

    private func cell(_ name: String, in row: ExportRowV1) -> ExportCellV1? {
        row.cells.first { $0.columnName == name }?.value
    }

    private func graphSnapshot(_ graph: CompleteGraph) -> [String] {
        [
            graph.profile.displayName,
            graph.program.name,
            graph.phase.name,
            graph.day.name,
            graph.exercise.name,
            graph.warmup.movement,
            graph.cooldown.movement,
            graph.session.note ?? "nil",
            String(graph.set.reps ?? -1),
            graph.food.name,
            graph.recipe.name,
            graph.meal.adhocName ?? "nil",
            graph.photo.imageRef,
            graph.setting.value,
        ]
    }

    private func id(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", suffix))!
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func istanbulCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }
}
