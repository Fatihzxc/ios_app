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
        let viewModel = makeViewModel(repository)

        await viewModel.start(workoutDayID: plan.workoutDayID)

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

        await viewModel.skipWarmup()

        XCTAssertEqual(viewModel.currentSetDraft?.measurement.weightKg, 12.5)
        XCTAssertEqual(viewModel.currentSetDraft?.measurement.reps, 8)
        XCTAssertEqual(
            viewModel.currentSetDraft?.measurement.performedVariant,
            "standing-neutral"
        )
        XCTAssertEqual(viewModel.recommendationReason, .ohp(.increaseAllowed))
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
        let heldViewModel = makeViewModel(heldRepository)

        await heldViewModel.start(workoutDayID: heldPlan.workoutDayID)
        await heldViewModel.skipWarmup()

        XCTAssertEqual(heldViewModel.currentSetDraft?.measurement.weightKg, 10)
        XCTAssertNotEqual(heldViewModel.currentSetDraft?.measurement.weightKg, 12.5)
        XCTAssertEqual(
            heldViewModel.recommendationReason,
            .ohp(.previousResponseUncertain)
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
        let viewModel = makeViewModel(repository)
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

    private func makeViewModel(_ repository: FakeSessionRepository) -> SessionViewModel {
        SessionViewModel(repository: repository, now: { self.now })
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
    private(set) var deletedSessionIDs: [UUID] = []
    private(set) var summaryUpdates: [SummaryUpdate] = []
    private(set) var ohpSymptomUpdates: [OHPSymptomUpdate] = []
    private(set) var deloadUpdates: [DeloadUpdate] = []

    init(plan: SessionWorkoutPlanSnapshot) {
        self.plan = plan
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
    func fetchHealthCheckReminders() async throws -> [HealthCheckReminder] { [] }
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

private enum FakeSessionError: Error {
    case load
    case save
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
