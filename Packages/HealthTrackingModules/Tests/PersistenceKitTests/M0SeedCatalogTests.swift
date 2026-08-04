import CoreModels
@testable import PersistenceKit
import XCTest

final class M0SeedCatalogTests: XCTestCase {
    func testCatalogIsPureAndMapsTheRequirementProgramExactly() {
        let installedAt = Date(timeIntervalSinceReferenceDate: 123_456)

        let payload = M0SeedCatalog.make(installedAt: installedAt)

        XCTAssertEqual(payload.profile.id, UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
        XCTAssertEqual(payload.profile.displayName, "")
        XCTAssertEqual(payload.profile.heightCm, 185)
        XCTAssertEqual(payload.profile.startWeightKg, 98)
        XCTAssertEqual(payload.profile.targetWeightKg, 90)
        XCTAssertEqual(payload.profile.proteinTargetG, 120)
        XCTAssertEqual(payload.profile.unitsSystem, UnitsSystem.metric)
        XCTAssertNil(payload.profile.calorieTarget)
        XCTAssertNil(payload.profile.carbTargetG)
        XCTAssertNil(payload.profile.fatTargetG)
        XCTAssertEqual(payload.profile.programStartDate, installedAt)
        XCTAssertEqual(payload.profile.weeklyWorkoutTarget, 3)

        XCTAssertEqual(payload.program.id, UUID(uuidString: "00000000-0000-4000-8000-000000000100"))
        XCTAssertEqual(payload.program.name, "Tam Vücut v3 (Postür → Recomp)")
        XCTAssertEqual(payload.program.descriptionText, "")
        XCTAssertTrue(payload.program.isActive)
        XCTAssertEqual(
            payload.phases.map {
                PhaseSnapshot(
                    id: $0.id, name: $0.name, orderIndex: $0.orderIndex,
                    monthStart: $0.monthStart, monthEnd: $0.monthEnd,
                    trainingFocus: $0.trainingFocus, nutritionFocus: $0.nutritionFocus,
                    milestone: $0.milestone, entryCriteria: $0.entryCriteria
                )
            },
            [
                PhaseSnapshot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000111")!, name: "Temel", orderIndex: 1, monthStart: 1, monthEnd: 2, trainingFocus: "Teknik + alışkanlık; OHP kademeli giriş; ölçümleri başlat", nutritionFocus: "Ölçülü açık; 120 g protein", milestone: "Alışkanlık + baseline + check-up", entryCriteria: ""),
                PhaseSnapshot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000112")!, name: "İnşa", orderIndex: 2, monthStart: 3, monthEnd: 6, trainingFocus: "Çift progresyon; 10 kg yükler tırmanır; 20 kg tavan", nutritionFocus: "Açığı sürdür; bel+güç izle", milestone: "Bel↓, güç↑, ayarlanabilir DB", entryCriteria: ""),
                PhaseSnapshot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000113")!, name: "İlerleme", orderIndex: 3, monthStart: 7, monthEnd: 9, trainingFocus: "Ağır DB; bileşiklerde ağır/az tekrar (kemik)", nutritionFocus: "Kilo düştükçe açığı yeniden kalibre", milestone: "Güç sıçraması + beslenme ayarı", entryCriteria: ""),
                PhaseSnapshot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000114")!, name: "Konsolidasyon", orderIndex: 4, monthStart: 10, monthEnd: 12, trainingFocus: "Hacim eklemeyi durdur; kaliteyi koru", nutritionFocus: "Sürdürülebilir bakım", milestone: "Veriye dayalı 2. yıl kararı", entryCriteria: "")
            ]
        )
        XCTAssertEqual(
            payload.workoutDays.map { DaySnapshot(id: $0.id, name: $0.name, orderIndex: $0.orderIndex, focus: $0.focus) },
            [
                DaySnapshot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000201")!, name: "Gün A", orderIndex: 1, focus: "Squat Ağırlıklı"),
                DaySnapshot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000202")!, name: "Gün B", orderIndex: 2, focus: "Hinge Ağırlıklı"),
                DaySnapshot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000203")!, name: "Gün C", orderIndex: 3, focus: "Unilateral + Taşıma")
            ]
        )
        XCTAssertEqual(payload, M0SeedCatalog.make(installedAt: installedAt))
    }
}

private struct PhaseSnapshot: Equatable {
    let id: UUID
    let name: String
    let orderIndex: Int
    let monthStart: Int
    let monthEnd: Int
    let trainingFocus: String
    let nutritionFocus: String
    let milestone: String
    let entryCriteria: String
}

private struct DaySnapshot: Equatable {
    let id: UUID
    let name: String
    let orderIndex: Int
    let focus: String
}
