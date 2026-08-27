import Foundation
import ProgressPhotosKit
import XCTest

final class PhotoAssetCleanupJournalTests: XCTestCase {
    func testOpaqueCleanupIntentSurvivesJournalRecreationAndExactRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let assetID = "00000000-0000-0000-0000-000000000065"
        let first = FilePhotoAssetCleanupJournal(
            applicationSupportDirectory: root
        )
        try await first.addPendingAssetID(assetID)

        let recreated = FilePhotoAssetCleanupJournal(
            applicationSupportDirectory: root
        )
        let restored = try await recreated.loadPendingAssetIDs()
        XCTAssertEqual(restored, [assetID])
        let journalURL = root
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
            .appendingPathComponent("cleanup-journal.json")
        let persistedText = String(
            decoding: try Data(contentsOf: journalURL),
            as: UTF8.self
        )
        XCTAssertFalse(persistedText.contains(root.path))

        try await recreated.removePendingAssetID(assetID)
        let afterRemoval = try await FilePhotoAssetCleanupJournal(
            applicationSupportDirectory: root
        ).loadPendingAssetIDs()
        XCTAssertTrue(afterRemoval.isEmpty)
    }

    func testJournalRejectsPathsInsteadOfPersistingThem() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let journal = FilePhotoAssetCleanupJournal(
            applicationSupportDirectory: root
        )

        do {
            try await journal.addPendingAssetID("/private/photo.jpg")
            XCTFail("Cleanup intent must contain only an opaque asset ID.")
        } catch {
            XCTAssertEqual(
                error as? PhotoAssetCleanupJournalError,
                .invalidContents
            )
        }
    }
}
