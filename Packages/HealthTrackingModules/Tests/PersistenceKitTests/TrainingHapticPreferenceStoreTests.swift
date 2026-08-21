import CoreModels
import Foundation
import PersistenceKit
import SwiftData
import XCTest

@MainActor
final class TrainingHapticPreferenceStoreTests: XCTestCase {
    func testMissingPreferenceDefaultsEnabledAndSaveUsesOneVersionedAppSetting() throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let store = SwiftDataTrainingHapticPreferenceStore(modelContext: context)

        XCTAssertTrue(try store.loadHapticsEnabled())

        try store.saveHapticsEnabled(false)
        try store.saveHapticsEnabled(true)

        let settings = try context.fetch(FetchDescriptor<AppSetting>())
            .filter { $0.key == SwiftDataTrainingHapticPreferenceStore.key }
        let setting = try XCTUnwrap(settings.first)
        let payloadData = try XCTUnwrap(setting.value.data(using: .utf8))
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        )

        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(setting.key, "haptics.enabled")
        XCTAssertEqual(payload["schemaVersion"] as? Int, 1)
        XCTAssertEqual(payload["isEnabled"] as? Bool, true)
        XCTAssertTrue(try store.loadHapticsEnabled())
    }

    func testDisabledPreferenceSurvivesContainerRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("haptics.store")

        try writeDisabledPreference(at: storeURL)

        let reopened = try ModelContainerFactory.make(for: .local(storeURL: storeURL))
        let relaunchedStore = SwiftDataTrainingHapticPreferenceStore(
            modelContext: ModelContext(reopened)
        )

        XCTAssertFalse(try relaunchedStore.loadHapticsEnabled())
    }

    func testDuplicatePreferenceRowsAreRejectedInsteadOfChoosingArbitrarily() throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        context.insert(AppSetting(key: "haptics.enabled", value: validPayload(false)))
        context.insert(AppSetting(key: "haptics.enabled", value: validPayload(true)))
        try context.save()
        let store = SwiftDataTrainingHapticPreferenceStore(modelContext: context)

        XCTAssertThrowsError(try store.loadHapticsEnabled()) { error in
            XCTAssertEqual(
                error as? TrainingHapticPreferenceStoreError,
                .duplicateSettings(count: 2)
            )
        }
    }

    func testMalformedOrUnsupportedPayloadIsRejected() throws {
        let container = try ModelContainerFactory.make(for: .inMemory)
        let context = ModelContext(container)
        let setting = AppSetting(key: "haptics.enabled", value: "not-json")
        context.insert(setting)
        try context.save()
        let store = SwiftDataTrainingHapticPreferenceStore(modelContext: context)

        XCTAssertThrowsError(try store.loadHapticsEnabled()) { error in
            XCTAssertEqual(error as? TrainingHapticPreferenceStoreError, .invalidPayload)
        }

        setting.value = "{\"schemaVersion\":2,\"isEnabled\":false}"
        try context.save()
        XCTAssertThrowsError(try store.loadHapticsEnabled()) { error in
            XCTAssertEqual(
                error as? TrainingHapticPreferenceStoreError,
                .unsupportedSchemaVersion(2)
            )
        }
    }

    private func writeDisabledPreference(at storeURL: URL) throws {
        let container = try ModelContainerFactory.make(for: .local(storeURL: storeURL))
        let store = SwiftDataTrainingHapticPreferenceStore(
            modelContext: ModelContext(container)
        )
        try store.saveHapticsEnabled(false)
    }

    private func validPayload(_ isEnabled: Bool) -> String {
        "{\"schemaVersion\":1,\"isEnabled\":\(isEnabled)}"
    }
}
