import CoreModels
import Foundation

public enum M1SeedCatalog {
    public static func make(
        installedAt: Date,
        programStartDate: Date? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> M1SeedPayload {
        let ferritinDueDate = calendar.date(byAdding: .month, value: 1, to: installedAt)!

        return M1SeedPayload(
            exercises: exercises(installedAt: installedAt),
            warmups: warmups(installedAt: installedAt),
            cooldowns: cooldowns(installedAt: installedAt),
            reminders: [
                reminder(
                    id: SeedIdentifiers.ferritinReminder,
                    installedAt: installedAt,
                    name: "Ferritin",
                    dueDate: ferritinDueDate,
                    recurrence: .none
                ),
                reminder(
                    id: SeedIdentifiers.vitaminDReminder,
                    installedAt: installedAt,
                    name: "D vitamini",
                    dueDate: installedAt,
                    recurrence: .none
                ),
                reminder(
                    id: SeedIdentifiers.generalCheckupReminder,
                    installedAt: installedAt,
                    name: "Genel check-up",
                    dueDate: installedAt,
                    recurrence: .yearly
                )
            ],
            programState: .init(
                id: SeedIdentifiers.programState,
                createdAt: installedAt,
                updatedAt: installedAt,
                programID: SeedIdentifiers.program,
                currentPhaseID: SeedIdentifiers.phase1,
                phaseStartedAt: programStartDate ?? installedAt,
                trainingWeekIndex: 1,
                deloadStatus: .none,
                deloadReason: nil,
                deloadUpdatedAt: nil,
                lastDeloadSkippedAt: nil,
                lastDeloadAction: nil
            )
        )
    }
}

private extension M1SeedCatalog {
    static func exercises(installedAt: Date) -> [M1SeedPayload.Exercise] {
        [
            exercise(
                id: SeedIdentifiers.gobletSquat,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayA,
                name: "Goblet Squat", order: 1, sets: 3, low: 15, high: 25,
                rirLow: 0, rirHigh: 1, category: .compound, allowsFailure: true,
                rule: .doubleProgression, measurement: .weightReps,
                safety: "3sn eksantrik; topuk kalkarsa plaka"
            ),
            exercise(
                id: SeedIdentifiers.chinUp,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayA,
                name: "Chin-up", order: 2, sets: 3, low: 6, high: 12,
                rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false,
                rule: .bodyweightProgression, measurement: .reps,
                safety: "faile gitme; boyun nötr"
            ),
            exercise(
                id: SeedIdentifiers.dbFloorPress,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayA,
                name: "DB Floor Press", order: 3, sets: 4, low: 8, high: 12,
                rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false,
                rule: .doubleProgression, measurement: .weightReps,
                safety: "dirsek 45°, yerde 1sn"
            ),
            exercise(
                id: SeedIdentifiers.dbRomanianDeadlift,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayA,
                name: "DB Romanian Deadlift", order: 4, sets: 3, low: 10, high: 12,
                rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false,
                rule: .doubleProgression, measurement: .weightReps,
                safety: "kalça menteşesi; bel değil hamstring"
            ),
            exercise(
                id: SeedIdentifiers.proneYTW,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayA,
                name: "Prone Y-T-W", order: 5, sets: 2, low: 8, high: 8,
                rirLow: 0, rirHigh: 0, category: .accessory, allowsFailure: false,
                rule: .timeQuality, measurement: .reps,
                safety: "ağırlıksız; tepede 2sn"
            ),
            exercise(
                id: SeedIdentifiers.facePull,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayA,
                name: "Face Pull (bant)", order: 6, sets: 3, low: 15, high: 20,
                rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: false,
                rule: .timeQuality, measurement: .reps,
                safety: "hafif; omuz yukarı kalkmasın"
            ),
            exercise(
                id: SeedIdentifiers.singleLegCalfRaise,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayA,
                name: "Tek Bacak Calf Raise", order: 7, sets: 2, low: 12, high: 20,
                rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: false,
                rule: .doubleProgression, measurement: .reps,
                safety: "1.set düz diz, 2.set bükük"
            ),
            exercise(
                id: SeedIdentifiers.plankPallof,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayA,
                name: "Plank / Pallof", order: 8, sets: 3, low: 30, high: 60,
                rirLow: 0, rirHigh: 0, category: .core, allowsFailure: false,
                rule: .timeQuality, measurement: .duration,
                safety: "haftada 1 Pallof"
            ),

            exercise(
                id: SeedIdentifiers.doubleDBRDL,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayB,
                name: "DB RDL (çift)", order: 1, sets: 3, low: 10, high: 12,
                rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false,
                rule: .doubleProgression, measurement: .weightReps,
                safety: "A'dan ağır; DB bacaktan uzaklaşmasın"
            ),
            exercise(
                id: SeedIdentifiers.singleArmDBRow,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayB,
                name: "Tek Kol DB Row", order: 2, sets: 4, low: 10, high: 12,
                rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false,
                rule: .doubleProgression, measurement: .weightReps,
                safety: "gövde döndürme"
            ),
            exercise(
                id: SeedIdentifiers.pushUp,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayB,
                name: "Push-up", order: 3, sets: 2, low: 10, high: 20,
                rirLow: 0, rirHigh: 1, category: .compound, allowsFailure: true,
                rule: .bodyweightProgression, measurement: .reps,
                safety: "kolaysa ayak yüksekte"
            ),
            exercise(
                id: SeedIdentifiers.dbOverheadPress,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayB,
                name: "DB Overhead Press", order: 4, sets: 3, low: 8, high: 12,
                rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false,
                rule: .gradedEntryOHP, measurement: .weightReps,
                safety: "Sağ işaret parmağı uyuşursa kes → Half-Kneeling DB Press",
                startingWeight: 10
            ),
            exercise(
                id: SeedIdentifiers.bulgarianSplitSquat,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayB,
                name: "Bulgarian Split Squat", order: 5, sets: 3, low: 8, high: 12,
                rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false,
                rule: .doubleProgression, measurement: .weightReps,
                safety: "gövde dik/hafif öne"
            ),
            exercise(
                id: SeedIdentifiers.gluteBridgeHipThrust,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayB,
                name: "Glute Bridge / Hip Thrust", order: 6, sets: 3, low: 12, high: 20,
                rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: true,
                rule: .doubleProgression, measurement: .reps,
                safety: "topuktan it; beli yaylandırma"
            ),
            exercise(
                id: SeedIdentifiers.wallSlide,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayB,
                name: "Wall Slide", order: 7, sets: 2, low: 10, high: 12,
                rirLow: 0, rirHigh: 0, category: .accessory, allowsFailure: false,
                rule: .timeQuality, measurement: .reps,
                safety: "temas kaybolmadan"
            ),
            exercise(
                id: SeedIdentifiers.deadBug,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayB,
                name: "Dead Bug", order: 8, sets: 2, low: 8, high: 10,
                rirLow: 0, rirHigh: 0, category: .core, allowsFailure: false,
                rule: .timeQuality, measurement: .reps,
                safety: "bel yerden kalkmasın"
            ),
            exercise(
                id: SeedIdentifiers.copenhagenPlank,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayB,
                name: "Copenhagen Plank", order: 9, sets: 2, low: 15, high: 30,
                rirLow: 0, rirHigh: 0, category: .core, allowsFailure: false,
                rule: .timeQuality, measurement: .duration,
                safety: "aşama: diz → ayak sehpada"
            ),

            exercise(
                id: SeedIdentifiers.reverseLunge,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayC,
                name: "Reverse Lunge (DB)", order: 1, sets: 3, low: 8, high: 12,
                rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false,
                rule: .doubleProgression, measurement: .weightReps,
                safety: "ağırlık ön ayakta"
            ),
            exercise(
                id: SeedIdentifiers.nordicHamstringCurl,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayC,
                name: "Nordic Hamstring Curl", order: 2, sets: 2, low: 3, high: 5,
                rirLow: 0, rirHigh: 0, category: .compound, allowsFailure: false,
                rule: .timeQuality, measurement: .reps,
                safety: "İlk 2 hafta 2×3'ü aşma (DOMS)"
            ),
            exercise(
                id: SeedIdentifiers.pullUpBanded,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayC,
                name: "Pull-up / bantlı", order: 3, sets: 2, low: nil, high: nil,
                rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false,
                rule: .bodyweightProgression, measurement: .reps,
                safety: "skapular set; zorsa bant"
            ),
            exercise(
                id: SeedIdentifiers.bandedSingleArmRow,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayC,
                name: "Bantlı / Tek Kol Row", order: 4, sets: 3, low: 12, high: 15,
                rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: false,
                rule: .doubleProgression, measurement: .reps,
                safety: "bitişte en zor"
            ),
            exercise(
                id: SeedIdentifiers.halfKneelingDBPress,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayC,
                name: "Half-Kneeling DB Press", order: 5, sets: 3, low: 8, high: 10,
                rirLow: 1, rirHigh: 2, category: .compound, allowsFailure: false,
                rule: .doubleProgression, measurement: .weightReps,
                safety: "OHP'de semptomda dönüş yeri"
            ),
            exercise(
                id: SeedIdentifiers.dbLateralRaise,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayC,
                name: "DB Lateral Raise", order: 6, sets: 3, low: 12, high: 20,
                rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: false,
                rule: .doubleProgression, measurement: .weightReps,
                safety: "omuz hizasında dur"
            ),
            exercise(
                id: SeedIdentifiers.farmersCarry,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayC,
                name: "Farmer's Carry", order: 7, sets: 3, low: 30, high: 40,
                rirLow: 0, rirHigh: 0, category: .accessory, allowsFailure: false,
                rule: .timeQuality, measurement: .steps,
                safety: "en ağır 2 DB"
            ),
            exercise(
                id: SeedIdentifiers.curl,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayC,
                name: "Curl", order: 8, sets: 2, low: 10, high: 15,
                rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: false,
                rule: .doubleProgression, measurement: .weightReps,
                safety: "curl 10 kg başlangıç", startingWeight: 10,
                supersetGroupID: SeedIdentifiers.curlTricepsSuperset, supersetOrder: 1
            ),
            exercise(
                id: SeedIdentifiers.triceps,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayC,
                name: "Triceps", order: 9, sets: 2, low: 10, high: 15,
                rirLow: 0, rirHigh: 1, category: .accessory, allowsFailure: false,
                rule: .doubleProgression, measurement: .reps,
                safety: "başlangıç ağırlığını ilk kayıtta seç",
                supersetGroupID: SeedIdentifiers.curlTricepsSuperset, supersetOrder: 2
            ),
            exercise(
                id: SeedIdentifiers.sidePlankPallof,
                installedAt: installedAt,
                dayID: SeedIdentifiers.dayC,
                name: "Side Plank / Pallof", order: 10, sets: 2, low: 20, high: 40,
                rirLow: 0, rirHigh: 0, category: .core, allowsFailure: false,
                rule: .timeQuality, measurement: .duration,
                safety: "kalça düşerse bitti"
            )
        ]
    }

    static func warmups(installedAt: Date) -> [M1SeedPayload.Warmup] {
        warmups(
            installedAt: installedAt,
            dayID: SeedIdentifiers.dayA,
            ids: SeedIdentifiers.warmupDayA,
            entries: [
                (.raise, "İp / koşu", "60–90 sn"),
                (.raise, "Kol çevirme", "10"),
                (.raise, "Çömeliş-kalkış", "8"),
                (.raise, "Bacak sallama ön-arka", "10/bacak"),
                (.activate, "Knee-to-wall", "10/taraf"),
                (.activate, "90/90 kalça", "8/yön"),
                (.activate, "Band pull-apart", "15"),
                (.potentiate, "BW squat", "8"),
                (.potentiate, "DB squat rampa", "~10 kg × 5")
            ]
        ) + warmups(
            installedAt: installedAt,
            dayID: SeedIdentifiers.dayB,
            ids: SeedIdentifiers.warmupDayB,
            entries: [
                (.raise, "İp / koşu", "60–90 sn"),
                (.raise, "Kol çevirme", "10"),
                (.raise, "Çömeliş-kalkış", "8"),
                (.raise, "Bacak sallama ön-arka", "10/bacak"),
                (.activate, "Yarım diz kalça fleksörü", "8/taraf"),
                (.activate, "Bacak sallama yan + ön", "10"),
                (.activate, "Open book", "8/taraf"),
                (.activate, "Omuz dış rotasyon", "15/kol"),
                (.activate, "Wall slide", "10"),
                (.potentiate, "Boş hinge", "8"),
                (.potentiate, "Hafif hinge", "5"),
                (.potentiate, "OHP boş press", "8")
            ]
        ) + warmups(
            installedAt: installedAt,
            dayID: SeedIdentifiers.dayC,
            ids: SeedIdentifiers.warmupDayC,
            entries: [
                (.raise, "İp / koşu", "60–90 sn"),
                (.raise, "Kol çevirme", "10"),
                (.raise, "Çömeliş-kalkış", "8"),
                (.raise, "Bacak sallama ön-arka", "10/bacak"),
                (.activate, "Yarım diz kalça fleksörü", "8/taraf"),
                (.activate, "Wall slide", "10"),
                (.activate, "Omuz dış rotasyon", "15/kol"),
                (.potentiate, "BW lunge", "5/bacak"),
                (.potentiate, "Hafif lunge", "3/bacak")
            ]
        )
    }

    static func cooldowns(installedAt: Date) -> [M1SeedPayload.Cooldown] {
        cooldowns(
            installedAt: installedAt,
            dayID: SeedIdentifiers.dayA,
            ids: SeedIdentifiers.cooldownDayA
        ) + cooldowns(
            installedAt: installedAt,
            dayID: SeedIdentifiers.dayB,
            ids: SeedIdentifiers.cooldownDayB
        ) + cooldowns(
            installedAt: installedAt,
            dayID: SeedIdentifiers.dayC,
            ids: SeedIdentifiers.cooldownDayC
        )
    }

    static func exercise(
        id: UUID,
        installedAt: Date,
        dayID: UUID,
        name: String,
        order: Int,
        sets: Int,
        low: Int?,
        high: Int?,
        rirLow: Int,
        rirHigh: Int,
        category: ExerciseCategory,
        allowsFailure: Bool,
        rule: ProgressionRule,
        measurement: ExerciseMeasurementKind,
        safety: String?,
        startingWeight: Double? = nil,
        supersetGroupID: UUID? = nil,
        supersetOrder: Int? = nil
    ) -> M1SeedPayload.Exercise {
        .init(
            id: id,
            createdAt: installedAt,
            updatedAt: installedAt,
            workoutDayID: dayID,
            name: name,
            orderIndex: order,
            targetSets: sets,
            repLow: low,
            repHigh: high,
            rirLow: rirLow,
            rirHigh: rirHigh,
            category: category,
            allowFailure: allowsFailure,
            cues: "",
            safetyNote: safety,
            startingWeightKg: startingWeight,
            progressionRule: rule,
            measurementKind: measurement,
            supersetGroupID: supersetGroupID,
            supersetOrder: supersetOrder
        )
    }

    static func warmups(
        installedAt: Date,
        dayID: UUID,
        ids: [UUID],
        entries: [(WarmupPhase, String, String)]
    ) -> [M1SeedPayload.Warmup] {
        precondition(ids.count == entries.count)
        return zip(ids, entries).enumerated().map { index, pair in
            M1SeedPayload.Warmup(
                id: pair.0,
                createdAt: installedAt,
                updatedAt: installedAt,
                workoutDayID: dayID,
                phase: pair.1.0,
                movement: pair.1.1,
                dose: pair.1.2,
                orderIndex: index + 1
            )
        }
    }

    static func cooldowns(
        installedAt: Date,
        dayID: UUID,
        ids: [UUID]
    ) -> [M1SeedPayload.Cooldown] {
        let entries: [(String, String, String?)] = [
            ("Pektoral germe", "30 sn × 2/taraf", nil),
            ("C6 nöral gliding", "1 × 10", "Uyuşma dönerse dur"),
            ("Chin tuck", "1 × 10", nil)
        ]
        precondition(ids.count == entries.count)
        return zip(ids, entries).enumerated().map { index, pair in
            M1SeedPayload.Cooldown(
                id: pair.0,
                createdAt: installedAt,
                updatedAt: installedAt,
                workoutDayID: dayID,
                movement: pair.1.0,
                dose: pair.1.1,
                note: pair.1.2,
                orderIndex: index + 1
            )
        }
    }

    static func reminder(
        id: UUID,
        installedAt: Date,
        name: String,
        dueDate: Date,
        recurrence: HealthCheckRecurrence
    ) -> M1SeedPayload.Reminder {
        .init(
            id: id,
            createdAt: installedAt,
            updatedAt: installedAt,
            name: name,
            dueDate: dueDate,
            recurrence: recurrence,
            status: .pending
        )
    }
}
