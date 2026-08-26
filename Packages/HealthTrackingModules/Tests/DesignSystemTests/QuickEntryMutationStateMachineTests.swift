import XCTest
@testable import DesignSystem

final class QuickEntryMutationStateMachineTests: XCTestCase {
    func testSaveSuppressesDuplicateTapAndAcceptsOnlyTheExactAttempt() throws {
        var machine = QuickEntryMutationStateMachine<String>()
        let requestID = UUID()

        XCTAssertEqual(machine.phase, .idle)

        let attempt = try XCTUnwrap(machine.beginSave(requestID: requestID))
        XCTAssertEqual(
            attempt,
            QuickEntryMutationAttempt(requestID: requestID, generation: 1, kind: .save)
        )
        XCTAssertEqual(machine.phase, .saving(attempt))
        XCTAssertNil(machine.beginSave(requestID: UUID()))

        let staleAttempt = QuickEntryMutationAttempt(
            requestID: requestID,
            generation: attempt.generation + 1,
            kind: .save
        )
        XCTAssertFalse(machine.completeSave(staleAttempt, undoToken: "stale"))
        XCTAssertEqual(machine.phase, .saving(attempt))

        XCTAssertTrue(machine.completeSave(attempt, undoToken: "saved-row"))
        XCTAssertEqual(machine.phase, .saved(undoToken: "saved-row"))
    }

    func testFailedSaveRetriesTheSameRequestWithANewerGeneration() throws {
        var machine = QuickEntryMutationStateMachine<String>()
        let requestID = UUID()
        let firstAttempt = try XCTUnwrap(machine.beginSave(requestID: requestID))

        XCTAssertTrue(machine.failSave(firstAttempt))
        XCTAssertEqual(machine.phase, .saveFailed(requestID: requestID))
        XCTAssertNil(machine.beginUndo(requestID: UUID()))

        let retryAttempt = try XCTUnwrap(machine.retrySave())
        XCTAssertEqual(retryAttempt.requestID, requestID)
        XCTAssertGreaterThan(retryAttempt.generation, firstAttempt.generation)
        XCTAssertEqual(retryAttempt.kind, .save)
        XCTAssertEqual(machine.phase, .saving(retryAttempt))

        XCTAssertFalse(machine.completeSave(firstAttempt, undoToken: "stale"))
        XCTAssertTrue(machine.completeSave(retryAttempt, undoToken: "saved-row"))
    }

    func testFailedUndoRetainsTokenAndRetryUsesSameRequestID() throws {
        var machine = QuickEntryMutationStateMachine<String>()
        let saveAttempt = try XCTUnwrap(machine.beginSave(requestID: UUID()))
        XCTAssertTrue(machine.completeSave(saveAttempt, undoToken: "saved-row"))

        let undoRequestID = UUID()
        let firstUndoAttempt = try XCTUnwrap(machine.beginUndo(requestID: undoRequestID))
        XCTAssertEqual(firstUndoAttempt.kind, .undo)
        XCTAssertEqual(
            machine.phase,
            .undoing(attempt: firstUndoAttempt, undoToken: "saved-row")
        )
        XCTAssertNil(machine.beginUndo(requestID: UUID()))

        XCTAssertTrue(machine.failUndo(firstUndoAttempt))
        XCTAssertEqual(
            machine.phase,
            .undoFailed(requestID: undoRequestID, undoToken: "saved-row")
        )

        let retryAttempt = try XCTUnwrap(machine.retryUndo())
        XCTAssertEqual(retryAttempt.requestID, undoRequestID)
        XCTAssertGreaterThan(retryAttempt.generation, firstUndoAttempt.generation)
        XCTAssertEqual(retryAttempt.kind, .undo)
        XCTAssertFalse(machine.completeUndo(firstUndoAttempt))
        XCTAssertTrue(machine.completeUndo(retryAttempt))
        XCTAssertEqual(machine.phase, .idle)
    }

    func testUndoTokenExpiresOnlyExplicitlyOrWhenANewSaveBegins() throws {
        var machine = QuickEntryMutationStateMachine<String>()
        let firstSave = try XCTUnwrap(machine.beginSave(requestID: UUID()))
        XCTAssertTrue(machine.completeSave(firstSave, undoToken: "first-token"))

        let replacementSave = try XCTUnwrap(machine.beginSave(requestID: UUID()))
        XCTAssertEqual(machine.phase, .saving(replacementSave))
        XCTAssertTrue(machine.completeSave(replacementSave, undoToken: "second-token"))

        XCTAssertTrue(machine.expireUndo())
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertFalse(machine.expireUndo())
        XCTAssertNil(machine.retrySave())
        XCTAssertNil(machine.retryUndo())
    }

    func testWrongOperationKindCanNeverCompleteCurrentAttempt() throws {
        var machine = QuickEntryMutationStateMachine<String>()
        let saveAttempt = try XCTUnwrap(machine.beginSave(requestID: UUID()))
        let wrongKind = QuickEntryMutationAttempt(
            requestID: saveAttempt.requestID,
            generation: saveAttempt.generation,
            kind: .undo
        )

        XCTAssertFalse(machine.failSave(wrongKind))
        XCTAssertFalse(machine.completeSave(wrongKind, undoToken: "wrong"))
        XCTAssertEqual(machine.phase, .saving(saveAttempt))
    }
}
