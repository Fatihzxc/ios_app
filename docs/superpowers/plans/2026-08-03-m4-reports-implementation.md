# M4 Reports and Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seçili 1A/3A/6A/1Y yerel takvim aralığında eksik veriyi sıfır diye göstermeyen erişilebilir raporları ve kullanıcı eylemiyle üretilen sürümlü CSV/JSON/ZIP dışa aktarımını teslim etmek.

**Architecture:** ReportsKit, SwiftData’dan bağımsız immutable rapor kayıtlarını, saf dataset builder’ları, Swift Charts sunumunu ve export codec’lerini sahiplenir; yalnız DesignSystem ve merkezi Epley hesabı için GuidanceKit’e bağlıdır. PersistenceKit, feature-owned ReportsRepository protokolünü SwiftDataReportsRepository ile uygular ve 24 V2 modelini immutable projeksiyonlara dönüştürür. App’in mevcut lazy TrackerFeatureBundle bileşimi korunur; rapor bağımlılıkları yalnız Progress ilk açıldığında kurulur.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Charts, SwiftData, Observation, AXChartDescriptor, UIKit system share sheet, Foundation FileHandle, XCTest/XCUITest, XcodeGen 2.46.0+, GitHub Actions macos-15.

**Spec:** docs/superpowers/specs/2026-08-03-health-tracking-app-design.md; Saglik-Takip-App-Gereksinim-Dokumani-v1.md §§3 US7, 7.8, 12, 14 M4; docs/superpowers/plans/2026-08-03-health-tracking-app-roadmap.md M4.1–M4.9.

## Global Constraints

- Platform iPhone/iOS 17+; Türkçe birincil ve bütün kullanıcı metinleri String Catalog’dan gelir.
- ReportsKit SwiftData, CloudKit, PhotosUI, PersistenceKit, ModelContext veya başka feature view katmanını import etmez.
- UI doğrudan ModelContext/@Query kullanmaz; ReportsRepository initializer ile enjekte edilir.
- M0 V2 envanterindeki 24 model korunur; M4 yeni @Model, schema version veya migration eklemez.
- Sıfır geçerli sonuçtur; eksik veri nil/boş observation’dır ve grafiğe uydurma sıfır eklenmez.
- Tarih sınırları enjekte edilen Calendar/timezone ile hesaplanır; 86_400 ve gizli Calendar.current kullanılmaz.
- Yüklü tekrar e1RM yalnız GuidanceKit.EpleyEstimate.calculate üzerinden hesaplanır; bodyweight/süre/adıma uygulanmaz.
- Protein paydası yalnız gerçek MealEntry içeren ve pozitif hedefi bulunan günlerdir; boş DailyNutritionLog eksiktir.
- Faz geçmişi ProgramPhase ay alanlarından türetilmez; mevcut state kısmi, yalnız gerçek kullanıcı geçişleri kalıcı geçmiş olur.
- Foto binary’si SwiftData/JSON varsayılanına gömülmez; ZIP’e yalnız açık opt-in, güvenli ad ve checksum manifestiyle girer.
- CSV RFC 4180 CRLF/escaping; JSON schemaVersion; UUID lowercase, UTC ISO-8601 ve locale-independent finite sayı kullanır.
- Export geçici dosyaları share completion/cancel sonrasında idempotent temizlenir; sağlık payload’ı loglanmaz.
- Grafikler seri-sonu etiketi, AXChartDescriptor/Audio Graphs ve görünür metin tablo fallback’i sağlar.
- Her görev test-only RED push, hosted beklenen failure, aynı commit amend GREEN, exact-SHA hosted kabul ve review döngüsüdür.
- Simulator sonucu fiziksel cihaz paylaşımı veya gerçek foto seçimi diye raporlanmaz.

---

## File and ownership map

~~~text
Packages/HealthTrackingModules/Sources/ReportsKit/{DateRange,Domain,Repository,Builders,Charts,Export,Presentation,Resources}
Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift
Packages/HealthTrackingModules/Sources/CoreModels/Values/PhaseTransitionLedger.swift
Packages/HealthTrackingModules/Tests/ReportsKitTests/
Packages/HealthTrackingModules/Tests/PersistenceKitTests/ReportsRepositoryTests.swift
HealthTrackingAppTests/ReportsCompositionTests.swift
HealthTrackingAppUITests/M4ReportsAcceptanceUITests.swift
scripts/verify-m4-reports.sh
docs/evidence/M4/acceptance.md
~~~

ReportsKit presentation-neutral değerleri sahiplenir. PersistenceKit tek SwiftData okuma sınırıdır. ProgressPhotosKit foto byte/compare sahibidir; M4 share renderer orada kalır. App yalnız mevcut lazy Progress route içinde kablolar.

### Task 0: Focused M4 branch CI

**Files:**
- Create: scripts/verify-m4-reports.sh
- Modify: scripts/test-ios.sh
- Modify: .github/workflows/ios.yml
- Modify: scripts/verify-trackers.sh
- Modify: scripts/verify-m3-acceptance.sh

**Interfaces:**
- Consumes: mevcut full test, cold-launch ve small-phone işleri.
- Produces: scripts/test-ios.sh --focused-testing TestIdentifier; test/m4.0…m4.8 push’larında focused job, main/PR/M4.9’da full job.

- [ ] **Step 1: Fail-closed workflow testlerini yaz**

Full test job guard’ını tam olarak kilitle. Test-only RED commit yeni verifier’ı `scripts/test-ios.sh` içindeki mevcut static-gate zincirine ekler, fakat focused flag/job’ı henüz eklemez; böylece pre-existing full workflow aynı committe erken ve yalnız eksik M4 CI sözleşmesi nedeniyle başarısız olur:

~~~yaml
if: ${{ github.event_name != 'push' || !startsWith(github.ref_name, 'test/m4.') || startsWith(github.ref_name, 'test/m4.9-') }}
~~~

Focused job bunun exact tersini kullanır. Self-test her terimi siler, &&/|| değiştirir, M4.9’u focused yola sokar, continue-on-error ekler ve broad --only-testing kullanır; her mutasyon fail olmalıdır.

- [ ] **Step 2: RED’i doğrula**

~~~bash
bash -n scripts/verify-m4-reports.sh
scripts/verify-m4-reports.sh --self-test
scripts/verify-m4-reports.sh
~~~

Expected: real verifier test-m4-focused ve --focused-testing eksikliğiyle fail; inherited M0–M3 self-testleri pass. Hosted old full job da `scripts/test-ios.sh` üzerinden aynı verifier RED’ine ulaşır; yeni job henüz varmış gibi varsayılmaz.

- [ ] **Step 3: Minimum focused runner’ı uygula**

--focused-testing tam bir non-empty identifier kabul eder; bütün static verifier/self-testleri, bootstrap, targeted Debug test ve Local Release build çalıştırır. Mevcut flag’leri değiştirme. Job:

~~~yaml
test-m4-focused:
  if: ${{ github.event_name == 'push' && startsWith(github.ref_name, 'test/m4.') && !startsWith(github.ref_name, 'test/m4.9-') }}
  runs-on: macos-15
  timeout-minutes: 60
~~~

M3 verifier’ları yalnız bu exact güvenli full-job guard’ını kabul eder. Pull request ve main hiçbir koşulda focused yola düşmez.

- [ ] **Step 4: GREEN’i doğrula**

~~~bash
bash -n scripts/test-ios.sh
scripts/verify-trackers.sh --self-test
scripts/verify-m3-acceptance.sh --self-test
scripts/verify-m4-reports.sh --self-test
scripts/test-ios.sh --focused-testing HealthTrackingAppTests
git diff --check
~~~

M4.0 test-only push erken verifier RED; amend sonrası focused/cold/small exact GREEN olmalıdır.

- [ ] **Step 5: Commit**

~~~bash
git add .github/workflows/ios.yml scripts/test-ios.sh scripts/verify-trackers.sh scripts/verify-m3-acceptance.sh scripts/verify-m4-reports.sh
git commit -m "ci: add focused M4 branch verification"
~~~

### Task 1: M4.1 date range and missing coverage

**Files:**
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/DateRange/ReportDateRange.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Domain/ReportsDashboardSource.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Repository/ReportsRepository.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Presentation/ReportsDashboardViewModel.swift
- Create: Packages/HealthTrackingModules/Tests/ReportsKitTests/ReportDateRangeTests.swift
- Create: Packages/HealthTrackingModules/Tests/ReportsKitTests/ReportsDashboardViewModelTests.swift
- Modify: Packages/HealthTrackingModules/Package.swift
- Modify: project.yml
- Modify: scripts/verify-m4-reports.sh

**Interfaces:**
- Consumes: injected Calendar and reference Date.
- Produces: ReportDateRangePreset, ReportDateInterval, ReportCoverage, ReportsDashboardSource, ReportsRepository.fetchDashboardSource(in:).

- [ ] **Step 1: Failing DST/boundary tests**

~~~swift
public enum ReportDateRangePreset: String, CaseIterable, Sendable {
    case oneMonth, threeMonths, sixMonths, oneYear
}
public struct ReportDateInterval: Equatable, Sendable {
    public let start: Date
    public let endExclusive: Date
    public func contains(_ date: Date) -> Bool
}
~~~

Istanbul ve Los Angeles DST fixture’ları; end next local day, start Calendar month/year subtraction, endExclusive timestamp excluded. Empty coverage observedCount 0 ve first/last nil.

- [ ] **Step 2: RED komutu**

~~~bash
scripts/test-ios.sh --focused-testing ReportsKitTests/ReportDateRangeTests
~~~

Expected: missing ReportDateRangeResolver compile failure.

- [ ] **Step 3: Saf resolver ve repository boundary**

Resolver calendar.startOfDay, date(byAdding: .day, value: 1), sonra preset için -1/-3/-6 month veya -1 year kullanır. ReportsDashboardSource sonraki görevlerin immutable array’lerini default [] ile taşır; numeric sentinel yoktur.

~~~swift
let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: startOfReferenceDay) else {
    throw ReportDateRangeError.unrepresentableBoundary
}
let component: Calendar.Component = preset == .oneYear ? .year : .month
let amount = preset == .oneMonth ? -1 : preset == .threeMonths ? -3 : preset == .sixMonths ? -6 : -1
guard let start = calendar.date(byAdding: component, value: amount, to: endExclusive) else {
    throw ReportDateRangeError.unrepresentableBoundary
}
return ReportDateInterval(start: start, endExclusive: endExclusive)
~~~

- [ ] **Step 4: Wiring ve GREEN**

ReportsKit dependencies DesignSystem+GuidanceKit; PersistenceKit dependency listesine ReportsKit; yeni ReportsKitTests Local scheme’e. Verifier ReportsKit altında SwiftData/CloudKit/PhotosUI/PersistenceKit/ModelContext importlarını reddeder.

~~~bash
scripts/test-ios.sh --focused-testing ReportsKitTests
scripts/verify-m4-reports.sh --self-test
git diff --check
~~~

- [ ] **Step 5: Commit**

~~~bash
git add Packages/HealthTrackingModules/Package.swift Packages/HealthTrackingModules/Sources/ReportsKit Packages/HealthTrackingModules/Tests/ReportsKitTests project.yml scripts/verify-m4-reports.sh
git commit -m "feat(reports): add local date range contract"
~~~

### Task 2: M4.2 body and strength datasets

**Files:**
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Domain/BodyStrengthReport.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Builders/BodyStrengthDatasetBuilder.swift
- Create: Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift
- Create: Packages/HealthTrackingModules/Tests/ReportsKitTests/BodyStrengthDatasetBuilderTests.swift
- Create: Packages/HealthTrackingModules/Tests/PersistenceKitTests/ReportsRepositoryTests.swift
- Modify: scripts/verify-m4-reports.sh

**Interfaces:**
- Consumes: interval, BodyMetric, completed WorkoutSession, SetLog, ExerciseTemplate, exact GuidanceKit Epley.
- Produces: ReportBodyMetricRecord, ReportExerciseSetRecord, BodyStrengthReport.

- [ ] **Step 1: Failing aggregation tests**

Tests require latest actual body observation per local day; stable date/createdAt/UUID ordering; no missing-day zero; completed non-warmup sets only; volume sum(weight*reps); session max e1RM. Bodyweight/süre/adım e1RM nil.

~~~swift
guard record.measurement == .weightedRepetitions,
      let estimate = EpleyEstimate.calculate(
          weightKg: record.weightKg,
          reps: record.reps
      ) else { return nil }
~~~

- [ ] **Step 2: RED komutu**

~~~bash
scripts/test-ios.sh --focused-testing ReportsKitTests/BodyStrengthDatasetBuilderTests
~~~

- [ ] **Step 3: Builder ve finite filtering**

Persistence projection invalid persisted finite/range değerinde typed integrity error verir, asla zero coercion yapmaz. Chart body points local-day reduce edilir; export source bütün valid satırları korur.

~~~swift
let eligible = records.filter { $0.sessionCompleted && !$0.isWarmup }
let volume = eligible.reduce(into: 0.0) { total, record in
    guard let weight = record.weightKg, let reps = record.reps else { return }
    total += weight * Double(reps)
}
let estimatedOneRepMax = eligible.compactMap { record -> Double? in
    guard record.measurement == .weightedRepetitions else { return nil }
    return EpleyEstimate.calculate(weightKg: record.weightKg, reps: record.reps)
}.max()
~~~

- [ ] **Step 4: Read-only repository GREEN**

In-memory V2 tests exact boundary, deterministic order, invalid-row fail, no ModelContext mutation.

~~~bash
scripts/test-ios.sh --focused-testing ReportsKitTests/BodyStrengthDatasetBuilderTests
scripts/test-ios.sh --focused-testing PersistenceKitTests/ReportsRepositoryTests
scripts/verify-m4-reports.sh --self-test
git diff --check
~~~

- [ ] **Step 5: Commit**

~~~bash
git add Packages/HealthTrackingModules/Sources/ReportsKit Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift Packages/HealthTrackingModules/Tests/ReportsKitTests Packages/HealthTrackingModules/Tests/PersistenceKitTests/ReportsRepositoryTests.swift scripts/verify-m4-reports.sh
git commit -m "feat(reports): build body and strength datasets"
~~~

### Task 3: M4.3 honest protein adherence

**Files:**
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Domain/ProteinAdherenceReport.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Builders/ProteinAdherenceBuilder.swift
- Create: Packages/HealthTrackingModules/Tests/ReportsKitTests/ProteinAdherenceBuilderTests.swift
- Extend: Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift
- Extend: Packages/HealthTrackingModules/Tests/PersistenceKitTests/ReportsRepositoryTests.swift
- Extend: scripts/verify-m4-reports.sh

**Interfaces:**
- Consumes: actual MealEntry rows and current UserProfile.proteinTargetG.
- Produces: ReportNutritionDayRecord and ProteinAdherenceReport.

- [ ] **Step 1: Failing denominator tests**

~~~swift
public struct ProteinAdherenceReport: Equatable, Sendable {
    public let observedDayCount: Int
    public let targetDayCount: Int
    public let hitDayCount: Int
    public let excludedTargetlessDayCount: Int
    public let adherencePercent: Double?
    public let provenance: ProteinTargetProvenance
}
~~~

Empty DailyNutritionLog missing; actual zero-protein MealEntry observed zero; non-finite/non-positive target excluded; denominator zero -> nil; otherwise hit/target*100.

- [ ] **Step 2: RED**

~~~bash
scripts/test-ios.sh --focused-testing ReportsKitTests/ProteinAdherenceBuilderTests
~~~

- [ ] **Step 3: Projection and provenance**

Repository emits only dates with at least one MealEntry and sums resolved snapshot macros. Historical target snapshots do not exist, so current valid target is applied only to observed days and result is currentProfileAppliedToObservedDays; UI cannot label it historical target truth.

~~~swift
let targetDays = days.filter { day in
    day.entryCount > 0 && (day.proteinTargetG.map { $0.isFinite && $0 > 0 } ?? false)
}
let hitDays = targetDays.filter { day in
    guard let target = day.proteinTargetG else { return false }
    return day.proteinTotalG >= target
}
let percent = targetDays.isEmpty
    ? nil
    : Double(hitDays.count) / Double(targetDays.count) * 100
~~~

- [ ] **Step 4: GREEN and mutations**

Verifier mutations calendar-day denominator, empty-log zero and nil-to-zero; all fail.

~~~bash
scripts/test-ios.sh --focused-testing ReportsKitTests/ProteinAdherenceBuilderTests
scripts/test-ios.sh --focused-testing PersistenceKitTests/ReportsRepositoryTests
git diff --check
~~~

- [ ] **Step 5: Commit**

~~~bash
git add Packages/HealthTrackingModules/Sources/ReportsKit Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift Packages/HealthTrackingModules/Tests/ReportsKitTests Packages/HealthTrackingModules/Tests/PersistenceKitTests/ReportsRepositoryTests.swift scripts/verify-m4-reports.sh
git commit -m "feat(reports): add honest protein adherence"
~~~

### Task 4: M4.4 lifestyle, posture, and phase evidence

**Files:**
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Domain/LifestylePhaseReport.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Builders/LifestylePhaseDatasetBuilder.swift
- Create: Packages/HealthTrackingModules/Sources/CoreModels/Values/PhaseTransitionLedger.swift
- Create: Packages/HealthTrackingModules/Tests/CoreModelsTests/PhaseTransitionLedgerTests.swift
- Create: Packages/HealthTrackingModules/Tests/ReportsKitTests/LifestylePhaseDatasetBuilderTests.swift
- Modify: Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataTrainingRepository.swift
- Extend: Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift
- Create: Packages/HealthTrackingModules/Tests/PersistenceKitTests/PhaseTransitionLedgerRepositoryTests.swift

**Interfaces:**
- Consumes: SleepLog, MoodLog, PostureMetric, current ProgramState/ProgramPhase and future actual phase mutations.
- Produces: PhaseTransitionLedgerV1, ReportPhaseSegment, PhaseTimelineProvenance and gap-aware series.

- [ ] **Step 1: Failing ledger/gap tests**

~~~swift
public struct PhaseTransitionLedgerV1: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var records: [PhaseTransitionRecord]
}
~~~

Malformed/unknown version fails closed; append only actual phase change; state+ledger rollback together. Missing local day splits line; explicit mood/posture 0 remains point. Lone ProgramState is partialCurrentState; monthStart/monthEnd creates nothing.

- [ ] **Step 2: RED**

~~~bash
scripts/test-ios.sh --focused-testing CoreModelsTests/PhaseTransitionLedgerTests
scripts/test-ios.sh --focused-testing ReportsKitTests/LifestylePhaseDatasetBuilderTests
~~~

- [ ] **Step 3: Atomic AppSetting ledger**

Key, "phase-transition-ledger.v1." öneki ile lowercase program UUID birleştirilerek üretilir. On actual change append old/new IDs, old phaseStartedAt, transition date and update ProgramState in one transaction. Same phase is no-op. Sort date then UUID; duplicate logical transition fails.

~~~swift
guard state.currentPhaseId != phaseID else { return state }
ledger.records.append(
    PhaseTransitionRecord(
        programID: programID,
        fromPhaseID: state.currentPhaseId,
        toPhaseID: phaseID,
        fromStartedAt: state.phaseStartedAt,
        transitionedAt: date
    )
)
state.currentPhaseId = phaseID
state.phaseStartedAt = date
~~~

- [ ] **Step 4: GREEN**

~~~bash
scripts/test-ios.sh --focused-testing CoreModelsTests/PhaseTransitionLedgerTests
scripts/test-ios.sh --focused-testing ReportsKitTests/LifestylePhaseDatasetBuilderTests
scripts/test-ios.sh --focused-testing PersistenceKitTests/PhaseTransitionLedgerRepositoryTests
git diff --check
~~~

- [ ] **Step 5: Commit**

~~~bash
git add Packages/HealthTrackingModules/Sources/CoreModels/Values/PhaseTransitionLedger.swift Packages/HealthTrackingModules/Sources/ReportsKit Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories Packages/HealthTrackingModules/Tests/CoreModelsTests/PhaseTransitionLedgerTests.swift Packages/HealthTrackingModules/Tests/ReportsKitTests Packages/HealthTrackingModules/Tests/PersistenceKitTests/PhaseTransitionLedgerRepositoryTests.swift
git commit -m "feat(reports): add lifestyle and phase history"
~~~


### Task 5: M4.5 private, share-safe photo comparison

**Files:**
- Create: Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Share/ProgressPhotoComparisonShareDomain.swift
- Create: Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Share/UIKitProgressPhotoComparisonRenderer.swift
- Create: Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Share/ProgressPhotoComparisonShareCoordinator.swift
- Create: Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/ProgressPhotoComparisonShareTests.swift
- Modify: Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoGalleryViewModel.swift
- Modify: Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoGalleryView.swift
- Modify: Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Resources/Localizable.xcstrings
- Create: Packages/HealthTrackingModules/Sources/DesignSystem/Platform/SystemActivityView.swift

**Interfaces:**
- Consumes: exactly two already-normalized full images from ProgressPhotoGalleryViewModel.
- Produces: ProgressPhotoComparisonShareDescriptor, ProgressPhotoComparisonRendering, and a one-use temp artifact.

- [ ] **Step 1: Failing privacy/lifecycle tests**

~~~swift
public struct ProgressPhotoShareItem: Equatable, Sendable {
    public let imageData: Data
    public let date: Date
    public let pose: ProgressPhotoPose
}
public struct ProgressPhotoComparisonShareDescriptor: Equatable, Sendable {
    public let before: ProgressPhotoShareItem
    public let after: ProgressPhotoShareItem
}
~~~

Tests require chronological order, explicit user tap, unavailable/corrupt rejection, image/date/pose only, no note/assetID/path bytes in rendered metadata, and cleanup after completed/cancelled/failed share.

- [ ] **Step 2: RED**

~~~bash
scripts/test-ios.sh --focused-testing ProgressPhotosKitTests/ProgressPhotoComparisonShareTests
~~~

- [ ] **Step 3: Renderer/coordinator**

UIKit renderer decodes normalized JPEGs, draws an accessible before/after composite with localized date/pose captions, encodes a metadata-free JPEG, writes to an owned complete-file-protected temporary directory, and returns an idempotent cleanup closure. It never reads model notes or exposes opaque IDs.

~~~swift
let descriptor = ProgressPhotoComparisonShareDescriptor(
    before: ProgressPhotoShareItem(imageData: beforeData, date: before.date, pose: before.pose),
    after: ProgressPhotoShareItem(imageData: afterData, date: after.date, pose: after.pose)
)
let renderedData = try await renderer.render(descriptor)
return try temporaryStore.writeOneUseJPEG(renderedData)
~~~

- [ ] **Step 4: Gallery integration GREEN**

Share button exists only after two full images are available, is at least 52 pt, has stable identifier photos.compare.share, preserves selection on error, and routes system activity completion to cleanup.

~~~bash
scripts/test-ios.sh --focused-testing ProgressPhotosKitTests/ProgressPhotoComparisonShareTests
scripts/test-ios.sh --focused-testing HealthTrackingAppUITests/ProgressPhotoGalleryUITests
git diff --check
~~~

- [ ] **Step 5: Commit**

~~~bash
git add Packages/HealthTrackingModules/Sources/ProgressPhotosKit Packages/HealthTrackingModules/Sources/DesignSystem/Platform/SystemActivityView.swift Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests
git commit -m "feat(photos): share safe comparisons"
~~~

### Task 6: M4.6 one typed tabular schema and RFC 4180 CSV

**Files:**
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Export/ExportSchemaV1.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Export/ExportSnapshotV1.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Export/RFC4180CSVEncoder.swift
- Create: Packages/HealthTrackingModules/Tests/ReportsKitTests/ExportSchemaInventoryTests.swift
- Create: Packages/HealthTrackingModules/Tests/ReportsKitTests/RFC4180CSVEncoderTests.swift
- Extend: Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift
- Create: Packages/HealthTrackingModules/Tests/PersistenceKitTests/ReportsExportRepositoryTests.swift

**Interfaces:**
- Consumes: all 24 HealthTrackingSchemaV2 model types, selected range, selected module set.
- Produces: ExportTableV1 arrays for profile_program, training, nutrition, metrics, lifestyle, health, photos, system and CSV files with fixed schemas.

- [ ] **Step 1: Failing inventory/escaping tests**

~~~swift
public enum ExportCellV1: Equatable, Sendable {
    case null
    case text(String)
    case integer(Int64)
    case decimal(Double)
    case boolean(Bool)
    case timestamp(Date)
    case uuid(UUID)
}
public struct ExportTableV1: Equatable, Sendable {
    public let module: ExportModuleV1
    public let columns: [ExportColumnV1]
    public let rows: [ExportRowV1]
}
~~~

Inventory test maps exactly UserProfile, Program, ProgramPhase, ProgramState, WorkoutDayTemplate, ExerciseTemplate, WarmupItem, CooldownItem, WorkoutSession, SetLog, WorkoutSessionProgress, Food, Recipe, DailyNutritionLog, MealEntry, BodyMetric, PostureMetric, SleepLog, MoodLog, HealthCheckReminder, BloodworkResult, ProgressPhoto, AppReminder, AppSetting. Session-progress Data codecs export decoded UUID arrays, never raw blobs.

CSV tests cover comma, quote, CR/LF, Turkish text, empty string versus null, UTC timestamps, lowercase UUID, dot decimal, NaN/infinity rejection, CRLF records, stable row order, and formula-leading = + - @ tab/carriage-return neutralization for text cells.

- [ ] **Step 2: RED**

~~~bash
scripts/test-ios.sh --focused-testing ReportsKitTests/RFC4180CSVEncoderTests
~~~

- [ ] **Step 3: Fixed schema and encoder**

Every module table begins record_type,id,created_at,updated_at and has a versioned fixed union of typed nullable columns. Unquoted empty field means null; quoted empty means an actual empty string. Text beginning with spreadsheet formula characters receives a leading apostrophe in CSV only; an original leading apostrophe is doubled first so the schema-aware round-trip decoder can reverse the transform without ambiguity. JSON Task 7 preserves original text.

~~~swift
switch cell {
case .null:
    return ""
case let .text(value) where value.isEmpty:
    return "\"\""
case let .text(value):
    return escapeRFC4180(reversiblyNeutralizeSpreadsheetFormula(value))
case let .decimal(value):
    guard value.isFinite else { throw ExportEncodingError.nonFiniteNumber }
    return localeIndependentDecimal(value)
default:
    return escapeRFC4180(canonicalString(for: cell))
}
~~~

Time-series rows are range-filtered. Referenced profile/program/templates/settings required to interpret selected rows are included and marked config_scope=referenced. Sorting is module, record_type, primary timestamp, UUID.

- [ ] **Step 4: Repository mapping and GREEN**

~~~bash
scripts/test-ios.sh --focused-testing ReportsKitTests/ExportSchemaInventoryTests
scripts/test-ios.sh --focused-testing ReportsKitTests/RFC4180CSVEncoderTests
scripts/test-ios.sh --focused-testing PersistenceKitTests/ReportsExportRepositoryTests
git diff --check
~~~

- [ ] **Step 5: Commit**

~~~bash
git add Packages/HealthTrackingModules/Sources/ReportsKit/Export Packages/HealthTrackingModules/Tests/ReportsKitTests Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift Packages/HealthTrackingModules/Tests/PersistenceKitTests/ReportsExportRepositoryTests.swift
git commit -m "feat(reports): export RFC 4180 CSV"
~~~

### Task 7: M4.7 versioned JSON, safe ZIP, opt-in photos, and temp cleanup

**Files:**
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Export/JSONExportEncoderV1.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Export/CRC32.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Export/StoredZIPWriter.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Export/ExportManifestV1.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Export/ReportExportCoordinator.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Presentation/ReportExportViewModel.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Presentation/ReportExportView.swift
- Create: Packages/HealthTrackingModules/Tests/ReportsKitTests/JSONExportEncoderTests.swift
- Create: Packages/HealthTrackingModules/Tests/ReportsKitTests/StoredZIPWriterTests.swift
- Create: Packages/HealthTrackingModules/Tests/ReportsKitTests/ReportExportCoordinatorTests.swift
- Modify: Packages/HealthTrackingModules/Sources/ReportsKit/Resources/Localizable.xcstrings

**Interfaces:**
- Consumes: Task 6 ExportTableV1, optional photo byte provider supplied by app, system activity completion.
- Produces: JSON root schemaVersion=1; CSV URLs, JSON URL, or Both ZIP URL; manifest and cleanup token.

- [ ] **Step 1: Failing JSON/ZIP/lifecycle tests**

~~~swift
public enum ReportExportFormat: String, Sendable {
    case csv, json, bothZip
}
public struct ReportExportRequest: Equatable, Sendable {
    public let interval: ReportDateInterval
    public let modules: Set<ExportModuleV1>
    public let format: ReportExportFormat
    public let includesPhotos: Bool
}
~~~

Require includesPhotos only when format == bothZip and explicit toggle true; default false. JSON sorted keys, native null/bool/number/string, original text, stable table/row order. ZIP tests cover stored method, CRC32, UTF-8 and data-descriptor flags, sorted safe relative names, duplicate/traversal/absolute/symlink rejection, UInt32/count/offset limits, cancellation, and partial-output cleanup.

- [ ] **Step 2: RED**

~~~bash
scripts/test-ios.sh --focused-testing ReportsKitTests/StoredZIPWriterTests
scripts/test-ios.sh --focused-testing ReportsKitTests/ReportExportCoordinatorTests
~~~

- [ ] **Step 3: Streaming ZIP and manifest**

StoredZIPWriter streams FileHandle chunks, computes CRC32/size while writing, emits local header + data descriptor + central directory + EOCD with the canonical DOS timestamp 1980-01-01 00:00, and throws explicit zip32LimitExceeded before truncation. Manifest includes schema version, selected range/modules, each relative path, byte size, SHA-256, media type, photo opt-in state, and missing/corrupt photo status. Photo entry names use the form photos/{lowercase photo UUID}.jpg, never imageRef/path/note. Neither JSON nor manifest bytes include a wall-clock generation field.

~~~swift
guard !request.includesPhotos || request.format == .bothZip else {
    throw ReportExportError.photosRequireZIP
}
let orderedEntries = try entries.sorted { $0.relativePath < $1.relativePath }
try await zipWriter.writeStored(entries: orderedEntries, to: outputURL)
~~~

- [ ] **Step 4: Coordinator and cleanup GREEN**

Coordinator creates one protected temp directory, writes deterministic artifacts, and returns an ExportArtifactToken. token.cleanup() is idempotent. ViewModel calls cleanup on share success, share cancel, view cancellation and generation supersession. Export error preserves user selection and offers retry.

ReportExportView exposes selected range, eight module toggles and CSV/JSON/İkisi format. Photo inclusion is hidden for CSV/JSON and defaults off for İkisi; enabling it requires an explicit toggle. Work exceeding 400 ms shows cancellable progress without discarding the selection.

~~~bash
scripts/test-ios.sh --focused-testing ReportsKitTests/JSONExportEncoderTests
scripts/test-ios.sh --focused-testing ReportsKitTests/StoredZIPWriterTests
scripts/test-ios.sh --focused-testing ReportsKitTests/ReportExportCoordinatorTests
git diff --check
~~~

- [ ] **Step 5: Commit**

~~~bash
git add Packages/HealthTrackingModules/Sources/ReportsKit/Export Packages/HealthTrackingModules/Sources/ReportsKit/Presentation Packages/HealthTrackingModules/Sources/ReportsKit/Resources/Localizable.xcstrings Packages/HealthTrackingModules/Tests/ReportsKitTests
git commit -m "feat(reports): export versioned JSON and ZIP"
~~~

### Task 8: M4.8 accessible Swift Charts and lazy Progress composition

**Files:**
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Charts/ReportLineChart.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Charts/ReportBarChart.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Charts/ReportChartDescriptorFactory.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Charts/ReportTextTable.swift
- Replace: Packages/HealthTrackingModules/Sources/ReportsKit/Foundation/ReportsFoundationView.swift
- Create: Packages/HealthTrackingModules/Sources/ReportsKit/Presentation/ReportsDashboardView.swift
- Create: Packages/HealthTrackingModules/Tests/ReportsKitTests/ReportChartDescriptorTests.swift
- Extend: Packages/HealthTrackingModules/Tests/ReportsKitTests/ReportsDashboardViewModelTests.swift
- Modify: App/Application/TrackerFeatureBundle.swift
- Modify: App/Application/TrackerFeatureRouting.swift
- Modify: App/Application/AppDependencies.swift
- Create: HealthTrackingAppTests/ReportsCompositionTests.swift
- Modify: Packages/HealthTrackingModules/Sources/ReportsKit/Resources/Localizable.xcstrings

**Interfaces:**
- Consumes: Tasks 1–4 reports, Task 7 export VM, existing tracker callbacks.
- Produces: ReportsDashboardBuilder.build(source:interval:calendar:), range selector, body/strength/protein/lifestyle/posture/phase dashboard, export sheet, AX descriptors and visible tables.

- [ ] **Step 1: Failing descriptor/composition tests**

Descriptor tests assert title, axis labels/units, exact observed points only, gap-separated series, summary/coverage and end values. Composition tests assert root construction/Today launch instantiates zero ReportsRepository; first Progress route exactly one cached instance; repeat route reuses it.

- [ ] **Step 2: RED**

~~~bash
scripts/test-ios.sh --focused-testing ReportsKitTests/ReportChartDescriptorTests
scripts/test-ios.sh --focused-testing HealthTrackingAppTests/ReportsCompositionTests
~~~

- [ ] **Step 3: Charts and fallback**

Each chart uses direct annotation on the final actual point, shape/text plus color, accessibilityChartDescriptor, and an always-reachable DisclosureGroup text table listing date/value/unit. Empty and partial states say the next useful action; they never display zero trend. ViewModel fetches SwiftData source on MainActor then builds Sendable datasets off-main with cancellation generation guards.

Strength presentation includes an accessible exercise picker containing only exercises with valid observed series. The selected-range summary states observation counts, first/last dates, missing/partial provenance and protein numerator/denominator; it does not infer a trend when fewer than two observations exist.

~~~swift
let source = try await repository.fetchDashboardSource(in: interval)
let report = try await Task.detached(priority: .userInitiated) {
    try ReportsDashboardBuilder.build(source: source, interval: interval, calendar: calendar)
}.value
guard generation == loadGeneration, !Task.isCancelled else { return }
self.report = report
~~~

- [ ] **Step 4: Lazy wiring and GREEN**

TrackerFeatureBundle receives ReportsRepository and export/photo capabilities from DefaultTrackerFeatureFactory; no eager AppDependencies repository is added. Progress keeps existing quick entries/history and adds reports without nested NavigationStack. Range selector uses 1A/3A/6A/1Y localized labels and remains operable at AX5.

~~~bash
scripts/test-ios.sh --focused-testing ReportsKitTests
scripts/test-ios.sh --focused-testing HealthTrackingAppTests/ReportsCompositionTests
scripts/verify-m4-reports.sh --self-test
git diff --check
~~~

- [ ] **Step 5: Commit**

~~~bash
git add Packages/HealthTrackingModules/Sources/ReportsKit App/Application/TrackerFeatureBundle.swift App/Application/TrackerFeatureRouting.swift App/Application/AppDependencies.swift HealthTrackingAppTests/ReportsCompositionTests.swift Packages/HealthTrackingModules/Tests/ReportsKitTests
git commit -m "feat(reports): add accessible report dashboard"
~~~

### Task 9: M4.9 US7 acceptance, round trip, performance, and evidence

**Files:**
- Create: HealthTrackingAppUITests/M4ReportsAcceptanceUITests.swift
- Create: HealthTrackingAppUITests/M4ReportsAccessibilityUITests.swift
- Modify: App/Support/AppUITestLaunchConfiguration.swift
- Create: HealthTrackingAppTests/M4ExportRoundTripTests.swift
- Create: Packages/HealthTrackingModules/Tests/ReportsKitTests/ReportsLargeDatasetTests.swift
- Extend: scripts/verify-m4-reports.sh
- Modify: .github/workflows/ios.yml
- Create: docs/evidence/M4/acceptance.md

**Interfaces:**
- Consumes: all M4 behavior and exact accepted task SHAs/runs.
- Produces: immutable M4.9 acceptance SHA, screenshot/XCResult/export artifacts, evidence-gate RED/GREEN, then no-ff main merge.

- [ ] **Step 1: Acceptance-only RED**

Use fixed now/timezone and deterministic report repository. UI covers 1A/3A/6A/1Y, kilo/bel, one weighted movement e1RM+volume, honest protein denominator/provenance, sleep/mood/posture gaps, partial phase copy, two-photo share, CSV/JSON/Both export, cancel/retry/cleanup, light/dark default/XXL/AX3/AX5, Reduce Motion, high contrast and small phone.

Round-trip test decodes JSON native cells and custom RFC4180 CSV back to ExportTableV1 equality, checks all 24 record types, then validates generated ZIP with the pure inspector. Hosted acceptance extracts an attached ZIP and runs /usr/bin/unzip -t plus manifest checksum verification.

- [ ] **Step 2: RED run**

~~~bash
scripts/test-ios.sh --focused-testing HealthTrackingAppUITests/M4ReportsAcceptanceUITests
~~~

Expected: a real missing M4 integration/evidence assertion; no deliberate syntax or manifest failure.

- [ ] **Step 3: GREEN audit**

Large fixture includes at least 10,000 time-series rows and 500 photo metadata rows. Test enforces deterministic output, bounded chart point reduction, cancellation responsiveness and a generous hosted performance ceiling; no health payload in logs. test/m4.9-* exact branch uses the full test/cold/small jobs, not focused CI.

- [ ] **Step 4: Evidence gate and final verification**

First accept immutable M4.9 implementation exact-SHA GREEN. Then push an evidence-gate test-only commit that fails only because docs/evidence/M4/acceptance.md is absent; amend with evidence document and production verifier. Record every prior RED/GREEN SHA/run, tests, artifacts/hashes, review, privacy scan, and physical-device-only items as NOT RUN/BLOCKED. The document explicitly states that its own byte-changing commit/run cannot be self-embedded; that exact SHA/run is retained in the SDD ledger and the later M5 trace/final handoff.

~~~bash
scripts/verify-m4-reports.sh --self-test
scripts/verify-m4-reports.sh
scripts/test-ios.sh
git diff --check
~~~

- [ ] **Step 5: Merge and main gate**

This is a controller-owned finishing step, not an implementer-subagent mutation. Preserve feat/m4-reports and task branches. After whole-branch review, the controller merges --no-ff into remote-confirmed main, pushes with exact lease, and requires exact main SHA test/cold/small GREEN before M5.

~~~bash
git merge --no-ff feat/m4-reports -m "merge: complete M4 reports and export"
git push --force-with-lease=refs/heads/main:a104fcad8429009d47359e6aebb1a6ace20f12e6 origin main:refs/heads/main
~~~

## Self-review checklist

- [ ] Every roadmap M4.1–M4.9 item maps to exactly one task above; CI support is isolated Task 0.
- [ ] All 24 V2 models appear in Task 6 inventory; no raw WorkoutSessionProgress Data leaks.
- [ ] Missing/zero, targetless denominator, phase provenance, photo opt-in and temp cleanup each have a named failing test.
- [ ] ReportsKit dependency direction and lazy cold-launch composition are explicit.
- [ ] CSV and JSON share ExportTableV1; format drift requires a test failure.
- [ ] ZIP paths/CRC/limits and external unzip validation are explicit.
- [ ] Chart AX descriptor, Audio Graphs, text fallback and matrix are explicit.
- [ ] Run the prohibited-word scan and require no matches.
- [ ] Verify every type used by a later task is produced in an earlier Interfaces block.
