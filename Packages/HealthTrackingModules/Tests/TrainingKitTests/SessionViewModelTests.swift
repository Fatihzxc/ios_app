import CoreModels
import Foundation
import TrainingKit
import XCTest

@MainActor
final class SessionViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 40_000)

    func testStartCreatesAndPersistsWarmupForANewSession() async {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: repository.plan.workoutDayID)

        let presentation = requireActive(viewModel.state)
        XCTAssertEqual(presentation.session.status, .inProgress)
        XCTAssertEqual(presentation.plan, repository.plan)
        XCTAssertEqual(presentation.progress.stage, .warmup)
        XCTAssertEqual(presentation.restoreSource, .inferredMissingProgress)
        XCTAssertEqual(repository.createRequests.count, 1)
        XCTAssertEqual(repository.transitions.map(\.status), [.inProgress])
        XCTAssertEqual(repository.progressUpdates.map(\.state.stage), [.warmup])
    }

    func testStartResumesStoredExerciseWithoutCreatingAnotherSession() async {
        let plan = makePlan()
        let repository = FakeSessionRepository(plan: plan)
        let session = makeSession(dayID: plan.workoutDayID)
        repository.inProgressSession = session
        repository.progress = WorkoutSessionProgressSnapshot(
            id: uuid("00000000-0000-0000-0000-000000000701"),
            createdAt: now,
            updatedAt: now,
            workoutSessionID: session.id,
            stage: .movement,
            currentExerciseTemplateID: plan.exercises[1].id,
            completedWarmupItemIDs: Set(plan.warmupItems.map(\.id)),
            warmupDisposition: .completed
        )
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: UUID())

        let presentation = requireActive(viewModel.state)
        XCTAssertEqual(presentation.session, session)
        XCTAssertEqual(presentation.progress.stage, .movement)
        XCTAssertEqual(presentation.currentExercise?.id, plan.exercises[1].id)
        XCTAssertEqual(presentation.restoreSource, .stored)
        XCTAssertTrue(repository.createRequests.isEmpty)
        XCTAssertTrue(repository.transitions.isEmpty)
        XCTAssertTrue(repository.progressUpdates.isEmpty)
    }

    func testWarmupExerciseCooldownAndSummaryNavigationPersistsEveryStage() async {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)

        await viewModel.toggleWarmupItem(id: repository.plan.warmupItems[0].id)
        XCTAssertEqual(
            requireActive(viewModel.state).progress.completedWarmupItemIDs,
            [repository.plan.warmupItems[0].id]
        )

        await viewModel.completeWarmup()
        var presentation = requireActive(viewModel.state)
        XCTAssertEqual(presentation.progress.stage, .movement)
        XCTAssertEqual(presentation.currentExercise?.id, repository.plan.exercises[0].id)
        XCTAssertEqual(presentation.progress.warmupDisposition, .completed)

        await viewModel.advanceExercise()
        presentation = requireActive(viewModel.state)
        XCTAssertEqual(presentation.currentExercise?.id, repository.plan.exercises[1].id)

        await viewModel.goBack()
        presentation = requireActive(viewModel.state)
        XCTAssertEqual(presentation.currentExercise?.id, repository.plan.exercises[0].id)

        await viewModel.advanceExercise()
        await viewModel.advanceExercise()
        presentation = requireActive(viewModel.state)
        XCTAssertEqual(presentation.progress.stage, .cooldown)

        await viewModel.toggleCooldownItem(id: repository.plan.cooldownItems[0].id)
        await viewModel.completeCooldown()
        presentation = requireActive(viewModel.state)
        XCTAssertEqual(presentation.progress.stage, .summary)
        XCTAssertEqual(presentation.progress.cooldownDisposition, .completed)
        XCTAssertEqual(presentation.session.status, .completed)
        XCTAssertEqual(
            repository.progressUpdates.map(\.state.stage),
            [.warmup, .warmup, .movement, .movement, .movement, .movement, .cooldown, .cooldown, .summary]
        )
        XCTAssertEqual(repository.transitions.map(\.status), [.inProgress, .completed])
    }

    func testSkipIntentsPersistExplicitChecklistDispositions() async {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)

        await viewModel.skipWarmup()
        var presentation = requireActive(viewModel.state)
        XCTAssertEqual(presentation.progress.stage, .movement)
        XCTAssertEqual(presentation.progress.warmupDisposition, .skipped)

        await viewModel.advanceExercise()
        await viewModel.advanceExercise()
        await viewModel.skipCooldown()
        presentation = requireActive(viewModel.state)
        XCTAssertEqual(presentation.progress.stage, .summary)
        XCTAssertEqual(presentation.progress.cooldownDisposition, .skipped)
        XCTAssertEqual(presentation.session.status, .completed)
    }

    func testIncompleteFinishKeepsValidSetsAndNeverCreatesPlaceholderSets() async {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        await viewModel.skipWarmup()

        XCTAssertEqual(viewModel.currentSetDraft?.measurement.weightKg, 10)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.reps, 8)
        await viewModel.saveCurrentSet()
        XCTAssertEqual(repository.saveSetRequests.count, 1)
        XCTAssertEqual(requireActive(viewModel.state).setLogs.count, 1)

        await viewModel.finishIncomplete()

        let presentation = requireActive(viewModel.state)
        XCTAssertEqual(presentation.progress.stage, .summary)
        XCTAssertEqual(presentation.session.status, .completed)
        XCTAssertEqual(presentation.setLogs.count, 1)
        XCTAssertEqual(repository.saveSetRequests.count, 1)
    }

    func testFinishingSessionMapsOnlyATrueRecordIntoTheSummaryPresentation() async {
        let plan = makePlan()
        let repository = FakeSessionRepository(plan: plan)
        let exercise = plan.exercises[0]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                measurements: [.init(weightKg: 10, reps: 10, rir: 1)]
            )
        ]
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        viewModel.currentSetDraft?.measurement.weightKg = 20
        viewModel.currentSetDraft?.measurement.reps = 10

        await viewModel.saveCurrentSet()
        await viewModel.finishIncomplete()

        let summary = requireActive(viewModel.state)
        XCTAssertEqual(summary.progress.stage, .summary)
        XCTAssertEqual(summary.personalRecords.records.count, 1)
        XCTAssertEqual(summary.personalRecords.records.first?.exerciseID, exercise.id)
        XCTAssertEqual(
            summary.personalRecords.records.first?.kind,
            .weightedEstimatedOneRepMax
        )
        XCTAssertTrue(summary.personalRecords.shouldEmitSuccessFeedback)
    }

    func testDeleteRequiresExplicitConfirmationAndIsIdempotentAtViewModelBoundary() async {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        let sessionID = requireActive(viewModel.state).session.id

        viewModel.requestDeletion()
        XCTAssertTrue(viewModel.isDeleteConfirmationPresented)
        XCTAssertTrue(repository.deletedSessionIDs.isEmpty)

        viewModel.cancelDeletion()
        XCTAssertFalse(viewModel.isDeleteConfirmationPresented)
        viewModel.requestDeletion()
        await viewModel.confirmDeletion()

        XCTAssertEqual(repository.deletedSessionIDs, [sessionID])
        XCTAssertEqual(viewModel.state, .dismissed)
        XCTAssertFalse(viewModel.isDeleteConfirmationPresented)
    }

    func testSetSaveFailurePreservesDraftAndRetriesTheExactRequest() async {
        let repository = FakeSessionRepository(plan: makePlan())
        repository.saveSetOutcomes = [.failure(FakeSessionError.save), .success(())]
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        await viewModel.skipWarmup()
        let originalMeasurement = viewModel.currentSetDraft?.measurement

        await viewModel.saveCurrentSet()

        XCTAssertEqual(viewModel.setSaveState, .repositoryFailed)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement, originalMeasurement)
        XCTAssertEqual(repository.saveSetRequests.count, 1)
        let failedRequest = repository.saveSetRequests[0]

        await viewModel.retrySetSave()

        XCTAssertEqual(viewModel.setSaveState, .saved(setID: failedRequest.id))
        XCTAssertEqual(repository.saveSetRequests.count, 2)
        XCTAssertEqual(repository.saveSetRequests[0], repository.saveSetRequests[1])
        XCTAssertEqual(requireActive(viewModel.state).setLogs.map(\.id), [failedRequest.id])
    }

    func testDraftAndRecommendationAdaptAcrossEveryMeasurementFamily() async {
        let plan = makeMeasurementFamilyPlan()
        let repository = FakeSessionRepository(plan: plan)
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()

        let expected: [(ExerciseMeasurementKind, Set<SetDraft.Field>)] = [
            (.weightReps, [.weightKg, .reps, .performedVariant, .rir]),
            (.reps, [.weightKg, .reps, .performedVariant, .rir]),
            (.duration, [.durationSec, .performedVariant, .rir]),
            (.steps, [.weightKg, .distanceSteps, .performedVariant, .rir]),
            (.quality, [.reps, .durationSec, .performedVariant, .rir]),
        ]

        for (index, expectation) in expected.enumerated() {
            let presentation = requireActive(viewModel.state)
            XCTAssertEqual(presentation.currentExercise?.measurementKind, expectation.0)
            XCTAssertEqual(viewModel.currentSetDraft?.enabledFields, expectation.1)
            XCTAssertEqual(viewModel.recommendationReason, .templateStartingValues)
            if index < expected.count - 1 {
                await viewModel.advanceExercise()
            }
        }
    }

    func testSameSessionSetBecomesNextDraftPrefillWithSpecificReason() async {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        await viewModel.skipWarmup()
        viewModel.currentSetDraft?.measurement.weightKg = 12.5
        viewModel.currentSetDraft?.measurement.reps = 9
        viewModel.currentSetDraft?.selectRIR(2)

        await viewModel.saveCurrentSet()

        XCTAssertEqual(viewModel.currentSetDraft?.setIndex, 2)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.weightKg, 12.5)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.reps, 9)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.rir, 2)
        XCTAssertEqual(viewModel.recommendationReason, .sameSessionPrevious)
    }

    func testStrictDoubleProgressionMapsCompletedHistoryToGuidanceWithoutWriting() async {
        let plan = makePlan()
        let repository = FakeSessionRepository(plan: plan)
        let exercise = plan.exercises[0]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                measurements: [
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 0),
                ]
            ),
        ]
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()

        XCTAssertEqual(viewModel.currentSetDraft?.prefillSource, .guidance)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.weightKg, 12.5)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.reps, 8)
        XCTAssertEqual(viewModel.recommendationReason, .doubleProgressionIncrease)
        XCTAssertTrue(repository.saveSetRequests.isEmpty)
    }

    func testMissingRIRMapsToSpecificHoldReasonAndNeverAddsLoad() async {
        let plan = makePlan()
        let repository = FakeSessionRepository(plan: plan)
        let exercise = plan.exercises[0]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                measurements: [
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: nil),
                ]
            ),
        ]
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()

        XCTAssertEqual(viewModel.currentSetDraft?.prefillSource, .guidance)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.weightKg, 10)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.reps, 12)
        XCTAssertEqual(
            viewModel.recommendationReason,
            .doubleProgressionHold(.missingRIR)
        )
        XCTAssertTrue(repository.saveSetRequests.isEmpty)
    }

    func testEquipmentCeilingComposesAfterProgressionAndClampsTheDraftToTwenty() async {
        let plan = makePlan()
        let repository = FakeSessionRepository(plan: plan)
        let exercise = plan.exercises[0]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                measurements: [
                    .init(weightKg: 20, reps: 12, rir: 1),
                    .init(weightKg: 20, reps: 12, rir: 0),
                ]
            ),
        ]
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()

        XCTAssertEqual(viewModel.currentSetDraft?.measurement.weightKg, 20)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.reps, 8)
        XCTAssertEqual(
            viewModel.recommendationReason,
            .equipmentCeiling(
                .init(weightKg: 20, phaseFocusApplied: false)
            )
        )
        XCTAssertTrue(repository.saveSetRequests.isEmpty)
    }

    func testPhaseThreeBoneFocusUsesTheRealPhaseAndExistingTemplateLowerBound() async {
        let plan = makeBoneFocusPlan()
        let repository = FakeSessionRepository(plan: plan)
        repository.configureProgram(week: 28, phaseOrderIndex: 3)
        let exercise = plan.exercises[0]
        let history = makeCompletedHistory(
            dayID: plan.workoutDayID,
            exerciseID: exercise.id,
            measurements: [
                .init(weightKg: 10, reps: 11, rir: 1),
                .init(weightKg: 10, reps: 11, rir: 1),
            ]
        )
        repository.completedExerciseHistory[exercise.id] = [history]
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()

        XCTAssertEqual(viewModel.currentSetDraft?.measurement.weightKg, 10)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.reps, exercise.repLow)
        XCTAssertEqual(
            viewModel.recommendationReason,
            .phaseTrainingFocus(.boneFocusLowerBound)
        )
        XCTAssertEqual(repository.completedExerciseHistory[exercise.id], [history])
        XCTAssertTrue(repository.saveSetRequests.isEmpty)
    }

    func testNonDoubleProgressionFallsBackToPriorSessionSameSetIndex() async {
        let plan = makeMeasurementFamilyPlan()
        let repository = FakeSessionRepository(plan: plan)
        let exercise = plan.exercises[1]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                measurements: [
                    .init(reps: 9, performedVariant: "Nötr tutuş", rir: 2),
                ]
            ),
        ]
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        await viewModel.advanceExercise()

        XCTAssertEqual(viewModel.currentSetDraft?.prefillSource, .priorSessionSameIndex)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.reps, 9)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.performedVariant, "Nötr tutuş")
        XCTAssertEqual(viewModel.recommendationReason, .priorSessionSameIndex)
    }

    func testBodyweightHistoryMapsSameVariantWithoutInventingExternalLoad() async {
        let plan = makePlan()
        let repository = FakeSessionRepository(plan: plan)
        let exercise = plan.exercises[1]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                measurements: [
                    .init(reps: 8, performedVariant: "bant-yesil", rir: 2),
                    .init(reps: 10, performedVariant: "bant-yesil", rir: 1),
                ]
            ),
        ]
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        await viewModel.advanceExercise()

        XCTAssertEqual(viewModel.currentSetDraft?.prefillSource, .guidance)
        XCTAssertNil(viewModel.currentSetDraft?.measurement.weightKg)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.reps, 12)
        XCTAssertEqual(
            viewModel.currentSetDraft?.measurement.performedVariant,
            "bant-yesil"
        )
        XCTAssertEqual(viewModel.recommendationReason, .bodyweight(.buildRepetitions))
        XCTAssertTrue(repository.saveSetRequests.isEmpty)
    }

    func testWeeklyPallofSuggestionExposesChoicesAndPersistsExplicitOverride() async {
        let plan = makePallofPlan()
        let repository = FakeSessionRepository(plan: plan)
        let exercise = plan.exercises[0]
        repository.weeklyPallofHistory = WeeklyPallofHistorySnapshot(
            eligibleExerciseTemplateIDs: [exercise.id, UUID()],
            completions: []
        )
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()

        XCTAssertEqual(viewModel.currentVariantOptions, [.pallof, .plank])
        XCTAssertEqual(viewModel.currentSetDraft?.prefillSource, .guidance)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.durationSec, 30)
        XCTAssertNil(viewModel.currentSetDraft?.measurement.weightKg)
        XCTAssertNil(viewModel.currentSetDraft?.measurement.reps)
        XCTAssertNil(viewModel.currentSetDraft?.measurement.distanceSteps)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.performedVariant, "pallof")
        XCTAssertEqual(viewModel.recommendationReason, .weeklyPallof(.pallofDue))

        viewModel.selectPerformedVariant(.plank)
        await viewModel.saveCurrentSet()

        XCTAssertEqual(repository.saveSetRequests.count, 1)
        XCTAssertEqual(
            repository.saveSetRequests[0].measurement.performedVariant,
            "plank"
        )
        XCTAssertNil(repository.saveSetRequests[0].measurement.reps)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.performedVariant, "plank")
    }

    func testOHPQuestionBlocksWarmupWritesPriorSessionAndThenAllowsQualifiedIncrease() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        repository.configureProgram(week: 3)
        let exercise = plan.exercises[0]
        let prior = makeCompletedHistory(
            dayID: plan.workoutDayID,
            exerciseID: exercise.id,
            ohpSymptomResponse: .notAsked,
            measurements: [
                .init(weightKg: 10, reps: 12, rir: 1),
                .init(weightKg: 10, reps: 12, rir: 1),
                .init(weightKg: 10, reps: 12, rir: 1),
            ]
        )
        repository.completedExerciseHistory[exercise.id] = [prior]
        var safetyContexts: [TrainingSymptomSafetyContext] = []
        let viewModel = SessionViewModel(
            repository: repository,
            now: { self.now },
            symptomSafetyPresentationProvider: { context in
                safetyContexts.append(context)
                guard context == .priorOverheadPressResponse(.notAsked) else { return nil }
                return self.missingAnswerSafetyPresentation
            }
        )

        await viewModel.start(workoutDayID: plan.workoutDayID)

        XCTAssertEqual(safetyContexts.last, .priorOverheadPressResponse(.notAsked))
        XCTAssertEqual(
            viewModel.symptomSafetyPresentation,
            missingAnswerSafetyPresentation
        )
        XCTAssertEqual(
            viewModel.ohpSafetyState,
            .awaitingPreviousSessionResponse(
                sessionID: prior.session.id,
                entryVariant: .standingNeutral
            )
        )
        await viewModel.skipWarmup()
        XCTAssertEqual(requireActive(viewModel.state).progress.stage, .warmup)

        await viewModel.answerPreviousOHPSymptom(.symptomFree)

        XCTAssertEqual(
            repository.ohpSymptomUpdates,
            [
                .init(
                    id: prior.session.id,
                    response: .symptomFree,
                    date: now
                ),
            ]
        )
        XCTAssertEqual(
            viewModel.ohpSafetyState,
            .ready(entryVariant: .standingNeutral, loadIncreasePolicy: .allowed)
        )
        XCTAssertNil(
            viewModel.symptomSafetyPresentation,
            "An explicit symptom-free answer must clear only the fail-closed missing-answer L2."
        )

        await viewModel.skipWarmup()

        XCTAssertEqual(viewModel.currentSetDraft?.measurement.weightKg, 12.5)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.reps, 8)
        XCTAssertEqual(
            viewModel.currentSetDraft?.measurement.performedVariant,
            "standing-neutral"
        )
        XCTAssertEqual(viewModel.recommendationReason, .ohp(.increaseAllowed))
    }

    func testStoredPriorSymptomsAndUncertaintyStopOHPAtTheSafeAlternative() async {
        for response in [OHPSymptomResponse.symptomsPresent, .uncertain] {
            let plan = makeOHPPlan()
            let repository = FakeSessionRepository(plan: plan)
            repository.configureProgram(week: 3)
            let exercise = plan.exercises[0]
            repository.completedExerciseHistory[exercise.id] = [
                makeCompletedHistory(
                    dayID: plan.workoutDayID,
                    exerciseID: exercise.id,
                    ohpSymptomResponse: response,
                    measurements: [
                        .init(weightKg: 10, reps: 12, rir: 1),
                        .init(weightKg: 10, reps: 12, rir: 1),
                        .init(weightKg: 10, reps: 12, rir: 1),
                    ]
                ),
            ]
            let viewModel = SessionViewModel(
                repository: repository,
                now: { self.now },
                symptomSafetyPresentationProvider: { context in
                    guard context == .priorOverheadPressResponse(response) else { return nil }
                    return self.missingAnswerSafetyPresentation
                }
            )

            await viewModel.start(workoutDayID: plan.workoutDayID)
            await viewModel.skipWarmup()

            XCTAssertEqual(
                viewModel.ohpSafetyState,
                .stopped(alternative: repository.ohpSafeAlternative),
                "Stored prior \(response) must stop OHP instead of merely holding its load."
            )
            XCTAssertEqual(viewModel.displayedExercise, repository.ohpSafeAlternative)
            XCTAssertFalse(viewModel.canReportCurrentOHPSymptom)
            XCTAssertEqual(
                viewModel.symptomSafetyPresentation,
                missingAnswerSafetyPresentation
            )
        }
    }

    func testAnsweringPriorSymptomsOrUncertaintyStopsOHPAtTheSafeAlternative() async {
        for response in [OHPSymptomResponse.symptomsPresent, .uncertain] {
            let plan = makeOHPPlan()
            let repository = FakeSessionRepository(plan: plan)
            repository.configureProgram(week: 3)
            let exercise = plan.exercises[0]
            let prior = makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                ohpSymptomResponse: .notAsked,
                measurements: [
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                ]
            )
            repository.completedExerciseHistory[exercise.id] = [prior]
            let viewModel = SessionViewModel(
                repository: repository,
                now: { self.now },
                symptomSafetyPresentationProvider: { _ in
                    self.missingAnswerSafetyPresentation
                }
            )

            await viewModel.start(workoutDayID: plan.workoutDayID)
            await viewModel.answerPreviousOHPSymptom(response)
            await viewModel.skipWarmup()

            XCTAssertEqual(
                repository.ohpSymptomUpdates,
                [.init(id: prior.session.id, response: response, date: now)]
            )
            XCTAssertEqual(
                viewModel.ohpSafetyState,
                .stopped(alternative: repository.ohpSafeAlternative)
            )
            XCTAssertEqual(viewModel.displayedExercise, repository.ohpSafeAlternative)
            XCTAssertFalse(viewModel.canReportCurrentOHPSymptom)
            XCTAssertEqual(
                viewModel.symptomSafetyPresentation,
                missingAnswerSafetyPresentation
            )
        }
    }

    func testOHPFirstSessionAndUncertainHistoryNeverIncreaseLoad() async {
        let firstPlan = makeOHPPlan()
        let firstRepository = FakeSessionRepository(plan: firstPlan)
        firstRepository.configureProgram(week: 5)
        let firstViewModel = makeViewModel(firstRepository)

        await firstViewModel.start(workoutDayID: firstPlan.workoutDayID)
        XCTAssertEqual(
            firstViewModel.ohpSafetyState,
            .ready(
                entryVariant: .standingStandard,
                loadIncreasePolicy: .blocked(.firstSession)
            )
        )
        await firstViewModel.skipWarmup()
        XCTAssertEqual(firstViewModel.currentSetDraft?.measurement.weightKg, 10)
        XCTAssertEqual(firstViewModel.currentSetDraft?.measurement.reps, 8)
        XCTAssertEqual(
            firstViewModel.currentSetDraft?.measurement.performedVariant,
            "standing-standard"
        )
        XCTAssertEqual(firstViewModel.recommendationReason, .ohp(.firstSession))

        let heldPlan = makeOHPPlan()
        let heldRepository = FakeSessionRepository(plan: heldPlan)
        heldRepository.configureProgram(week: 4)
        let heldExercise = heldPlan.exercises[0]
        heldRepository.completedExerciseHistory[heldExercise.id] = [
            makeCompletedHistory(
                dayID: heldPlan.workoutDayID,
                exerciseID: heldExercise.id,
                ohpSymptomResponse: .uncertain,
                measurements: [
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                ]
            ),
        ]
        var heldSafetyContexts: [TrainingSymptomSafetyContext] = []
        let heldViewModel = SessionViewModel(
            repository: heldRepository,
            now: { self.now },
            symptomSafetyPresentationProvider: { context in
                heldSafetyContexts.append(context)
                guard context == .priorOverheadPressResponse(.uncertain) else { return nil }
                return self.missingAnswerSafetyPresentation
            }
        )

        await heldViewModel.start(workoutDayID: heldPlan.workoutDayID)
        XCTAssertEqual(
            heldSafetyContexts.last,
            .priorOverheadPressResponse(.uncertain)
        )
        XCTAssertEqual(
            heldViewModel.symptomSafetyPresentation,
            missingAnswerSafetyPresentation
        )
        await heldViewModel.skipWarmup()

        XCTAssertEqual(
            heldViewModel.ohpSafetyState,
            .stopped(alternative: heldRepository.ohpSafeAlternative)
        )
        XCTAssertEqual(heldViewModel.displayedExercise, heldRepository.ohpSafeAlternative)
        XCTAssertEqual(
            heldViewModel.currentSetDraft?.exerciseTemplateID,
            heldRepository.ohpSafeAlternative.id
        )
        XCTAssertNotEqual(heldViewModel.currentSetDraft?.measurement.weightKg, 12.5)
        XCTAssertFalse(heldViewModel.canReportCurrentOHPSymptom)
        XCTAssertTrue(
            heldSafetyContexts.contains(.priorOverheadPressResponse(.uncertain))
        )
    }

    func testOHPCeilingRetainsTheSafetyReasonWhileClampingTheLoad() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        repository.configureProgram(week: 5)
        let exercise = plan.exercises[0]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                ohpSymptomResponse: .symptomFree,
                measurements: [
                    .init(weightKg: 20, reps: 12, rir: 1),
                    .init(weightKg: 20, reps: 12, rir: 1),
                    .init(weightKg: 20, reps: 12, rir: 1),
                ]
            ),
        ]
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()

        XCTAssertEqual(viewModel.currentSetDraft?.measurement.weightKg, 20)
        XCTAssertEqual(
            viewModel.recommendationReason,
            .equipmentCeiling(
                .init(
                    weightKg: 20,
                    phaseFocusApplied: false,
                    ohpReason: .increaseAllowed
                )
            )
        )
    }

    func testCurrentOHPSymptomWritesCurrentSessionAndRoutesOnlyTheExerciseToAlternative() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        let symptomClient = SymptomEventClientSpy()
        repository.configureProgram(week: 5)
        let exercise = plan.exercises[0]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                ohpSymptomResponse: .symptomFree,
                measurements: [
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                ]
            ),
        ]
        let viewModel = makeViewModel(
            repository,
            symptomEventClient: symptomClient
        )
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let currentSessionID = requireActive(viewModel.state).session.id

        await viewModel.reportCurrentOHPSymptom()

        XCTAssertEqual(
            repository.ohpSymptomUpdates.last,
            .init(id: currentSessionID, response: .symptomsPresent, date: now)
        )
        XCTAssertEqual(
            viewModel.ohpSafetyState,
            .stopped(alternative: repository.ohpSafeAlternative)
        )
        XCTAssertEqual(viewModel.displayedExercise?.id, repository.ohpSafeAlternative.id)
        XCTAssertEqual(
            viewModel.currentSetDraft?.exerciseTemplateID,
            repository.ohpSafeAlternative.id
        )
        XCTAssertEqual(
            requireActive(viewModel.state).progress.currentExerciseTemplateID,
            exercise.id,
            "The safety stop must not corrupt the persisted Day B exercise order."
        )
        XCTAssertEqual(
            requireActive(viewModel.state).session.ohpSymptomResponse,
            .symptomsPresent
        )
        let event = SymptomJournalEvent(
            id: currentSessionID,
            occurredAt: now,
            source: .overheadPressCurrentSymptom
        )
        XCTAssertEqual(symptomClient.events, [event])
        XCTAssertEqual(viewModel.symptomJournalState, .recorded(event: event))
    }

    func testCurrentOHPSymptomStopsBeforeTheRepositoryWriteCompletes() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        let symptomClient = SymptomEventClientSpy()
        repository.configureProgram(week: 5)
        let exercise = plan.exercises[0]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                ohpSymptomResponse: .symptomFree,
                measurements: [
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                ]
            ),
        ]
        repository.suspendNextOHPSymptomUpdate()
        let viewModel = SessionViewModel(
            repository: repository,
            now: { self.now },
            symptomEventClient: symptomClient,
            symptomSafetyPresentationProvider: { context in
                guard context == .currentOverheadPressResponse(.symptomsPresent) else {
                    return nil
                }
                return self.missingAnswerSafetyPresentation
            }
        )
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let currentSessionID = requireActive(viewModel.state).session.id
        let expectedRequest = SessionOHPSymptomWriteRequest(
            sessionID: currentSessionID,
            response: .symptomsPresent,
            reportedAt: now
        )
        let progressUpdateCount = repository.progressUpdates.count
        let transitionCount = repository.transitions.count
        let deletionCount = repository.deletedSessionIDs.count

        let report = Task { await viewModel.reportCurrentOHPSymptom() }
        await repository.waitUntilOHPSymptomUpdateIsSuspended()

        XCTAssertEqual(
            viewModel.ohpSymptomWriteState,
            .saving(request: expectedRequest)
        )
        XCTAssertNotNil(activePresentation(from: viewModel.state))
        XCTAssertEqual(
            viewModel.ohpSafetyState,
            .stopped(alternative: repository.ohpSafeAlternative)
        )
        XCTAssertEqual(viewModel.displayedExercise, repository.ohpSafeAlternative)
        XCTAssertFalse(viewModel.canReportCurrentOHPSymptom)
        XCTAssertEqual(
            requireActive(viewModel.state).session.ohpSymptomCheckedAt,
            expectedRequest.reportedAt
        )
        XCTAssertEqual(
            viewModel.symptomSafetyPresentation,
            missingAnswerSafetyPresentation
        )
        XCTAssertEqual(viewModel.symptomJournalState, .idle)
        XCTAssertTrue(symptomClient.events.isEmpty)
        XCTAssertTrue(viewModel.hasPendingCurrentOHPSymptomWrite)

        let stoppedState = viewModel.state
        await viewModel.advanceExercise()
        await viewModel.goBack()
        await viewModel.finishIncomplete()
        viewModel.requestDeletion()
        await viewModel.confirmDeletion()

        XCTAssertEqual(
            repository.progressUpdates.count,
            progressUpdateCount,
            "Pending current-symptom persistence must block exercise progress and completion."
        )
        XCTAssertEqual(repository.transitions.count, transitionCount)
        XCTAssertEqual(repository.deletedSessionIDs.count, deletionCount)
        XCTAssertEqual(viewModel.state, stoppedState)
        XCTAssertFalse(viewModel.isDeleteConfirmationPresented)
        XCTAssertEqual(viewModel.symptomJournalState, .idle)

        await viewModel.reportCurrentOHPSymptom()
        await viewModel.retryCurrentOHPSymptomWrite()
        XCTAssertEqual(
            repository.ohpSymptomUpdates,
            [expectedRequest.repositoryUpdate],
            "A pending exact write must reject a second write or retry."
        )
        XCTAssertTrue(symptomClient.events.isEmpty)

        repository.resumeSuspendedOHPSymptomUpdate()
        await report.value

        XCTAssertEqual(viewModel.ohpSymptomWriteState, .idle)
        XCTAssertFalse(viewModel.hasPendingCurrentOHPSymptomWrite)
        XCTAssertFalse(viewModel.isSessionRouteMutationInFlight)

        let progressCountAfterSymptomWrite = repository.progressUpdates.count
        await viewModel.advanceExercise()
        XCTAssertEqual(repository.progressUpdates.count, progressCountAfterSymptomWrite + 1)
        XCTAssertEqual(requireActive(viewModel.state).progress.stage, .cooldown)
        XCTAssertFalse(viewModel.isSessionRouteMutationInFlight)
    }

    func testAdvanceRouteFirstRejectsSymptomAndDuplicateRoutesUntilChosenProgressCompletes() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        configureCurrentOHPSymptomScenario(repository)
        let symptomClient = SymptomEventClientSpy()
        let viewModel = makeViewModel(repository, symptomEventClient: symptomClient)
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let safetyState = viewModel.ohpSafetyState
        let progressCount = repository.progressUpdates.count
        let transitionCount = repository.transitions.count
        repository.suspendNextProgressUpdate()

        let advance = Task { await viewModel.advanceExercise() }
        await repository.waitUntilProgressUpdateIsSuspended()

        XCTAssertTrue(viewModel.isSessionRouteMutationInFlight)
        XCTAssertFalse(viewModel.canReportCurrentOHPSymptom)
        XCTAssertEqual(repository.progress?.stage, .cooldown)
        await viewModel.reportCurrentOHPSymptom()
        await viewModel.advanceExercise()
        await viewModel.goBack()
        await viewModel.finishIncomplete()
        XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)
        XCTAssertTrue(symptomClient.events.isEmpty)
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .idle)
        XCTAssertEqual(viewModel.ohpSafetyState, safetyState)
        XCTAssertEqual(repository.progressUpdates.count, progressCount + 1)
        XCTAssertEqual(repository.transitions.count, transitionCount)

        repository.resumeSuspendedProgressUpdate()
        await advance.value

        XCTAssertFalse(viewModel.isSessionRouteMutationInFlight)
        XCTAssertEqual(requireActive(viewModel.state).progress.stage, .cooldown)
        XCTAssertEqual(repository.progress?.stage, .cooldown)
        XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)
        XCTAssertTrue(symptomClient.events.isEmpty)
    }

    func testGoBackRouteFirstRejectsSymptomUntilChosenProgressCompletes() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        configureCurrentOHPSymptomScenario(repository)
        let symptomClient = SymptomEventClientSpy()
        let viewModel = makeViewModel(repository, symptomEventClient: symptomClient)
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let safetyState = viewModel.ohpSafetyState
        let progressCount = repository.progressUpdates.count
        repository.suspendNextProgressUpdate()

        let goBack = Task { await viewModel.goBack() }
        await repository.waitUntilProgressUpdateIsSuspended()

        XCTAssertTrue(viewModel.isSessionRouteMutationInFlight)
        XCTAssertFalse(viewModel.canReportCurrentOHPSymptom)
        XCTAssertEqual(repository.progress?.stage, .warmup)
        await viewModel.reportCurrentOHPSymptom()
        await viewModel.goBack()
        XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)
        XCTAssertTrue(symptomClient.events.isEmpty)
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .idle)
        XCTAssertEqual(viewModel.ohpSafetyState, safetyState)
        XCTAssertEqual(repository.progressUpdates.count, progressCount + 1)

        repository.resumeSuspendedProgressUpdate()
        await goBack.value

        XCTAssertFalse(viewModel.isSessionRouteMutationInFlight)
        XCTAssertEqual(requireActive(viewModel.state).progress.stage, .warmup)
        XCTAssertEqual(repository.progress?.stage, .warmup)
        XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)
    }

    func testFinishRouteFirstKeepsTheLockThroughProgressAndTransition() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        configureCurrentOHPSymptomScenario(repository)
        let symptomClient = SymptomEventClientSpy()
        let viewModel = makeViewModel(repository, symptomEventClient: symptomClient)
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let progressCount = repository.progressUpdates.count
        let transitionCount = repository.transitions.count
        repository.suspendNextProgressUpdate()
        repository.suspendNextTransition()

        let finish = Task { await viewModel.finishIncomplete() }
        await repository.waitUntilProgressUpdateIsSuspended()

        XCTAssertTrue(viewModel.isSessionRouteMutationInFlight)
        XCTAssertFalse(viewModel.canReportCurrentOHPSymptom)
        XCTAssertEqual(repository.progress?.stage, .summary)
        await viewModel.reportCurrentOHPSymptom()
        XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)
        XCTAssertEqual(repository.progressUpdates.count, progressCount + 1)
        XCTAssertEqual(repository.transitions.count, transitionCount)

        repository.resumeSuspendedProgressUpdate()
        await repository.waitUntilTransitionIsSuspended()

        XCTAssertTrue(viewModel.isSessionRouteMutationInFlight)
        XCTAssertEqual(requireActive(viewModel.state).progress.stage, .summary)
        XCTAssertEqual(repository.transitions.count, transitionCount + 1)
        XCTAssertNil(repository.inProgressSession)
        await viewModel.reportCurrentOHPSymptom()
        XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)
        XCTAssertTrue(symptomClient.events.isEmpty)

        repository.resumeSuspendedTransition()
        await finish.value

        let completed = requireActive(viewModel.state)
        XCTAssertFalse(viewModel.isSessionRouteMutationInFlight)
        XCTAssertEqual(completed.progress.stage, .summary)
        XCTAssertEqual(completed.session.status, .completed)
        XCTAssertEqual(repository.progress?.stage, .summary)
        XCTAssertEqual(repository.transitions.count, transitionCount + 1)
        XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)
    }

    func testRouteLockClearsAfterAppliedProgressFailureWithoutAcceptingSymptom() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        configureCurrentOHPSymptomScenario(repository)
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        repository.progressUpdateOutcomes = [.failure(FakeSessionError.save)]
        repository.suspendNextProgressUpdate()

        let advance = Task { await viewModel.advanceExercise() }
        await repository.waitUntilProgressUpdateIsSuspended()
        XCTAssertTrue(viewModel.isSessionRouteMutationInFlight)
        await viewModel.reportCurrentOHPSymptom()
        XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)

        repository.resumeSuspendedProgressUpdate()
        await advance.value

        XCTAssertFalse(viewModel.isSessionRouteMutationInFlight)
        XCTAssertEqual(viewModel.state, .failed(.progress))
        XCTAssertEqual(repository.progress?.stage, .cooldown)
        XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)
    }

    func testCurrentOHPSymptomWriteFailureRetainsStopAndRetriesTheExactRequestOnce() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        repository.ohpSymptomUpdateOutcomes = [
            .failure(FakeSessionError.save),
            .success(()),
        ]
        let symptomClient = SymptomEventClientSpy()
        repository.configureProgram(week: 5)
        let exercise = plan.exercises[0]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                ohpSymptomResponse: .symptomFree,
                measurements: [
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                ]
            ),
        ]
        var clock = now
        let viewModel = SessionViewModel(
            repository: repository,
            now: { clock },
            symptomEventClient: symptomClient,
            symptomSafetyPresentationProvider: { context in
                guard context == .currentOverheadPressResponse(.symptomsPresent) else {
                    return nil
                }
                return self.missingAnswerSafetyPresentation
            }
        )
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let sessionID = requireActive(viewModel.state).session.id
        let request = SessionOHPSymptomWriteRequest(
            sessionID: sessionID,
            response: .symptomsPresent,
            reportedAt: now
        )

        await viewModel.reportCurrentOHPSymptom()

        XCTAssertNotNil(activePresentation(from: viewModel.state))
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .failed(request: request))
        XCTAssertEqual(
            viewModel.ohpSafetyState,
            .stopped(alternative: repository.ohpSafeAlternative)
        )
        XCTAssertEqual(viewModel.displayedExercise, repository.ohpSafeAlternative)
        XCTAssertFalse(viewModel.canReportCurrentOHPSymptom)
        XCTAssertEqual(
            requireActive(viewModel.state).session.ohpSymptomResponse,
            .symptomsPresent
        )
        XCTAssertEqual(
            requireActive(viewModel.state).session.ohpSymptomCheckedAt,
            request.reportedAt
        )
        XCTAssertEqual(
            viewModel.symptomSafetyPresentation,
            missingAnswerSafetyPresentation
        )
        XCTAssertEqual(repository.ohpSymptomUpdates, [request.repositoryUpdate])
        XCTAssertEqual(viewModel.symptomJournalState, .idle)
        XCTAssertTrue(symptomClient.events.isEmpty)
        XCTAssertTrue(viewModel.hasPendingCurrentOHPSymptomWrite)

        let failedStoppedState = viewModel.state
        let progressUpdateCount = repository.progressUpdates.count
        let transitionCount = repository.transitions.count
        await viewModel.advanceExercise()
        await viewModel.goBack()
        await viewModel.finishIncomplete()

        XCTAssertEqual(
            repository.progressUpdates.count,
            progressUpdateCount,
            "A failed pending write must keep route actions fail closed until exact retry succeeds."
        )
        XCTAssertEqual(repository.transitions.count, transitionCount)
        XCTAssertEqual(viewModel.state, failedStoppedState)
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .failed(request: request))
        XCTAssertEqual(viewModel.symptomJournalState, .idle)
        XCTAssertTrue(symptomClient.events.isEmpty)

        clock = now.addingTimeInterval(3_600)
        await viewModel.retryCurrentOHPSymptomWrite()

        let expectedEvent = SymptomJournalEvent(
            id: sessionID,
            occurredAt: request.reportedAt,
            source: .overheadPressCurrentSymptom
        )
        XCTAssertEqual(
            repository.ohpSymptomUpdates,
            [request.repositoryUpdate, request.repositoryUpdate],
            "Retry must preserve the original session, response, and timestamp."
        )
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .idle)
        XCTAssertFalse(viewModel.hasPendingCurrentOHPSymptomWrite)
        XCTAssertEqual(symptomClient.events, [expectedEvent])
        XCTAssertEqual(viewModel.symptomJournalState, .recorded(event: expectedEvent))

        await viewModel.retryCurrentOHPSymptomWrite()
        await viewModel.reportCurrentOHPSymptom()
        XCTAssertEqual(repository.ohpSymptomUpdates.count, 2)
        XCTAssertEqual(symptomClient.events, [expectedEvent])
    }

    func testDeletionFailurePreservesStoppedSymptomRetryAndExactRequest() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        configureCurrentOHPSymptomScenario(repository)
        repository.ohpSymptomUpdateOutcomes = [
            .failure(FakeSessionError.save),
            .success(()),
        ]
        repository.deleteOutcomes = [.failure(FakeSessionError.save)]
        let symptomClient = SymptomEventClientSpy()
        let viewModel = SessionViewModel(
            repository: repository,
            now: { self.now },
            symptomEventClient: symptomClient,
            symptomSafetyPresentationProvider: { context in
                guard context == .currentOverheadPressResponse(.symptomsPresent) else {
                    return nil
                }
                return self.missingAnswerSafetyPresentation
            }
        )
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let sessionID = requireActive(viewModel.state).session.id
        let request = SessionOHPSymptomWriteRequest(
            sessionID: sessionID,
            response: .symptomsPresent,
            reportedAt: now
        )
        await viewModel.reportCurrentOHPSymptom()
        let stoppedState = viewModel.state

        viewModel.requestDeletion()
        await viewModel.confirmDeletion()

        XCTAssertEqual(viewModel.state, stoppedState)
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .failed(request: request))
        XCTAssertTrue(viewModel.hasPendingCurrentOHPSymptomWrite)
        XCTAssertEqual(
            viewModel.ohpSafetyState,
            .stopped(alternative: repository.ohpSafeAlternative)
        )
        XCTAssertEqual(viewModel.symptomSafetyPresentation, missingAnswerSafetyPresentation)
        XCTAssertTrue(viewModel.hasSessionDeletionFailure)
        XCTAssertFalse(viewModel.isDeleteConfirmationPresented)
        XCTAssertTrue(repository.deletedSessionIDs.isEmpty)
        XCTAssertTrue(symptomClient.events.isEmpty)

        await viewModel.retryCurrentOHPSymptomWrite()

        XCTAssertEqual(
            repository.ohpSymptomUpdates,
            [request.repositoryUpdate, request.repositoryUpdate]
        )
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .idle)
        XCTAssertFalse(viewModel.hasPendingCurrentOHPSymptomWrite)
        XCTAssertNotNil(activePresentation(from: viewModel.state))
        XCTAssertEqual(
            viewModel.ohpSafetyState,
            .stopped(alternative: repository.ohpSafeAlternative)
        )
        XCTAssertEqual(symptomClient.events.count, 1)
    }

    func testSuccessfulDeletionIsTheOnlyDeletionPathThatDiscardsPendingSymptomRetry() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        configureCurrentOHPSymptomScenario(repository)
        repository.ohpSymptomUpdateOutcomes = [.failure(FakeSessionError.save)]
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let sessionID = requireActive(viewModel.state).session.id
        await viewModel.reportCurrentOHPSymptom()
        XCTAssertTrue(viewModel.hasPendingCurrentOHPSymptomWrite)

        viewModel.requestDeletion()
        await viewModel.confirmDeletion()

        XCTAssertEqual(repository.deletedSessionIDs, [sessionID])
        XCTAssertEqual(viewModel.state, .dismissed)
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .idle)
        XCTAssertFalse(viewModel.hasPendingCurrentOHPSymptomWrite)
        XCTAssertFalse(viewModel.hasSessionDeletionFailure)
    }

    func testDeleteFirstLeaseRejectsSymptomRoutesAndDuplicateDeleteUntilSuccess() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        configureCurrentOHPSymptomScenario(repository)
        let symptomClient = SymptomEventClientSpy()
        let viewModel = makeViewModel(repository, symptomEventClient: symptomClient)
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let sessionID = requireActive(viewModel.state).session.id
        let progressCount = repository.progressUpdates.count
        let transitionCount = repository.transitions.count
        repository.suspendNextDeletion()

        viewModel.requestDeletion()
        let deletion = Task { await viewModel.confirmDeletion() }
        await repository.waitUntilDeletionIsSuspended()

        XCTAssertTrue(viewModel.isSessionDeletionInFlight)
        XCTAssertFalse(viewModel.canReportCurrentOHPSymptom)
        await viewModel.reportCurrentOHPSymptom()
        await viewModel.advanceExercise()
        await viewModel.goBack()
        await viewModel.finishIncomplete()
        XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)
        XCTAssertTrue(symptomClient.events.isEmpty)
        XCTAssertEqual(repository.progressUpdates.count, progressCount)
        XCTAssertEqual(repository.transitions.count, transitionCount)

        viewModel.cancelDeletion()
        viewModel.requestDeletion()
        XCTAssertFalse(viewModel.isDeleteConfirmationPresented)
        await viewModel.confirmDeletion()
        XCTAssertEqual(repository.deleteAttempts, [sessionID])
        XCTAssertTrue(repository.deletedSessionIDs.isEmpty)

        repository.resumeSuspendedDeletion()
        await deletion.value

        XCTAssertFalse(viewModel.isSessionDeletionInFlight)
        XCTAssertEqual(repository.deleteAttempts, [sessionID])
        XCTAssertEqual(repository.deletedSessionIDs, [sessionID])
        XCTAssertEqual(viewModel.state, .dismissed)
        XCTAssertTrue(repository.ohpSymptomUpdates.isEmpty)
        XCTAssertTrue(symptomClient.events.isEmpty)
    }

    func testSuspendedDeletionFailureRetainsStoppedExactRetryUntilLeaseReleases() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        configureCurrentOHPSymptomScenario(repository)
        repository.ohpSymptomUpdateOutcomes = [
            .failure(FakeSessionError.save),
            .success(()),
        ]
        repository.deleteOutcomes = [.failure(FakeSessionError.save)]
        let symptomClient = SymptomEventClientSpy()
        let viewModel = SessionViewModel(
            repository: repository,
            now: { self.now },
            symptomEventClient: symptomClient,
            symptomSafetyPresentationProvider: { context in
                guard context == .currentOverheadPressResponse(.symptomsPresent) else {
                    return nil
                }
                return self.missingAnswerSafetyPresentation
            }
        )
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let sessionID = requireActive(viewModel.state).session.id
        let request = SessionOHPSymptomWriteRequest(
            sessionID: sessionID,
            response: .symptomsPresent,
            reportedAt: now
        )
        await viewModel.reportCurrentOHPSymptom()
        repository.suspendNextDeletion()

        viewModel.requestDeletion()
        let deletion = Task { await viewModel.confirmDeletion() }
        await repository.waitUntilDeletionIsSuspended()

        XCTAssertTrue(viewModel.isSessionDeletionInFlight)
        await viewModel.retryCurrentOHPSymptomWrite()
        XCTAssertEqual(repository.ohpSymptomUpdates, [request.repositoryUpdate])
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .failed(request: request))
        XCTAssertTrue(viewModel.hasPendingCurrentOHPSymptomWrite)

        repository.resumeSuspendedDeletion()
        await deletion.value

        XCTAssertFalse(viewModel.isSessionDeletionInFlight)
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .failed(request: request))
        XCTAssertEqual(
            viewModel.ohpSafetyState,
            .stopped(alternative: repository.ohpSafeAlternative)
        )
        XCTAssertEqual(viewModel.symptomSafetyPresentation, missingAnswerSafetyPresentation)
        XCTAssertTrue(viewModel.hasSessionDeletionFailure)
        XCTAssertTrue(repository.deletedSessionIDs.isEmpty)
        XCTAssertTrue(symptomClient.events.isEmpty)

        await viewModel.retryCurrentOHPSymptomWrite()

        XCTAssertEqual(
            repository.ohpSymptomUpdates,
            [request.repositoryUpdate, request.repositoryUpdate]
        )
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .idle)
        XCTAssertFalse(viewModel.hasPendingCurrentOHPSymptomWrite)
        XCTAssertEqual(symptomClient.events.count, 1)
    }

    func testRouteFirstLeaseRejectsDeletionRequestAndConfirmationBeforeRepositoryAwait() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        configureCurrentOHPSymptomScenario(repository)
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        repository.suspendNextProgressUpdate()

        let advance = Task { await viewModel.advanceExercise() }
        await repository.waitUntilProgressUpdateIsSuspended()

        XCTAssertTrue(viewModel.isSessionRouteMutationInFlight)
        viewModel.requestDeletion()
        XCTAssertFalse(viewModel.isDeleteConfirmationPresented)
        await viewModel.confirmDeletion()
        XCTAssertTrue(repository.deleteAttempts.isEmpty)
        XCTAssertTrue(repository.deletedSessionIDs.isEmpty)

        repository.resumeSuspendedProgressUpdate()
        await advance.value

        XCTAssertFalse(viewModel.isSessionRouteMutationInFlight)
        XCTAssertEqual(requireActive(viewModel.state).progress.stage, .cooldown)
        XCTAssertTrue(repository.deleteAttempts.isEmpty)
    }

    func testCancelledDeletionReleasesLeaseAndPreservesExactStoppedRetry() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        configureCurrentOHPSymptomScenario(repository)
        repository.ohpSymptomUpdateOutcomes = [
            .failure(FakeSessionError.save),
            .success(()),
        ]
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let sessionID = requireActive(viewModel.state).session.id
        let request = SessionOHPSymptomWriteRequest(
            sessionID: sessionID,
            response: .symptomsPresent,
            reportedAt: now
        )
        await viewModel.reportCurrentOHPSymptom()
        repository.suspendNextDeletion()

        viewModel.requestDeletion()
        let deletion = Task { await viewModel.confirmDeletion() }
        await repository.waitUntilDeletionIsSuspended()
        XCTAssertTrue(viewModel.isSessionDeletionInFlight)

        deletion.cancel()
        repository.resumeSuspendedDeletion()
        await deletion.value

        XCTAssertFalse(viewModel.isSessionDeletionInFlight)
        XCTAssertEqual(repository.deleteAttempts, [sessionID])
        XCTAssertTrue(repository.deletedSessionIDs.isEmpty)
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .failed(request: request))
        XCTAssertEqual(
            viewModel.ohpSafetyState,
            .stopped(alternative: repository.ohpSafeAlternative)
        )
        XCTAssertNotNil(activePresentation(from: viewModel.state))

        await viewModel.retryCurrentOHPSymptomWrite()
        XCTAssertEqual(viewModel.ohpSymptomWriteState, .idle)
        XCTAssertFalse(viewModel.hasPendingCurrentOHPSymptomWrite)
    }

    func testStartTailOwnsSessionUntilInitialProgressFinishesAndDeleteFirstRejectsRestart() async {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)
        repository.suspendNextProgressUpdate()

        let start = Task { await viewModel.start(workoutDayID: repository.plan.workoutDayID) }
        await repository.waitUntilProgressUpdateIsSuspended()

        XCTAssertEqual(viewModel.activeSessionMutationCount, 1)
        XCTAssertTrue(viewModel.isSessionMutationInFlight)
        await assertDeletionRejectedWhileSessionMutationOwned(viewModel, repository)

        repository.resumeSuspendedProgressUpdate()
        await start.value

        XCTAssertEqual(viewModel.activeSessionMutationCount, 0)
        XCTAssertFalse(viewModel.isSessionMutationInFlight)
        XCTAssertNotNil(activePresentation(from: viewModel.state))

        let createCount = repository.createRequests.count
        let transitionCount = repository.transitions.count
        let progressCount = repository.progressUpdates.count
        repository.suspendNextDeletion()
        viewModel.requestDeletion()
        let deletion = Task { await viewModel.confirmDeletion() }
        await repository.waitUntilDeletionIsSuspended()

        await viewModel.start(workoutDayID: repository.plan.workoutDayID)

        XCTAssertTrue(viewModel.isSessionDeletionInFlight)
        XCTAssertEqual(repository.createRequests.count, createCount)
        XCTAssertEqual(repository.transitions.count, transitionCount)
        XCTAssertEqual(repository.progressUpdates.count, progressCount)

        repository.resumeSuspendedDeletion()
        await deletion.value

        XCTAssertEqual(viewModel.state, .dismissed)
        XCTAssertFalse(viewModel.isSessionDeletionInFlight)
        XCTAssertEqual(viewModel.activeSessionMutationCount, 0)
    }

    func testRestoredStartKeepsItsOwnerThroughTheActiveSymptomJournalTail() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        repository.configureProgram(week: 5)
        let checkedAt = now.addingTimeInterval(-300)
        let sessionID = uuid("00000000-0000-4000-8000-000000000758")
        repository.inProgressSession = WorkoutSessionSnapshot(
            id: sessionID,
            createdAt: checkedAt.addingTimeInterval(-600),
            updatedAt: checkedAt,
            date: checkedAt.addingTimeInterval(-600),
            status: .inProgress,
            workoutDayTemplateID: plan.workoutDayID,
            ohpSymptomResponse: .symptomsPresent,
            ohpSymptomCheckedAt: checkedAt
        )
        repository.progress = WorkoutSessionProgressSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000759"),
            createdAt: checkedAt,
            updatedAt: checkedAt,
            workoutSessionID: sessionID,
            stage: .movement,
            currentExerciseTemplateID: plan.exercises[0].id,
            completedWarmupItemIDs: Set(plan.warmupItems.map(\.id)),
            warmupDisposition: .completed
        )
        let symptomClient = SymptomEventClientSpy()
        symptomClient.suspendNextRecord()
        let viewModel = makeViewModel(repository, symptomEventClient: symptomClient)

        let start = Task { await viewModel.start(workoutDayID: plan.workoutDayID) }
        await symptomClient.waitUntilRecordIsSuspended()

        XCTAssertEqual(viewModel.activeSessionMutationCount, 1)
        await assertDeletionRejectedWhileSessionMutationOwned(viewModel, repository)

        symptomClient.resumeSuspendedRecord()
        await start.value

        let expected = SymptomJournalEvent(
            id: sessionID,
            occurredAt: checkedAt,
            source: .overheadPressCurrentSymptom
        )
        XCTAssertEqual(viewModel.activeSessionMutationCount, 0)
        XCTAssertEqual(symptomClient.events, [expected])
        XCTAssertEqual(viewModel.symptomJournalState, .recorded(event: expected))
        XCTAssertNotNil(activePresentation(from: viewModel.state))
    }

    func testWarmupAndCooldownChecklistOwnersBlockDeletionUntilProgressReturns() async {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        repository.suspendNextProgressUpdate()

        let warmup = Task {
            await viewModel.toggleWarmupItem(id: repository.plan.warmupItems[0].id)
        }
        await repository.waitUntilProgressUpdateIsSuspended()

        XCTAssertEqual(viewModel.activeSessionMutationCount, 1)
        await assertDeletionRejectedWhileSessionMutationOwned(viewModel, repository)

        repository.resumeSuspendedProgressUpdate()
        await warmup.value
        XCTAssertEqual(viewModel.activeSessionMutationCount, 0)

        await viewModel.skipWarmup()
        await viewModel.advanceExercise()
        await viewModel.advanceExercise()
        XCTAssertEqual(requireActive(viewModel.state).progress.stage, .cooldown)
        repository.suspendNextProgressUpdate()

        let cooldown = Task {
            await viewModel.toggleCooldownItem(id: repository.plan.cooldownItems[0].id)
        }
        await repository.waitUntilProgressUpdateIsSuspended()

        XCTAssertEqual(viewModel.activeSessionMutationCount, 1)
        await assertDeletionRejectedWhileSessionMutationOwned(viewModel, repository)

        repository.resumeSuspendedProgressUpdate()
        await cooldown.value

        XCTAssertEqual(viewModel.activeSessionMutationCount, 0)
        XCTAssertEqual(
            requireActive(viewModel.state).progress.completedCooldownItemIDs,
            [repository.plan.cooldownItems[0].id]
        )
    }

    func testPriorResponseAndDeloadOwnersBlockDeletionThroughRepositoryStateWrites() async {
        do {
            let plan = makeOHPPlan()
            let repository = FakeSessionRepository(plan: plan)
            repository.configureProgram(week: 3)
            let exercise = plan.exercises[0]
            let prior = makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                ohpSymptomResponse: .notAsked,
                measurements: [.init(weightKg: 10, reps: 12, rir: 1)]
            )
            repository.completedExerciseHistory[exercise.id] = [prior]
            let viewModel = makeViewModel(repository)
            await viewModel.start(workoutDayID: plan.workoutDayID)
            repository.suspendNextOHPSymptomUpdate()

            let answer = Task { await viewModel.answerPreviousOHPSymptom(.symptomFree) }
            await repository.waitUntilOHPSymptomUpdateIsSuspended()

            XCTAssertEqual(viewModel.activeSessionMutationCount, 1)
            await assertDeletionRejectedWhileSessionMutationOwned(viewModel, repository)

            repository.resumeSuspendedOHPSymptomUpdate()
            await answer.value

            XCTAssertEqual(viewModel.activeSessionMutationCount, 0)
            XCTAssertEqual(repository.ohpSymptomUpdates.first?.id, prior.session.id)
        }

        do {
            let plan = makePlan()
            let repository = FakeSessionRepository(plan: plan)
            repository.configureProgram(week: 5, deloadStatus: .none)
            let viewModel = makeViewModel(repository)
            await viewModel.start(workoutDayID: plan.workoutDayID)
            repository.suspendNextDeloadUpdate()

            let response = Task { await viewModel.respondToDeload(.accepted) }
            await repository.waitUntilDeloadUpdateIsSuspended()

            XCTAssertEqual(viewModel.activeSessionMutationCount, 1)
            await assertDeletionRejectedWhileSessionMutationOwned(viewModel, repository)

            repository.resumeSuspendedDeloadUpdate()
            await response.value

            XCTAssertEqual(viewModel.activeSessionMutationCount, 0)
            XCTAssertEqual(repository.deloadUpdates.count, 1)
            XCTAssertNotNil(activePresentation(from: viewModel.state))
        }
    }

    func testSetSaveAndExactRetryEachOwnTheirWholeRepositoryLifetime() async {
        let repository = FakeSessionRepository(plan: makePlan())
        repository.saveSetOutcomes = [
            .failure(FakeSessionError.save),
            .success(()),
        ]
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        await viewModel.skipWarmup()
        repository.suspendNextSetSave()

        let save = Task { await viewModel.saveCurrentSet() }
        await repository.waitUntilSetSaveIsSuspended()

        XCTAssertEqual(viewModel.activeSessionMutationCount, 1)
        await assertDeletionRejectedWhileSessionMutationOwned(viewModel, repository)

        repository.resumeSuspendedSetSave()
        await save.value

        XCTAssertEqual(viewModel.activeSessionMutationCount, 0)
        XCTAssertEqual(viewModel.setSaveState, .repositoryFailed)
        let failedRequest = repository.saveSetRequests[0]
        repository.suspendNextSetSave()

        let retry = Task { await viewModel.retrySetSave() }
        await repository.waitUntilSetSaveIsSuspended()

        XCTAssertEqual(viewModel.activeSessionMutationCount, 1)
        await assertDeletionRejectedWhileSessionMutationOwned(viewModel, repository)

        repository.resumeSuspendedSetSave()
        await retry.value

        XCTAssertEqual(viewModel.activeSessionMutationCount, 0)
        XCTAssertEqual(repository.saveSetRequests, [failedRequest, failedRequest])
        XCTAssertEqual(viewModel.setSaveState, .saved(setID: failedRequest.id))
    }

    func testSummarySaveOwnerBlocksDeletionUntilItsDismissalCommits() async {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        await viewModel.skipWarmup()
        await viewModel.finishIncomplete()
        repository.suspendNextSummaryUpdate()

        let save = Task { await viewModel.saveSummary() }
        await repository.waitUntilSummaryUpdateIsSuspended()

        XCTAssertEqual(viewModel.activeSessionMutationCount, 1)
        await assertDeletionRejectedWhileSessionMutationOwned(viewModel, repository)

        repository.resumeSuspendedSummaryUpdate()
        await save.value

        XCTAssertEqual(viewModel.activeSessionMutationCount, 0)
        XCTAssertEqual(repository.summaryUpdates.count, 1)
        XCTAssertEqual(viewModel.state, .dismissed)
        XCTAssertTrue(repository.deletedSessionIDs.isEmpty)
    }

    func testOverlappingOwnersReleaseOnlyTheirExactTokenBeforeDeletionBecomesAvailable() async {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        await viewModel.skipWarmup()
        let sessionID = requireActive(viewModel.state).session.id
        repository.suspendNextSetSave()
        repository.suspendNextProgressUpdate()

        let save = Task { await viewModel.saveCurrentSet() }
        await repository.waitUntilSetSaveIsSuspended()
        let advance = Task { await viewModel.advanceExercise() }
        await repository.waitUntilProgressUpdateIsSuspended()

        XCTAssertEqual(viewModel.activeSessionMutationCount, 2)
        XCTAssertTrue(viewModel.isSessionMutationInFlight)

        repository.resumeSuspendedSetSave()
        await save.value

        XCTAssertEqual(
            viewModel.activeSessionMutationCount,
            1,
            "The first completion must remove only its exact owner token."
        )
        await assertDeletionRejectedWhileSessionMutationOwned(viewModel, repository)

        repository.resumeSuspendedProgressUpdate()
        await advance.value

        XCTAssertEqual(viewModel.activeSessionMutationCount, 0)
        XCTAssertFalse(viewModel.isSessionMutationInFlight)
        viewModel.requestDeletion()
        await viewModel.confirmDeletion()
        XCTAssertEqual(repository.deletedSessionIDs, [sessionID])
        XCTAssertEqual(viewModel.state, .dismissed)
    }

    func testCancelledSessionMutationReleasesOnlyItsOwnerAndAllowsDeletion() async {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        await viewModel.skipWarmup()
        let sessionID = requireActive(viewModel.state).session.id
        repository.suspendNextSetSave()

        let save = Task { await viewModel.saveCurrentSet() }
        await repository.waitUntilSetSaveIsSuspended()
        XCTAssertEqual(viewModel.activeSessionMutationCount, 1)

        save.cancel()
        repository.resumeSuspendedSetSave()
        await save.value

        XCTAssertEqual(viewModel.activeSessionMutationCount, 0)
        XCTAssertEqual(viewModel.setSaveState, .repositoryFailed)
        XCTAssertNotNil(activePresentation(from: viewModel.state))
        viewModel.requestDeletion()
        await viewModel.confirmDeletion()
        XCTAssertEqual(repository.deletedSessionIDs, [sessionID])
        XCTAssertEqual(viewModel.state, .dismissed)
    }

    func testJournalRetryMayFinishAfterDeletionWithoutRepublishingSessionState() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        configureCurrentOHPSymptomScenario(repository)
        let symptomClient = SymptomEventClientSpy(
            outcomes: [.failure(FakeSessionError.save), .success(())]
        )
        let viewModel = makeViewModel(repository, symptomEventClient: symptomClient)
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let sessionID = requireActive(viewModel.state).session.id
        let event = SymptomJournalEvent(
            id: sessionID,
            occurredAt: now,
            source: .overheadPressCurrentSymptom
        )
        await viewModel.reportCurrentOHPSymptom()
        XCTAssertEqual(viewModel.activeSessionMutationCount, 0)
        symptomClient.suspendNextRecord()

        let retry = Task { await viewModel.retrySymptomJournal() }
        await symptomClient.waitUntilRecordIsSuspended()

        XCTAssertEqual(
            viewModel.activeSessionMutationCount,
            0,
            "Metrics-only journal retry must not own the session deletion boundary."
        )
        viewModel.requestDeletion()
        await viewModel.confirmDeletion()
        XCTAssertEqual(repository.deletedSessionIDs, [sessionID])
        XCTAssertEqual(viewModel.state, .dismissed)

        symptomClient.resumeSuspendedRecord()
        await retry.value

        XCTAssertEqual(viewModel.state, .dismissed)
        XCTAssertEqual(symptomClient.events, [event, event])
        XCTAssertEqual(viewModel.symptomJournalState, .recorded(event: event))
        XCTAssertEqual(repository.ohpSymptomUpdates.count, 1)
    }

    func testOrdinaryDeletionFailureRetainsTheExistingRecoverableFailureRoute() async {
        let repository = FakeSessionRepository(plan: makePlan())
        repository.deleteOutcomes = [.failure(FakeSessionError.save)]
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)

        viewModel.requestDeletion()
        await viewModel.confirmDeletion()

        XCTAssertEqual(viewModel.state, .failed(.deletion))
        XCTAssertFalse(viewModel.hasPendingCurrentOHPSymptomWrite)
        XCTAssertFalse(viewModel.hasSessionDeletionFailure)
        XCTAssertFalse(viewModel.isDeleteConfirmationPresented)
        XCTAssertTrue(repository.deletedSessionIDs.isEmpty)

        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        XCTAssertNotNil(activePresentation(from: viewModel.state))
    }

    func testJournalFailureKeepsOHPStoppedAndRetryDoesNotRewriteTrainingState() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        repository.configureProgram(week: 5)
        let exercise = plan.exercises[0]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                ohpSymptomResponse: .symptomFree,
                measurements: [
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                ]
            ),
        ]
        let symptomClient = SymptomEventClientSpy(
            outcomes: [.failure(FakeSessionError.save), .success(())]
        )
        let viewModel = makeViewModel(
            repository,
            symptomEventClient: symptomClient
        )
        await viewModel.start(workoutDayID: plan.workoutDayID)
        await viewModel.skipWarmup()
        let sessionID = requireActive(viewModel.state).session.id

        await viewModel.reportCurrentOHPSymptom()

        let event = SymptomJournalEvent(
            id: sessionID,
            occurredAt: now,
            source: .overheadPressCurrentSymptom
        )
        XCTAssertNotNil(activePresentation(from: viewModel.state))
        XCTAssertEqual(
            viewModel.ohpSafetyState,
            .stopped(alternative: repository.ohpSafeAlternative)
        )
        XCTAssertEqual(viewModel.symptomJournalState, .failed(event: event))
        XCTAssertEqual(repository.ohpSymptomUpdates.count, 1)

        await viewModel.retrySymptomJournal()

        XCTAssertEqual(symptomClient.events, [event, event])
        XCTAssertEqual(viewModel.symptomJournalState, .recorded(event: event))
        XCTAssertEqual(
            repository.ohpSymptomUpdates.count,
            1,
            "Retrying the journal must not rewrite the safety response."
        )
        XCTAssertEqual(
            viewModel.ohpSafetyState,
            .stopped(alternative: repository.ohpSafeAlternative)
        )
    }

    func testRestoringSymptomPresentSessionReemitsTheSameStableEvent() async {
        let plan = makeOHPPlan()
        let repository = FakeSessionRepository(plan: plan)
        repository.configureProgram(week: 5)
        let checkedAt = now.addingTimeInterval(-300)
        let sessionID = uuid("00000000-0000-4000-8000-000000000756")
        repository.inProgressSession = WorkoutSessionSnapshot(
            id: sessionID,
            createdAt: checkedAt.addingTimeInterval(-600),
            updatedAt: checkedAt,
            date: checkedAt.addingTimeInterval(-600),
            status: .inProgress,
            workoutDayTemplateID: plan.workoutDayID,
            ohpSymptomResponse: .symptomsPresent,
            ohpSymptomCheckedAt: checkedAt
        )
        repository.progress = WorkoutSessionProgressSnapshot(
            id: uuid("00000000-0000-4000-8000-000000000757"),
            createdAt: checkedAt,
            updatedAt: checkedAt,
            workoutSessionID: sessionID,
            stage: .movement,
            currentExerciseTemplateID: plan.exercises[0].id,
            completedWarmupItemIDs: Set(plan.warmupItems.map(\.id)),
            warmupDisposition: .completed
        )
        let symptomClient = SymptomEventClientSpy()
        let expected = SymptomJournalEvent(
            id: sessionID,
            occurredAt: checkedAt,
            source: .overheadPressCurrentSymptom
        )

        let first = makeViewModel(repository, symptomEventClient: symptomClient)
        await first.start(workoutDayID: UUID())
        let restoredAgain = makeViewModel(repository, symptomEventClient: symptomClient)
        await restoredAgain.start(workoutDayID: UUID())

        XCTAssertEqual(symptomClient.events, [expected, expected])
        XCTAssertEqual(first.symptomJournalState, .recorded(event: expected))
        XCTAssertEqual(restoredAgain.symptomJournalState, .recorded(event: expected))
        XCTAssertEqual(
            first.ohpSafetyState,
            .stopped(alternative: repository.ohpSafeAlternative)
        )
    }

    func testScheduledDeloadBlocksWarmupUntilAcceptedAndThenPrefillsHalfLoad() async {
        let plan = makePlan()
        let repository = FakeSessionRepository(plan: plan)
        repository.configureProgram(week: 5, deloadStatus: .none)
        let exercise = plan.exercises[0]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                measurements: [
                    .init(weightKg: 20, reps: 12, rir: 1),
                    .init(weightKg: 20, reps: 12, rir: 1),
                    .init(weightKg: 20, reps: 12, rir: 1),
                ]
            ),
        ]
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: plan.workoutDayID)

        XCTAssertEqual(
            viewModel.deloadState,
            .recommendation(reason: .scheduled, trainingWeekIndex: 5)
        )
        await viewModel.skipWarmup()
        XCTAssertEqual(requireActive(viewModel.state).progress.stage, .warmup)

        await viewModel.respondToDeload(.accepted)

        XCTAssertEqual(
            repository.deloadUpdates,
            [
                .init(
                    programID: repository.activeProgram!.id,
                    reason: .scheduled,
                    action: .accepted,
                    date: now
                ),
            ]
        )
        XCTAssertEqual(
            viewModel.deloadState,
            .active(reason: .scheduled, trainingWeekIndex: 5)
        )
        await viewModel.skipWarmup()
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.weightKg, 10)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.reps, 8)
        guard case let .deload(reason) = viewModel.recommendationReason else {
            XCTFail("Expected active deload recommendation reason.")
            return
        }
        XCTAssertEqual(reason.reason, .scheduled)
        XCTAssertEqual(reason.defaultFraction, 0.5)
        XCTAssertEqual(reason.allowedFractionRange, 0.4...0.5)
    }

    func testReactiveDeloadUsesTwoCompletedSessionsAndTechniqueReviewSuppressesTheWeek() async {
        let plan = makePlan()
        let repository = FakeSessionRepository(plan: plan)
        repository.configureProgram(week: 6, deloadStatus: .none)
        let exercise = plan.exercises[0]
        let older = makeCompletedHistory(
            sessionID: uuid("00000000-0000-0000-0000-000000000760"),
            completedAt: now.addingTimeInterval(-14 * 24 * 60 * 60),
            dayID: plan.workoutDayID,
            exerciseID: exercise.id,
            measurements: [
                .init(weightKg: 10, reps: 10, rir: 1),
                .init(weightKg: 10, reps: 10, rir: 1),
                .init(weightKg: 10, reps: 10, rir: 1),
            ]
        )
        let newer = makeCompletedHistory(
            sessionID: uuid("00000000-0000-0000-0000-000000000761"),
            completedAt: now.addingTimeInterval(-7 * 24 * 60 * 60),
            dayID: plan.workoutDayID,
            exerciseID: exercise.id,
            measurements: [
                .init(weightKg: 10, reps: 9, rir: 1),
                .init(weightKg: 10, reps: 9, rir: 1),
                .init(weightKg: 10, reps: 9, rir: 1),
            ]
        )
        repository.completedExerciseHistory[exercise.id] = [newer, older]
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: plan.workoutDayID)

        XCTAssertEqual(
            viewModel.deloadState,
            .recommendation(reason: .reactive(exerciseID: exercise.id), trainingWeekIndex: 6)
        )
        await viewModel.respondToDeload(.techniqueReview)

        XCTAssertEqual(viewModel.deloadState, .notRequired)
        XCTAssertEqual(repository.programState?.deloadStatus, .skipped)
        XCTAssertEqual(repository.programState?.lastDeloadAction, .techniqueReview)
        XCTAssertEqual(repository.deloadUpdates.last?.reason, .reactive)
        await viewModel.skipWarmup()
        XCTAssertEqual(requireActive(viewModel.state).progress.stage, .movement)
    }

    func testStoredActiveReactiveDeloadSurvivesReloadWithoutASecondDecision() async {
        let plan = makePlan()
        let repository = FakeSessionRepository(plan: plan)
        repository.configureProgram(
            week: 6,
            deloadStatus: .active,
            deloadReason: .reactive
        )
        let exercise = plan.exercises[0]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: plan.workoutDayID,
                exerciseID: exercise.id,
                measurements: [
                    .init(weightKg: 20, reps: 10, rir: 1),
                    .init(weightKg: 20, reps: 10, rir: 1),
                ]
            ),
        ]
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: plan.workoutDayID)

        guard case let .active(reason, trainingWeekIndex) = viewModel.deloadState,
              case .reactive(exerciseID: _) = reason else {
            XCTFail("Persisted reactive deload must reopen as active.")
            return
        }
        XCTAssertEqual(trainingWeekIndex, 6)
        XCTAssertTrue(repository.deloadUpdates.isEmpty)
        await viewModel.skipWarmup()
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.weightKg, 10)
    }

    func testSummaryValuesStayNilUntilChosenAndSaveOnlyExplicitInput() async {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        await viewModel.skipWarmup()
        await viewModel.finishIncomplete()

        XCTAssertNil(viewModel.summaryRecovery)
        XCTAssertEqual(viewModel.summaryNote, "")
        XCTAssertTrue(repository.summaryUpdates.isEmpty)

        await viewModel.saveSummary()
        XCTAssertEqual(repository.summaryUpdates.count, 1)
        XCTAssertNil(repository.summaryUpdates[0].recovery)
        XCTAssertNil(repository.summaryUpdates[0].note)
        XCTAssertEqual(viewModel.state, .dismissed)

        let secondRepository = FakeSessionRepository(plan: makePlan())
        let secondViewModel = makeViewModel(secondRepository)
        await secondViewModel.start(workoutDayID: secondRepository.plan.workoutDayID)
        await secondViewModel.skipWarmup()
        await secondViewModel.finishIncomplete()
        secondViewModel.selectRecovery(4)
        secondViewModel.updateSummaryNote("  Güçlü hissettim  ")
        await secondViewModel.saveSummary()

        XCTAssertEqual(secondRepository.summaryUpdates.count, 1)
        XCTAssertEqual(secondRepository.summaryUpdates[0].recovery, 4)
        XCTAssertEqual(secondRepository.summaryUpdates[0].note, "Güçlü hissettim")
    }

    func testRecoveryAcceptsDocumentedOneToTenRangeAndRejectsOutsideValues() {
        let repository = FakeSessionRepository(plan: makePlan())
        let viewModel = makeViewModel(repository)

        viewModel.selectRecovery(10)
        XCTAssertEqual(viewModel.summaryRecovery, 10)

        viewModel.selectRecovery(11)
        XCTAssertEqual(viewModel.summaryRecovery, 10)

        viewModel.selectRecovery(0)
        XCTAssertEqual(viewModel.summaryRecovery, 10)

        viewModel.selectRecovery(nil)
        XCTAssertNil(viewModel.summaryRecovery)
    }

    func testLoadAndProgressFailuresHaveStableRecoverableStates() async {
        let repository = FakeSessionRepository(plan: makePlan())
        repository.fetchPlanError = FakeSessionError.load
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        XCTAssertEqual(viewModel.state, .failed(.load))

        repository.fetchPlanError = nil
        await viewModel.start(workoutDayID: repository.plan.workoutDayID)
        XCTAssertNotNil(activePresentation(from: viewModel.state))
    }

    private func assertDeletionRejectedWhileSessionMutationOwned(
        _ viewModel: SessionViewModel,
        _ repository: FakeSessionRepository,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let attemptCount = repository.deleteAttempts.count
        viewModel.requestDeletion()
        XCTAssertFalse(viewModel.isDeleteConfirmationPresented, file: file, line: line)
        await viewModel.confirmDeletion()
        XCTAssertEqual(repository.deleteAttempts.count, attemptCount, file: file, line: line)
        XCTAssertTrue(repository.deletedSessionIDs.isEmpty, file: file, line: line)
    }

    private func makeViewModel(
        _ repository: FakeSessionRepository,
        symptomEventClient: (any SymptomEventClient)? = nil
    ) -> SessionViewModel {
        if let symptomEventClient {
            return SessionViewModel(
                repository: repository,
                now: { self.now },
                symptomEventClient: symptomEventClient
            )
        }
        return SessionViewModel(repository: repository, now: { self.now })
    }

    private func configureCurrentOHPSymptomScenario(
        _ repository: FakeSessionRepository
    ) {
        repository.configureProgram(week: 5)
        let exercise = repository.plan.exercises[0]
        repository.completedExerciseHistory[exercise.id] = [
            makeCompletedHistory(
                dayID: repository.plan.workoutDayID,
                exerciseID: exercise.id,
                ohpSymptomResponse: .symptomFree,
                measurements: [
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                    .init(weightKg: 10, reps: 12, rir: 1),
                ]
            ),
        ]
    }

    private var missingAnswerSafetyPresentation: TrainingSymptomSafetyPresentation {
        TrainingSymptomSafetyPresentation(
            disclaimer: "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.",
            levelTwoMessage:
                "Hareketi durdur. Kalıcı veya kötüleşen belirtiler bir sağlık "
                + "profesyoneli tarafından değerlendirilmelidir.",
            requiresUrgentAssessment: false
        )
    }

    private func makePlan() -> SessionWorkoutPlanSnapshot {
        let dayID = uuid("00000000-0000-0000-0000-000000000710")
        return SessionWorkoutPlanSnapshot(
            workoutDayID: dayID,
            name: "Gün A",
            focus: "Tam vücut",
            warmupItems: [
                .init(
                    id: uuid("00000000-0000-0000-0000-000000000711"),
                    title: "İp / koşu",
                    detail: "60–90 sn",
                    orderIndex: 1
                ),
                .init(
                    id: uuid("00000000-0000-0000-0000-000000000712"),
                    title: "Band pull-apart",
                    detail: "15",
                    orderIndex: 2
                ),
            ],
            exercises: [
                .init(
                    id: uuid("00000000-0000-0000-0000-000000000713"),
                    name: "DB Floor Press",
                    orderIndex: 1,
                    targetSets: 3,
                    repLow: 8,
                    repHigh: 12,
                    rirLow: 1,
                    rirHigh: 2,
                    allowFailure: true,
                    cues: "Dirsek 45°",
                    safetyNote: "Yerde kontrollü dur",
                    startingWeightKg: 10,
                    progressionRule: .doubleProgression,
                    measurementKind: .weightReps
                ),
                .init(
                    id: uuid("00000000-0000-0000-0000-000000000714"),
                    name: "Chin-up",
                    orderIndex: 2,
                    targetSets: 2,
                    repLow: 6,
                    repHigh: 12,
                    rirLow: 1,
                    rirHigh: 2,
                    allowFailure: false,
                    cues: "Boyun nötr",
                    safetyNote: "Faile gitme",
                    startingWeightKg: nil,
                    progressionRule: .bodyweightProgression,
                    measurementKind: .reps
                ),
            ],
            cooldownItems: [
                .init(
                    id: uuid("00000000-0000-0000-0000-000000000715"),
                    title: "Pektoral germe",
                    detail: "30 sn × 2/taraf",
                    note: nil,
                    orderIndex: 1
                ),
            ]
        )
    }

    private func makeMeasurementFamilyPlan() -> SessionWorkoutPlanSnapshot {
        let base = makePlan()
        let kinds: [(String, ExerciseMeasurementKind, Double?, Int?)] = [
            ("Ağırlık + tekrar", .weightReps, 10, 8),
            ("Tekrar", .reps, nil, 10),
            ("Süre", .duration, nil, 30),
            ("Adım", .steps, 20, 40),
            ("Kalite", .quality, nil, nil),
        ]
        let exercises = kinds.enumerated().map { index, value in
            SessionExerciseSnapshot(
                id: UUID(),
                name: value.0,
                orderIndex: index + 1,
                targetSets: 1,
                repLow: value.3,
                repHigh: value.3,
                rirLow: 0,
                rirHigh: 2,
                allowFailure: false,
                cues: "",
                safetyNote: "Güvenli teknik",
                startingWeightKg: value.2,
                progressionRule: .timeQuality,
                measurementKind: value.1
            )
        }
        return SessionWorkoutPlanSnapshot(
            workoutDayID: base.workoutDayID,
            name: "Ölçüm aileleri",
            focus: "UI sözleşmesi",
            warmupItems: base.warmupItems,
            exercises: exercises,
            cooldownItems: base.cooldownItems
        )
    }

    private func makeBoneFocusPlan() -> SessionWorkoutPlanSnapshot {
        let base = makePlan()
        return SessionWorkoutPlanSnapshot(
            workoutDayID: base.workoutDayID,
            name: "Kemik odağı",
            focus: "Faz 3 alt tekrar bandı",
            warmupItems: base.warmupItems,
            exercises: [
                .init(
                    id: uuid("00000000-0000-0000-0000-000000000716"),
                    name: "Tanımlı ağır odak hareketi",
                    orderIndex: 1,
                    targetSets: 3,
                    repLow: 8,
                    repHigh: 12,
                    rirLow: 1,
                    rirHigh: 2,
                    allowFailure: false,
                    cues: "Şablondaki sınırları koru",
                    safetyNote: nil,
                    startingWeightKg: 10,
                    progressionRule: .boneFocusHeavy,
                    measurementKind: .weightReps
                ),
            ],
            cooldownItems: base.cooldownItems
        )
    }

    private func makeCompletedHistory(
        sessionID: UUID? = nil,
        completedAt explicitCompletedAt: Date? = nil,
        dayID: UUID,
        exerciseID: UUID,
        ohpSymptomResponse: OHPSymptomResponse = .notAsked,
        measurements: [SetMeasurementInput]
    ) -> CompletedExerciseHistorySnapshot {
        let completedAt = explicitCompletedAt ?? now.addingTimeInterval(-3_600)
        let session = WorkoutSessionSnapshot(
            id: sessionID ?? uuid("00000000-0000-0000-0000-000000000730"),
            date: completedAt,
            status: .completed,
            workoutDayTemplateID: dayID,
            ohpSymptomResponse: ohpSymptomResponse,
            ohpSymptomCheckedAt: ohpSymptomResponse == .notAsked ? nil : completedAt
        )
        let setLogs = measurements.enumerated().map { offset, measurement in
            SetLogSnapshot(
                id: UUID(
                    uuidString: String(
                        format: "00000000-0000-0000-0000-%012d",
                        731 + offset
                    )
                )!,
                createdAt: completedAt,
                updatedAt: completedAt,
                workoutSessionID: session.id,
                exerciseTemplateID: exerciseID,
                setIndex: offset + 1,
                measurement: measurement,
                isWarmupSet: false,
                completedAt: completedAt
            )
        }
        return CompletedExerciseHistorySnapshot(session: session, setLogs: setLogs)
    }

    private func makeOHPPlan() -> SessionWorkoutPlanSnapshot {
        let dayID = uuid("00000000-0000-0000-0000-000000000750")
        return SessionWorkoutPlanSnapshot(
            workoutDayID: dayID,
            name: "OHP günü",
            focus: "Kademeli omuz presi",
            warmupItems: [
                .init(
                    id: uuid("00000000-0000-0000-0000-000000000751"),
                    title: "Omuz hazırlığı",
                    detail: "8 tekrar",
                    orderIndex: 1
                ),
            ],
            exercises: [
                .init(
                    id: uuid("00000000-0000-0000-0000-000000000752"),
                    name: "DB Overhead Press",
                    orderIndex: 1,
                    targetSets: 3,
                    repLow: 8,
                    repHigh: 12,
                    rirLow: 1,
                    rirHigh: 2,
                    allowFailure: false,
                    cues: "Kontrollü uygula",
                    safetyNote: "Semptom olursa hareketi durdur",
                    startingWeightKg: 10,
                    progressionRule: .gradedEntryOHP,
                    measurementKind: .weightReps
                ),
            ],
            cooldownItems: []
        )
    }

    private func makePallofPlan() -> SessionWorkoutPlanSnapshot {
        let dayID = uuid("00000000-0000-0000-0000-000000000740")
        return SessionWorkoutPlanSnapshot(
            workoutDayID: dayID,
            name: "Pallof günü",
            focus: "Haftalık core seçimi",
            warmupItems: [
                .init(
                    id: uuid("00000000-0000-0000-0000-000000000741"),
                    title: "Hazırlık",
                    detail: "30 sn",
                    orderIndex: 1
                ),
            ],
            exercises: [
                .init(
                    id: uuid("00000000-0000-0000-0000-000000000742"),
                    name: "Plank / Pallof",
                    orderIndex: 1,
                    targetSets: 2,
                    repLow: 30,
                    repHigh: 60,
                    rirLow: 0,
                    rirHigh: 0,
                    allowFailure: false,
                    cues: "Kontrollü uygula",
                    safetyNote: "Kalçayı sabit tut",
                    startingWeightKg: nil,
                    progressionRule: .timeQuality,
                    measurementKind: .duration
                ),
            ],
            cooldownItems: []
        )
    }

    private func makeSession(dayID: UUID) -> WorkoutSessionSnapshot {
        WorkoutSessionSnapshot(
            id: uuid("00000000-0000-0000-0000-000000000720"),
            date: now,
            status: .inProgress,
            workoutDayTemplateID: dayID
        )
    }

    private func requireActive(
        _ state: SessionViewState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> SessionPresentation {
        guard let presentation = activePresentation(from: state) else {
            XCTFail("Expected active session, got \(state)", file: file, line: line)
            return SessionPresentation.placeholder
        }
        return presentation
    }

    private func activePresentation(from state: SessionViewState) -> SessionPresentation? {
        guard case let .active(presentation) = state else { return nil }
        return presentation
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}

@MainActor
private final class FakeSessionRepository: TrainingRepository {
    struct Transition: Equatable {
        let id: UUID
        let status: WorkoutSessionStatus
        let date: Date
    }

    struct SummaryUpdate: Equatable {
        let id: UUID
        let recovery: Int?
        let note: String?
        let date: Date
    }

    struct OHPSymptomUpdate: Equatable {
        let id: UUID
        let response: OHPSymptomResponse
        let date: Date
    }

    struct DeloadUpdate: Equatable {
        let programID: UUID
        let reason: DeloadReason
        let action: DeloadAction
        let date: Date
    }

    let plan: SessionWorkoutPlanSnapshot
    var inProgressSession: WorkoutSessionSnapshot?
    var progress: WorkoutSessionProgressSnapshot?
    var setLogs: [SetLogSnapshot] = []
    var completedExerciseHistory: [UUID: [CompletedExerciseHistorySnapshot]] = [:]
    var weeklyPallofHistory = WeeklyPallofHistorySnapshot(
        eligibleExerciseTemplateIDs: [],
        completions: []
    )
    var saveSetOutcomes: [Result<Void, Error>] = []
    var ohpSymptomUpdateOutcomes: [Result<Void, Error>] = []
    var progressUpdateOutcomes: [Result<Void, Error>] = []
    var transitionOutcomes: [Result<Void, Error>] = []
    var deleteOutcomes: [Result<Void, Error>] = []
    var fetchPlanError: Error?
    var activeProgram: Program?
    var programState: ProgramState?
    var programPhases: [ProgramPhase] = []
    var ohpSafeAlternative = SessionExerciseSnapshot(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000753")!,
        name: "Half-Kneeling DB Press",
        orderIndex: 5,
        targetSets: 3,
        repLow: 8,
        repHigh: 10,
        rirLow: 1,
        rirHigh: 2,
        allowFailure: false,
        cues: "Yarım diz çökerek kontrollü uygula",
        safetyNote: "OHP güvenli alternatifi",
        startingWeightKg: 7.5,
        progressionRule: .doubleProgression,
        measurementKind: .weightReps
    )

    private(set) var createRequests: [WorkoutSessionCreateRequest] = []
    private(set) var transitions: [Transition] = []
    private(set) var progressUpdates: [WorkoutSessionProgressUpdate] = []
    private(set) var saveSetRequests: [SetLogSaveRequest] = []
    private(set) var deleteAttempts: [UUID] = []
    private(set) var deletedSessionIDs: [UUID] = []
    private(set) var summaryUpdates: [SummaryUpdate] = []
    private(set) var ohpSymptomUpdates: [OHPSymptomUpdate] = []
    private(set) var deloadUpdates: [DeloadUpdate] = []
    private var suspendsNextOHPSymptomUpdate = false
    private var ohpSymptomUpdateIsSuspended = false
    private var ohpSymptomUpdateStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var ohpSymptomUpdateResumeContinuation: CheckedContinuation<Void, Never>?
    private var suspendsNextProgressUpdate = false
    private var progressUpdateIsSuspended = false
    private var progressUpdateStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var progressUpdateResumeContinuation: CheckedContinuation<Void, Never>?
    private var suspendsNextTransition = false
    private var transitionIsSuspended = false
    private var transitionStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var transitionResumeContinuation: CheckedContinuation<Void, Never>?
    private var suspendsNextDeletion = false
    private var deletionIsSuspended = false
    private var deletionStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var deletionResumeContinuation: CheckedContinuation<Void, Never>?
    private let deloadUpdateSuspension = OneShotSuspensionGate()
    private let setSaveSuspension = OneShotSuspensionGate()
    private let summaryUpdateSuspension = OneShotSuspensionGate()

    init(plan: SessionWorkoutPlanSnapshot) {
        self.plan = plan
    }

    func suspendNextOHPSymptomUpdate() {
        suspendsNextOHPSymptomUpdate = true
    }

    func waitUntilOHPSymptomUpdateIsSuspended() async {
        if ohpSymptomUpdateIsSuspended { return }
        await withCheckedContinuation { continuation in
            ohpSymptomUpdateStartWaiters.append(continuation)
        }
    }

    func resumeSuspendedOHPSymptomUpdate() {
        ohpSymptomUpdateResumeContinuation?.resume()
        ohpSymptomUpdateResumeContinuation = nil
    }

    func suspendNextProgressUpdate() {
        suspendsNextProgressUpdate = true
    }

    func waitUntilProgressUpdateIsSuspended() async {
        if progressUpdateIsSuspended { return }
        await withCheckedContinuation { continuation in
            progressUpdateStartWaiters.append(continuation)
        }
    }

    func resumeSuspendedProgressUpdate() {
        progressUpdateResumeContinuation?.resume()
        progressUpdateResumeContinuation = nil
    }

    func suspendNextTransition() {
        suspendsNextTransition = true
    }

    func waitUntilTransitionIsSuspended() async {
        if transitionIsSuspended { return }
        await withCheckedContinuation { continuation in
            transitionStartWaiters.append(continuation)
        }
    }

    func resumeSuspendedTransition() {
        transitionResumeContinuation?.resume()
        transitionResumeContinuation = nil
    }

    func suspendNextDeletion() {
        suspendsNextDeletion = true
    }

    func waitUntilDeletionIsSuspended() async {
        if deletionIsSuspended { return }
        await withCheckedContinuation { continuation in
            deletionStartWaiters.append(continuation)
        }
    }

    func resumeSuspendedDeletion() {
        deletionResumeContinuation?.resume()
        deletionResumeContinuation = nil
    }

    func suspendNextDeloadUpdate() {
        deloadUpdateSuspension.suspendNext()
    }

    func waitUntilDeloadUpdateIsSuspended() async {
        await deloadUpdateSuspension.waitUntilSuspended()
    }

    func resumeSuspendedDeloadUpdate() {
        deloadUpdateSuspension.resume()
    }

    func suspendNextSetSave() {
        setSaveSuspension.suspendNext()
    }

    func waitUntilSetSaveIsSuspended() async {
        await setSaveSuspension.waitUntilSuspended()
    }

    func resumeSuspendedSetSave() {
        setSaveSuspension.resume()
    }

    func suspendNextSummaryUpdate() {
        summaryUpdateSuspension.suspendNext()
    }

    func waitUntilSummaryUpdateIsSuspended() async {
        await summaryUpdateSuspension.waitUntilSuspended()
    }

    func resumeSuspendedSummaryUpdate() {
        summaryUpdateSuspension.resume()
    }

    func fetchUserProfile() async throws -> UserProfile? { nil }
    func fetchActiveProgram() async throws -> Program? { activeProgram }
    func fetchProgramPhases(programID: UUID) async throws -> [ProgramPhase] {
        programPhases.filter { $0.program?.id == nil || $0.program?.id == programID }
    }
    func fetchWorkoutDays(programID: UUID) async throws -> [WorkoutDayTemplate] { [] }
    func fetchExerciseTemplates(workoutDayID: UUID) async throws -> [ExerciseTemplate] { [] }
    func fetchWarmupItems(workoutDayID: UUID) async throws -> [WarmupItem] { [] }
    func fetchCooldownItems(workoutDayID: UUID) async throws -> [CooldownItem] { [] }
    func fetchProgramState(programID: UUID) async throws -> ProgramState? {
        programState?.programId == programID ? programState : nil
    }

    func configureProgram(
        week: Int,
        phaseOrderIndex: Int = 1,
        deloadStatus: DeloadStatus = .skipped,
        deloadReason: DeloadReason? = nil
    ) {
        let programID = UUID(uuidString: "00000000-0000-0000-0000-000000000754")!
        let phaseID = UUID(uuidString: "00000000-0000-0000-0000-000000000755")!
        activeProgram = Program(id: programID, name: "OHP programı", isActive: true)
        programState = ProgramState(
            programId: programID,
            currentPhaseId: phaseID,
            trainingWeekIndex: week,
            deloadStatus: deloadStatus,
            deloadReason: deloadReason
        )
        programPhases = [
            ProgramPhase(
                id: phaseID,
                name: "Test fazı",
                orderIndex: phaseOrderIndex,
                monthStart: 1,
                monthEnd: 12
            ),
        ]
    }

    func applyDeloadAction(
        programID: UUID,
        reason: DeloadReason,
        action: DeloadAction,
        at date: Date
    ) async throws -> ProgramState {
        guard let programState, programState.programId == programID else {
            throw FakeSessionError.load
        }
        deloadUpdates.append(
            .init(programID: programID, reason: reason, action: action, date: date)
        )
        programState.deloadStatus = action == .accepted ? .active : .skipped
        programState.deloadReason = reason
        programState.deloadUpdatedAt = date
        programState.lastDeloadSkippedAt = action == .accepted ? nil : date
        programState.lastDeloadAction = action
        programState.updatedAt = date
        await deloadUpdateSuspension.pauseIfRequested()
        try Task.checkCancellation()
        return programState
    }

    func createWorkoutSession(
        _ request: WorkoutSessionCreateRequest
    ) async throws -> WorkoutSessionSnapshot {
        createRequests.append(request)
        return WorkoutSessionSnapshot(
            id: request.id,
            date: request.date,
            status: .planned,
            workoutDayTemplateID: request.workoutDayTemplateID
        )
    }

    func fetchInProgressWorkoutSession() async throws -> WorkoutSessionSnapshot? {
        inProgressSession
    }

    func transitionWorkoutSession(
        id: UUID,
        to status: WorkoutSessionStatus,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        transitions.append(.init(id: id, status: status, date: date))
        let source = inProgressSession ?? WorkoutSessionSnapshot(
            id: id,
            date: date,
            status: .planned,
            workoutDayTemplateID: plan.workoutDayID
        )
        let updated = WorkoutSessionSnapshot(
            id: source.id,
            createdAt: source.createdAt,
            updatedAt: date,
            date: source.date,
            status: status,
            workoutDayTemplateID: source.workoutDayTemplateID,
            perceivedRecovery: source.perceivedRecovery,
            note: source.note,
            ohpSymptomResponse: source.ohpSymptomResponse,
            ohpSymptomCheckedAt: source.ohpSymptomCheckedAt
        )
        inProgressSession = status == .inProgress ? updated : nil
        if suspendsNextTransition {
            suspendsNextTransition = false
            transitionIsSuspended = true
            let waiters = transitionStartWaiters
            transitionStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                transitionResumeContinuation = continuation
            }
            transitionIsSuspended = false
        }
        if !transitionOutcomes.isEmpty {
            try transitionOutcomes.removeFirst().get()
        }
        return updated
    }

    func fetchWorkoutSessionProgress(
        sessionID: UUID
    ) async throws -> WorkoutSessionProgressSnapshot? {
        progress
    }

    func saveWorkoutSessionProgress(
        _ update: WorkoutSessionProgressUpdate
    ) async throws -> WorkoutSessionProgressSnapshot {
        progressUpdates.append(update)
        let snapshot = WorkoutSessionProgressSnapshot(
            id: progress?.id ?? update.id,
            createdAt: progress?.createdAt ?? update.updatedAt,
            updatedAt: update.updatedAt,
            workoutSessionID: update.workoutSessionID,
            stage: update.state.stage,
            currentExerciseTemplateID: update.state.currentExerciseTemplateID,
            completedWarmupItemIDs: update.state.completedWarmupItemIDs,
            completedCooldownItemIDs: update.state.completedCooldownItemIDs,
            warmupDisposition: update.state.warmupDisposition,
            cooldownDisposition: update.state.cooldownDisposition
        )
        progress = snapshot
        if suspendsNextProgressUpdate {
            suspendsNextProgressUpdate = false
            progressUpdateIsSuspended = true
            let waiters = progressUpdateStartWaiters
            progressUpdateStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                progressUpdateResumeContinuation = continuation
            }
            progressUpdateIsSuspended = false
        }
        if !progressUpdateOutcomes.isEmpty {
            try progressUpdateOutcomes.removeFirst().get()
        }
        return snapshot
    }

    func fetchSessionExercises(
        workoutDayID: UUID
    ) async throws -> [SessionExerciseSnapshot] {
        plan.exercises
    }

    func fetchSetLogs(workoutSessionID: UUID) async throws -> [SetLogSnapshot] {
        setLogs
    }

    func fetchCompletedExerciseHistory(
        exerciseTemplateID: UUID
    ) async throws -> [CompletedExerciseHistorySnapshot] {
        completedExerciseHistory[exerciseTemplateID, default: []]
    }

    func fetchWeeklyPallofHistory() async throws -> WeeklyPallofHistorySnapshot {
        weeklyPallofHistory
    }

    func fetchOHPSafeAlternative() async throws -> SessionExerciseSnapshot {
        ohpSafeAlternative
    }

    func updateWorkoutSessionOHPSymptomResponse(
        id: UUID,
        response: OHPSymptomResponse,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        ohpSymptomUpdates.append(.init(id: id, response: response, date: date))
        if suspendsNextOHPSymptomUpdate {
            suspendsNextOHPSymptomUpdate = false
            ohpSymptomUpdateIsSuspended = true
            let waiters = ohpSymptomUpdateStartWaiters
            ohpSymptomUpdateStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                ohpSymptomUpdateResumeContinuation = continuation
            }
            ohpSymptomUpdateIsSuspended = false
        }
        if !ohpSymptomUpdateOutcomes.isEmpty {
            try ohpSymptomUpdateOutcomes.removeFirst().get()
        }
        let historySession = completedExerciseHistory.values
            .flatMap { $0 }
            .map(\.session)
            .first { $0.id == id }
        let source = inProgressSession?.id == id ? inProgressSession : historySession
        guard let source else { throw FakeSessionError.load }
        let updated = WorkoutSessionSnapshot(
            id: source.id,
            createdAt: source.createdAt,
            updatedAt: date,
            date: source.date,
            status: source.status,
            workoutDayTemplateID: source.workoutDayTemplateID,
            perceivedRecovery: source.perceivedRecovery,
            note: source.note,
            ohpSymptomResponse: response,
            ohpSymptomCheckedAt: date
        )
        if inProgressSession?.id == id {
            inProgressSession = updated
        }
        return updated
    }

    func saveSet(_ request: SetLogSaveRequest) async throws -> SetLogSnapshot {
        saveSetRequests.append(request)
        await setSaveSuspension.pauseIfRequested()
        try Task.checkCancellation()
        if !saveSetOutcomes.isEmpty {
            try saveSetOutcomes.removeFirst().get()
        }
        let snapshot = SetLogSnapshot(
            id: request.id,
            createdAt: request.completedAt,
            updatedAt: request.completedAt,
            workoutSessionID: request.workoutSessionID,
            exerciseTemplateID: request.exerciseTemplateID,
            setIndex: request.setIndex,
            measurement: request.measurement,
            isWarmupSet: request.isWarmupSet,
            completedAt: request.completedAt
        )
        setLogs.append(snapshot)
        return snapshot
    }

    func deleteWorkoutSession(id: UUID) async throws {
        deleteAttempts.append(id)
        if suspendsNextDeletion {
            suspendsNextDeletion = false
            deletionIsSuspended = true
            let waiters = deletionStartWaiters
            deletionStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                deletionResumeContinuation = continuation
            }
            deletionIsSuspended = false
        }
        try Task.checkCancellation()
        if !deleteOutcomes.isEmpty {
            try deleteOutcomes.removeFirst().get()
        }
        deletedSessionIDs.append(id)
        inProgressSession = nil
        progress = nil
        setLogs.removeAll { $0.workoutSessionID == id }
    }

    func fetchSessionPlan(
        workoutDayID: UUID
    ) async throws -> SessionWorkoutPlanSnapshot? {
        if let fetchPlanError { throw fetchPlanError }
        return plan.workoutDayID == workoutDayID ? plan : nil
    }

    func updateWorkoutSessionSummary(
        id: UUID,
        perceivedRecovery: Int?,
        note: String?,
        at date: Date
    ) async throws -> WorkoutSessionSnapshot {
        summaryUpdates.append(
            .init(id: id, recovery: perceivedRecovery, note: note, date: date)
        )
        await summaryUpdateSuspension.pauseIfRequested()
        try Task.checkCancellation()
        return WorkoutSessionSnapshot(
            id: id,
            date: date,
            status: .completed,
            workoutDayTemplateID: plan.workoutDayID,
            perceivedRecovery: perceivedRecovery,
            note: note
        )
    }
}

private extension SessionOHPSymptomWriteRequest {
    var repositoryUpdate: FakeSessionRepository.OHPSymptomUpdate {
        .init(id: sessionID, response: response, date: reportedAt)
    }
}

private enum FakeSessionError: Error {
    case load
    case save
}

@MainActor
private final class OneShotSuspensionGate {
    private var suspendsNextCall = false
    private var isSuspended = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func suspendNext() {
        suspendsNextCall = true
    }

    func waitUntilSuspended() async {
        if isSuspended { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func pauseIfRequested() async {
        guard suspendsNextCall else { return }
        suspendsNextCall = false
        isSuspended = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
        isSuspended = false
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

@MainActor
private final class SymptomEventClientSpy: SymptomEventClient {
    var outcomes: [Result<Void, Error>]
    private(set) var events: [SymptomJournalEvent] = []
    private let recordSuspension = OneShotSuspensionGate()

    init(outcomes: [Result<Void, Error>] = []) {
        self.outcomes = outcomes
    }

    func suspendNextRecord() {
        recordSuspension.suspendNext()
    }

    func waitUntilRecordIsSuspended() async {
        await recordSuspension.waitUntilSuspended()
    }

    func resumeSuspendedRecord() {
        recordSuspension.resume()
    }

    func record(_ event: SymptomJournalEvent) async throws {
        events.append(event)
        await recordSuspension.pauseIfRequested()
        try Task.checkCancellation()
        if !outcomes.isEmpty {
            try outcomes.removeFirst().get()
        }
    }
}

private extension SessionPresentation {
    static var placeholder: SessionPresentation {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let dayID = UUID()
        return SessionPresentation(
            session: WorkoutSessionSnapshot(
                id: UUID(),
                date: date,
                status: .inProgress,
                workoutDayTemplateID: dayID
            ),
            plan: SessionWorkoutPlanSnapshot(
                workoutDayID: dayID,
                name: "",
                focus: "",
                warmupItems: [],
                exercises: [],
                cooldownItems: []
            ),
            progress: SessionProgressState(stage: .warmup),
            setLogs: [],
            restoreSource: .inferredMissingProgress
        )
    }
}
