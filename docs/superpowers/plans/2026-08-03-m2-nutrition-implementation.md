# M2 Beslenme — Uygulama Planı

> **Yürütme kuralı:** Bu plan `feat/m2-nutrition` dalında, görev başına test-only RED → aynı commit amend ile GREEN → exact-SHA CI → review döngüsüyle uygulanır.

**Goal:** Food ve doğrudan makrolu Recipe kütüphanelerini, yerel gün temelli beslenme kaydını, donmuş makro snapshot'larını ve erişilebilir üç-dokunuş hızlı ekleme akışını uçtan uca teslim etmek.

**Architecture:** `NutritionKit` saf domain değerlerini, repository protokollerini, view model'leri ve SwiftUI akışlarını sahiplenir; `PersistenceKit` protokollerin SwiftData implementasyonunu sağlar; app target yalnız dependency composition, Today sunum adaptörü, routing ve deterministik UI-test fixture'larını kurar. `TrainingKit` ile `NutritionKit` birbirini import etmez.

**Tech Stack:** Swift 5.9, SwiftUI, Observation, SwiftData, XCTest, XCUITest, XcodeGen 2.46+, iOS 17+, GitHub Actions `macos-15` / Xcode 16.4.

**Binding references:**

- `Saglik-Takip-App-Gereksinim-Dokumani-v1.md`
- `docs/superpowers/specs/2026-08-03-health-tracking-app-design.md`
- `docs/superpowers/specs/2026-08-21-m2-nutrition-design.md`
- `docs/superpowers/plans/2026-08-03-health-tracking-app-roadmap.md`
- `docs/superpowers/plans/2026-08-03-m1-training-implementation.md`
- `docs/evidence/M1/acceptance.md`

**Base:** evidence-only successor `438d6da20f9412e7779bf703fab81f425e6b576b`; accepted M1.16 implementation exact SHA `f2f04725307c119d0fe6c4aa7aa9bc328f3b04e4` · GitHub Actions [32488207271](https://github.com/Fatihzxc/ios_app/actions/runs/32488207271).

---

## 1. Milestone-wide execution contract

### 1.1 Her M2.x görevi öncesi

1. Çalışma ağacının temiz olduğunu ve `git rev-parse HEAD` değerini kaydet.
2. Aktif dalın `feat/m2-nutrition` olduğunu doğrula.
3. Ulaşılabiliyorsa `origin` ve `gitea` branch uçlarını kısa zaman aşımıyla gözlemle.
4. Test-only commit GitHub'a itilene kadar o görevin production dosyalarına dokunma.
5. Daha sonraki bir M2 davranışını geniş testi erkenden yeşile çevirmek için önceki göreve taşıma.
6. `RecipeItem`, barkod, harici food veritabanı, HealthKit food import veya öneri motoru ekleme; bunlar kapsam dışıdır.

### 1.2 RED checkpoint

1. Yalnız test, test fixture ve testin derlenmesi için zorunlu minimum manifest/harness değişikliğini ekle.
2. Yeni `NutritionKitTests` target'ı production sembolü yokken derlenemiyorsa önce `Package.swift` sözleşme testiyle eksik target/dependency davranışını RED yap.
3. En dar yerel/static doğrulamayı çalıştır.
4. Görevin nihai subject'iyle provisional commit oluştur.
5. Provisional ucu GitHub'a ve erişilebilen Gitea'ya gönder.
6. Assert edilen eksik davranış yüzünden oluşan GitHub Actions failure'ı şarttır. Checkout, runner, billing, timeout, zero-test veya ilgisiz failure RED sayılmaz.
7. Run ID, job ID, URL, head SHA ve ayırt edici failure satırını commit dışında M2.8 kanıtı için kaydet.

### 1.3 GREEN checkpoint

1. Yalnız görevin testleriyle istenen davranışı ve zorunlu küçük refactor'u uygula.
2. Provisional commit'i amend et; aynı görev için ayrı implementation commit'i ekleme.
3. Önce focused testleri, sonra macOS/CI üzerinde `./scripts/test-ios.sh` tam hattını çalıştır.
4. Local Debug testleri, Local Release build, screenshot export sözleşmesi ve Cloud compile-only adımlarını ilgili görevde koru.
5. `git diff --check`, localization/requirements doğrulayıcıları ve görev özelindeki statik sınır taramalarını çalıştır.
6. Gereksinim kapsamı, mimari sınırlar, data integrity, timezone/DST, erişilebilirlik, localization, privacy ve test kalitesi review'u yap.
7. Doğrulanmış tüm Critical/Important bulguları önce testle göster, aynı commit'e amend ederek çöz.
8. Gözlemlenen provisional uç için exact `--force-with-lease` kullan.
9. Yalnız exact final SHA'nın GitHub Actions sonucu GREEN ise görevi kabul et.

### 1.4 Remote outage ve branch politikası

GitHub ve Gitea normalde her provisional ve accepted ucu alır. Kullanıcının bağlayıcı talimatına göre Gitea erişimi kesilirse kısa, sınırlı denemeden sonra yerel/GitHub hattı beklemeden ilerler. Her ertelenmiş gönderim için branch, beklenen eski uç ve yeni exact SHA kaydedilir; servis döndüğünde canlı uç okunmadan force push yapılmaz. M2.8 sonunda erişilemiyorsa durum dürüstçe kanıta yazılır; bu dış servis arızası sonraki milestone'u bloke etmez.

M2.8 exact tree kabul edilmeden `feat/m3-trackers` açılmaz. Milestone branch'leri M5 sonunda kullanıcı talimatına uygun biçimde `main` dalına birleştirilir; `main` push ve `main` CI ayrıca doğrulanır.

### 1.5 Review ve kanıt

- Kullanılabilirse Fable 5 medium review istenir; kullanılamıyorsa `NOT RUN` yazılır ve başka model bu adla sunulmaz.
- Review biçimi: Critical, Important, Minor, coverage, test quality, architecture, date/time correctness, accessibility/localization, security/privacy, verdict.
- `docs/evidence/M2/acceptance.md`, immutable git geçmişi ve Actions verilerinden M2.8'de oluşturulur.
- Kanıt tüm RED/GREEN çiftlerini, exact hash/run/job URL'lerini, test sayılarını, artifact bilgilerini, screenshot envanteri/hash'lerini, remote eşitliğini ve gerçek cihaz/Fable durumunu içerir.

---

## 2. Ortak mimari ve dosya düzeni

Beklenen production alanları:

```text
Packages/HealthTrackingModules/Sources/NutritionKit/
  Domain/
    NutritionMacros.swift
    NutritionInputs.swift
    NutritionValidation.swift
    NutritionDay.swift
  Repository/
    NutritionDayRepository.swift
    FoodRepository.swift
    RecipeRepository.swift
    MealEntryRepository.swift
  Snapshots/
    NutritionSnapshots.swift
  Day/
    NutritionDayView.swift
    NutritionDayViewModel.swift
  FoodLibrary/
    FoodLibraryView.swift
    FoodLibraryViewModel.swift
    FoodEditorView.swift
  RecipeLibrary/
    RecipeLibraryView.swift
    RecipeLibraryViewModel.swift
    RecipeEditorView.swift
  QuickAdd/
    NutritionQuickAddView.swift
    NutritionQuickAddViewModel.swift
  Resources/Localizable.xcstrings

Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/
  SwiftDataNutritionRepository.swift
  RecipeArchiveCodec.swift

Packages/HealthTrackingModules/Tests/NutritionKitTests/
Packages/HealthTrackingModules/Tests/PersistenceKitTests/
HealthTrackingAppTests/
HealthTrackingAppUITests/
docs/evidence/M2/
```

Dosya adları implementation sırasında küçük ölçüde sıkılaştırılabilir; sahiplik ve dependency yönü tasarım güncellenmeden değişemez.

### 2.1 Bağımlılık yönü

- `NutritionKit` → `CoreModels`, `DesignSystem`.
- `PersistenceKit` → mevcut bağımlılıklar + `NutritionKit`.
- App target → iki modülü compose eder.
- `NutritionKit` içinde `import SwiftData`, `ModelContext`, `@Query` veya `@Model` yoktur.
- `PersistenceKit` view/view-model içermez.
- `TrainingKit` ↔ `NutritionKit` doğrudan import yasaktır.

### 2.2 Sayısal sözleşme

- Domain hesapları `Decimal` ile yapılır; CoreModels'taki mevcut `Double` alanlar yalnız persistence giriş/çıkış sınırıdır.
- Her `Double` önce `isFinite` kontrolünden geçer; negatif makro, sıfır/negatif porsiyon ve zorunlu boş metin açık validation error üretir.
- Toplama/ölçekleme altı ondalık basamağa banker rounding (`.bankers`) ile normalize edilir.
- UI formatlaması domain değerini değiştirmez; görünür yuvarlama ile kaydedilen snapshot birbirinden ayrıdır.

### 2.3 Gün ve snapshot sözleşmesi

- Gün, enjekte edilen `Calendar` ile `dateInterval(of: .day, for:)` kullanılarak `[start, end)` aralığına normalize edilir; `86_400` saniye eklenmez.
- Sorgu 0 kayıtta oluşturur, 1 kayıtta döndürür, 2+ mantıksal eşleşmede integrity error üretir; sessizce rastgele kayıt seçmez.
- MealEntry bir ve yalnız bir kaynak biçimine sahiptir: recipe, food veya ad-hoc.
- Recipe/Food kaydında source ID ve o anda çözülmüş makrolar yazılır. Kaynak güncellenmesi/silinmesi/arşivlenmesi geçmiş snapshot'ı değiştirmez.
- Quantity düzenleme, güncel kaynağı tekrar okumaz; kaydın kendi başlangıç snapshot oranını ölçekler.

---

## 3. M2.1 — Nutrition repository contracts ve local day

**Final subject:** `feat(nutrition): add local-day repository contracts`

**Test files:**

- Add `Packages/HealthTrackingModules/Tests/NutritionKitTests/NutritionDayContractTests.swift`
- Add `Packages/HealthTrackingModules/Tests/PersistenceKitTests/NutritionDayRepositoryTests.swift`
- Extend `Packages/HealthTrackingModules/Tests/PersistenceKitTests/ModelContainerFactoryTests.swift`
- Add/extend manifest contract test as needed.

**Production files:**

- Modify `Packages/HealthTrackingModules/Package.swift`
- Modify `project.yml`
- Add `Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionDay.swift`
- Add `Packages/HealthTrackingModules/Sources/NutritionKit/Snapshots/NutritionSnapshots.swift`
- Add `Packages/HealthTrackingModules/Sources/NutritionKit/Repository/NutritionDayRepository.swift`
- Add `Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataNutritionRepository.swift`

### RED

Önce manifest/target sözleşmesini, ardından iki repository seviyesinde şunları kanıtla:

- `NutritionKitTests` target'ı Local scheme'de gerçekten çalışır; zero-test başarı kabul edilmez.
- Aynı yerel gün içindeki farklı saatler aynı normalize başlangıcını ve aynı log'u üretir.
- Ardışık günler, ay/yıl sınırı ve DST'nin 23/25 saatlik günleri ayrı log'lardır.
- Enjekte edilen Gregorian takvim ile en az iki timezone davranışı deterministiktir.
- 0 eşleşme atomik create+save, 1 eşleşme fetch, 2+ eşleşme explicit duplicate-day error verir.
- Create save failure rollback yapar; yarım DailyNutritionLog bırakmaz.
- Fetch sırası deterministiktir; `Date.now`, `Calendar.current` veya global locale saklı dependency değildir.
- Gün silme API'si ileride kullanılırsa nullify ilişki nedeniyle children'ı önce silme sözleşmesi test edilir; aksi halde public API eklenmez.

Expected RED: Nutrition target'ın CoreModels bağımlılığı/test target'ı ve repository türleri yoktur.

### GREEN

`NutritionDayKey`/eşdeğer immutable değerini ve küçük `NutritionDayRepository` protokolünü ekle. SwiftData implementasyonu predicate'te `[start, end)` kullanır, sonuç sayısını doğrular ve transaction failure'da rollback eder. Mevcut V2 schema model envanteri değişmez; yeni model/schema migration eklenmez.

### Verification

- Focused Nutrition day ve Persistence repository testleri.
- Manifestte `NutritionKitTests`; `project.yml` Local scheme test listesinde aynı target.
- `rg 'import SwiftData|ModelContext|@Query|@Model' Sources/NutritionKit` boş.
- `rg '86400|86_400|Calendar\.current|Date\.now'` yeni day/repository yolunda açıklamasız kullanım bulmaz.
- Full suite, Local Release ve Cloud compile-only.

---

## 4. M2.2 — Decimal-safe macro math ve hedef sunumu

**Final subject:** `feat(nutrition): add decimal macro calculations`

**Test files:**

- Add `Packages/HealthTrackingModules/Tests/NutritionKitTests/NutritionMacrosTests.swift`
- Add `Packages/HealthTrackingModules/Tests/NutritionKitTests/NutritionTargetPresentationTests.swift`
- Add persistence boundary cases to `NutritionDayRepositoryTests.swift`.

**Production files:**

- Add `Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionMacros.swift`
- Add `Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionValidation.swift`
- Extend `Packages/HealthTrackingModules/Sources/NutritionKit/Snapshots/NutritionSnapshots.swift`
- Extend `SwiftDataNutritionRepository.swift` only for boundary mapping.

### RED

Kanıtla:

- calories/protein/carb/fat ayrı Decimal alanlardır ve deterministic toplanır/çıkarılır/ölçeklenir.
- `0.1 + 0.2` gibi binary floating-point girdiler UI/domain toplamında sürüklenme üretmez.
- Altı ondalık banker rounding pozitif ara değerlerde ve tam yarım örneklerde sabittir.
- Negative, NaN, +∞ ve -∞ persistence boundary'de reddedilir; taşma sessizce sıfıra çevrilmez.
- Sıfır ya da negatif quantity/servings reddedilir.
- Protein hedefi pozitifse consumed/target/remaining/progress sunulur; hedef `nil`, sıfır, negatif veya nonfinite ise hedefsiz total sunulur.
- Opsiyonel calorie/carb/fat hedefleri her biri bağımsız hedefli ya da hedefsiz olabilir.
- Hedef aşımı progress'i veri olarak korur; UI bar clamp'i hesap değerini kaybetmez.
- Boş gün tam sıfır totals üretir.

Expected RED: macro domain ve target presentation türleri yoktur.

### GREEN

Validated `NutritionMacros`, quantity/target değerleri ve hedef sunum tiplerini ekle. Double dönüşümlerini tek bir boundary mapper'da topla. Validation error'ları kullanıcı metni değil stabil semantic case'ler olsun.

### Verification

- Focused macro/target tests.
- Property-style tablo testleri: identity, associativity'nin normalize edilmiş beklentisi, ölçeklemede zero/one ve round-trip sınırı.
- Statik scan production NutritionKit hesap yolunda doğrudan `Double` arithmetic kalmadığını doğrular.
- Full suite.

---

## 5. M2.3 — User-created Food library

**Final subject:** `feat(nutrition): add food library`

**Test files:**

- Add `Packages/HealthTrackingModules/Tests/NutritionKitTests/FoodInputTests.swift`
- Add `Packages/HealthTrackingModules/Tests/NutritionKitTests/FoodLibraryViewModelTests.swift`
- Add `Packages/HealthTrackingModules/Tests/PersistenceKitTests/FoodRepositoryTests.swift`
- Add targeted app composition tests if routing is introduced.

**Production files:**

- Add `Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionInputs.swift`
- Add `Packages/HealthTrackingModules/Sources/NutritionKit/Repository/FoodRepository.swift`
- Add `Packages/HealthTrackingModules/Sources/NutritionKit/FoodLibrary/FoodLibraryViewModel.swift`
- Add `Packages/HealthTrackingModules/Sources/NutritionKit/FoodLibrary/FoodLibraryView.swift`
- Add `Packages/HealthTrackingModules/Sources/NutritionKit/FoodLibrary/FoodEditorView.swift`
- Extend `SwiftDataNutritionRepository.swift`
- Extend `NutritionKit/Resources/Localizable.xcstrings`

### RED

Kanıtla:

- Name ve serving unit Unicode whitespace trim sonrası boş olamaz; brand/fiber opsiyoneldir.
- Serving size pozitif ve finite; tüm macro/fiber değerleri finite ve nonnegative'dir.
- Create input'tan `source == .userCreated`, stabil ID ve doğru timestamps ile snapshot döner.
- Yalnız user-created Food düzenlenir/silinir; HealthKit kaynak için explicit immutable-source error vardır.
- Update `createdAt`/ID/source'u korur, `updatedAt`'i enjekte edilen clock ile değiştirir.
- Delete referenced/unreferenced durumda MealEntry snapshot geçmişini etkilemez.
- Save failure create/update/delete işlemlerini rollback eder.
- Arama name ve brand üzerinde case/diacritic insensitive'dir; whitespace query tüm listeye eşittir.
- Sıra normalized name, brand, UUID tie-break ile deterministiktir.
- View model loading/content/empty/search-empty/error/save-error durumlarını ayırır; başarısız mutation doğrulanmış önceki listeyi kaybetmez.

Expected RED: Food repository/input/view-model API'leri yoktur.

### GREEN

Food snapshot/input mapper, dar repository protokolü, SwiftData implementasyonu ve library/editor UI ekle. Form label/error/action metinlerini String Catalog'a koy. View/view-model sınırına yalnız snapshot geçsin.

### Verification

- Food input, repository ve view-model focused tests.
- VoiceOver labels/values/hints; 44pt minimum controls; Dynamic Type layout review.
- Lokalizasyon doğrulayıcı ve `git diff --check`.
- Full suite.

---

## 6. M2.4 — Direct-macro Recipe library ve arşiv

**Final subject:** `feat(nutrition): add direct macro recipes`

**Test files:**

- Add `Packages/HealthTrackingModules/Tests/NutritionKitTests/RecipeInputTests.swift`
- Add `Packages/HealthTrackingModules/Tests/NutritionKitTests/RecipeLibraryViewModelTests.swift`
- Add `Packages/HealthTrackingModules/Tests/PersistenceKitTests/RecipeRepositoryTests.swift`
- Add `Packages/HealthTrackingModules/Tests/PersistenceKitTests/RecipeArchiveCodecTests.swift`

**Production files:**

- Add `Packages/HealthTrackingModules/Sources/NutritionKit/Repository/RecipeRepository.swift`
- Add `Packages/HealthTrackingModules/Sources/NutritionKit/RecipeLibrary/RecipeLibraryViewModel.swift`
- Add `Packages/HealthTrackingModules/Sources/NutritionKit/RecipeLibrary/RecipeLibraryView.swift`
- Add `Packages/HealthTrackingModules/Sources/NutritionKit/RecipeLibrary/RecipeEditorView.swift`
- Add `Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/RecipeArchiveCodec.swift`
- Extend `SwiftDataNutritionRepository.swift`
- Extend Nutrition localization catalog.

### RED

Kanıtla:

- Direct Recipe name dolu, servings pozitif/finite ve toplam makrolar finite/nonnegative olmalıdır.
- MVP create her zaman `isDirectMacros == true`; RecipeItem/composed yol üretmez.
- Standard kategori customName kabul etmez; custom kategori trim edilmiş dolu ad ister.
- Recipe toplamı bütün yield içindir; bir consumed serving `totals / recipe.servings` sonucunu verir.
- Search, kategori filtresi ve name/category/UUID sırası deterministiktir.
- Update ID/createdAt'i korur ve geçmiş MealEntry snapshot'larını değiştirmez.
- Referanssız delete hard delete yapar.
- En az bir MealEntry tarafından referanslanan delete recipe'yi arşivler, aktif library/quick-add'dan çıkarır ama source record'u korur.
- Restore arşivi kaldırır ve recipe'yi tekrar aktif listeler.
- Arşiv payload'ı `AppSetting.key == "nutrition.recipe.archive"` altında versioned, canonical JSON ve sıralı benzersiz UUID listesi kullanır.
- Eksik setting boş arşivdir; malformed/unsupported payload explicit corruption error'dır, sessiz reset yapılmaz.
- Duplicate AppSetting key integrity error'dır.
- Archive/delete/restore save failure atomik rollback yapar.

Expected RED: Recipe ve archive API'leri yoktur.

### GREEN

Recipe input/snapshot/repository/UI'ını uygula. Frozen CoreModels schema'yı değiştirme; `isArchived` alanı eklemek yerine strict AppSetting codec kullan. UI aktif ve arşivli öğünleri açıkça ayırsın, restore erişilebilir olsun.

### Verification

- Recipe input/repository/archive codec/view-model focused tests.
- Schema V2 model sayısı ve migration testleri unchanged.
- `RecipeItem`/barcode/network/HealthKit-food implementation'ı olmadığı static review ile doğrulanır.
- Full suite.

---

## 7. M2.5 — MealEntry immutable snapshot işlemleri

**Final subject:** `feat(nutrition): add immutable meal snapshots`

**Test files:**

- Add `Packages/HealthTrackingModules/Tests/NutritionKitTests/MealEntryResolutionTests.swift`
- Add `Packages/HealthTrackingModules/Tests/PersistenceKitTests/MealEntryRepositoryTests.swift`
- Extend day/macro contract tests.

**Production files:**

- Add `Packages/HealthTrackingModules/Sources/NutritionKit/Repository/MealEntryRepository.swift`
- Extend nutrition inputs, snapshots and macro resolver.
- Extend `SwiftDataNutritionRepository.swift`.

### RED

Her üç source biçimini ve mutation'ı kanıtla:

- Recipe create: recipeId var, foodId/adhocName yok; resolved macro = full totals × consumed quantity / recipe.servings.
- Food create: foodId var, recipeId/adhocName yok; resolved macro = per-serving macros × quantity.
- Ad-hoc create: yalnız trimmed adhocName var; girilen makrolar verilen quantity için nihai consumed total olarak snapshot edilir, ilk create'te tekrar ölçeklenmez.
- Zero/multiple source, missing source, archived recipe, immutable/nonexistent Food ve invalid category/quantity/macro açık error üretir.
- Log date selected local day'i belirler; `loggedAt` gün içindeki event zamanıdır ve gün kimliği yerine kullanılmaz.
- Insert day yoksa aynı transaction'da fetch-or-create + entry save yapar.
- Kaynak create sonrasında update/delete/archive edilince geçmiş entry ID/quantity/resolved macro değişmez.
- Quantity edit source'u yeniden okumadan entry'nin kendi snapshot-per-unit oranını ölçekler; ad-hoc da aynı kurala uyar.
- Category edit yalnız kategori/timestamp'i değiştirir; source/macro aynı kalır.
- Delete totals'i anında azaltır; son entry silinince gün log'unu otomatik silmek veya korumak seçimi testte sabitlenir (tasarım tercihi: boş gün log'u korunur).
- Cross-day move public API değilse yoktur; varsa source transaction bütünlüğü açık test edilir.
- Duplicate confirm aynı request ID için tek entry üretir; save failure hiçbir yarım day/entry bırakmaz.

Expected RED: meal entry request/resolution/repository API'leri yoktur.

### GREEN

Validated request enum'u ile compile-time source ayrımını kur; persistence katmanı yine runtime invariant'i doğrulasın. Entry snapshot'larını deterministic order (`loggedAt`, `createdAt`, UUID) ile döndür. Totals her repository sonucunda immutable entries üzerinden hesaplanır.

### Verification

- Üç source ailesi, edit/delete, rollback ve historical immutability focused tests.
- Persistence model erişimi yalnız PersistenceKit'te.
- Decimal calculation yolu ve Double boundary tekrar taranır.
- Full suite.

---

## 8. M2.6 — Daily calendar/day UI

**Final subject:** `feat(nutrition): add daily nutrition view`

**Test files:**

- Add `Packages/HealthTrackingModules/Tests/NutritionKitTests/NutritionDayViewModelTests.swift`
- Add `HealthTrackingAppTests/NutritionCompositionTests.swift`
- Add `HealthTrackingAppUITests/NutritionDayUITests.swift`
- Extend screenshot export contract in `.github/workflows/ios.yml`.

**Production files:**

- Add `NutritionKit/Day/NutritionDayViewModel.swift`
- Add `NutritionKit/Day/NutritionDayView.swift`
- Modify `NutritionFoundationView.swift`
- Modify `App/Application/AppDependencies.swift`
- Modify `App/Application/AppRootView.swift` only as needed for injected root/routing.
- Modify `App/Support/AppUITestLaunchConfiguration.swift` and deterministic fixture installer.
- Extend localization/requirements verification scripts as appropriate.

### RED

View-model ve UI contract'larında şunları kanıtla:

- Initial load selected local today; previous/next day calendar component ile ilerler, sabit saniye kullanmaz.
- Date picker seçimi aynı normalize-day yoluna gider.
- Loading, loaded-empty, loaded-content ve recoverable error farklı durumlardır; retry aynı günü yükler.
- Dört standard kategori her zaman stabil sıradadır; custom kategoriler localized standard'lardan sonra deterministic sıralanır.
- Her kategori subtotal ve day total entry mutation sonrası repository cevabından anında yenilenir.
- Protein hedefi ve mevcut opsiyonel hedefler bar/remaining ile; hedefsiz macro yalnız total ile gösterilir.
- Delete failure optimistic görünümü rollback eder ve kullanıcıya retry edilebilir hata verir.
- Date/navigation düğmeleri semantic labels, values, hints ve minimum hit target taşır.
- VoiceOver reading order: date/header → day total → categories → entries/actions.
- Light/dark, XXL/AX5, reduce motion ve increase contrast senaryoları için deterministik screenshot attachment'ları oluşur.

Expected RED: nutrition root placeholder'dır ve day view/view-model yoktur.

### GREEN

Day view model ve UI'ı immutable presentation modelleriyle kur. Büyük Dynamic Type'ta yatay sıkışan makro satırlarını dikey/scroll uyumlu hale getir. Boş/error state için DesignSystem bileşenlerini kullan. AppDependencies repository ve view model'i compose etsin; view ModelContext görmesin.

### Verification

- NutritionKit day view-model ve app composition tests.
- XCUITest: date navigation, empty/content/error/retry, totals and delete.
- Screenshot export exact-name/owner set contract.
- Light/dark/AX5 görsel inceleme; text clipping ve off-screen primary action yok.
- Full suite.

---

## 9. M2.7 — Frequent recipe, optimistic üç-dokunuş ve Today

**Final subject:** `feat(nutrition): add three tap quick meal`

**Test files:**

- Add `Packages/HealthTrackingModules/Tests/NutritionKitTests/QuickAddViewModelTests.swift`
- Add `Packages/HealthTrackingModules/Tests/NutritionKitTests/MealCategorySuggestionTests.swift`
- Extend recipe repository usage-ranking tests.
- Add `HealthTrackingAppTests/TodayNutritionCompositionTests.swift`
- Add `HealthTrackingAppUITests/NutritionQuickAddUITests.swift`
- Extend Today UI tests for navigation only where ownership requires.

**Production files:**

- Add `NutritionKit/QuickAdd/NutritionQuickAddViewModel.swift`
- Add `NutritionKit/QuickAdd/NutritionQuickAddView.swift`
- Add category suggestion/ranking domain helpers.
- Extend repository usage query and day view route.
- Modify app composition/Today presentation bridge without cross-module imports.
- Extend UI-test fixtures, localization and screenshot contract.

### RED

Kanıtla:

- Local hour 05...10 breakfast, 11...15 lunch, 16...21 dinner, diğer saatler snack önerir; Calendar/timezone enjekte edilir.
- Kullanıcının seçtiği kategori saat önerisini override eder ve confirm boyunca korunur.
- Active recipes usage count descending, most-recent-use descending, normalized name ve UUID tie-break sırasındadır.
- Arşivli recipe görünmez; hiç kullanım yoksa name/UUID sırası deterministiktir.
- Kabul akışı tam üç kullanıcı dokunuşudur: kategori `+` (1), recipe seç (2), varsayılan 1.0 porsiyonu onayla (3).
- Confirm sırasında optimistic entry ve totals hemen görünür; repository success gerçek snapshot'la reconcile eder.
- Aynı confirm'in çift tetiklenmesi request ID ile tek insert'tir.
- Failure optimistic entry/totals'i tamamen rollback eder, seçim/context'i korur ve erişilebilir hata + retry sunar.
- Quantity değiştirme opsiyonu kabul yolunu bozmaz; varsayılan 1.0 için ek dokunuş zorunlu değildir.
- Today beslenme özeti loaded/empty/error durumunda M1 workout direktifini geciktirmez veya değiştirmez.
- Today “Öğün ekle” app-owned route ile seçili bugünün Nutrition quick-add ekranına gider; modüller birbirini import etmez.
- VoiceOver kullanıcı category/recipe/macro/quantity/confirm sonucunu anlaşılır biçimde duyabilir.

Expected RED: quick-add coordinator/ranking/category inference ve Today nutrition bridge yoktur.

### GREEN

Quick-add view model'i request-ID tabanlı optimistic state machine olarak uygula. Usage ranking'i geçmiş MealEntry source ID'lerinden türet; gizli mutable sayaç veya schema alanı ekleme. App target, Nutrition özetini küçük app-owned/Training'in zaten kabul ettiği presentation değerine map etsin; launch-directive critical path'i nutrition fetch beklemesin.

### Verification

- Quick-add/category/ranking focused tests.
- UI test üç dokunuşu explicit activity/step count ile kanıtlar; sonra total ve relaunch persistence kontrol edilir.
- VoiceOver smoke, AX5 ve dark screenshot'ları inspect edilir.
- Import-boundary statik scan.
- Full suite ve cold-launch regression karşılaştırması.

---

## 10. M2.8 — US4/US5 audit, relaunch ve evidence

**Final subject:** `test: add M2 nutrition acceptance gates`

**Test files:**

- Add `HealthTrackingAppUITests/M2AcceptanceUITests.swift`
- Add/extend `HealthTrackingAppUITests/NutritionAccessibilityUITests.swift`
- Add any narrowly missing Nutrition/Persistence contract tests discovered by audit.

**Production/verification files:**

- Add `scripts/verify-nutrition.sh` with mutation-tested self-test mode.
- Modify `scripts/test-ios.sh` and `.github/workflows/ios.yml` to run the verifier.
- Extend screenshot export expected/owner sets.
- Add `docs/evidence/M2/acceptance.md` only after exact GREEN data is available.

### RED

Önce yalnız acceptance tests/verifier contract'ını commit et ve şu eksik/bağlayıcı milestone davranışlarından kaynaklanan gerçek RED'i elde et:

- US4: recipe create/edit/archive/restore ve historical immutability.
- US5: selected local today'de ≤3 tap saved breakfast, immediate total, relaunch persistence.
- DST/timezone boundary: aynı instant farklı local day veya aynı local day farklı saat senaryosu.
- Food, recipe ve ad-hoc entries toplamda birlikte doğru çalışır.
- Targeted/untargeted macro presentation.
- VoiceOver, AX5, dark, reduce motion ve increase contrast.
- `verify-nutrition.sh --self-test` kasıtlı mutation'ları reddeder; gerçek tree gerekli sembol/test/scheme/workflow/screenshot/localization sözleşmelerini sağlar.

Acceptance testi gerçekten mevcut tree zaten tüm davranışı sağlıyorsa, milestone verifier'daki yeni eksik bağlayıcı gate RED sebebi olabilir. Yapay `XCTFail` veya production dışı geçici failure kabul edilmez.

### GREEN

Audit'in gösterdiği yalnız eksik production/gate düzeltmelerini aynı commit'e amend et. `verify-nutrition.sh`:

- M2 test target/scheme wiring'ini,
- repository/day/macro/snapshot/quick-add contract isimlerini,
- SwiftData ve cross-module import sınırlarını,
- local-day yolunda sabit saniye/global Calendar kullanımının olmamasını,
- screenshot canonical set/owner eşleşmesini,
- localized accessibility/action metinlerini,
- M2 evidence şablonunun exact SHA alanlarını

doğrulasın ve self-test mutation'ları olmadan güvenilir sayılmasın.

### Final exact-tree review

1. Bütün M2.1–M2.8 commit subject/hash sırasını ve her RED/GREEN Actions çiftini doğrula.
2. Full test suite, Local Release, Cloud compile-only, fresh clone bootstrap ve hygiene GREEN olmalı.
3. Artifact'tan gerçek test counts ve screenshot dosyalarını çıkar; canonical set eksiksiz/benzersiz olmalı.
4. Tüm yeni M2 screenshot'larını görsel olarak incele; en az normal light/dark, AX5, error, empty, three-tap sonrası totals.
5. Cold launch median M1 baseline ile karşılaştır; Today workout cevabının 1 saniye bütçesini koruduğunu kanıtla.
6. Secret/PII/log taraması yap; beslenme adları/makroları telemetry veya console'a yazılmamalı.
7. Critical/Important review bulgusu sıfır olana kadar test-first düzeltip exact CI'yı tekrarla.
8. Accepted exact SHA ve remote uçlarını kontrol et; Gitea erişilemiyorsa sınırlı deneme ve ertelenmiş senkron bilgisini dürüstçe kaydet.
9. `docs/evidence/M2/acceptance.md` son kanıt verileriyle amend edilir; evidence içeren exact SHA için son CI GREEN olmadan milestone kabul edilmez.

### M2 acceptance checklist

- [ ] US4 direct-macro recipe workflow çalışır.
- [ ] US5 saved breakfast seçili bugüne en fazla üç dokunuşta eklenir.
- [ ] Gün toplamı UI'da anlık değişir ve relaunch sonrası aynıdır.
- [ ] Source değişikliği/silinmesi/arşivi geçmiş snapshot'ı bozmaz.
- [ ] Aynı local day için tam bir mantıksal DailyNutritionLog vardır; duplicate data explicit error'dır.
- [ ] DST/timezone testleri ve day navigation geçer.
- [ ] Hedefli/hedefsiz bütün makrolar doğru sunulur.
- [ ] Food/Recipe/ad-hoc CRUD validation ve rollback testleri geçer.
- [ ] VoiceOver/Dynamic Type/dark/contrast/motion kanıtları incelenmiştir.
- [ ] NutritionKit'te SwiftData ve TrainingKit↔NutritionKit import'u yoktur.
- [ ] Full CI ve evidence exact final SHA ile eşleşir.

---

## 11. Commit ve CI sırası

Plan belgeleri M1 accepted SHA'dan açılan `feat/m2-nutrition` dalındaki ilk commit'tir:

1. `docs: define M2 nutrition execution`
2. `feat(nutrition): add local-day repository contracts`
3. `feat(nutrition): add decimal macro calculations`
4. `feat(nutrition): add food library`
5. `feat(nutrition): add direct macro recipes`
6. `feat(nutrition): add immutable meal snapshots`
7. `feat(nutrition): add daily nutrition view`
8. `feat(nutrition): add three tap quick meal`
9. `test: add M2 nutrition acceptance gates`

Her feature commit önce test-only provisional biçimde aynı subject'le kırmızıya gider, sonra implementation aynı commit'e amend edilir. Kanıt dokümanı yalnız son task'ta gerçek immutable run/artifact verisiyle oluşturulur; tahmini test sayısı veya uydurma cihaz sonucu yazılmaz.

---

## 12. Handoff koşulu

M2 tamamlanmış sayılmak için `feat/m2-nutrition` exact tip'i:

- yukarıdaki kabul checklist'inin tamamını,
- sıfır Critical/Important review bulgusunu,
- GitHub Actions GREEN sonucunu,
- canonical artifact/screenshot ve test-count kanıtını,
- temiz çalışma ağacını

sağlamalıdır. Bu koşullar sağlandığında exact accepted tipten `feat/m3-trackers` açılır. Gitea erişimsizliği kaydedilir ama kullanıcı talimatına göre ilerleme durmaz. Bütün feature branch'lerin `main`e nihai merge'i ve `main` CI doğrulaması M5 kapanışında yapılır.
