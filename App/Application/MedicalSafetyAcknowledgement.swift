import CoreModels
import Foundation
import HealthSafetyKit
import Observation
import SwiftData

@MainActor
protocol MedicalSafetyAcknowledgementStore: AnyObject {
    func loadAcknowledged() throws -> Bool
    func saveAcknowledged() throws
}

@MainActor
@Observable
final class MedicalSafetyAcknowledgementController {
    private(set) var isLevelZeroVisible: Bool
    let levelOnePresentation = MedicalDisclaimerPresentation.permanent

    private let store: any MedicalSafetyAcknowledgementStore

    init(store: any MedicalSafetyAcknowledgementStore) {
        self.store = store
        isLevelZeroVisible = !((try? store.loadAcknowledged()) ?? false)
    }

    @discardableResult
    func acknowledge() -> Bool {
        guard isLevelZeroVisible else { return true }
        do {
            try store.saveAcknowledged()
            isLevelZeroVisible = false
            return true
        } catch {
            isLevelZeroVisible = true
            return false
        }
    }
}

@MainActor
final class SwiftDataMedicalSafetyAcknowledgementStore:
    MedicalSafetyAcknowledgementStore {
    static let key = "medical.safety.l0.acknowledged.v1"

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadAcknowledged() throws -> Bool {
        let settings = try matchingSettings()
        guard let setting = settings.first else { return false }
        guard setting.value == "true" else {
            throw MedicalSafetyAcknowledgementStoreError.invalidValue
        }
        return true
    }

    func saveAcknowledged() throws {
        let settings = try matchingSettings()
        let timestamp = Date.now
        if let setting = settings.first {
            setting.value = "true"
            setting.updatedAt = timestamp
        } else {
            modelContext.insert(
                AppSetting(
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    key: Self.key,
                    value: "true"
                )
            )
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw MedicalSafetyAcknowledgementStoreError.saveFailed
        }
    }

    private func matchingSettings() throws -> [AppSetting] {
        let settings: [AppSetting]
        do {
            settings = try modelContext.fetch(FetchDescriptor<AppSetting>())
                .filter { $0.key == Self.key }
        } catch {
            throw MedicalSafetyAcknowledgementStoreError.loadFailed
        }
        guard settings.count <= 1 else {
            throw MedicalSafetyAcknowledgementStoreError.duplicateSettings
        }
        return settings
    }
}

private enum MedicalSafetyAcknowledgementStoreError: Error {
    case duplicateSettings
    case invalidValue
    case loadFailed
    case saveFailed
}
