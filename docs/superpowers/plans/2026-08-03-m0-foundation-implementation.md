# M0 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS 17+ local-only uygulamayı beş tab ile açan, tam v1 SwiftData şemasını taşıyan, M0 başlangıç verisini idempotent yükleyen, onaylı DesignSystem temelini gösteren ve macOS CI'da build/test geçen foundation milestone'unu üretmek.

**Architecture:** `HealthTrackingApp` yalnız composition root ve app-level route'ları sahiplenir. Yerel `HealthTrackingModules` Swift package target'ları model, persistence, repository protocol, design ve feature root'larını taşır. SwiftData yalnız `PersistenceKit` içinde görülür; view/view model'ler `TrainingRepository` tüketir. XcodeGen Local ve Cloud scheme'lerini aynı kaynaklardan, farklı entitlement/persistence config ile üretir.

**Tech Stack:** Swift 5.9 package manifest, SwiftUI, Observation, SwiftData, CloudKit, XCTest/XCUITest, String Catalog, XcodeGen 2.46.0+, GitHub Actions `macos-15`.

## Global Constraints

- Bu plan `docs/superpowers/plans/2026-08-03-health-tracking-app-roadmap.md` yürütme protokolüne tabidir.
- Kaynak gereksinimin M0 kabulü ile onaylı tasarım spec'in M0, mimari, veri modeli, erişilebilirlik ve test bölümleri bağlayıcıdır.
- Her task test-only RED push → minimum GREEN → Fable review → review fix → full verification → tek final task commit döngüsünü izler.
- Windows üzerinde `xcodebuild` bulunmadığından macOS Actions sonucu zorunlu kanıttır. Windows sonucu build olarak adlandırılmaz.
- `HealthTrackingApp.xcodeproj` generated output'tur ve commit edilmez. `project.yml` tek doğruluk kaynağıdır.
- Local scheme hiçbir iCloud entitlement gerektirmez. Cloud scheme compile edilse bile gerçek sync ancak developer membership + gerçek Apple ortamı ile kabul edilir.
- SwiftData entity'lerinde CloudKit ile uyumsuz unique constraint kullanılmaz. Mantıksal uniqueness repository seviyesinde sağlanır.
- Kullanıcı bir kaydı silmiş veya düzenlemişse seed loader sonraki launch'ta bunu geri yazamaz.
- Bütün kullanıcı metinleri String Catalog'dadır. Debug assertion ve test fixture metinleri bu kurala dahil değildir.
- M0 dışındaki feature davranışları için sahte buton veya çalışıyormuş gibi görünen placeholder üretilmez.
- Kaynak M0 metnindeki “repository protokolleri” çoğul ifadesi artımlı uygulanır: M0 yalnız gerçek raw-program davranışını taşıyan `TrainingRepository` sözleşmesini teslim eder; Nutrition/Metrics/Lifestyle/Health/Reports protokolleri sahip feature milestone'larıyla eklenir. Bu bilinçli sapma M5 izlenebilirlik denetiminde açıkça kontrol edilir.

---

## 1. M0 final dosya haritası

```text
.github/workflows/ios.yml
.gitignore
Config/Base.xcconfig
Config/Debug.xcconfig
Config/Release.xcconfig
Config/CloudDebug.xcconfig
Config/CloudRelease.xcconfig
project.yml
scripts/bootstrap.sh
scripts/select-simulator.sh
scripts/test-ios.sh
scripts/verify-localization.sh
scripts/verify-requirements.sh
README.md
App/Application/HealthTrackingApp.swift
App/Application/AppDependencies.swift
App/Application/AppRootView.swift
App/Application/AppTab.swift
App/Application/AppBootstrapView.swift
App/Application/FoundationTodayView.swift
App/Support/AppEnvironment.swift
App/Resources/Localizable.xcstrings
App/Resources/Assets.xcassets/Contents.json
App/Resources/HealthTrackingApp.entitlements
HealthTrackingAppUITests/AppShellUITests.swift
HealthTrackingAppUITests/AccessibilitySmokeUITests.swift
Packages/HealthTrackingModules/Package.swift
Packages/HealthTrackingModules/Sources/CoreModels/Domain/*.swift
Packages/HealthTrackingModules/Sources/CoreModels/Models/*.swift
Packages/HealthTrackingModules/Sources/CoreModels/Schema/*.swift
Packages/HealthTrackingModules/Sources/PersistenceKit/Container/*.swift
Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/*.swift
Packages/HealthTrackingModules/Sources/PersistenceKit/Seed/*.swift
Packages/HealthTrackingModules/Sources/DesignSystem/Tokens/*.swift
Packages/HealthTrackingModules/Sources/DesignSystem/Components/*.swift
Packages/HealthTrackingModules/Sources/DesignSystem/Gallery/*.swift
Packages/HealthTrackingModules/Sources/TrainingKit/Repository/*.swift
Packages/HealthTrackingModules/Sources/TrainingKit/Foundation/*.swift
Packages/HealthTrackingModules/Sources/NutritionKit/Foundation/*.swift
Packages/HealthTrackingModules/Sources/ReportsKit/Foundation/*.swift
Packages/HealthTrackingModules/Sources/SettingsKit/Foundation/*.swift
Packages/HealthTrackingModules/Tests/CoreModelsTests/*.swift
Packages/HealthTrackingModules/Tests/PersistenceKitTests/*.swift
Packages/HealthTrackingModules/Tests/DesignSystemTests/*.swift
Packages/HealthTrackingModules/Tests/TrainingKitTests/*.swift
```

M0 sonunda `MetricsKit`, `ProgressPhotosKit`, `SleepMoodKit`, `HealthChecksKit`, `NotificationsKit` ve `HealthKitBridge` henüz target değildir; onları gerçek davranışla birlikte ilgili milestone ekler. İlgili entity'ler migration riskini azaltmak için v1 şemasında bulunur, fakat feature API/UI dead code'u oluşturulmaz.

## 2. Tam v1 model inventory

M0 şemasında aşağıdaki 23 model bulunur:

1. `UserProfile`
2. `Program`
3. `ProgramPhase`
4. `WorkoutDayTemplate`
5. `ExerciseTemplate`
6. `WarmupItem`
7. `CooldownItem`
8. `WorkoutSession`
9. `SetLog`
10. `ProgramState`
11. `BodyMetric`
12. `ProgressPhoto`
13. `SleepLog`
14. `MoodLog`
15. `PostureMetric`
16. `HealthCheckReminder`
17. `BloodworkResult`
18. `Food`
19. `Recipe`
20. `DailyNutritionLog`
21. `MealEntry`
22. `AppReminder`
23. `AppSetting`

Bu sayı ve model adlarının tamamı contract testinde sabitlenir. Kaynakta açıkça v1.1 olarak işaretlenen `RecipeItem`, v1 dışı food-bileşimli Recipe davranışıyla birlikte daha sonraki schema migration'da eklenir ve M0'a dead code olarak alınmaz.

Her modelde `id: UUID`, `createdAt: Date`, `updatedAt: Date` vardır. Cloud-mirrored ilişkiler opsiyoneldir; zorunlu scalar'lar güvenli default taşır. `SetLog.weightKg`, `SetLog.reps`, `ExerciseTemplate.repLow` ve `ExerciseTemplate.repHigh` onaylı spec uyarınca opsiyoneldir.

---

## Task M0.1 — Canonical XcodeGen project ve macOS CI bootstrap

**Commit:** `build: bootstrap iOS project and macOS CI`

**Files:**

- Create: `.gitignore`
- Create: `project.yml`
- Create: `Config/Base.xcconfig`
- Create: `Config/Debug.xcconfig`
- Create: `Config/Release.xcconfig`
- Create: `Config/CloudDebug.xcconfig`
- Create: `Config/CloudRelease.xcconfig`
- Create: `scripts/bootstrap.sh`
- Create: `scripts/select-simulator.sh`
- Create: `scripts/test-ios.sh`
- Create: `.github/workflows/ios.yml`
- Create: `App/Application/HealthTrackingApp.swift`
- Create: `App/Application/BootstrapView.swift`
- Create: `App/Resources/Localizable.xcstrings`
- Create: `App/Resources/Assets.xcassets/Contents.json`
- Create: `App/Resources/HealthTrackingApp.entitlements`
- Create: `HealthTrackingAppUITests/BootstrapUITests.swift`

### Step 1: Test-first app/project contract

- [ ] Create `HealthTrackingAppUITests/BootstrapUITests.swift` first. Test launches with `-ui-testing`, asserts `bootstrap.root` exists, asserts localized “Kurulum hazır” text exists, and captures an `XCTAttachment` screenshot.
- [ ] Create `project.yml`, configs and workflow without `HealthTrackingApp.swift`/`BootstrapView.swift` implementation.
- [ ] Ensure `project.yml` declares four configs (`Debug`, `Release`, `Cloud Debug`, `Cloud Release`), Local and Cloud shared schemes, app target and UI test target.
- [ ] Push the test-only provisional task commit. Expected RED: the app target fails to build because no SwiftUI app entry point exists. Infrastructure parse/generation must succeed before that failure; the exact compiler/linker wording may vary by Xcode.
- [ ] Save Actions run URL and the first relevant compiler error in task notes.

`project.yml` must encode this contract:

```yaml
name: HealthTrackingApp
options:
  minimumXcodeGenVersion: 2.46.0
  deploymentTarget:
    iOS: "17.0"
configs:
  Debug: debug
  Release: release
  Cloud Debug: debug
  Cloud Release: release
targets:
  HealthTrackingApp:
    type: application
    platform: iOS
    sources:
      - App
    configFiles:
      Debug: Config/Debug.xcconfig
      Release: Config/Release.xcconfig
      Cloud Debug: Config/CloudDebug.xcconfig
      Cloud Release: Config/CloudRelease.xcconfig
    info:
      path: App/Resources/Info.plist
      properties:
        CFBundleDisplayName: Sağlık Takip
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        CloudKitEnabled: $(CLOUDKIT_ENABLED)
        CloudKitContainerIdentifier: $(ICLOUD_CONTAINER_IDENTIFIER)
  HealthTrackingAppUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - HealthTrackingAppUITests
    dependencies:
      - target: HealthTrackingApp
schemes:
  HealthTrackingApp-Local:
    build:
      targets:
        HealthTrackingApp: all
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - HealthTrackingAppUITests
    archive:
      config: Release
  HealthTrackingApp-Cloud:
    build:
      targets:
        HealthTrackingApp: all
    run:
      config: Cloud Debug
    archive:
      config: Cloud Release
```

`Config/Base.xcconfig` is the single location for:

```text
PRODUCT_BUNDLE_IDENTIFIER = com.fatihzxc.HealthTrackingApp
ICLOUD_CONTAINER_IDENTIFIER = iCloud.com.fatihzxc.HealthTrackingApp
IPHONEOS_DEPLOYMENT_TARGET = 17.0
SWIFT_STRICT_CONCURRENCY = complete
```

Debug/Release include Base and set `CLOUDKIT_ENABLED = NO`, with no `CODE_SIGN_ENTITLEMENTS`. Cloud configs include their corresponding local config, set `CLOUDKIT_ENABLED = YES`, and set `CODE_SIGN_ENTITLEMENTS = App/Resources/HealthTrackingApp.entitlements`.

`HealthTrackingApp.entitlements` is not left to the executor to invent. M0 contains exactly the CloudKit service/container and key-value store identifiers:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>$(ICLOUD_CONTAINER_IDENTIFIER)</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.ubiquity-kvstore-identifier</key>
    <string>$(TeamIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)</string>
</dict>
</plist>
```

`aps-environment` and `UIBackgroundModes = remote-notification` are deliberately absent in M0's compile-only Cloud path. M5.6 adds them with the correctly signed developer/distribution profile when real SwiftData CloudKit background-sync acceptance begins; M0 does not claim push-driven sync.

### Step 2: Minimum app implementation

- [ ] Implement `@main struct HealthTrackingApp: App` with only `BootstrapView`.
- [ ] Implement `BootstrapView` using a localized key, `.accessibilityIdentifier("bootstrap.root")`, semantic system colors and Dynamic Type font. Do not build M0 tab behavior yet.
- [ ] Add a valid String Catalog entry for `bootstrap.ready` with Turkish value `Kurulum hazır`.
- [ ] Add `.xcodeproj`, DerivedData, xcuserdata, `.build`, result bundles and secret/signing files to `.gitignore`; do not ignore `project.yml`, source assets or evidence docs.

### Step 3: Robust scripts

- [ ] `scripts/bootstrap.sh` must use `set -euo pipefail`, verify `xcodegen` exists and is at least 2.46.0, run `xcodegen generate --spec project.yml`, then `xcodebuild -list -project HealthTrackingApp.xcodeproj`.
- [ ] `scripts/select-simulator.sh` must parse `xcrun simctl list devices available --json` and print one available iPhone destination. It must fail non-zero with a clear message when no iPhone simulator exists; it may not silently skip tests.
- [ ] `scripts/test-ios.sh` must call bootstrap, obtain the destination, run the Local scheme's complete test action and Local Release build with `CODE_SIGNING_ALLOWED=NO`, and preserve an `.xcresult` path. It accepts optional `--only-testing TestBundleName` for task-level RED/GREEN runs; with no option it always executes every app, package and UI test target wired into the scheme.
- [ ] `.github/workflows/ios.yml` uses `actions/checkout`, `macos-15`, logs `xcodebuild -version` and `xcodegen --version`, installs XcodeGen only when absent/too old, runs `scripts/test-ios.sh`, and uploads xcresult on success or failure.
- [ ] Package test targets are added incrementally to `HealthTrackingApp-Local.test.targets` with XcodeGen's `package: HealthTrackingModules/TargetTests` syntax as each target appears. They run as iOS Simulator XCTest bundles inside the same `xcodebuild test`; CI never relies on host-side `swift test` or macOS compilation of UI-heavy package targets.

### Step 4: Verify, review, commit

- [ ] Run local static checks: YAML parse if available, shell syntax through `bash -n` only where bash exists, `git diff --check`, secret scan and generated-project ignore check.
- [ ] Run Fable 5 medium review against requirement M0, design spec architecture/Windows rules, and task diff.
- [ ] Fix all verified Critical/Important findings and re-review if any behavior changes.
- [ ] Amend the provisional task commit, push task branch with `--force-with-lease`, and require macOS GREEN for generation, UI test and Release build.
- [ ] Record final commit hash and Actions URL.

---

## Task M0.2 — Shared domain values, ReminderSchedule ve set validator

**Commit:** `feat(core): add shared domain values and validation`

**Files:**

- Create: `Packages/HealthTrackingModules/Package.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Domain/ModelEnums.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Domain/MealCategory.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Domain/ReminderSchedule.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Domain/ReminderScheduleCodec.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Domain/SetMeasurementInput.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Domain/SetMeasurementValidator.swift`
- Create: `Packages/HealthTrackingModules/Tests/CoreModelsTests/ReminderScheduleCodecTests.swift`
- Create: `Packages/HealthTrackingModules/Tests/CoreModelsTests/SetMeasurementValidatorTests.swift`
- Modify: `project.yml`

### Step 1: Define the package boundary

- [ ] Create a package with `// swift-tools-version: 5.9`, `defaultLocalization: "tr"`, iOS 17 as its only platform, and initial `CoreModels` library/test targets. Package tests are built for the iOS Simulator by the generated Xcode scheme; host-side macOS `swift test` is not a project contract.
- [ ] Apply `swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]` to every library and test target through one manifest helper so `SWIFT_STRICT_CONCURRENCY = complete` is not limited to the app target.
- [ ] Add local package syntax to `project.yml` exactly as XcodeGen documents:

```yaml
packages:
  HealthTrackingModules:
    path: Packages/HealthTrackingModules
targets:
  HealthTrackingApp:
    dependencies:
      - package: HealthTrackingModules
        product: CoreModels
schemes:
  HealthTrackingApp-Local:
    test:
      targets:
        - HealthTrackingAppUITests
        - package: HealthTrackingModules/CoreModelsTests
```

### Step 2: Write failing codec and validator tests

- [ ] `ReminderScheduleCodecTests` covers deterministic round-trip for `oneTime`, `daily`, `weekly` and `intervalDays`; schema version 1; invalid version; malformed JSON; invalid hour/minute; empty/duplicate weekday; `count < 1`.
- [ ] `SetMeasurementValidatorTests` covers all five measurement kinds and every invalid missing-field combination.
- [ ] Explicitly test `weightKg == 0` is preserved and valid for `weightReps`; `nil` means absent.
- [ ] Explicitly test reps/duration/steps must be greater than zero, optional weight must be finite and non-negative, and RIR when present is integer 0…10.
- [ ] Push test-only provisional commit. Expected RED: missing types/symbols, not a test setup failure.

### Step 3: Implement exact public values

All simple enums conform to `String, Codable, CaseIterable, Sendable` unless an associated value prevents `CaseIterable`:

```swift
public enum UnitsSystem: String, Codable, CaseIterable, Sendable { case metric, imperial }
public enum ExerciseCategory: String, Codable, CaseIterable, Sendable { case compound, accessory, core }
public enum ProgressionRule: String, Codable, CaseIterable, Sendable {
    case doubleProgression, gradedEntryOHP, boneFocusHeavy, timeQuality, bodyweightProgression
}
public enum ExerciseMeasurementKind: String, Codable, CaseIterable, Sendable {
    case weightReps, reps, duration, steps, quality
}
public enum WorkoutSessionStatus: String, Codable, CaseIterable, Sendable {
    case planned, inProgress, completed, skipped
}
public enum WarmupPhase: String, Codable, CaseIterable, Sendable { case raise, activate, potentiate }
public enum BodyMetricType: String, Codable, CaseIterable, Sendable { case weight, waist, custom }
public enum ProgressPhotoPose: String, Codable, CaseIterable, Sendable { case front, side, back }
public enum HealthCheckRecurrence: String, Codable, CaseIterable, Sendable { case none, monthly, quarterly, yearly }
public enum HealthCheckStatus: String, Codable, CaseIterable, Sendable { case pending, done }
public enum FoodSource: String, Codable, CaseIterable, Sendable { case userCreated, healthKit }
public enum AppReminderType: String, Codable, CaseIterable, Sendable { case workout, measurement, bloodwork, mealLog, custom }
public enum DeloadStatus: String, Codable, CaseIterable, Sendable { case none, recommended, active, skipped }
public enum DeloadReason: String, Codable, CaseIterable, Sendable { case scheduled, reactive }
public enum DeloadAction: String, Codable, CaseIterable, Sendable { case accepted, stay, techniqueReview, skipped }
public enum OHPSymptomResponse: String, Codable, CaseIterable, Sendable {
    case notAsked, symptomFree, symptomsPresent, uncertain
}
```

Also define `MealCategory` as a Codable/Hashable/Sendable value with `kind` (`breakfast`, `lunch`, `dinner`, `snack`, `custom`) and nonblank `customName` only when kind is custom. Persisting models store this value, never a localized label.

`ReminderSchedule` public contract:

```swift
public enum ReminderWeekday: Int, Codable, CaseIterable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
}

public enum ReminderSchedule: Equatable, Sendable {
    case oneTime(Date)
    case daily(hour: Int, minute: Int)
    case weekly(weekdays: Set<ReminderWeekday>, hour: Int, minute: Int)
    case intervalDays(count: Int, hour: Int, minute: Int)
}

public enum ReminderScheduleCodec {
    public static func encode(_ schedule: ReminderSchedule) throws -> String
    public static func decode(_ json: String) throws -> ReminderSchedule
}
```

Codec stores a private envelope with `schemaVersion == 1`, sorted JSON keys, milliseconds-since-1970 date encoding and sorted weekday raw values. Validation happens both before encode and after decode.

Set validation contract:

```swift
public struct SetMeasurementInput: Equatable, Sendable {
    public var weightKg: Double?
    public var reps: Int?
    public var durationSec: Int?
    public var distanceSteps: Int?
    public var performedVariant: String?
    public var rir: Int?
}

public enum SetMeasurementValidator {
    public static func validate(
        _ input: SetMeasurementInput,
        for kind: ExerciseMeasurementKind
    ) throws
}
```

The validator rejects fields that contradict the selected kind only when they would create ambiguous persistence; `rir` and `performedVariant` remain cross-kind optional metadata. Views may call this validator but may not duplicate its rules.

### Step 4: Verify, review, commit

- [ ] Run RED then GREEN target command:

```bash
./scripts/test-ios.sh --only-testing CoreModelsTests
```

- [ ] Run full Local scheme via `scripts/test-ios.sh`.
- [ ] Run Fable review for enum completeness, `0` semantics, codec forward failure and invariant coverage.
- [ ] Resolve findings, re-run target + full suite, amend the one task commit, and require GREEN Actions.

---

## Task M0.3 — Program ve training SwiftData schema

**Commit:** `feat(core): add program and training schema`

**Files:**

- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/UserProfile.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/Program.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/ProgramPhase.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/WorkoutDayTemplate.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/ExerciseTemplate.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/WarmupItem.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/CooldownItem.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/WorkoutSession.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/SetLog.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/ProgramState.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Domain/TrainingModelValidator.swift`
- Create: `Packages/HealthTrackingModules/Tests/CoreModelsTests/TrainingModelRoundTripTests.swift`
- Create: `Packages/HealthTrackingModules/Tests/CoreModelsTests/TrainingModelDefaultsTests.swift`

### Step 1: Write failing schema tests

- [ ] Create an in-memory `ModelContainer` containing only these ten model types.
- [ ] Test insert/save/new-context fetch round-trip for every scalar and relationship.
- [ ] Test optional relationships survive missing parents without crash.
- [ ] Test `SetLog` preserves nil measurement fields, zero weight and `performedVariant` exactly.
- [ ] Test `trainingWeekIndex` default is 1 and `TrainingModelValidator` rejects values below 1.
- [ ] Test UserProfile weekly target default 3 and `TrainingModelValidator` rejects values outside 1…7.
- [ ] Test no `@Attribute(.unique)` metadata is used by exercising duplicate IDs in the in-memory store; repository, not schema, owns uniqueness.
- [ ] Push tests first. Expected RED: model symbols do not exist.

### Step 2: Implement exact model fields

Every initializer accepts `id`, `createdAt`, `updatedAt` with defaults and all domain fields with safe defaults. In addition, every non-optional persisted property has a safe default on the **property declaration itself** (`var status: WorkoutSessionStatus = .planned`, not only `init(status: = .planned)`); this is required by the SwiftData CloudKit schema validator. Optional relationships/defaultable to-many relationships are declared optional at the property level as required by the approved CloudKit model. The persisted inventory is:

| Model | Domain fields beyond id/timestamps |
|---|---|
| `UserProfile` | `displayName`, `heightCm`, `startWeightKg`, `targetWeightKg`, `birthYear?`, `unitsSystem`, `proteinTargetG`, `calorieTarget?`, `carbTargetG?`, `fatTargetG?`, `programStartDate`, `weeklyWorkoutTarget` |
| `Program` | `name`, `descriptionText`, `isActive`, optional `[WorkoutDayTemplate]`, optional `[ProgramPhase]` |
| `ProgramPhase` | `name`, `orderIndex`, `monthStart`, `monthEnd`, `trainingFocus`, `nutritionFocus`, `milestone`, `entryCriteria`, optional `program` |
| `WorkoutDayTemplate` | `name`, `orderIndex`, `focus`, optional `program`, optional `[ExerciseTemplate]`, optional `[WarmupItem]`, optional `[CooldownItem]` |
| `ExerciseTemplate` | `name`, `orderIndex`, `targetSets`, `repLow?`, `repHigh?`, `rirLow`, `rirHigh`, `category`, `allowFailure`, `cues`, `safetyNote?`, `startingWeightKg?`, `progressionRule`, `measurementKind`, `supersetGroupId?`, `supersetOrder?`, optional `workoutDayTemplate` |
| `WarmupItem` | `phase`, `movement`, `dose`, `orderIndex`, optional `workoutDayTemplate` |
| `CooldownItem` | `movement`, `dose`, `note?`, `orderIndex`, optional `workoutDayTemplate` |
| `WorkoutSession` | `date`, `status`, `workoutDayTemplateId`, `perceivedRecovery?`, `note?`, `ohpSymptomResponse`, `ohpSymptomCheckedAt?`, optional `[SetLog]` |
| `SetLog` | `exerciseTemplateId`, `setIndex`, `weightKg?`, `reps?`, `durationSec?`, `distanceSteps?`, `performedVariant?`, `rir?`, `isWarmupSet`, `completedAt`, optional `workoutSession` |
| `ProgramState` | `programId`, `currentPhaseId`, `phaseStartedAt`, `trainingWeekIndex`, `deloadStatus`, `deloadReason?`, `deloadUpdatedAt?`, `lastDeloadSkippedAt?`, `lastDeloadAction?` |

### Step 3: Relationship and validation rules

- [ ] Use explicit inverse relationships where SwiftData inference is ambiguous; delete rules must not cascade user history from template deletion. A template/program delete uses nullify for historical ID references.
- [ ] Model initializers remain hydration-safe and do not trap on potentially corrupted/synced user values. `TrainingModelValidator.validateWeeklyWorkoutTarget(_:)` and `validateTrainingWeekIndex(_:)` return typed errors; seed/repository/view model creation paths must call them instead of clamping silently.
- [ ] `SetLog` exposes `measurementInput` and `validate(for:)` delegating to the central validator; it does not duplicate kind rules.
- [ ] Model names and English field names exactly match the approved spec. No `CoreData` naming appears.

### Step 4: Verify, review, commit

- [ ] Run `./scripts/test-ios.sh --only-testing CoreModelsTests`, then `./scripts/test-ios.sh` for the full Local scheme.
- [ ] Fable review must explicitly inspect CloudKit compatibility, relationship/delete semantics, optional measurement fields, strict RIR prerequisites and missing Pull-up rep ceiling representation.
- [ ] Resolve verified findings, re-run, amend one task commit and require Actions GREEN.

---

## Task M0.4 — Remaining v1 SwiftData schema

**Commit:** `feat(core): complete v1 persistence schema`

**Files:**

- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/BodyMetric.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/ProgressPhoto.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/SleepLog.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/MoodLog.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/PostureMetric.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/HealthCheckReminder.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/BloodworkResult.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/Food.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/Recipe.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/DailyNutritionLog.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/MealEntry.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/AppReminder.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Models/AppSetting.swift`
- Create: `Packages/HealthTrackingModules/Tests/CoreModelsTests/RemainingModelRoundTripTests.swift`
- Create: `Packages/HealthTrackingModules/Tests/CoreModelsTests/ModelInventoryTests.swift`

### Step 1: Write failing model inventory and round-trip tests

- [ ] Assert the final schema model-name set equals the exact 23-model inventory in this plan; count-only assertion is insufficient.
- [ ] Round-trip every scalar, optional field, enum/value type and relationship.
- [ ] Test `PostureMetric.symptomScore == 0` persists as zero, not nil.
- [ ] Test `DailyNutritionLog.date` allows duplicate raw rows at schema level; later repository contract owns day uniqueness.
- [ ] Test `ProgressPhoto.imageRef` accepts a stable opaque asset ID and never an absolute-path-specific API.
- [ ] Test MealEntry resolved macro values remain unchanged after its source Recipe object is mutated.
- [ ] Test AppReminder schedule string round-trips through `ReminderScheduleCodec`.
- [ ] Push tests first and capture missing-symbol RED.

### Step 2: Implement remaining fields

| Model | Domain fields beyond id/timestamps |
|---|---|
| `BodyMetric` | `date`, `type`, `customName?`, `value`, `unit` |
| `ProgressPhoto` | `date`, `imageRef`, `pose`, `note?` |
| `SleepLog` | `date`, `durationHours`, `quality`, `note?` |
| `MoodLog` | `date`, `moodScore?`, `moodTags`, `energy?`, `note?` |
| `PostureMetric` | `date`, `wallTestPass?`, `symptomScore?`, `region?`, `note?` |
| `HealthCheckReminder` | `name`, `dueDate`, `recurrence`, `status` |
| `BloodworkResult` | `date`, `marker`, `value`, `unit`, `note?` |
| `Food` | `name`, `brand?`, `servingSize`, `servingUnit`, per-serving calories/protein/carb/fat, `fiberG?`, `source` |
| `Recipe` | `name`, `category`, `servings`, `isDirectMacros`, total calories/protein/carb/fat, `note?` |
| `DailyNutritionLog` | normalized-intent `date`, optional `[MealEntry]` |
| `MealEntry` | `category`, `recipeId?`, `foodId?`, `adhocName?`, `quantity`, resolved calories/protein/carb/fat, `loggedAt`, optional `dailyNutritionLog` |
| `AppReminder` | `type`, `schedule`, `message`, `isEnabled` |
| `AppSetting` | `key`, `value` |

Every non-optional property in these models likewise carries a declaration-level default suitable for CloudKit validation; initializer defaults alone do not satisfy the contract. All numeric user values remain raw persisted input at model layer. Range/finite checks are centralized in the future owning repository; M0 tests only guarantee representability and no false missing-value interpretation.

### Step 3: Verify, review, commit

- [ ] Run `./scripts/test-ios.sh --only-testing CoreModelsTests`, then `./scripts/test-ios.sh` for the full Local scheme.
- [ ] Fable review checks exact source fields, v1/v1.1 boundary, snapshot semantics, zero/nil semantics, binary-free photo model and CloudKit-safe schema.
- [ ] Resolve Critical/Important findings, amend one commit and require Actions GREEN.

---

## Task M0.5 — Versioned container, persistence modes ve Training repository

**Commit:** `feat(persistence): add model container and training repository`

**Files:**

- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Schema/HealthTrackingSchemaV1.swift`
- Create: `Packages/HealthTrackingModules/Sources/CoreModels/Schema/HealthTrackingMigrationPlan.swift`
- Create: `Packages/HealthTrackingModules/Sources/TrainingKit/Repository/TrainingRepository.swift`
- Create: `Packages/HealthTrackingModules/Sources/PersistenceKit/Container/PersistenceMode.swift`
- Create: `Packages/HealthTrackingModules/Sources/PersistenceKit/Container/PersistenceDescriptor.swift`
- Create: `Packages/HealthTrackingModules/Sources/PersistenceKit/Container/ModelContainerFactory.swift`
- Create: `Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataTrainingRepository.swift`
- Create: `Packages/HealthTrackingModules/Tests/PersistenceKitTests/ModelContainerFactoryTests.swift`
- Create: `Packages/HealthTrackingModules/Tests/PersistenceKitTests/TrainingRepositoryContractTests.swift`
- Modify: `Packages/HealthTrackingModules/Package.swift`
- Modify: `project.yml`

### Step 1: Add targets and failing contracts

- [ ] Add `TrainingKit` product/target depending on `CoreModels`.
- [ ] Add `PersistenceKit` product/target depending on `CoreModels` and `TrainingKit`.
- [ ] Add `PersistenceKitTests` depending on all three.
- [ ] Add both products to app target dependencies in `project.yml`.
- [ ] Add `package: HealthTrackingModules/PersistenceKitTests` to the Local scheme test targets; keep `CoreModelsTests` and UI tests in the same action.
- [ ] Write tests before implementations and capture expected missing-symbol RED.

### Step 2: Define exact public interfaces

```swift
public enum PersistenceMode: Equatable, Sendable {
    case inMemory
    case local(storeURL: URL)
    case cloud(storeURL: URL, privateDatabaseIdentifier: String)
}

public struct PersistenceDescriptor: Equatable, Sendable {
    public let storeURL: URL?
    public let isStoredInMemoryOnly: Bool
    public let privateDatabaseIdentifier: String?
}

@MainActor
public enum ModelContainerFactory {
    public static func descriptor(for mode: PersistenceMode) throws -> PersistenceDescriptor
    public static func make(for mode: PersistenceMode) throws -> ModelContainer
}

@MainActor
public protocol TrainingRepository: AnyObject {
    func fetchUserProfile() async throws -> UserProfile?
    func fetchActiveProgram() async throws -> Program?
    func fetchWorkoutDays(programID: UUID) async throws -> [WorkoutDayTemplate]
}
```

`SwiftDataTrainingRepository` initializer is `public init(modelContext: ModelContext)`. Fetches use stable sort: active program by `updatedAt` then UUID, days by `orderIndex` then UUID. Duplicate logical rows are surfaced as a typed repository integrity error; an arbitrary record is not silently selected.

### Step 3: Implement schema and modes

- [ ] `HealthTrackingSchemaV1: VersionedSchema` uses `Schema.Version(1, 0, 0)` and the exact 23-model list.
- [ ] `HealthTrackingMigrationPlan: SchemaMigrationPlan` contains V1 and no stages yet.
- [ ] In-memory config sets `isStoredInMemoryOnly: true` and `.none` CloudKit.
- [ ] Local config uses provided URL and `.none` CloudKit.
- [ ] Cloud config uses provided URL and `.private(identifier)` CloudKit.
- [ ] Empty/whitespace Cloud container identifier throws a typed configuration error before constructing a container.
- [ ] Deterministic unit/contract tests instantiate in-memory/local modes and test the Cloud descriptor as a pure value. A separate best-effort Cloud-schema probe below may attempt private-container construction, but it never claims network sync.
- [ ] Add a Cloud-schema validation probe inside `PersistenceKitTests`, executed by the Local scheme's package-test action, that attempts `ModelContainer` construction with the private-database configuration. If the runner rejects it solely because a signed entitlement/container is unavailable, record that exact capability error as `BLOCKED` rather than `PASS`; a schema-validation/default error is always a test failure. The remaining entitlement-dependent runtime validation stays an explicit M5.6 risk.

### Step 4: Repository contract tests

- [ ] Empty store returns nil/empty.
- [ ] Inserted profile/active program/days fetch correctly in a new context.
- [ ] Day order is deterministic.
- [ ] Two active programs and two profiles each produce integrity error.
- [ ] No UI module imports SwiftData or `ModelContext`; enforce with `rg` in verification.

### Step 5: Verify, review, commit

- [ ] Run `./scripts/test-ios.sh --only-testing PersistenceKitTests`, then `./scripts/test-ios.sh` for all wired package/UI tests and the Local Release build.
- [ ] Compile Cloud scheme with signing disabled; log that this is compile-only.
- [ ] Fable review focuses on Cloud/local separation, actor isolation, remote-ready protocol, duplicate handling and schema coverage.
- [ ] Resolve findings, amend one commit and require Actions GREEN.

---

## Task M0.6 — Idempotent M0 seed loader

**Commit:** `feat(persistence): seed foundation program idempotently`

**Files:**

- Create: `Packages/HealthTrackingModules/Sources/PersistenceKit/Seed/SeedIdentifiers.swift`
- Create: `Packages/HealthTrackingModules/Sources/PersistenceKit/Seed/M0SeedPayload.swift`
- Create: `Packages/HealthTrackingModules/Sources/PersistenceKit/Seed/M0SeedCatalog.swift`
- Create: `Packages/HealthTrackingModules/Sources/PersistenceKit/Seed/SeedLoading.swift`
- Create: `Packages/HealthTrackingModules/Sources/PersistenceKit/Seed/SwiftDataSeedLoader.swift`
- Create: `Packages/HealthTrackingModules/Tests/PersistenceKitTests/M0SeedCatalogTests.swift`
- Create: `Packages/HealthTrackingModules/Tests/PersistenceKitTests/SwiftDataSeedLoaderTests.swift`

### Step 1: Write failing seed tests

- [ ] First run yields exactly one profile, one active program, four phases and three day shells.
- [ ] A/B/C are ordered 1/2/3 and attached to the program.
- [ ] Profile values are height 185, start 98, target 90, protein 120, metric, weekly target 3, passed install date; calorie/carb/fat targets nil.
- [ ] Program and phase values exactly match requirement section 10.2; no invented numeric entry threshold.
- [ ] Second and third runs leave all counts and IDs unchanged.
- [ ] User edits after seed marker are preserved.
- [ ] User deletion after seed marker is preserved and not resurrected.
- [ ] Simulated partial pre-marker seed is repaired by deterministic ID without overwriting existing edited scalar values.
- [ ] Save failure rolls back and does not write marker.
- [ ] Push tests first and capture missing-symbol RED.

### Step 2: Stable IDs and payload

Use explicit stable UUID constants:

```text
profile: 00000000-0000-4000-8000-000000000001
program: 00000000-0000-4000-8000-000000000100
phase1:  00000000-0000-4000-8000-000000000111
phase2:  00000000-0000-4000-8000-000000000112
phase3:  00000000-0000-4000-8000-000000000113
phase4:  00000000-0000-4000-8000-000000000114
dayA:    00000000-0000-4000-8000-000000000201
dayB:    00000000-0000-4000-8000-000000000202
dayC:    00000000-0000-4000-8000-000000000203
```

`M0SeedCatalog.make(installedAt:)` is pure. `displayName` is empty because the requirement does not provide one; UI uses localized “Profilim” fallback. Phase `entryCriteria` remains empty when no source criterion exists; UI hides empty checklist text rather than inventing one.

### Step 3: Loader contract

```swift
@MainActor
public protocol SeedLoading: AnyObject {
    func seedIfNeeded(installedAt: Date) throws
}

@MainActor
public final class SwiftDataSeedLoader: SeedLoading {
    public init(modelContext: ModelContext)
    public func seedIfNeeded(installedAt: Date) throws
}
```

- [ ] Marker is `AppSetting(key: "seed.catalog.version", value: "1")` and is repository-level unique.
- [ ] Existing valid marker returns immediately without scanning/recreating deleted seed entities.
- [ ] Without marker, deterministic IDs implement fetch-or-create; existing records are linked if needed but scalar user edits are not reset.
- [ ] Marker is inserted only after all entities/relationships are ready in the same save boundary.
- [ ] Failure calls rollback and rethrows typed seed error.

### Step 4: Verify, review, commit

- [ ] Run `./scripts/test-ios.sh --only-testing PersistenceKitTests` repeatedly, then `./scripts/test-ios.sh` for the full suite.
- [ ] Fable review explicitly checks idempotency, delete preservation, crash recovery, source-exact phase text and no uniqueness constraint.
- [ ] Resolve findings, amend one commit and require Actions GREEN.

---

## Task M0.7 — DesignSystem tokens, components ve gallery

**Commit:** `feat(design): add accessible foundation design system`

**Files:**

- Create: `Packages/HealthTrackingModules/Sources/DesignSystem/Tokens/SRGBColor.swift`
- Create: `Packages/HealthTrackingModules/Sources/DesignSystem/Tokens/AppColors.swift`
- Create: `Packages/HealthTrackingModules/Sources/DesignSystem/Tokens/AppTypography.swift`
- Create: `Packages/HealthTrackingModules/Sources/DesignSystem/Tokens/AppSpacing.swift`
- Create: `Packages/HealthTrackingModules/Sources/DesignSystem/Tokens/AppRadius.swift`
- Create: `Packages/HealthTrackingModules/Sources/DesignSystem/Tokens/AppMotion.swift`
- Create: `Packages/HealthTrackingModules/Sources/DesignSystem/Components/AppCard.swift`
- Create: `Packages/HealthTrackingModules/Sources/DesignSystem/Components/PrimaryActionButton.swift`
- Create: `Packages/HealthTrackingModules/Sources/DesignSystem/Components/StatusPill.swift`
- Create: `Packages/HealthTrackingModules/Sources/DesignSystem/Components/FeatureStateView.swift`
- Create: `Packages/HealthTrackingModules/Sources/DesignSystem/Gallery/DesignSystemGalleryView.swift`
- Create: `Packages/HealthTrackingModules/Sources/DesignSystem/Resources/Localizable.xcstrings`
- Create: `Packages/HealthTrackingModules/Tests/DesignSystemTests/ColorContrastTests.swift`
- Create: `Packages/HealthTrackingModules/Tests/DesignSystemTests/TokenContractTests.swift`
- Modify: `Packages/HealthTrackingModules/Package.swift`
- Modify: `project.yml`

### Step 1: Write failing token tests

- [ ] Test exact approved hex values for all background, ink, accent, state and border tokens in light/dark.
- [ ] Implement test-side WCAG formula first and assert at least these normal-text pairs ≥4.5: primary/base, primary/raised, secondary/base, tertiary/base, onAction/action in both schemes where semantically used.
- [ ] Assert state/icon pairs and strong border against their intended surface ≥3.0.
- [ ] Assert spacing set is exactly 2/4/8/12/16/24/32/40, horizontal padding 20 and radii 8/10/14/16.
- [ ] Push test-only provisional commit and capture missing-symbol RED.
- [ ] Add `package: HealthTrackingModules/DesignSystemTests` to the Local scheme test action before the RED push so CI actually executes this package test bundle.

### Step 2: Implement inspectable tokens

```swift
public struct SRGBColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    public init(hex: String) throws
    public var relativeLuminance: Double { get }
    public func contrastRatio(against other: SRGBColor) -> Double
    public var swiftUIColor: Color { get }
}

public enum ColorSchemeVariant: CaseIterable, Sendable { case light, dark }
public enum AppColorRole: CaseIterable, Sendable {
    case backgroundBase, backgroundRaised, backgroundSunken
    case inkPrimary, inkSecondary, inkTertiary
    case accentAction, accentOnAction
    case stateSuccess, stateWarning, stateDanger, stateInfo
    case borderHairline, borderStrong
}
public enum AppColors {
    public static func value(_ role: AppColorRole, scheme: ColorSchemeVariant) -> SRGBColor
    public static func color(_ role: AppColorRole, scheme: ColorScheme) -> Color
}
```

Feature code imports roles only; raw hex literals outside `AppColors.swift` fail verification.

Typography uses `Font.TextStyle`/Dynamic Type and exposes directive, titleLarge, titleMedium, body, label, caption, micro, numericHero and numericRow exactly as spec. Motion helper returns 120/220/320 ms normally and 120 ms opacity transition under Reduce Motion.

The `DesignSystem` target declares `resources: [.process("Resources")]` in `Package.swift`. Every package-localized lookup uses `String(localized: ..., bundle: .module)`; a bare lookup that falls back to the app bundle fails the localization verification.

### Step 3: Implement accessible components

- [ ] `AppCard` uses raised background, 16pt radius where appropriate, no shadow and caller-provided content.
- [ ] `PrimaryActionButton` has minimum 44×44 target, action/onAction pair, loading/disabled states and caller-provided localized accessibility label.
- [ ] `StatusPill` always includes text plus optional SF Symbol; color is never sole meaning.
- [ ] `FeatureStateView` has typed `loading`, `empty`, `error` presentation and only shows retry when a real closure is supplied.
- [ ] Gallery renders every token/component in light and dark previews plus Dynamic Type-friendly live screen. No production navigation points to a debug-only fake action.

### Step 4: Verify, review, commit

- [ ] Run `./scripts/test-ios.sh --only-testing DesignSystemTests`, then `./scripts/test-ios.sh` for the full Local suite.
- [ ] Generate gallery screenshots in light/dark from UI test or preview host and attach to review context.
- [ ] Fable review checks exact Opus-approved direction, contrast, semantic token use, no shadow, Dynamic Type, Reduce Motion and state clarity.
- [ ] Resolve findings, amend one commit and require Actions GREEN.

---

## Task M0.8 — Composition root, beş tab ve raw seed görünümü

**Commit:** `feat(app): add five-tab foundation shell`

**Files:**

- Delete: `App/Application/BootstrapView.swift`
- Delete: `HealthTrackingAppUITests/BootstrapUITests.swift`
- Modify: `App/Application/HealthTrackingApp.swift`
- Create: `App/Application/AppDependencies.swift`
- Create: `App/Application/AppRootView.swift`
- Create: `App/Application/AppTab.swift`
- Create: `App/Application/AppBootstrapView.swift`
- Create: `App/Application/FoundationTodayView.swift`
- Create: `App/Support/AppEnvironment.swift`
- Modify: `App/Resources/Localizable.xcstrings`
- Create: `Packages/HealthTrackingModules/Sources/TrainingKit/Foundation/FoundationProgramViewModel.swift`
- Create: `Packages/HealthTrackingModules/Sources/TrainingKit/Foundation/FoundationProgramView.swift`
- Create: `Packages/HealthTrackingModules/Sources/TrainingKit/Resources/Localizable.xcstrings`
- Create: `Packages/HealthTrackingModules/Sources/NutritionKit/Foundation/NutritionFoundationView.swift`
- Create: `Packages/HealthTrackingModules/Sources/NutritionKit/Resources/Localizable.xcstrings`
- Create: `Packages/HealthTrackingModules/Sources/ReportsKit/Foundation/ReportsFoundationView.swift`
- Create: `Packages/HealthTrackingModules/Sources/ReportsKit/Resources/Localizable.xcstrings`
- Create: `Packages/HealthTrackingModules/Sources/SettingsKit/Foundation/SettingsFoundationView.swift`
- Create: `Packages/HealthTrackingModules/Sources/SettingsKit/Resources/Localizable.xcstrings`
- Create: `Packages/HealthTrackingModules/Tests/TrainingKitTests/FoundationProgramViewModelTests.swift`
- Create: `HealthTrackingAppUITests/AppShellUITests.swift`
- Modify: `Packages/HealthTrackingModules/Package.swift`
- Modify: `project.yml`

### Step 1: Write ViewModel and UI tests first

- [ ] ViewModel tests cover loading→content, empty and repository error using a hand-written fake `TrainingRepository`.
- [ ] Content snapshot value contains profile fallback label, active program name, ordered four phases and ordered A/B/C day names; the view never receives `ModelContext`.
- [ ] XCUITest launches with `-ui-testing`, finds five tab identifiers, taps each, asserts a distinct root identifier, returns to Training and asserts seed program/day labels.
- [ ] XCUITest relaunches in a fresh `-ui-testing` in-memory process and asserts the same deterministic visible seed counts. This is launch determinism evidence only; M0.6 repository tests own idempotency and a later local-store integration test owns persistence evidence.
- [ ] Push tests first. Expected RED: missing views/composition symbols.

### Step 2: Add real feature root targets

Add package products/targets:

- `TrainingKit` adds `DesignSystem` dependency.
- `NutritionKit`, `ReportsKit`, `SettingsKit` depend `DesignSystem`.
- Each target owns its Turkish String Catalog resource.
- Every resource-owning target declares `resources: [.process("Resources")]`, and target code uses `String(localized: ..., bundle: .module)`.
- Add `package: HealthTrackingModules/TrainingKitTests` to the Local scheme test action. The foundation-only Nutrition/Reports/Settings targets have no test target until they gain behavior beyond static honest state views.

Do **not** create `GuidanceKit` in M0. The approved architecture requires it to remain SwiftUI-free and pure. `FoundationTodayView` lives in the app composition target and consumes the injected Training foundation state. M1 creates `GuidanceKit` only when the first pure rotation rule and its failing unit test are delivered; it never depends on `DesignSystem` or a feature view.

Foundation root views communicate honest milestone state:

- Today: active program/foundation summary; no training recommendation yet.
- Training: raw M0 seed profile/program/phase/day list.
- Nutrition: localized empty-state explanation that records arrive in M2; no add button.
- Progress: localized empty-state explanation that trackers arrive in M3/M4; no fake chart.
- Settings: local/cloud mode status and a navigation link to DesignSystem gallery; no unimplemented toggle.

### Step 3: Composition root and environment

`AppEnvironment` contract:

```swift
enum AppEnvironment {
    case uiTesting
    case local
    case cloud(privateDatabaseIdentifier: String)

    static func resolve(
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main
    ) throws -> AppEnvironment
}
```

- `-ui-testing` always chooses in-memory.
- Local config chooses a deterministic Application Support store URL and CloudKit `.none`.
- Cloud config requires nonblank plist container identifier and chooses private CloudKit.
- The plist resolver accepts `CloudKitEnabled` only as a real `Bool` or the build-substituted strings `YES`/`NO`; every other value is a typed configuration error.
- Invalid configuration renders localized fatal `FeatureStateView`; it does not crash or silently switch cloud data into a different local store.

`AppDependencies` owns the `ModelContainer`, one main-context `SwiftDataSeedLoader`, and `SwiftDataTrainingRepository`. It exposes protocols, not `ModelContext`, to views. Launch calls seed exactly once per composition lifecycle before content state.

### Step 4: Five-tab routing

`AppTab` is `String, CaseIterable, Identifiable` with cases today, training, nutrition, progress, settings. `AppRootView` uses one `NavigationStack` per tab so paths do not leak between features. Labels use SF Symbols plus localized text. Identifiers:

```text
tab.today / root.today
tab.training / root.training
tab.nutrition / root.nutrition
tab.progress / root.progress
tab.settings / root.settings
```

### Step 5: Verify, review, commit

- [ ] Run `./scripts/test-ios.sh --only-testing TrainingKitTests`, then `./scripts/test-ios.sh` for every package/UI test and Local Release build, followed by the explicit Cloud compile-only command.
- [ ] Run `rg -n "ModelContext|import SwiftData"` across App and feature targets; only composition/PersistenceKit/CoreModels-approved files may match.
- [ ] Fable receives light/dark screenshots of all five roots and reviews route ownership, truthful placeholders, seed display, loading/error states, localization and accessibility.
- [ ] Resolve findings, amend one commit and require Actions GREEN.

---

## Task M0.9 — Accessibility smoke, localization gate, README ve M0 acceptance

**Commit:** `test: add M0 acceptance gates and setup guide`

**Files:**

- Create: `HealthTrackingAppUITests/AccessibilitySmokeUITests.swift`
- Create: `scripts/verify-localization.sh`
- Create: `scripts/verify-requirements.sh`
- Create: `README.md`
- Create: `docs/evidence/M0/acceptance.md`
- Modify: `scripts/test-ios.sh`
- Modify: `.github/workflows/ios.yml`

### Step 1: Write failing acceptance checks

- [ ] Add UI test at an accessibility content size that traverses all five tabs and asserts root/title/primary content remain hittable without clipped duplicate controls.
- [ ] Add VoiceOver-facing accessibility label/value/hint assertions for tab labels, seed rows, error/empty states and gallery controls.
- [ ] Add light/dark screenshot attachments.
- [ ] Add `verify-localization.sh` contract tests/fixtures so it fails on raw Turkish user-visible literals in Swift views and missing catalog keys, while allowing test fixture/debug assertion strings.
- [ ] Add `verify-requirements.sh` to assert expected module products, exact 23 model names, scheme/config names, ignored `.xcodeproj`, and absence of TODO/TBD/placeholder markers in production sources.
- [ ] Push tests/checks first. Expected RED: accessibility assertions and/or the new verification scripts fail because their required localization/README/evidence contracts are not yet wired; an unavailable simulator or broken test discovery is not an acceptable RED.

### Step 2: Write the novice README

README must provide exact, copyable steps for:

1. Install latest stable Xcode and iOS simulator platform.
2. Install XcodeGen (`brew install xcodegen`).
3. Clone, `./scripts/bootstrap.sh`, then `open HealthTrackingApp.xcodeproj`.
4. Select `HealthTrackingApp-Local`, choose an available iPhone simulator and press Run.
5. Connect a personal iPhone, select Personal Team and understand free signing expiry.
6. Explain that `HealthTrackingApp-Cloud` requires suitable Apple Developer membership/capability and same iCloud account.
7. Explain Local data works without CloudKit; Cloud compile is not sync proof.
8. Run tests with `./scripts/test-ios.sh` and locate `.xcresult`.
9. Troubleshoot missing XcodeGen, no simulator, signing and iCloud configuration without asking the user to edit Swift.

README must not claim TestFlight, Cloud sync, notifications or HealthKit are complete at M0.

### Step 3: Fresh final verification

- [ ] From a clean clone/worktree on macOS, run bootstrap twice and assert the second generation produces no source/project-spec change.
- [ ] Run all package tests.
- [ ] Run Local Debug test suite including UI/accessibility.
- [ ] Run Local Release build with signing disabled.
- [ ] Run Cloud Debug compile-only build with signing disabled.
- [ ] Run localization and requirement scripts.
- [ ] Run `git diff --check`, tracked secret scan, TODO/TBD/placeholder scan and `git status --short`.
- [ ] Populate `docs/evidence/M0/acceptance.md` with exact Xcode/XcodeGen/iOS runtime, test counts, final task hashes, Fable results, Actions URLs and honest device-only `NOT RUN` entries.

### Step 4: Fable milestone review and commit

- [ ] Ask Fable 5 medium to review the entire `M0-base..HEAD` diff against requirement M0 and approved spec, not only Task M0.9.
- [ ] Require explicit remaining Critical/Important list, all-M0 acceptance assessment and `READY/NOT READY`.
- [ ] Validate and fix findings; any code behavior fix gets a failing regression test first and its owning earlier task commit is amended if history has not been shared, otherwise a focused fix commit is documented.
- [ ] Re-run the complete fresh verification after the last change.
- [ ] Finalize Task M0.9 commit and require final Actions GREEN.

---

## 3. M0 Definition of Done checklist

- [ ] `project.yml` generates Local and Cloud schemes on macOS with XcodeGen 2.46.0+.
- [ ] Generated `.xcodeproj` is ignored and disposable.
- [ ] Local Debug tests and Local Release build pass on `macos-15`.
- [ ] Cloud Debug compiles with signing disabled; real sync is explicitly unverified.
- [ ] All non-optional mirrored attributes have declaration-level defaults and the Cloud-shaped container probe has no schema-validation failure. Entitlement-only construction failure is recorded as `BLOCKED` for M5.6, never converted to an M0 pass.
- [ ] Exact 23-model V1 schema is in an in-memory round-trip suite.
- [ ] No schema-level unique constraint conflicts with CloudKit design.
- [ ] M0 seed produces exact profile/program/four phase/A-B-C shell data once.
- [ ] Seed reruns, edits, deletion and partial-crash repair have tests.
- [ ] Repository protocol hides `ModelContext` from UI.
- [ ] Five tabs launch and have isolated navigation roots.
- [ ] Raw seed content is visible on Training root.
- [ ] Light/dark semantic token contrast gates pass.
- [ ] Dynamic Type and accessibility smoke pass.
- [ ] Every user-visible string is catalog-backed Turkish.
- [ ] README clean-clone path is executed, not merely proofread.
- [ ] Every M0 task has Fable review, one final task commit and green CI evidence.
- [ ] `docs/evidence/M0/acceptance.md` contains no unsupported success claim.

## 4. Expected commit sequence

```text
build: bootstrap iOS project and macOS CI
feat(core): add shared domain values and validation
feat(core): add program and training schema
feat(core): complete v1 persistence schema
feat(persistence): add model container and training repository
feat(persistence): seed foundation program idempotently
feat(design): add accessible foundation design system
feat(app): add five-tab foundation shell
test: add M0 acceptance gates and setup guide
```

No commit in this sequence may contain the next task's production behavior. Review-only notes and CI URLs belong in evidence, not source comments.
