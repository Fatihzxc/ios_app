import CoreModels
import Foundation
import SwiftData
import TrainingKit

public enum TrainingHapticPreferenceStoreError: Error, Equatable, Sendable {
    case duplicateSettings(count: Int)
    case invalidPayload
    case unsupportedSchemaVersion(Int)
    case loadFailed
    case saveFailed
}

@MainActor
public final class SwiftDataTrainingHapticPreferenceStore: TrainingHapticPreferenceStore {
    public static let key = "haptics.enabled"

    private static let schemaVersion = 1

    private struct Payload: Codable {
        let schemaVersion: Int
        let isEnabled: Bool
    }

    private let modelContext: ModelContext
    private let now: @MainActor () -> Date

    public init(
        modelContext: ModelContext,
        now: @escaping @MainActor () -> Date = { .now }
    ) {
        self.modelContext = modelContext
        self.now = now
    }

    public func loadHapticsEnabled() throws -> Bool {
        let settings = try matchingSettings()
        guard let setting = settings.first else { return true }
        guard let data = setting.value.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw TrainingHapticPreferenceStoreError.invalidPayload
        }
        guard payload.schemaVersion == Self.schemaVersion else {
            throw TrainingHapticPreferenceStoreError.unsupportedSchemaVersion(
                payload.schemaVersion
            )
        }
        return payload.isEnabled
    }

    public func saveHapticsEnabled(_ isEnabled: Bool) throws {
        let settings = try matchingSettings()
        let payload = Payload(
            schemaVersion: Self.schemaVersion,
            isEnabled: isEnabled
        )
        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            throw TrainingHapticPreferenceStoreError.saveFailed
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw TrainingHapticPreferenceStoreError.saveFailed
        }

        if let setting = settings.first {
            setting.value = value
            setting.updatedAt = now()
        } else {
            let timestamp = now()
            modelContext.insert(
                AppSetting(
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    key: Self.key,
                    value: value
                )
            )
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw TrainingHapticPreferenceStoreError.saveFailed
        }
    }

    private func matchingSettings() throws -> [AppSetting] {
        let allSettings: [AppSetting]
        do {
            allSettings = try modelContext.fetch(FetchDescriptor<AppSetting>())
        } catch {
            throw TrainingHapticPreferenceStoreError.loadFailed
        }
        let settings = allSettings.filter { $0.key == Self.key }
        guard settings.count <= 1 else {
            throw TrainingHapticPreferenceStoreError.duplicateSettings(count: settings.count)
        }
        return settings
    }
}
