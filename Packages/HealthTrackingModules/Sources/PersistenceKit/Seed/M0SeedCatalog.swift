import CoreModels
import Foundation

public enum M0SeedCatalog {
    public static func make(installedAt: Date) -> M0SeedPayload {
        M0SeedPayload(
            profile: .init(
                id: SeedIdentifiers.profile,
                createdAt: installedAt,
                updatedAt: installedAt,
                displayName: "",
                heightCm: 185,
                startWeightKg: 98,
                targetWeightKg: 90,
                unitsSystem: .metric,
                proteinTargetG: 120,
                calorieTarget: nil,
                carbTargetG: nil,
                fatTargetG: nil,
                programStartDate: installedAt,
                weeklyWorkoutTarget: 3
            ),
            program: .init(
                id: SeedIdentifiers.program,
                createdAt: installedAt,
                updatedAt: installedAt,
                name: "Tam Vücut v3 (Postür → Recomp)",
                descriptionText: "",
                isActive: true
            ),
            phases: [
                .init(id: SeedIdentifiers.phase1, createdAt: installedAt, updatedAt: installedAt, name: "Temel", orderIndex: 1, monthStart: 1, monthEnd: 2, trainingFocus: "Teknik + alışkanlık; OHP kademeli giriş; ölçümleri başlat", nutritionFocus: "Ölçülü açık; 120 g protein", milestone: "Alışkanlık + baseline + check-up", entryCriteria: ""),
                .init(id: SeedIdentifiers.phase2, createdAt: installedAt, updatedAt: installedAt, name: "İnşa", orderIndex: 2, monthStart: 3, monthEnd: 6, trainingFocus: "Çift progresyon; 10 kg yükler tırmanır; 20 kg tavan", nutritionFocus: "Açığı sürdür; bel+güç izle", milestone: "Bel↓, güç↑, ayarlanabilir DB", entryCriteria: ""),
                .init(id: SeedIdentifiers.phase3, createdAt: installedAt, updatedAt: installedAt, name: "İlerleme", orderIndex: 3, monthStart: 7, monthEnd: 9, trainingFocus: "Ağır DB; bileşiklerde ağır/az tekrar (kemik)", nutritionFocus: "Kilo düştükçe açığı yeniden kalibre", milestone: "Güç sıçraması + beslenme ayarı", entryCriteria: ""),
                .init(id: SeedIdentifiers.phase4, createdAt: installedAt, updatedAt: installedAt, name: "Konsolidasyon", orderIndex: 4, monthStart: 10, monthEnd: 12, trainingFocus: "Hacim eklemeyi durdur; kaliteyi koru", nutritionFocus: "Sürdürülebilir bakım", milestone: "Veriye dayalı 2. yıl kararı", entryCriteria: "")
            ],
            workoutDays: [
                .init(id: SeedIdentifiers.dayA, createdAt: installedAt, updatedAt: installedAt, name: "Gün A", orderIndex: 1, focus: "Squat Ağırlıklı"),
                .init(id: SeedIdentifiers.dayB, createdAt: installedAt, updatedAt: installedAt, name: "Gün B", orderIndex: 2, focus: "Hinge Ağırlıklı"),
                .init(id: SeedIdentifiers.dayC, createdAt: installedAt, updatedAt: installedAt, name: "Gün C", orderIndex: 3, focus: "Unilateral + Taşıma")
            ]
        )
    }
}
