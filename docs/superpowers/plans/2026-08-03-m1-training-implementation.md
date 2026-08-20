# M1 Bugün ve Antrenman — Uygulama Planı

> **Yürütme kuralı:** Bu plan `feat/m1-training` dalında, görev başına test-only RED → aynı commit amend ile GREEN → exact-SHA CI → review döngüsüyle uygulanır.

**Goal:** Bugün direktifi, tam A/B/C programı, resumable session kaydı ve bağlayıcı guidance kurallarını uçtan uca teslim etmek.

**Architecture:** `GuidanceKit` saf karar motorudur; `TrainingKit` repository protokolleri, immutable snapshot'lar, view model ve SwiftUI akışlarına sahiptir; `PersistenceKit` SwiftData implementasyonlarını sağlar; app target yalnız composition/routing yapar.

**Tech Stack:** Swift 5.9, SwiftUI, Observation, SwiftData, XCTest, XCUITest, XcodeGen 2.46+, iOS 17+, GitHub Actions `macos-15` / Xcode 16.4.

**Binding references:**

- `Saglik-Takip-App-Gereksinim-Dokumani-v1.md`
- `docs/superpowers/specs/2026-08-03-health-tracking-app-design.md`
- `docs/superpowers/specs/2026-08-20-m1-training-design.md`
- `docs/superpowers/plans/2026-08-03-health-tracking-app-roadmap.md`
- `docs/handoff/CONTINUE-M0-FOUNDATION.md`

**Base:** `87b5330e8288598ce33853967e830d183636cef1` (`feat/m0-foundation` accepted)

---

## 1. Milestone-wide execution contract

### 1.1 Before every M1.x task

1. Confirm clean tree and record `git rev-parse HEAD`.
2. Confirm current branch is `feat/m1-training`.
3. Inspect live `origin` and `gitea` tips when reachable.
4. Keep the task's production files untouched until the test-only commit is pushed.
5. Do not mix later M1 behavior into an earlier task merely to make a broad test pass.

### 1.2 RED checkpoint

1. Add only tests, fixtures, and the minimum test harness required to compile the test.
2. If a brand-new target cannot be referenced before its manifest entry exists, use a contract test against `Package.swift` as the first RED; add the target in GREEN.
3. Run the narrowest relevant local/static command available.
4. Commit with the task's final subject.
5. Push the provisional tip to GitHub and reachable Gitea.
6. Require a GitHub Actions failure caused by the asserted missing behavior. Infrastructure, billing, checkout, zero-test or unrelated failures do not qualify.
7. Record run ID, job ID, URL, head SHA and failure excerpt outside the commit until final M1 evidence is assembled.

### 1.3 GREEN checkpoint

1. Implement only the behavior asserted by the task plus required refactor.
2. Amend the provisional task commit; do not add a second implementation commit for the same task.
3. Run focused tests, then `./scripts/test-ios.sh` on macOS/CI.
4. Require Local Debug tests, Local Release build, screenshot export contract and Cloud compile-only where workflow applies.
5. Run `git diff --check`, localization verification, requirements verification and task-specific static scans.
6. Review requirement coverage, architecture boundaries, safety, accessibility, localization, privacy and test quality.
7. Resolve every verified Critical/Important finding with test-first corrections and amend again.
8. Push with exact `--force-with-lease` against the observed provisional tip.
9. Accept only the exact final SHA whose GitHub Actions run is GREEN.

### 1.4 Remote outage policy

GitHub and Gitea normally receive every provisional and accepted tip. Per the user's 2026-08-20 instruction, Gitea unavailability does not pause local/GitHub progress. For every deferred push record branch, expected old tip and new exact SHA. When Gitea returns, inspect the live tip and reconcile without overwriting unknown work. M1 cannot receive final milestone acceptance until the backlog is empty.

### 1.5 Review and evidence

- Request Fable 5 medium when available. If unavailable, record `NOT RUN`; do not substitute another model under its name.
- Review output format: Critical, Important, Minor, coverage, test quality, architecture, accessibility/localization, security/privacy, verdict.
- `docs/evidence/M1/acceptance.md` is assembled in M1.16 from immutable git history and Actions data. It includes all task RED/GREEN pairs, exact hashes, run/job URLs, test counts, artifacts, remote equality and honest device-only/Fable status.

---

## 2. Common file layout

New production areas expected across M1:

```text
Packages/HealthTrackingModules/Sources/GuidanceKit/
  Rotation/
  Progression/
  Safety/
  Deload/
  Phase/
  Records/
  Today/

Packages/HealthTrackingModules/Sources/TrainingKit/
  Repository/
  Snapshots/
  Today/
  Session/
  History/
  Haptics/
  Resources/Localizable.xcstrings

Packages/HealthTrackingModules/Sources/PersistenceKit/
  Repositories/
  Seed/

Packages/HealthTrackingModules/Tests/GuidanceKitTests/
Packages/HealthTrackingModules/Tests/TrainingKitTests/
Packages/HealthTrackingModules/Tests/PersistenceKitTests/
```

Names may be tightened during implementation, but ownership and dependency direction may not change without updating the design first.

---

## 3. M1.1 — Tam seed catalog

**Final subject:** `feat(seed): add complete training catalog`

**Test files:**

- Add `Packages/HealthTrackingModules/Tests/PersistenceKitTests/M1SeedCatalogFixtureTests.swift`
- Extend `Packages/HealthTrackingModules/Tests/PersistenceKitTests/SwiftDataSeedLoaderTests.swift`
- Extend `Packages/HealthTrackingModules/Tests/PersistenceKitTests/TrainingRepositoryContractTests.swift`

**Production files:**

- Add `Packages/HealthTrackingModules/Sources/PersistenceKit/Seed/M1SeedPayload.swift`
- Add `Packages/HealthTrackingModules/Sources/PersistenceKit/Seed/M1SeedCatalog.swift`
- Extend `Packages/HealthTrackingModules/Sources/PersistenceKit/Seed/SeedIdentifiers.swift`
- Modify `Packages/HealthTrackingModules/Sources/PersistenceKit/Seed/SwiftDataSeedLoader.swift`
- Modify `Packages/HealthTrackingModules/Sources/TrainingKit/Repository/TrainingRepository.swift`
- Modify `Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataTrainingRepository.swift`

### RED

Write fixture tests proving:

- exactly 27 exercise records with 8/9/10 distribution across A/B/C;
- exact day/order/name/sets/rep/RIR/category/failure/rule/safety/starting-weight data;
- master-design measurement mapping, including bodyweight corrections and nil Pull-up ceiling;
- Curl and Triceps are separate with one stable superset group;
- all common/day-specific warmups and three cooldowns exist in deterministic order;
- Ferritin, D vitamini and Genel check-up reminders exist with correct recurrence semantics;
- one ProgramState points to Program and phase 1;
- marker 1 upgrades once, marker 2 is idempotent, and deletion after marker 2 is not resurrected;
- save failure rolls back every M1 addition.

Expected RED: M0 payload contains only profile/program/phases/day shells.

### GREEN

Implement an immutable M1 payload and deterministic IDs. Evolve seed loader to version 2 while preserving marker-1 upgrade and post-marker deletion semantics. Associate every child with the existing program/day objects and insert in one transaction. Add repository reads required to assert the full ordered program.

### Verification

- Focused: `PersistenceKitTests/M1SeedCatalogFixtureTests`, seed loader and repository contracts.
- Static: exactly 27 unique exercise IDs/names; no `/` row accidentally expanded except the explicit Curl/Triceps split; no placeholder safety note.
- Full suite and both persistence modes compile; Cloud compile is not sync proof.

---

## 4. M1.2 — Guidance rotation

**Final subject:** `feat(guidance): add workout rotation`

**Test files:**

- Add `Packages/HealthTrackingModules/Tests/GuidanceKitTests/WorkoutRotationTests.swift`
- Add `Packages/HealthTrackingModules/Tests/GuidanceKitTests/TodayDirectiveTests.swift`

**Production files:**

- Modify `Packages/HealthTrackingModules/Package.swift`
- Add `Packages/HealthTrackingModules/Sources/GuidanceKit/Rotation/WorkoutRotation.swift`
- Add `Packages/HealthTrackingModules/Sources/GuidanceKit/Today/TodayDirective.swift`

### RED

Start with a manifest contract test if the absent target prevents test compilation. Then prove:

- in-progress session wins over all other decisions;
- no history selects A;
- A→B→C→A uses `orderIndex`, not localized names;
- same-day completion, previous-calendar-day completion and weekly-target reached return distinct rest reasons;
- rest preserves the next template;
- explicit override changes rest to train without mutating history;
- week/day boundaries use injected calendar and timezone;
- duplicate/missing template inputs return explicit invalid-data results rather than arbitrary selection.

Expected RED: `GuidanceKit` and rotation types do not exist.

### GREEN

Add library/test targets and pure Sendable value types. Implement deterministic rotation and reason codes without repository/UI imports. Do not add progression logic in this task.

### Verification

- `GuidanceKitTests/WorkoutRotationTests`
- `GuidanceKitTests/TodayDirectiveTests`
- Static import scan rejects SwiftUI/SwiftData/CloudKit/UIKit under `Sources/GuidanceKit`.
- Full suite.

---

## 5. M1.3 — Set invariant ve draft state

**Final subject:** `feat(training): add validated set drafts`

**Test files:**

- Extend `Packages/HealthTrackingModules/Tests/CoreModelsTests/SetMeasurementValidatorTests.swift`
- Add `Packages/HealthTrackingModules/Tests/TrainingKitTests/SetDraftTests.swift`
- Add persistence mutation cases to `Packages/HealthTrackingModules/Tests/PersistenceKitTests/TrainingRepositoryContractTests.swift`

**Production files:**

- Modify `Packages/HealthTrackingModules/Sources/CoreModels/Domain/SetMeasurementValidator.swift`
- Add `Packages/HealthTrackingModules/Sources/TrainingKit/Session/SetDraft.swift`
- Add `Packages/HealthTrackingModules/Sources/TrainingKit/Snapshots/TrainingSnapshots.swift`
- Extend `Packages/HealthTrackingModules/Sources/TrainingKit/Repository/TrainingRepository.swift`
- Extend `Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataTrainingRepository.swift`

### RED

Cover every measurement kind and boundary:

- weightReps needs finite nonnegative weight and positive reps;
- reps needs positive reps and may carry optional valid weight;
- duration needs positive seconds and rejects unrelated measurements;
- steps needs positive steps and may carry optional valid weight;
- quality permits an empty completion marker or exactly one positive reps/duration value;
- RIR nil is permitted, 0...10 valid, outside invalid;
- invalid/ambiguous input never changes persistent set count;
- logical duplicate set index is rejected;
- prefill precedence is guidance → same-session previous → prior-session same index → seed;
- `RIR —` maps to nil, never zero.

Expected RED: draft and write repository APIs do not exist; validator gaps fail where present.

### GREEN

Introduce immutable snapshots and a mutable view-model draft that delegates final validation to CoreModels. Repository repeats validation inside the transaction and returns the saved snapshot. Keep SwiftData model references out of view/view-model APIs.

### Verification

- CoreModels validator tests.
- TrainingKit draft tests.
- Persistence mutation/rollback tests.
- Static scan: no `ModelContext`/`import SwiftData` in TrainingKit.

---

## 6. M1.4 — Session lifecycle ve restore

**Final subject:** `feat(training): add resumable session lifecycle`

**Test files:**

- Add `Packages/HealthTrackingModules/Tests/CoreModelsTests/WorkoutSessionProgressCodecTests.swift`
- Add `Packages/HealthTrackingModules/Tests/CoreModelsTests/SchemaV2MigrationTests.swift`
- Add `Packages/HealthTrackingModules/Tests/PersistenceKitTests/WorkoutSessionLifecycleTests.swift`
- Add `Packages/HealthTrackingModules/Tests/TrainingKitTests/SessionCoordinatorTests.swift`

**Production files:**

- Add `Packages/HealthTrackingModules/Sources/CoreModels/Domain/WorkoutSessionProgressCodec.swift`
- Add `Packages/HealthTrackingModules/Sources/CoreModels/Models/WorkoutSessionProgress.swift`
- Add `Packages/HealthTrackingModules/Sources/CoreModels/Schema/HealthTrackingSchemaV2.swift`
- Modify `Packages/HealthTrackingModules/Sources/CoreModels/Schema/HealthTrackingMigrationPlan.swift`
- Modify `Packages/HealthTrackingModules/Sources/PersistenceKit/Container/ModelContainerFactory.swift`
- Extend training repository protocol/implementation
- Add `Packages/HealthTrackingModules/Sources/TrainingKit/Session/SessionCoordinator.swift`

### RED

Prove:

- V1 disk store opens under V2 and retains M0 records;
- session progress UUID collections encode deterministically and malformed/unknown versions fail;
- one in-progress session and one progress row per session;
- legal planned/inProgress/completed/skipped transitions and illegal transition rejection;
- completed/skipped cannot reopen;
- each set/progress mutation survives a new container/repository instance;
- restore uses stored stage, current exercise and checklist state;
- missing/corrupt progress falls back from set history without deleting safe data;
- incomplete completion keeps valid sets and adds no fake set;
- session deletion cleans sets and progress idempotently.

Expected RED: progress entity/schema and lifecycle APIs do not exist.

### GREEN

Add schema V2 by preserving all V1 models and adding only `WorkoutSessionProgress`; use lightweight migration. Implement atomic lifecycle repository methods and a coordinator that expresses user intents without persistence imports.

### Verification

- Schema/model tests and real file-backed migration test.
- Lifecycle contract suite with repository re-instantiation.
- Cloud scheme compile.
- Model inventory updated intentionally for exactly one new entity.

---

## 7. M1.5 — Guided session UI

**Final subject:** `feat(training): add guided session flow`

**Test files:**

- Add `Packages/HealthTrackingModules/Tests/TrainingKitTests/SessionViewModelTests.swift`
- Add `HealthTrackingAppUITests/TrainingSessionFlowUITests.swift`
- Extend app composition tests as needed.

**Production files:**

- Add `TrainingKit/Session/SessionViewModel.swift`
- Add `TrainingKit/Session/TrainingSessionView.swift`
- Add `TrainingKit/Session/WarmupStageView.swift`
- Add `TrainingKit/Session/ExerciseStageView.swift`
- Add `TrainingKit/Session/SetEntryBar.swift`
- Add `TrainingKit/Session/CooldownStageView.swift`
- Add `TrainingKit/Session/SessionSummaryView.swift`
- Add localized strings to TrainingKit catalog
- Modify `App/Application/AppDependencies.swift`
- Modify `App/Application/AppRootView.swift`
- Modify `App/Support/AppUITestLaunchConfiguration.swift`

### RED

View-model tests cover load, start, resume, stage navigation, skip, incomplete finish, delete confirmation intent, save retry and optional summary values. UI tests prove:

- Today/Training can open a real full-screen session;
- warmup → exercises → cooldown → summary order;
- target, recommendation reason, safety note and failure warning appear at the correct exercise;
- accepted prefill saves in one tap;
- one stepper change plus save and RIR chip plus save each require two taps;
- record bar adapts to weight/reps/duration/steps/quality;
- session resume survives relaunch using real in-memory seed/repository path;
- optional recovery/note remain empty unless chosen.

Expected RED: session views/view model/routes are absent.

### GREEN

Build the session deck using existing DesignSystem tokens. Keep interaction state in the view model, mutations in repository, and rules in GuidanceKit. Provide stable accessibility identifiers only where tests or automation need a semantic contract.

### Verification

- TrainingKit view-model suite.
- Targeted XCUITest flow.
- Light/dark screenshots for warmup, each measurement bar family, safety, cooldown and summary.
- No raw colors, magic `kg`, direct ModelContext or fake actions.

---

## 8. M1.6 — Strict double progression

**Final subject:** `feat(guidance): add strict double progression`

**Test files:**

- Add `Packages/HealthTrackingModules/Tests/GuidanceKitTests/DoubleProgressionTests.swift`
- Extend SessionViewModel and UI tests for reason rendering.

**Production files:**

- Add `GuidanceKit/Progression/DoubleProgression.swift`
- Wire immutable history inputs through repository snapshots and session view model
- Extend TrainingKit catalog.

### RED

Truth-table tests require all sets at `repHigh`, every RIR present, every `rir <= rirLow`, and real external weight. Individually violate each condition. Cover mixed weights, warmup exclusion, nil rep ceiling, empty set list and the exact +2.5/reset-to-repLow result.

Expected RED: no double-progression engine exists.

### GREEN

Return a structured suggestion with proposed measurement and reason code. Do not persist suggestions; only user-confirmed set values persist.

### Verification

- Full truth-table unit suite.
- View-model mapping for missing RIR and hold reasons.
- UI evidence that missing RIR never displays +2.5 kg.

---

## 9. M1.7 — Bodyweight ve haftalık Pallof

**Final subject:** `feat(guidance): add bodyweight and Pallof progression`

**Test files:**

- Add `GuidanceKitTests/BodyweightProgressionTests.swift`
- Add `GuidanceKitTests/WeeklyPallofSelectionTests.swift`
- Extend set/session UI tests for variant persistence.

**Production files:**

- Add `GuidanceKit/Progression/BodyweightProgression.swift`
- Add `GuidanceKit/Progression/WeeklyPallofSelection.swift`
- Extend draft/session UI for `performedVariant`.

### RED

Cover same-variant comparison, below/at ceiling, nil ceiling, no defined harder variant, optional external weight, week boundaries across both Pallof templates, prior Pallof vs no Pallof and explicit user override persisted as the real variant.

Expected RED: engines and variant control are absent.

### GREEN

Implement conservative bodyweight outputs and one program-wide Pallof decision. Never convert band assistance to kilograms or invent a variant.

### Verification

- Guidance unit suites.
- Repository round-trip of performedVariant.
- UI screenshot/VoiceOver value for variant chooser.

---

## 10. M1.8 — OHP safety gate

**Final subject:** `feat(guidance): add OHP safety gate`

**Test files:**

- Add `GuidanceKitTests/OHPSafetyGateTests.swift`
- Add repository tests for writing the prior/current session symptom result
- Add `HealthTrackingAppUITests/OHPSafetyFlowUITests.swift`

**Production files:**

- Add `GuidanceKit/Safety/OHPSafetyGate.swift`
- Extend SessionCoordinator/ViewModel/View and repository methods
- Extend localization catalog.

### RED

Cover first session, weeks 1–2/3–4/5+, notAsked/symptomFree/symptomsPresent/uncertain, response written to prior OHP session, current symptom stop, no increase without explicit symptomFree and Half-Kneeling alternative. Test wording exposes no diagnosis.

Expected RED: OHP engine and UI gate are absent.

### GREEN

Insert the single prior-session question before warmup when required. Current symptom action stops only OHP, records the event on the current session and routes to the existing Half-Kneeling template. Do not create M3 PostureMetric behavior.

### Verification

- Guidance and repository suites.
- UI screenshots for question, blocked state and alternative.
- Static scan for required safety/non-medical localization keys.

---

## 11. M1.9 — Equipment ceiling ve phase focus

**Final subject:** `feat(guidance): add equipment and phase rules`

**Test files:**

- Add `GuidanceKitTests/EquipmentCeilingTests.swift`
- Add `GuidanceKitTests/PhaseTrainingFocusTests.swift`

**Production files:**

- Add `GuidanceKit/Progression/EquipmentCeiling.swift`
- Add `GuidanceKit/Phase/PhaseTrainingFocus.swift`
- Wire reason codes to exercise presentation.

### RED

Cover below/at/over 20 kg, exact clamp, repeat→tempo→unilateral ordering, no invented tempo value, phase 1/2 vs phase 3/4 behavior, `boneFocusHeavy` only and existing lower rep bound.

Expected RED: ceiling/focus policies do not exist.

### GREEN

Compose ceiling after base progression and phase focus without mutating persisted history. Render the investment text as information, never requirement.

### Verification

- Guidance unit suites.
- UI reason rendering and locale-aware weight formatting.

---

## 12. M1.10 — Scheduled/reactive deload

**Final subject:** `feat(guidance): add deload workflow`

**Test files:**

- Add `GuidanceKitTests/TrainingWeekTests.swift`
- Add `GuidanceKitTests/DeloadGuidanceTests.swift`
- Add persistence `ProgramState` contract tests
- Add `HealthTrackingAppUITests/DeloadFlowUITests.swift`

**Production files:**

- Add `GuidanceKit/Deload/TrainingWeek.swift`
- Add `GuidanceKit/Deload/DeloadGuidance.swift`
- Extend repository ProgramState APIs
- Add TrainingKit deload presentation/actions.

### RED

Cover 1-based week calculation; increment only after a completed session in a new local program week; same-week stability; start-date edit recalculation; scheduled weeks 5/10/15; two-session stagnation at same load and non-increasing total reps; false positives; 50% default and equipment rounding; accept/stay/techniqueReview/skip; active/skipped rollover; perceivedRecovery exclusion.

Expected RED: week/deload engines and state mutations are absent.

### GREEN

Implement pure recommendation and repository-owned state transition. Add Today/session deload explanation and choices; no automatic program mutation beyond confirmed state.

### Verification

- Guidance truth tables and ProgramState persistence.
- UI tests for scheduled and reactive flows.
- Warning is visible text/icon plus optional haptic, never color/haptic alone.

---

## 13. M1.11 — Phase transition

**Final subject:** `feat(guidance): add phase transitions`

**Test files:**

- Add `GuidanceKitTests/PhaseTransitionTests.swift`
- Add repository active-phase transition tests
- Add TrainingKit phase-card view-model tests.

**Production files:**

- Add `GuidanceKit/Phase/PhaseTransition.swift`
- Extend ProgramState repository methods
- Add TrainingKit phase checklist/confirmation presentation
- Connect manual Settings route without implementing unrelated Settings redesign.

### RED

Cover month estimates at calendar boundaries, missing/empty criteria, no numerical invented threshold, confirm vs stay, next/last phase, manual phase selection, `phaseStartedAt` update and duplicate ProgramState integrity.

Expected RED: phase decision/mutation APIs are absent.

### GREEN

Return estimate and checklist only; write phase after explicit confirmation. “Şimdilik kal” dismisses current priority alert without fixed silence interval.

### Verification

- Guidance/repository/view-model suites.
- UI evidence for checklist and destructive-free explicit confirmation.

---

## 14. M1.12 — Personal record detection

**Final subject:** `feat(guidance): add personal record detection`

**Test files:**

- Add `GuidanceKitTests/PersonalRecordTests.swift`
- Add TrainingKit summary/history PR mapping tests.

**Production files:**

- Add `GuidanceKit/Records/EpleyEstimate.swift`
- Add `GuidanceKit/Records/PersonalRecordDetector.swift`
- Extend session summary/history presentation and strings.

### RED

Cover central Epley math and precision policy; weighted comparison; same-variant bodyweight reps/duration; steps only at same/higher load; first baseline; ties; invalid measurements; warmup exclusion; edited/deleted history recalculation; no PR for a different variant.

Expected RED: PR engine is absent.

### GREEN

Implement pure record results with baseline/notRecord/newRecord reason. Use restrained presentation and success haptic hook only for a true new record.

### Verification

- Deterministic unit tests.
- Summary/history state tests.
- Static/UI scan rejects confetti, badge, streak and score semantics.

---

## 15. M1.13 — History, edit ve delete

**Final subject:** `feat(training): add session history editing`

**Test files:**

- Add `PersistenceKitTests/TrainingHistoryRepositoryTests.swift`
- Add `TrainingKitTests/TrainingHistoryViewModelTests.swift`
- Add `HealthTrackingAppUITests/TrainingHistoryUITests.swift`

**Production files:**

- Add `TrainingKit/History/TrainingHistoryViewModel.swift`
- Add `TrainingKit/History/TrainingHistoryView.swift`
- Add `TrainingKit/History/WorkoutSessionDetailView.swift`
- Add `TrainingKit/History/EditSetView.swift`
- Extend repository history/edit/delete APIs and localization.

### RED

Cover deterministic reverse chronology and tie-break; empty/error/retry; missing template fallback; edit validation/rollback; set delete; session delete cleanup; destructive confirmation; updatedAt; and refreshed progression/PR after every mutation.

Expected RED: history UI and mutation contracts are absent.

### GREEN

Build repository-backed list/detail/edit flows. Never cache derived progression or PR in SwiftData. Preserve user input on recoverable save error.

### Verification

- Persistence and view-model suites.
- UI edit/delete/relaunch flow.
- VoiceOver custom actions for set edit/delete.

---

## 16. M1.14 — Today variants ve cold-launch performance

**Final subject:** `feat(app): add Today training guidance`

**Test files:**

- Add `TrainingKitTests/TodayViewModelTests.swift`
- Add `HealthTrackingAppTests/TodayCompositionTests.swift`
- Add `HealthTrackingAppUITests/TodayGuidanceUITests.swift`
- Add or extend launch performance measurement test.

**Production files:**

- Add `TrainingKit/Today/TodayViewModel.swift`
- Add `TrainingKit/Today/TodayView.swift`
- Add `TrainingKit/Today/TodayPresentation.swift`
- Modify AppDependencies/AppRootView and remove FoundationTodayView use
- Extend App UI-test launch configuration and catalogs.

### RED

Cover session/rest/resume/deload/phase/reminder states, alert priority and `+N`, real main actions, protein target-only foundation, no fake nutrition totals, empty/error retry, single consistent snapshot, and first meaningful directive ≤1 second.

Expected RED: app still renders FoundationTodayView and “Yakında”.

### GREEN

Replace Today foundation with TrainingKit Today. Repository provides one compact snapshot; view model evaluates guidance once and publishes content. Main action starts/resumes a real session. Protein card states only what is known.

### Verification

- View-model/composition/UI suites.
- Cold-launch measurement with raw attachments and documented repeat/median rule.
- Light/dark/default/AX screenshots for every directive class.
- Static scan ensures no dead FoundationTodayView route or fake action.

---

## 17. M1.15 — Haptic feedback contract

**Final subject:** `feat(app): add training haptics`

**Test files:**

- Add `TrainingKitTests/TrainingHapticControllerTests.swift`
- Add App setting/repository composition tests.

**Production files:**

- Add `TrainingKit/Haptics/TrainingHapticClient.swift`
- Add `TrainingKit/Haptics/TrainingHapticController.swift`
- Add app UIKit live client
- Extend AppSetting repository/composition and Settings foundation control
- Extend catalogs.

### RED

Cover medium set save, throttled selection using injected clock, success only for true PR/confirmed phase, warning for safety/deload, error for validation/repository error, persisted kill switch across relaunch and no calls when disabled.

Expected RED: haptic abstraction/wiring is absent.

### GREEN

Inject semantic client through app composition. Centralize preference and throttle; views emit intent results rather than direct UIKit feedback calls.

### Verification

- Deterministic fake-client tests.
- Static scan rejects direct generator use outside live adapter.
- UI exposes visible/audible semantics independent of haptics.

---

## 18. M1.16 — Accessibility ve milestone acceptance

**Final subject:** `test: add M1 accessibility and acceptance gates`

**Test/evidence files:**

- Add `HealthTrackingAppUITests/TrainingAccessibilityUITests.swift`
- Add `HealthTrackingAppUITests/M1AcceptanceUITests.swift`
- Extend `.github/workflows/ios.yml` screenshot artifact mapping
- Extend `scripts/verify-localization.sh`
- Extend `scripts/verify-requirements.sh`
- Add `docs/evidence/M1/acceptance.md`
- Update `README.md` only for user-visible M1 run/use behavior.

### RED

Add failing fixtures first for new localization and requirement verifiers. UI matrix covers:

- VoiceOver order and meaningful values/actions;
- light/dark;
- default, XXL, AX3 and AX5;
- Reduce Motion and high contrast;
- small and modern iPhone;
- session 52 pt targets and stepper spacing;
- one-tap accept and two-tap value/RIR paths;
- US1, US2, US3, US9;
- week A/B/C, resume and history;
- missing RIR and unanswered OHP never increase;
- all 27 seed exercise measurement/safety presentations;
- baseline/new PR behavior;
- haptic semantics, throttle and kill switch.

Expected RED: M1-specific audit scripts/tests/artifact mapping are absent or fail their fixtures.

### GREEN

Fix only defects exposed by acceptance tests. Export named canonical screenshots and require every expected attachment. Assemble evidence from immutable Actions/git data; do not put unverified claims in the document.

### Final verification

1. Fresh clone from GitHub and, when reachable, Gitea.
2. `scripts/bootstrap.sh` twice with identical generated output.
3. `scripts/verify-localization.sh --self-test` then real scan.
4. `scripts/verify-requirements.sh --self-test` then real scan.
5. `scripts/test-ios.sh --verify-bootstrap-idempotence`.
6. Targeted package/app suites and full `scripts/test-ios.sh`.
7. Local Release build and Cloud compile-only.
8. `git diff --check`; TODO/placeholder/secret/mojibake/scope/import scans.
9. Download and visually inspect every canonical screenshot.
10. Fresh full-M1 requirement/design review with zero Critical/Important.
11. Exact final SHA GREEN in GitHub Actions.
12. `HEAD == origin/feat/m1-training == gitea/feat/m1-training` and clean tree.

Device-only Cloud sync, live notifications and HealthKit remain `NOT RUN` unless genuine device/account evidence exists.

---

## 19. M1 completion matrix

M1 is complete only when every row has authoritative evidence:

| Requirement | Required evidence |
|---|---|
| US1 Today | UI test + canonical screenshots + ≤1 s measurement |
| US2 session | End-to-end UI test, relaunch restore and persistence contract |
| US3 progression | Guidance truth table + UI missing-RIR negative case |
| US9 deload/phase | Guidance/state tests + UI decision flows |
| 27 exercise seed | Exact fixture + repository round-trip + UI sampling/all-row contract |
| A/B/C week | Calendar-aware guidance + end-to-end persisted sessions |
| OHP safety | All response states + prior/current session writes + alternative UI |
| History/edit/delete | Repository rollback/recalc + destructive UI confirmation |
| PR | Deterministic algorithm + baseline negative + recomputation |
| Haptics | Fake-client semantics/throttle/kill-switch tests |
| Accessibility | Full matrix artifacts and VoiceOver contracts |
| Localization | Catalog validation + no user-visible raw technical errors |
| Architecture | Import/static scans and repository boundary review |
| CI/build | Exact-SHA Local tests, Release and Cloud compile |
| Remotes | Clean tree and identical exact final SHA |

Passing only a subset, a static scan, or the absence of a known failure is not milestone completion.
