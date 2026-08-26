# M3 Metrikler, Fotoğraf, Yaşam ve Sağlık — Uygulama Planı

> Yürütme, exact-SHA M2 `main` kapısından açılan `feat/m3-trackers` dalında görev başına test-only RED → aynı commit amend ile GREEN → exact-SHA CI → inceleme döngüsüdür.

**Goal:** BodyMetric, SleepLog, MoodLog, PostureMetric, HealthCheckReminder, BloodworkResult ve ProgressPhoto akışlarını local-first, erişilebilir ve tıbbi yorum üretmeyen biçimde uçtan uca teslim etmek; fotoğraf binary'sini SwiftData dışında tutmak ve manuel CKAsset hattını protokol-fake düzeyinde doğrulamak.

**Architecture:** Feature protokolleri kendi modüllerinde yaşar. `MetricsKit`, `SleepMoodKit`, `HealthChecksKit` ve `ProgressPhotosKit` yalnız `CoreModels`/`DesignSystem`, dependency-neutral `HealthSafetyKit` ve açık değer protokollerine bağlıdır. `PersistenceKit` SwiftData implementasyonlarını sağlar. `NotificationsKit` saf planlayıcı + sistem adaptör sınırını sahiplenir. App target composition, Today/Progress routing ve Training semptom olayını Metrics repository'ye çeviren adaptörü kurar. Feature modülleri birbirlerinin view katmanını veya `PersistenceKit`i import etmez.

**Frozen model rule:** M0 V2 entity envanteri değişmez; M3 yeni `@Model`, schema version veya migration eklemez. Mevcut `Double`/`String` alanları persistence sınırıdır; domain input'ları finite/range/trim validation uygular.

**Binding references:** gereksinim v1 §§6, 7.4–7.7, 7.9, 8, 11–12; ana tasarım §§3.2–3.3, 4.5–4.7, 6, 9.4, 10–14, M3 teslimleri; roadmap M3.1–M3.12; M2 kabul kanıtı.

**Platform/safety references:** Apple [Selecting Photos and Videos in iOS](https://developer.apple.com/documentation/photokit/selecting-photos-and-videos-in-ios), [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset), [CKServerChangeToken](https://developer.apple.com/documentation/cloudkit/ckserverchangetoken), [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications), [Scheduling a notification locally](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app) and [Encrypting Your App’s Files](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files); NHS inform [Degenerative cervical myelopathy](https://www.nhsinform.scot/illnesses-and-conditions/muscle-bone-and-joints/neck-and-back-problems-and-conditions/degenerative-cervical-myelopathy/) for non-diagnostic red-flag information.

## 1. Milestone-wide contract

1. Her M3.x için önce test/fixture/wiring-only commit GitHub'a gönderilir ve production sembolü/davranışı eksikliğinden qualifying RED alınır.
2. Aynı görev commit'i production ile amend edilir; exact SHA tam CI yeşil olmadan görev kabul edilmez.
3. Gitea kısa ve sınırlı kontrol edilir; erişilemiyorsa GitHub hattı beklemez. Bilinmeyen remote uç force push ile ezilmez.
4. Her repository sonucu CoreModels referans nesnesi değil immutable snapshot döndürür; UI doğrudan `ModelContext`, `@Query`, CloudKit veya file path görmez.
5. Takvim/gün/recurrence hesapları enjekte edilen `Calendar`/timezone kullanır; `Calendar.current`, `Date.now` ve sabit 86_400 saniye gizli dependency olamaz.
6. Sayısal değerler kayıttan önce `isFinite` ve alan aralığı kontrolünden geçer. UI formatter locale-aware; storage/domain doğrulaması locale-independent olur.
7. Save state `idle/saving/saved/error`, request-ID/generation guard, kullanıcı girdisini koruyan retry ve yalnız başarıyla yazılmış mutation için undo sözleşmesini taşır.
8. Sağlık verisi, fotoğraf adı/yolu veya marker değeri log/analytics'e yazılmaz. Tıbbi eşik/teşhis/yorum uydurulmaz.
9. Simulator/compile-only kanıtı CloudKit sync, gerçek notification delivery veya fiziksel cihaz davranışı olarak raporlanmaz.
10. `scripts/verify-trackers.sh` M3.1 test-only RED'inde oluşturulur, aynı dilimde production sözleşmesine geçirilir ve `scripts/test-ios.sh` ile GitHub Actions statik kapısına bağlanır. Her sonraki M3 görevi kendi dosya/dependency/localization/privacy sözleşmesini ve en az bir fail-closed mutation'ı bu doğrulayıcıya ekler.
11. Yeni Swift package target'ı açan test-only RED, SwiftPM'in target/test discovery yapabilmesi için yalnız davranışsız ve public API içermeyen bir module-marker kaynak dosyası ekleyebilir. Domain tipi, repository davranışı, validation veya UI bu marker'a konmaz; qualifying RED keşfedilmiş test target'ında eksik production sembolünden gelir, manifest/source-layout hatasından değil.
12. Workflow'daki mevcut targeted-test adımı her görev RED'inde o görevin keşfedilmiş bundle/test-case'ine yöneltilir; bu, qualifying failure'ı tam suite'den önce görünür kılar. GREEN yine aynı exact SHA üzerinde targeted adımı, eksiksiz Debug suite'i, Release build, screenshot export, Cloud compile-only, cold-launch ve small-phone işlerinin tamamını geçmek zorundadır; targeted adım hiçbir genel kapının yerine geçmez.

## 2. Expected module layout and dependency gates

```text
Sources/MetricsKit/{Domain,Repository,QuickEntry,BodyMetric,Posture,Resources}
Sources/SleepMoodKit/{Domain,Repository,Entry,Resources}
Sources/HealthChecksKit/{Domain,Repository,Reminder,Bloodwork,Resources}
Sources/ProgressPhotosKit/{Domain,Repository,AssetStore,Gallery,CloudAsset,Resources}
Sources/NotificationsKit/{Domain,Planner,SystemAdapter,Resources}
Sources/HealthSafetyKit/{Domain,Presentation,Resources}
Sources/PersistenceKit/Repositories/{SwiftDataMetricsRepository,SwiftDataLifestyleRepository,SwiftDataHealthChecksRepository,SwiftDataProgressPhotoRepository}.swift
Tests/{MetricsKitTests,SleepMoodKitTests,HealthChecksKitTests,ProgressPhotosKitTests,HealthSafetyKitTests,NotificationsKitTests}/
```

`Package.swift` adds one library and test target per feature. `MetricsKit`, `SleepMoodKit`, `HealthChecksKit` and `ProgressPhotosKit` depend only on `CoreModels`, `DesignSystem` and, when needed, the dependency-neutral `HealthSafetyKit`; `NotificationsKit` owns notification value contracts and does not import a tracker feature. `PersistenceKit` depends on the feature protocol products to implement them. `project.yml` exposes the new products to the app and adds every package test target to the Local scheme. App composition maps tracker snapshots to Today/Progress/Notifications inputs.

App owns a lazily created `TrackerFeatureBundle`/factory. Bootstrap and first meaningful Today directive receive only the factory closure; repositories and tracker ViewModels are instantiated on the first tracker action or Progress route, cached, and then shared by Today and Progress. Tests prove ordinary launch does not invoke the factory and the first route invokes it once. This preserves the existing cold-launch architecture instead of growing `AppDependencies` eager work.

Static verifier fails on feature `import SwiftData|PersistenceKit|TrainingKit|UserNotifications|CloudKit` except the named system-adapter folders may import their Apple framework; it rejects photo binary properties in CoreModels/SwiftData, feature-to-feature view imports, reverse imports from TrainingKit, and missing package/project/scheme wiring. `HealthSafetyKit` contains only pure values/rules and imports no tracker or UI feature.

## 3. M3.1 — Shared quick-entry state and accessible form contract

**Subject:** `feat(trackers): add shared quick-entry contract`

**Files:** `Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/{QuickEntryMutationStateMachine,QuickEntryValidationIssue,QuickEntryFormScaffold}.swift`; `Packages/HealthTrackingModules/Sources/DesignSystem/Resources/Localizable.xcstrings`; `Packages/HealthTrackingModules/Tests/DesignSystemTests/{QuickEntryMutationStateMachineTests,QuickEntryLayoutContractTests}.swift`; `scripts/verify-trackers.sh`; `scripts/test-ios.sh`; `.github/workflows/ios.yml`.

**RED tests:** Add DesignSystem/value tests for immutable validation issue presentation and a pure mutation state machine: one-at-a-time save, duplicate-tap suppression, monotonically increasing generation token, stale completion rejection, externally owned input unchanged on failure, same-request retry, post-success undo token and failed-undo recovery. Add view-contract tests for 52 pt actions, AX5 vertical layout, explicit labels/hints, keyboard dismissal and Reduce Motion behavior. Add test-only `scripts/verify-trackers.sh`, wire its self-test and real pass into local/hosted static gates, and require its fixture to fail on a missing generation guard/52 pt action/keyboard identifier. During the test-only RED, the real verifier validates test and wiring presence without short-circuiting compilation on absent production symbols; the discovered `DesignSystemTests` then fail because the production types do not exist. GREEN tightens the verifier to require those production contracts and its self-test mutates each one.

**GREEN:** Add shared value/presentation contracts, a synchronous pure `QuickEntryMutationStateMachine`, and the visual scaffold to DesignSystem. The state machine owns only request ID/generation/save-state transitions; it never stores user input, calls a repository or erases an error. Domain validation, async repository work, preserved form input and retry/undo execution remain in each feature ViewModel. Introduce a separate generic async coordinator target only if at least two implemented trackers later need truly identical non-visual behavior. No repository type erasure that loses Sendable/typed failures. Undo token is feature-supplied and expires only by explicit next mutation/lifecycle policy.

**Frozen API shape:** `QuickEntryMutationStateMachine<UndoToken: Equatable & Sendable>` exposes immutable `QuickEntryMutationAttempt { requestID, generation, kind }` values. `beginSave(requestID:)`, `retrySave()`, `completeSave(_:undoToken:)`, `failSave(_:)`, `beginUndo(requestID:)`, `retryUndo()`, `completeUndo(_:)`, `failUndo(_:)` and `expireUndo()` are synchronous mutating operations. Every completion accepts only the current exact attempt; stale attempts return `false` without state change. Retry preserves the failed operation's request ID but receives a strictly newer generation. Starting an explicit new save or calling `expireUndo()` is the only way a successful undo token is discarded. `QuickEntryValidationIssue` is immutable and carries stable ID, optional field identifier, localized presentation text and accessibility announcement. The scaffold owns a scrollable content region, AX-size vertical action policy, 52 pt minimum action frame, interactive keyboard dismissal plus named keyboard action, and Reduce Motion-safe transition selection; callers own localized field labels/hints.

**Verification:** mutation self-test deletes generation guard/52 pt/keyboard identifier and must fail; app cold-launch threshold unchanged.

## 4. M3.2 — BodyMetric repository and single-screen entry

**Subject:** `feat(metrics): add body metric quick entry`

**Wiring:** Add the `MetricsKit` product/target/test target, add it as a `PersistenceKit` dependency, expose `MetricsKit` to the app target, and add `MetricsKitTests` to the Local scheme. App files introduce the lazy `TrackerFeatureBundle` factory, tracker sheet routing and Progress destination; TrainingKit receives only an app-action callback value. Composition tests assert zero factory calls during bootstrap/root creation and one cached call after the first tracker route.

**RED tests:** `MetricsRepository` CRUD and immutable newest-first snapshot ordering (`date` descending, `createdAt` descending, UUID string ascending); positive finite values; weight/waist canonical units; custom requires trimmed name + nonblank preserved unit; a batch containing every non-empty weight/waist/custom row saves atomically and never materializes a blank row as zero; edit updates `updatedAt`; duplicate IDs/generated-ID collision/invalid persisted rows fail closed; stale-write, batch/save/delete rollback, exact-ID not-found and no cross-record mutation; metric and imperial presentation conversions round-trip without changing stored canonical values. UI test enters weight and waist from one screen, retries a failed save with both inputs preserved, relaunches and edits/deletes from Progress.

**GREEN:** Add `MetricsKit`, input validator, snapshots, VM/view and `SwiftDataMetricsRepository`. Today/Progress routes use one composed instance. TrainingKit exposes only an app-action callback for the single tracker launcher; the app-owned quick-entry sheet and Progress hub compose actual feature views so TrainingKit never imports tracker modules. Persistence stores explicit unit and maps values only at boundary; unit-mode changes presentation, not historical records.

**Verification:** real in-memory SwiftData tests; no SwiftData in MetricsKit; Turkish catalog; light/dark/AX5 screenshot.

## 5. M3.3 — Same-local-day Sleep/Mood upsert

**Subject:** `feat(lifestyle): add sleep and mood entry`

**Wiring:** Add the `SleepMoodKit` product/target/test target, its `PersistenceKit` implementation dependency, app product dependency/composition and Local-scheme test entry. No MetricsKit import is allowed; App owns the combined quick-entry route.

**RED tests:** `LifestyleRepository` local-day fetch/upsert with injected calendar across DST; 0/1/>1 integrity behavior; daily sleep duration finite and in `(0, 24]`, quality 1...10; mood requires score 1...10 or at least one normalized nonblank tag, optional energy 1...10; stable tag de-dup/order; note trimming; atomic combined save rollback; stale save; edit same day rather than duplicate. UI completes both in one fast-entry screen and relaunches.

**GREEN:** Add `SleepMoodKit` snapshots/input/VM/view and SwiftData repository. One explicit save action atomically upserts every non-empty section; a failure rolls back both records and preserves both form inputs. The UI never reports or silently creates a partial success.

**Verification:** Istanbul/New York DST cases, duplicate integrity mutation, Today and Progress routing, accessibility order/screenshot.

## 6. M3.4 — Posture, symptom journal and Training event adapter

**Subject:** `feat(metrics): add posture and symptom tracking`

**Wiring:** Add dependency-neutral `HealthSafetyKit` product/target/test target with pure presentation inputs/results, expose its test target in the Local scheme, and add it to MetricsKit (and later HealthChecksKit) dependencies. App adds the product only where it directly supplies acknowledgement/safety values. TrainingKit adds only `SymptomEventClient` and event values. App injects the Metrics repository adapter and safety presentation. No tracker imports another tracker view.

**RED tests:** optional wall test; optional 0...10 symptom but at least one meaningful field; trimmed region/note; weekly quick-entry/history ordering; worsening comparison uses only explicit previous values and does not diagnose. Define a Training-owned `SymptomEventClient` value protocol and prove the OHP current-symptom path emits an event whose stable event ID is the workout-session UUID. App adapter idempotently upserts that ID into `MetricsRepository` without either module importing the other. Failure exposes a retryable journal state but never resumes the unsafe OHP action or logs health payload; restoring a symptom-present session re-emits the same event so a prior failure is recovered without a duplicate.

**GREEN:** Extend MetricsKit repository/VM/view, add Training protocol + no-op default, app composition adapter. L1 disclaimer always visible; L2 content only for OHP symptom, increasing symptom, or explicit cervical red-flag information and recommends stop/professional evaluation without diagnosis.

**Verification:** TrainingKit↔MetricsKit import scan, fake event tests, UI weekly entry/relaunch/AX5/dark/high contrast.

## 7. M3.5 — Health-check recurrence and due states

**Subject:** `feat(health): add recurring health checks`

**Wiring:** Add `HealthChecksKit` product/target/test target, its PersistenceKit implementation dependency, app composition and Local-scheme test entry. Today receives immutable due-summary values through App mapping; it does not gain a HealthChecksKit import.

**RED tests:** reminder CRUD/order; due/pending/done derivation; completing pending reminder and generating next pending reminder in one transaction; `.none` generates none; monthly/quarterly/yearly calendar arithmetic preserves local time and clamps an invalid target day to that target month's last valid day, then uses the resulting due date as the next recurrence anchor; leap day/year/DST; retry idempotence cannot generate two successors; duplicate successor integrity error; rollback keeps original pending. Seed Ferritin/D vitamin/general reminders remain idempotent.

**GREEN:** Add `HealthChecksKit` pure recurrence engine, snapshots/VM/list/detail and SwiftData repository. Repository is sole source of next due date; UI/planner never reimplement recurrence. The persistence adapter stores an opaque predecessor-ID→successor-ID link in `AppSetting` in the same save as status/successor changes; retry resolves that link instead of inferring identity from user-visible name/date, and delete cleans its owned metadata. This adds no model/schema version and carries no marker/value payload. Remove the unused legacy `TrainingRepository.fetchHealthCheckReminders()` API that returns mutable CoreModels objects; Today continues to receive its already-immutable `TodayRepositorySnapshot.Reminder` projection, while all health-check CRUD moves behind the new feature-owned snapshot protocol.

**Verification:** at least Istanbul and Los Angeles calendars; mutation removes transaction/idempotency and fails; Today due card + Progress history.

## 8. M3.6 — Bloodwork reference CRUD and permanent disclaimer

**Subject:** `feat(health): add bloodwork reference records`

**RED tests:** nonblank trimmed marker/unit, finite value (negative permitted unless requirement explicitly forbids), stable date/id ordering, CRUD rollback/not-found/stale completion. Every loading/content/empty/error/editor/detail context exposes exact mandatory Turkish disclaimer and no normal/abnormal classification, range, color-only medical status or advice. UI add/edit/delete/relaunch.

**GREEN:** Extend HealthChecksKit and persistence. A central immutable `MedicalDisclaimerPresentation` value from HealthSafetyKit ensures exact L1 text while each feature renders it in its own view; L0 acknowledgement uses app setting but never replaces L1.

**Verification:** source scan rejects diagnostic keywords/range comparisons; AX5/dark/high contrast; privacy scan.

## 9. M3.7 — Local photo asset lifecycle

**Subject:** `feat(photos): add local progress photo storage`

**Wiring:** Add `ProgressPhotosKit` product/target/test target, PersistenceKit implementation dependency, app product/composition and Local-scheme test entry. `PhotosUI`, `UIKit` and `ImageIO` imports are restricted to named platform adapter/view files. Do not add `NSPhotoLibraryUsageDescription` for the system picker.

**RED tests:** `PhotoAssetStore` accepts bytes/orientation metadata through an injectable decoder; rejects invalid/oversized/corrupt input; normalizes orientation/metadata, produces bounded full image + thumbnail, generated opaque asset ID, and Application Support relative layout; atomic temp-write+rename; file protection where supported; cleanup on metadata save failure; repository deletion + file deletion compensation; missing/corrupt fallback; repeated delete idempotent; no absolute path exposed or binary persisted. The system Photos picker never triggers a broad Photo Library permission request; cancelled/load-failed selection preserves input, and denied/limited broader PhotoKit access must not disable picker-based local import.

**GREEN:** Add ProgressPhotosKit domain/store protocol, Foundation/ImageIO local adapter (UIKit/PhotosUI confined to platform adapter/view), progress-photo repository and app composition. Byte/pixel ceilings, full-image dimension, thumbnail dimension and encoding quality are explicit injectable policy values with conservative production defaults; tests use tiny policies and never depend on device memory. `imageRef` stores opaque ID only. Personal photo files use iOS complete data protection where supported; protected-data-unavailable errors retain the operation for retry instead of weakening protection or deleting local metadata.

**Verification:** temp-directory integration tests with injected file manager/faults; CoreModels/schema binary scan; local-only works with cloud disabled; import/relaunch/delete UI.

## 10. M3.8 — Gallery and exactly-two compare

**Subject:** `feat(photos): add gallery and comparison`

**RED tests:** chronological order date→pose→UUID, safe thumbnail loading, missing/corrupt placeholder, selection state exactly 0/1/2, same asset not duplicated, deletion updates selection, compare requires exactly two, and a third distinct selection replaces the oldest selection while announcing the replacement. Compare always orders the pair chronologically (older then newer), independent of tap order. Accessible labels include date/pose but not filesystem info. UI imports fixtures, compares two, handles missing asset, deletes, relaunches.

**GREEN:** Add gallery/compare VM/views and Progress routing. Use lazy thumbnails; full images load only in compare. Delete requires confirmation and compensation state on partial file/repository failure.

**Verification:** memory/large-gallery fixture; light/dark/AX5/Reduce Motion/high contrast screenshots.

## 11. M3.9 — Manual private CKAsset adapter contract

**Subject:** `feat(photos): add private cloud asset adapter`

**RED tests:** protocol-faked private database + separate custom zone; deterministic record name from opaque asset ID; upload/download with temp CKAsset file cleanup; checksum/size validation; idempotent existing-record handling; retry classification and injected exponential backoff; account available/restricted/noAccount/temporary states; local preservation while unavailable; backfill of pending local assets; persisted opaque `CKServerChangeToken` pagination and token-expired reset; download rebuild; idempotent deletion cleanup queue; cancellation/generation guards; never claim success before server response. Upload temp files remain owned until the server operation finishes and are then removed by the adapter; downloaded staging assets are copied into the app container immediately because the system may reclaim their staged URLs.

**GREEN:** CloudKit adapter lives only in cloud-specific ProgressPhotosKit area/configuration; Local scheme can compile/run without a signed CloudKit session and uses local/no-op coordinator. The manual asset record contains only opaque asset ID, CKAsset binary, checksum and byte size—never date, pose, note, file path or tracker/health values. ProgressPhoto metadata remains on the SwiftData private-database path. Queue/token state uses non-health-payload identifiers and protocol storage. Entitlements/container identifiers are not changed merely to make simulator fakes pass.

**Verification:** exhaustive fake tests + Cloud scheme compile-only. Real upload/download/cross-device/account switch remain `NOT RUN` until signed real-device environment.

## 12. M3.10 — Medical safety L0/L1/L2

**Subject:** `feat(health): add medical safety layers`

**RED tests:** L0 shown once and persisted; dismissing/relaunching never hides L1; L1 exact disclaimer in posture/symptom/bloodwork/reminder contexts; L2 only for defined triggers and always contains stop + professional evaluation + cervical red-flag information where applicable; missing symptom answers fail closed; language contains no diagnosis. Accessibility focus moves to L2 heading and Reduce Motion avoids slide/scale.

**GREEN:** Complete the pure `MedicalSafetyPresentation` rule in dependency-neutral `HealthSafetyKit`; app supplies the acknowledgement setting store. MetricsKit and HealthChecksKit consume pure presentation values, never each other's views. L2 always says to stop the movement; it presents urgent-assessment information for new/significantly worsening limb weakness or numbness, loss of hand dexterity, balance/walking change, or bladder/bowel function change, and professional assessment for other persistent/worsening symptoms. It never labels the user with a condition.

**Frozen Turkish safety copy:** L1 is exactly “Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir.” General L2 begins “Hareketi durdur.” and says persistent or worsening symptoms should be assessed by a healthcare professional. Red-flag L2 says that new or significantly worsening arm/leg weakness or numbness, loss of hand dexterity, a balance/walking change, or a bladder/bowel-function change needs urgent medical assessment. It does not name a diagnosis, infer a condition, or provide a numeric medical threshold.

**Verification:** localization mutation and prohibited-language source scan; UI L0 once/L1 permanent/L2 triggered.

## 13. M3.11 — Health-check notification planning

**Subject:** `feat(notifications): schedule health check due dates`

**Wiring:** Add `NotificationsKit` product/target/test target, app dependency/composition and Local-scheme test entry. Only `SystemAdapter` imports UserNotifications. App maps `HealthCheckReminderSnapshot` to a notification-neutral descriptor, so NotificationsKit and HealthChecksKit remain independent. Launch reconciliation starts only after Today publishes its first meaningful directive and never requests permission; permission prompting is reachable solely from an explicit health-check UI action.

**RED tests:** planner maps repository due dates to stable notification IDs/content/routes; one pending request per reminder; overdue reminders reconcile both pending and delivered IDs so app relaunch cannot notify repeatedly; app launch/edit/complete/delete reschedules idempotently; completed/disabled removes pending and delivered requests; denied/notDetermined/authorized states preserve repository reminders; stale callbacks ignored; route decode rejects malformed/unknown IDs; no second recurrence calculation. Fake notification center verifies exact add/remove order and failure recovery. Identifier/userInfo contains only an opaque reminder ID and default lock-screen copy is generic—no health-check name, marker or value payload.

**GREEN:** Add NotificationsKit protocol/planner and UserNotifications adapter; HealthChecks repository snapshot is sole due-date input. Permission request occurs only from explicit user action.

**Verification:** simulator fake/integration; real delivery/permission behavior `NOT RUN` without device evidence.

## 14. M3.12 — Integration, accessibility, privacy and evidence

**Subject:** `test: add M3 tracker acceptance gates`

**RED:** acceptance/UI/verifier-only checkpoint must fail for a real missing integration/gate. Cover US6/US8, Today and Progress routes, all tracker persistence/relaunch, same-day edit, recurrence, notification fake, disk failure, PhotosPicker cancellation/load failure, broader PhotoKit denied/limited while the system picker remains usable, cloud unavailable/offline, CKAsset queue fake, local photo lifecycle, safety L0/L1/L2, dark/light default/XXL/AX3/AX5, Reduce Motion, high contrast, small phone and screenshot owner manifest.

**GREEN:** Compose all repositories/VMs behind the AppDependencies-owned lazy provider, replace Progress placeholders, add deterministic fixtures and final copy. Preserve Today launch ≤1.0 s by loading tracker summaries only after first meaningful directive unless a due reminder is already part of that directive.

**Evidence:** First obtain the accepted M3.12 implementation exact-SHA GREEN. Then use a separate evidence-gate test-only checkpoint that fails at the static gate because `docs/evidence/M3/acceptance.md` is absent; its successor adds the document and production verifier contract. The document records every RED/GREEN SHA/run, exact tests/artifacts/hashes, privacy scan, review, remote state, and explicit `NOT RUN/BLOCKED` device-only CloudKit/notification claims. It names the immutable accepted implementation SHA; the evidence-containing successor and later `main` merge are necessarily external records so the document does not pretend a commit contains its own SHA. Verifier self-tests delete and corrupt the evidence fixture fail-closed.

## 15. Final integration

1. Exact accepted M3 branch clean and equal to GitHub.
2. Preserve milestone branch; merge `--no-ff` into current remote-confirmed `main`.
3. Push `main`; exact merge SHA must pass all main/cold/small jobs and artifact review.
4. Bounded Gitea reconciliation; outage does not block GitHub/main or M4.
5. Only then branch `feat/m4-reports` and write/execute the detailed M4 plan.
