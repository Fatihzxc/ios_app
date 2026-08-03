# Sağlık & Antrenman Takip Uygulaması — Gereksinim Dokümanı (v1)

> **Bu doküman kimin için:** Claude Code + Opus'un bu iOS uygulamasını **sıfırdan, aşama aşama** inşa etmesi için yazılmış, uygulanmaya hazır bir ürün + teknik spesifikasyondur.
> **Dil notu:** Açıklamalar Türkçe; tüm kod-seviyesi tanımlar (entity, alan, ekran adları) İngilizcedir. Kullanıcı kodu bir "kara kutu" olarak görür; bu dokümanı onaylar, kodu değil.

---

## 0. Opus için çalışma talimatı (önce oku)

1. **Aşamalı ilerle.** Bölüm 14'teki milestone planına birebir uy. Her milestone sonunda **derlenip çalışan** bir Xcode projesi bırak; kullanıcı her aşamayı simülatörde/telefonda görebilmeli.
2. **Mimariyi modüler tut** (Bölüm 5). Her tracker (antrenman, beslenme, uyku…) kendi modülü/paketi olsun. Bugün tek kullanıcılı yerel bir uygulama; yarın çok kullanıcılı ücretli ürün olacak — veri erişimini **Repository protokolü** arkasına al ki ileride yerel yerine uzak backend takılabilsin.
3. **Belirsizlik olursa dur ve sor.** Bu doküman varsayımları Bölüm 2'de açıkça listeliyor; bunların dışında bir boşluk görürsen uydurma, kullanıcıya sor.
4. **Seed verisi zorunlu** (Bölüm 10). Uygulama boş açılmamalı; kullanıcının mevcut programı ve 12 aylık yol haritası gömülü gelmeli ki "Bugün ne yapmalıyım?" ekranı ilk günden anlamlı olsun.
5. **Kabul kriterleri** her milestone'un sonunda (Bölüm 14) ve genelde (Bölüm 15) tanımlı. Bir milestone, kriterleri geçmeden "bitti" sayılmaz.
6. **Kurulum adımlarını** (Bölüm 16) README olarak da projeye koy; kullanıcı Swift bilmiyor, projeyi açıp çalıştırmayı elinden tutarak anlat.

---

## 1. Ürün özeti & vizyon

Kişisel bir **sağlık, antrenman ve beslenme takip uygulaması**. Ayırt edici özelliği bir "kayıt defteri" olmaktan öte, kullanıcıya **ne zaman ne yapması gerektiğini açık ve seçik söyleyen** rehber-odaklı bir yapı olması: bugünün seansı, içinde bulunulan faz, önerilen bir sonraki ağırlık, deload zamanı, yaklaşan kan tahlili gibi şeyleri kullanıcı düşünmeden önüne koyar.

- **v1 (bu doküman):** Tek kullanıcı (uygulama sahibi + yakın çevre), iPhone-only, yerel veri + kullanıcının kendi iCloud'u. Hesap/backend yok.
- **Gelecek (ürünleşme):** Çok kullanıcılı, ücretli (abonelik), hesap sistemi + backend. v1 mimarisi bunu **engellememeli** (Bölüm 13). Ama bu özellikler v1'de **inşa edilmez**, sadece mimaride yer bırakılır.

**Rehberlik vaadi (ürünün kalbi):** Kullanıcı uygulamayı açtığında ilk gördüğü şey "Bugün ne yapmalıyım?" sorusunun net cevabıdır — tahmin ettirmez, söyler.

---

## 2. Benim adıma verilen kararlar (hepsi değiştirilebilir)

Kullanıcı bu uygulamayı bir "kara kutu" olarak istediği için tüm teknik/ürün kararlarını burada **açıkça** veriyorum. Her biri tek satırla geri çevrilebilir; kullanıcı "şunu değiştir" derse Opus ilgili bölümü günceller. Gizli varsayım yok.

| # | Karar | Gerekçe | Değiştirmek istersen |
|---|-------|---------|----------------------|
| D1 | **Native SwiftUI** (çapraz-platform değil) | iPhone-only + HealthKit + App Store + kara-kutu bakım için en temiz ve en az sürtünmeli yol | Android da istenirse React Native/Flutter'a geçilir (büyük değişiklik) |
| D2 | **SwiftData** (persistence) + **CloudKit** (kullanıcının özel iCloud'unda yedek/senkron) | Modern, sade, agent'ın rahat üreteceği yerel depolama; veri üçüncü sunucuya gitmez | Daha geniş iOS uyumu istenirse Core Data |
| D3 | **Minimum iOS 17** | SwiftData ve Swift Charts bunu gerektirir | iOS 16 desteklenecekse Core Data + farklı grafik kütüphanesi |
| D4 | **HealthKit = opsiyonel** (v1.1): kilo, uyku, adım, aktif enerji **okuma**; antrenman **yazma** opsiyonel | Manuel giriş azalır ama v1 çekirdeği buna bağlı değil | İstenmezse tamamen çıkarılır |
| D5 | **v1'de hesap/backend YOK**; yerel + özel iCloud. Çok kullanıcı/ücret ileride | Kişisel v1'i hızlı ve basit tutar; mimari geleceğe hazır | Baştan backend istenirse kapsam ~2x büyür |
| D6 | Uygulama **mevcut programımızla seed'lenir** (Gün A/B/C + ısınma/soğuma + 12 aylık 4 faz + hedeflerin) | "Bugün ne yapmalıyım?" ilk günden çalışsın | Boş başlasın istenirse seed kaldırılır |
| D7 | Notion **canlı senkron edilmez**; program/roadmap bir kez seed olarak alınır, Notion arşiv/başvuru kalır | v1'de Notion API entegrasyonu gereksiz karmaşa | İki yönlü Notion senkronu istenirse ayrı bir entegrasyon işi |
| D8 | Beslenme **MyFitnessPal tarzı**: SavedMeal'lar doğrudan makro girilerek (MVP), opsiyonel olarak Food'lardan bileştirerek (sonra) | Kullanıcının tarif dediği "besin değerine kadar girilmiş öğün" en hızlı böyle çözülür | Barkod/harici besin veritabanı istenirse ileride eklenir |
| D9 | **Bildirim/hatırlatma dahil** (seans, ölçüm, tahlil zamanı) | "Ne zaman" vaadi bildirim ister | İstenmezse kapatılır |
| D10 | **Rehber motoru** çift-progresyon + faz + deload mantığını içerir (Bölüm 9) | Ürünün asıl değeri; Notion'daki mantığın koda dökülmüş hali | Sadece kayıt defteri istenirse motor çıkarılır (değer düşer) |
| D11 | **MVP dilimi** = Bugün ekranı + antrenman kaydı önce; beslenme sonra (Bölüm 14) | En hızlı "çalışır ve değerli" kesit | Farklı öncelik istenirse milestone sırası değişir |
| D12 | **Doküman dili** Türkçe düzyazı + İngilizce kod tanımları | Kullanıcı Türkçe okuyup onaylıyor, kod standart İngilizce | Tam İngilizce spec istenirse çevrilir |

---

## 3. Hedef kullanıcı & kullanım senaryoları

**v1 kullanıcısı:** 29, 185 cm, ~98 kg → hedef ~90 kg; recomposition + postür düzeltme; boyun (servikal) geçmişi nedeniyle bazı hareketlerde güvenlik durakları var. Teknik açıdan sofistike ama uygulamayı basit ve yönlendirici istiyor. Yakın çevre de benzer amatör-ama-ciddi kullanıcılar.

**Ürünleşme kullanıcısı (ileride):** Antrenman + beslenmesini tek yerde, kendisine ne yapacağını söyleyen bir uygulamayla takip etmek isteyen genel kullanıcı.

**Temel senaryolar (user stories):**
- *US1 — Bugün:* "Uygulamayı açıyorum; bugün Gün B olduğunu, hangi fazda olduğumu, her hareket için önerilen ağırlığı görüyorum."
- *US2 — Seans:* "Seansı başlatıyorum; ısınma → hareketler (set/tekrar/RIR + güvenlik ipuçları) → soğuma akışını takip edip her seti tek dokunuşla kaydediyorum."
- *US3 — İlerleme önerisi:* "Bir hareketin tüm setlerinde hedef tekrara ulaştım; bir sonraki seansta uygulama bana +2.5 kg öneriyor."
- *US4 — Beslenme (tarif):* "Kahvaltı kategorisine sık yaptığım 3-5 öğünü besin değerine kadar bir kez kaydediyorum."
- *US5 — Günlük öğün:* "Bugünün gününü açıyorum; kahvaltıya kayıtlı tarifimi hızlıca seçip ekliyorum; günün makro toplamını hedefime karşı görüyorum."
- *US6 — Metrik & foto:* "Haftalık kilo/bel giriyorum, aylık ilerleme fotoğrafı yüklüyorum."
- *US7 — Rapor:* "İlerleme sekmesinde kilo, bel, güç ve beslenme uyumumu grafiklerle görüyor, rapor/çıktı alıyorum."
- *US8 — Uyku/ruh hali/tahlil:* "Uyku süresi+kalite, ruh hali giriyorum; ferritin/D tahlili için hatırlatma alıyorum."
- *US9 — Deload/faz:* "5. hafta geldiğinde uygulama deload öneriyor; faz geçiş kriteri oluşunca beni uyarıyor."

---

## 4. Kapsam

### v1 kapsamında (IN)
- Antrenman modülü: program (Gün A/B/C), günün seansı, set kaydı (ağırlık/tekrar/RIR), ısınma & soğuma akışı, güvenlik durakları, seans geçmişi.
- Rehber motoru: "Bugün" ekranı, faz takibi, çift-progresyon önerisi, deload/faz uyarıları.
- Beslenme modülü: Food + SavedMeal/Recipe kütüphanesi, meal kategorileri, günlük takvim (per-day view), hızlı öğün kaydı, günlük makro toplamı vs hedef.
- Vücut metrikleri: kilo, bel, opsiyonel ek ölçüler.
- İlerleme fotoğrafları: yükleme + galeri.
- Uyku, ruh hali kayıtları.
- Kan değeri: hatırlatma + (opsiyonel) sonuç kaydı (referans amaçlı, tıbbi tavsiye değil).
- Postür metrikleri: duvar testi, semptom günlüğü.
- Raporlar & grafikler: trend grafikleri, veri dışa aktarım (CSV/JSON).
- Hatırlatmalar/bildirimler.
- Yerel depolama + kullanıcının özel iCloud yedeği/senkronu.

### v1 kapsam DIŞI (OUT — bilerek ertelendi)
- Hesap sistemi, kayıt/giriş, çok kullanıcı, backend sunucu.
- Abonelik/ödeme/paywall.
- Android, iPad'e özel arayüz, Apple Watch uygulaması.
- Barkod tarama / harici büyük besin veritabanı (opsiyonel gelecek).
- Sosyal özellikler, paylaşım ağı, koçluk/AI sohbet.
- Canlı Notion senkronizasyonu.

---

## 5. Teknoloji yığını & mimari

- **UI:** SwiftUI (iOS 17+). Navigasyon: `TabView` tabanlı (Bölüm 8).
- **Persistence:** SwiftData (`@Model` entity'ler). Yerel store.
- **Senkron/yedek:** CloudKit (private database) — kullanıcının kendi iCloud'u. SwiftData + CloudKit entegrasyonu.
- **Grafikler:** Swift Charts.
- **Fotoğraf:** PhotosUI ile seçim; görüntüler uygulama container'ında (ve iCloud'da) saklanır, entity'de dosya referansı tutulur (binary'yi store'a gömme).
- **Bildirimler:** UserNotifications (local notifications).
- **HealthKit:** opsiyonel modül (D4), izin akışıyla; çekirdek buna bağlı değil.
- **Mimari desen:** Feature-modular + MVVM.
  - Her tracker ayrı bir Swift package/module: `WorkoutKit*`, `NutritionKit`, `MetricsKit`, `PhotosKit`, `SleepMoodKit`, `HealthChecksKit`, `GuidanceKit`, `ReportsKit`, ortak `CoreDataModels` + `DesignSystem`. (*Apple'ın WorkoutKit'iyle isim çakışmasın diye iç modülü `TrainingKit` adlandır.)
  - **DataStore/Repository protokolü:** Tüm veri erişimi `protocol XRepository` arkasında. v1'de `SwiftDataXRepository` implementasyonu. Ürünleşmede `RemoteXRepository` (backend) aynı protokole yazılır; UI/ViewModel değişmez. **Bu, geleceğe hazırlığın tek en önemli maddesi.**
  - ViewModel'ler `@Observable`; view'lar durumu enjekte alır (test edilebilirlik).
- **Lokalizasyon:** Türkçe birincil; tüm kullanıcı-görünür metin `String(localized:)`/catalog üzerinden — ürünleşmede İngilizce vb. eklenebilir.
- **Birimler:** metrik (kg, cm) varsayılan; birim sistemi ayarı (ürünleşme için imperial'e hazır).
- **Bağımlılık:** Mümkün olduğunca birinci-parti (Apple) framework; üçüncü-parti kütüphane minimumda. Gerekirse Swift Package Manager.

---

## 6. Veri modeli

> SwiftData `@Model` sınıfları olarak kurulacak. Alan adları İngilizce. İlişkiler (`1—n`, `n—n`) belirtildi. `id: UUID`, `createdAt: Date`, `updatedAt: Date` her entity'de bulunsun (aşağıda tekrar yazılmadı).

### Kullanıcı & program
**UserProfile** (v1'de tek kayıt): `displayName`, `heightCm: Double`, `startWeightKg: Double`, `targetWeightKg: Double`, `birthYear: Int?`, `unitsSystem: enum {metric, imperial}`, `proteinTargetG: Double`, `calorieTarget: Double?`, `carbTargetG: Double?`, `fatTargetG: Double?`, `programStartDate: Date`.

**Program**: `name`, `descriptionText`, `isActive: Bool`. — n WorkoutDayTemplate, n ProgramPhase.

**ProgramPhase** (12 aylık yol haritası): `name`, `orderIndex: Int`, `monthStart: Int`, `monthEnd: Int`, `trainingFocus: String`, `nutritionFocus: String`, `milestone: String`, `entryCriteria: String`. → Program.

**WorkoutDayTemplate**: `name` (ör. "Gün A"), `orderIndex`, `focus: String`. → Program; n ExerciseTemplate; n WarmupItem; n CooldownItem.

**ExerciseTemplate**: `name`, `orderIndex`, `targetSets: Int`, `repLow: Int`, `repHigh: Int`, `rirLow: Int`, `rirHigh: Int`, `category: enum {compound, accessory, core}`, `allowFailure: Bool`, `cues: String`, `safetyNote: String?`, `startingWeightKg: Double?`, `progressionRule: enum {doubleProgression, gradedEntryOHP, boneFocusHeavy, timeQuality}`. → WorkoutDayTemplate.

**WarmupItem**: `phase: enum {raise, activate, potentiate}`, `movement: String`, `dose: String`, `orderIndex`. → WorkoutDayTemplate.
**CooldownItem**: `movement: String`, `dose: String`, `note: String?`, `orderIndex`. → WorkoutDayTemplate.

### Antrenman kayıtları
**WorkoutSession**: `date: Date`, `status: enum {planned, inProgress, completed, skipped}`, `workoutDayTemplateId: UUID` (referans), `perceivedRecovery: Int?` (1-10), `note: String?`. → n SetLog.

**SetLog**: `exerciseTemplateId: UUID`, `setIndex: Int`, `weightKg: Double`, `reps: Int`, `rir: Int?`, `isWarmupSet: Bool`, `completedAt: Date`. → WorkoutSession.

### Vücut & fotoğraf & yaşam
**BodyMetric**: `date: Date`, `type: enum {weight, waist, custom}`, `customName: String?`, `value: Double`, `unit: String`.
**ProgressPhoto**: `date: Date`, `imageRef: String` (dosya yolu/asset id), `pose: enum {front, side, back}`, `note: String?`.
**SleepLog**: `date: Date`, `durationHours: Double`, `quality: Int` (1-10), `note: String?`.
**MoodLog**: `date: Date`, `moodScore: Int` (1-10) veya `moodTags: [String]`, `energy: Int?` (1-10), `note: String?`.
**PostureMetric**: `date: Date`, `wallTestPass: Bool?`, `symptomScore: Int?` (0-10), `region: String?`, `note: String?`.

### Sağlık kontrolleri
**HealthCheckReminder**: `name: String` (ör. "Ferritin"), `dueDate: Date`, `recurrence: enum {none, monthly, quarterly, yearly}`, `status: enum {pending, done}`.
**BloodworkResult** (opsiyonel, referans amaçlı): `date: Date`, `marker: String`, `value: Double`, `unit: String`, `note: String?`.

### Beslenme
**Food**: `name`, `brand: String?`, `servingSize: Double`, `servingUnit: String`, `caloriesPerServing: Double`, `proteinG: Double`, `carbG: Double`, `fatG: Double`, `fiberG: Double?`, `source: enum {userCreated, healthKit}`.
**Recipe** (kullanıcının "kaydettiği öğün/tarif"): `name`, `category: MealCategory`, `servings: Double`, `isDirectMacros: Bool`, `caloriesTotal: Double`, `proteinTotalG: Double`, `carbTotalG: Double`, `fatTotalG: Double`, `note: String?`. → n RecipeItem (opsiyonel, bileşimli tarifler için).
**RecipeItem** (opsiyonel — Food'lardan bileşim; v1.1): `foodId: UUID`, `quantity: Double`. → Recipe.
**MealCategory**: enum + custom → `{breakfast, lunch, dinner, snack, custom(String)}`. (Türkçe UI etiketleri: Kahvaltı, Öğle, Akşam, Ara Öğün.)
**DailyNutritionLog**: `date: Date` (günün sayfası, benzersiz). → n MealEntry. Hesaplanan: günün makro toplamları.
**MealEntry**: `category: MealCategory`, `recipeId: UUID?`, `foodId: UUID?`, `adhocName: String?`, `quantity: Double`, `caloriesResolved: Double`, `proteinResolved: Double`, `carbResolved: Double`, `fatResolved: Double`, `loggedAt: Date`. → DailyNutritionLog. (Kayıtlı bir Recipe seçmek bir MealEntry üretir; makrolar o an çözülüp sabitlenir ki tarif sonradan değişirse geçmiş bozulmasın.)

### Sistem
**AppReminder**: `type: enum {workout, measurement, bloodwork, mealLog, custom}`, `schedule: String` (cron benzeri veya basit kural), `message: String`, `isEnabled: Bool`.
**AppSetting** (key-value tercihler) veya UserProfile içine gömülü.

---

## 7. Özellik spesifikasyonu (modül modül)

Her modül: **amaç → ekran(lar) → davranış → kabul kriteri**.

### 7.1 Rehberlik — "Bugün" (Home)
- **Amaç:** Kullanıcıya bugün ne yapacağını tek bakışta söylemek.
- **Ekran:** Üstte faz bandı (ör. "Faz 2 · İnşa · Ay 4"), altında **bugünün eylemi**: sıradaki seans kartı (Gün A/B/C ya da "Dinlenme günü"), yaklaşan hatırlatmalar (ölçüm/tahlil), bugünün beslenme özeti (kayıtlı vs hedef), hızlı-eylem butonları (Seansı başlat, Öğün ekle, Kilo gir).
- **Davranış:** Sıradaki gün, son tamamlanan seansa göre rotasyondan hesaplanır (Bölüm 9). Deload haftasıysa banner gösterir. Faz geçiş kriteri oluşmuşsa uyarı kartı.
- **Kabul:** Uygulama açılışında en fazla 1 saniyede "bugün ne yapmalıyım" cevabı görünür; seans tek dokunuşla başlar.

### 7.2 Antrenman
- **Amaç:** Programı görmek ve seansı yönlendirmeli şekilde kaydetmek.
- **Ekranlar:** (a) Program genel görünüm (Gün A/B/C + fazlar), (b) Seans akışı: **Isınma** (Faz 1/2/3 listesi, işaretlenebilir) → **Hareketler** (her hareket için hedef set×tekrar×RIR, **önerilen ağırlık**, güvenlik ipucu, set-set kayıt) → **Soğuma** → seans özeti, (c) Seans geçmişi.
- **Davranış:** Her hareket için önerilen ağırlık çift-progresyondan gelir (Bölüm 9). OHP'de kademeli giriş + semptom kapısı (kullanıcı "semptomsuzum" onayı vermeden ilerletme). `allowFailure=false` hareketlerde "faile gitme" hatırlatması. Set kaydı: önceki set otomatik ön-doldurulur, kullanıcı düzeltir.
- **Kabul:** Bir seti kaydetmek ≤2 dokunuş; öneri mantığı Bölüm 9'a uygun; güvenlik notları ilgili harekette görünür.

### 7.3 Beslenme (MyFitnessPal referanslı)
- **Amaç:** Günlük öğünleri hızlı kaydetmek; sık öğünleri tarif olarak saklamak.
- **Ekranlar:** (a) **Günlük takvim / gün görünümü** — her gün kendi sayfası; kategoriler (Kahvaltı/Öğle/Akşam/Ara Öğün) altında o gün eklenen öğünler + kategori ve gün makro toplamı, üstte **günün toplamı vs hedef** (protein/kalori/karb/yağ bar'ları), (b) **Tarif/SavedMeal kütüphanesi** — kategoriye göre; yeni tarif: ad + besin değerleri doğrudan gir (MVP) veya Food'lardan bileştir (v1.1), (c) **Food kütüphanesi** — tekil besinler, (d) hızlı-ekle: bir güne, bir kategoriye kayıtlı tarifi seçip ekle.
- **Davranış:** Tarif seçince MealEntry üretilir, makrolar o an sabitlenir. Gün değiştirmek takvimden ileri/geri. Hedefler UserProfile'dan (protein 120 g vb.), ama genel kullanıcı için düzenlenebilir.
- **Kabul:** Kayıtlı bir kahvaltıyı bugüne eklemek ≤3 dokunuş; gün toplamı anlık güncellenir; tarif sonradan değişince geçmiş günler bozulmaz.

### 7.4 Vücut metrikleri & fotoğraflar
- **Ekranlar:** Metrik giriş (kilo/bel/özel), ilerleme fotoğrafı yükle (poz etiketiyle), foto galerisi (tarih sıralı, karşılaştırma).
- **Kabul:** Kilo/bel girişi tek ekran; foto yükleme PhotosUI ile; galeri kronolojik.

### 7.5 Uyku & ruh hali
- **Ekranlar:** Günlük uyku (süre + kalite 1-10), ruh hali (skor veya etiketler + enerji + not).
- **Kabul:** Her ikisi tek ekranda hızlı giriş.

### 7.6 Kan değerleri (referans, tıbbi tavsiye değil)
- **Ekranlar:** Hatırlatma listesi (Ferritin, D vitamini, genel — tarih/tekrar), opsiyonel sonuç kaydı.
- **Davranış:** Vadesi gelen hatırlatma "Bugün" ekranında ve bildirimle görünür. **UI'da net ibare:** "Bu bir tıbbi tavsiye değildir; değerleri bir hekimle değerlendir." Kırmızı-bayrak uyarıları (postür/servikal) bilgi olarak gösterilir.
- **Kabul:** Hatırlatma kurulabilir, tetiklenir; tıbbi-olmayan ibare görünür.

### 7.7 Postür metrikleri
- **Ekranlar:** Duvar testi (geçti/kaldı), semptom skoru (0-10, bölge), not.
- **Kabul:** Haftalık hızlı giriş; trend İlerleme'de grafiklenir.

### 7.8 Raporlar & grafikler
- **Ekranlar:** İlerleme panosu — kilo trendi, bel trendi, hareket-başı güç eğrisi (ör. Goblet Squat tahmini 1RM/hacim), beslenme uyumu (protein hedef tutturma %), uyku trendi, ruh hali, postür semptom trendi; **ilerleme fotoğrafı karşılaştırma**; **dışa aktarım** (CSV/JSON).
- **Davranış:** Swift Charts; tarih aralığı seçici (1A/3A/6A/1Y). Rapor = seçili aralığın özeti; export dosya olarak paylaşılabilir.
- **Kabul:** En az kilo, bel, bir hareketin gücü, protein uyumu grafiklenir; CSV export çalışır.

### 7.9 Hatırlatmalar & bildirimler
- **Davranış:** Seans günü hatırlatması, ölçüm zamanı, tahlil vadesi, öğün kaydı hatırlatması (opsiyonel). Kullanıcı ayarlardan açar/kapatır/saat seçer.
- **Kabul:** Local notification kurulup tetiklenir; ayarlardan yönetilir.

---

## 8. Bilgi mimarisi / navigasyon

**Tab bar (5 sekme):**
1. **Bugün** (Home / rehberlik)
2. **Antrenman** (program, seans, geçmiş)
3. **Beslenme** (günlük takvim, tarifler, food)
4. **İlerleme** (grafikler, fotoğraflar, rapor/export)
5. **Ayarlar** (profil & hedefler, program yönetimi, hatırlatmalar, birimler, veri export, iCloud, [ileride hesap])

Uyku/ruh hali/kan değeri/postür girişleri "Bugün" ve "İlerleme" içinden hızlı-eylem olarak erişilebilir; ayrıca "İlerleme" altında ilgili alt ekranlar.

---

## 9. Rehberlik & ilerleme mantığı (algoritma spesifikasyonu)

Bu bölüm ürünün beynidir; Notion'da kurulan mantığın koda dökülmüş halidir.

### 9.1 Sıradaki gün
- Rotasyon: WorkoutDayTemplate'ler `orderIndex` sırasıyla döngüsel (A→B→C→A…).
- Son `completed` WorkoutSession'ın günü + 1 = sıradaki gün. Hiç seans yoksa ilk gün.
- Haftalık hedef sıklık ayardan (varsayılan 3/hafta); ardışık günlerde otomatik "dinlenme" önerisi (aynı gün ikinci seansı engelleme).

### 9.2 Çift progresyon (per ExerciseTemplate, `doubleProgression`)
- Son tamamlanan seanstaki o hareketin çalışma setlerine bak.
- **Tüm** setler `repHigh`'a ulaştıysa **ve** kaydedilen RIR ≤ `rirLow` ise → sıradaki seansta önerilen ağırlık = son ağırlık **+ 2.5 kg**, hedef tekrar `repLow`'dan başlar.
- Değilse → ağırlık sabit, hedef "daha çok tekrar" (aynı ağırlıkta `repHigh`'a doğru).
- Öneri her zaman bir öneridir; kullanıcı override edebilir (girilen değer esas alınır).

### 9.3 OHP istisnası (`gradedEntryOHP`)
- İlk 4 hafta kademeli giriş: H1-2 oturarak nötr, H3-4 ayakta nötr, H5+ ayakta standart (WorkoutDayTemplate/ExerciseTemplate notunda faz bilgisi).
- Ağırlık artışı **yalnızca** kullanıcı "seans içi ve ertesi gün semptomsuzum" onayını verdiyse önerilir. Onay yoksa ağırlık sabit tutulur, uyarı gösterilir.

### 9.4 20 kg tavanı & kemik odağı
- Bir hareketin önerilen ağırlığı 20 kg'a ulaştığında (DB tavanı): "Ekipman tavanı" uyarısı + öneri sırası: tekrar/tempo/tek-taraflı; ayrıca "ayarlanabilir DB yatırımı" notu.
- `boneFocusHeavy` işaretli hareketlerde (Faz 3+) daha ağır/az tekrar önerisi.

### 9.5 Deload
- **Zamanlı:** her 5. antrenman haftasında "deload öner" (ağırlık %40-50, aynı hareketler).
- **Reaktif:** aynı hareket 2 ardışık seansta ilerlemediyse deload/uyarı.

### 9.6 Faz geçişi
- ProgramPhase `monthStart/monthEnd` + `programStartDate`'e göre tahmini faz; ayrıca kriter-temelli uyarı (ör. fazda geçen süre + bel/güç değişimi eşiği) → "Bir sonraki faza geçmeye hazır olabilirsin" kartı; geçiş kullanıcı onayıyla. Fazlar takvim değil durum: kullanıcı manuel faz set edebilir.

---

## 10. Başlangıç verisi (seed) — zorunlu

Uygulama ilk açılışta aşağıdakiyle seed'lenir (kullanıcı sonradan düzenleyebilir/silebilir). Bu, mevcut Notion programımızdır.

### 10.1 UserProfile (seed)
height 185, startWeight 98, targetWeight 90, proteinTargetG 120, unitsSystem metric, programStartDate = kurulum tarihi. (calorie/carb/fat hedefleri opsiyonel; kullanıcı girer.)

### 10.2 Program: "Tam Vücut v3 (Postür → Recomp)" — 4 ProgramPhase
| orderIndex | name | monthStart-End | trainingFocus | nutritionFocus | milestone |
|---|---|---|---|---|---|
| 1 | Temel | 1-2 | Teknik + alışkanlık; OHP kademeli giriş; ölçümleri başlat | Ölçülü açık; 120 g protein | Alışkanlık + baseline + check-up |
| 2 | İnşa | 3-6 | Çift progresyon; 10 kg yükler tırmanır; 20 kg tavan | Açığı sürdür; bel+güç izle | Bel↓, güç↑, ayarlanabilir DB |
| 3 | İlerleme | 7-9 | Ağır DB; bileşiklerde ağır/az tekrar (kemik) | Kilo düştükçe açığı yeniden kalibre | Güç sıçraması + beslenme ayarı |
| 4 | Konsolidasyon | 10-12 | Hacim eklemeyi durdur; kaliteyi koru | Sürdürülebilir bakım | Veriye dayalı 2. yıl kararı |

### 10.3 WorkoutDayTemplate'ler (3 gün) + ExerciseTemplate'ler
> Alanlar: sets × repLow-repHigh @ RIR rirLow-rirHigh, category, allowFailure, progressionRule, safetyNote. Starting weight bilinen yerlerde girildi (curl/OHP 10 kg).

**Gün A — Squat Ağırlıklı**
| # | name | sets×rep @RIR | category | allowFail | rule | not |
|---|---|---|---|---|---|---|
|1|Goblet Squat|3×15-25 @0-1|compound|true|doubleProgression|3sn eksantrik; topuk kalkarsa plaka|
|2|Chin-up|3×6-12 @1-2|compound|false|doubleProgression|faile gitme; boyun nötr|
|3|DB Floor Press|4×8-12 @1-2|compound|false|doubleProgression|dirsek 45°, yerde 1sn|
|4|DB Romanian Deadlift|3×10-12 @1-2|compound|false|doubleProgression|kalça menteşesi; bel değil hamstring|
|5|Prone Y-T-W|2×8 (poz)|accessory|false|timeQuality|ağırlıksız; tepede 2sn|
|6|Face Pull (bant)|3×15-20 @0-1|accessory|false|timeQuality|hafif; omuz yukarı kalkmasın|
|7|Tek Bacak Calf Raise|2×12-20 @0-1|accessory|false|doubleProgression|1.set düz diz, 2.set bükük|
|8|Plank / Pallof|3×30-60sn|core|false|timeQuality|haftada 1 Pallof|

**Gün B — Hinge Ağırlıklı**
| # | name | sets×rep @RIR | category | allowFail | rule | not |
|---|---|---|---|---|---|---|
|1|DB RDL (çift)|3×10-12 @1-2|compound|false|doubleProgression|A'dan ağır; DB bacaktan uzaklaşmasın|
|2|Tek Kol DB Row|4×10-12 @1-2|compound|false|doubleProgression|gövde döndürme|
|3|Push-up|2×10-20 @0-1|compound|true|doubleProgression|kolaysa ayak yüksekte|
|4|DB Overhead Press|3×8-12 @1-2|compound|false|**gradedEntryOHP**|🛑 sağ işaret parmağı uyuşursa kes → half-kneeling|
|5|Bulgarian Split Squat|3×8-12 @1-2|compound|false|doubleProgression|gövde dik/hafif öne|
|6|Glute Bridge/Hip Thrust|3×12-20 @0-1|accessory|true|doubleProgression|topuktan it; beli yaylandırma|
|7|Wall Slide|2×10-12|accessory|false|timeQuality|temas kaybolmadan|
|8|Dead Bug|2×8-10|core|false|timeQuality|bel yerden kalkmasın|
|9|Copenhagen Plank|2×15-30sn|core|false|timeQuality|aşama: diz→ayak sehpada|

**Gün C — Unilateral + Taşıma**
| # | name | sets×rep @RIR | category | allowFail | rule | not |
|---|---|---|---|---|---|---|
|1|Reverse Lunge (DB)|3×8-12 @1-2|compound|false|doubleProgression|ağırlık ön ayakta|
|2|Nordic Hamstring Curl|2×3-5|compound|false|timeQuality|🔥 ilk 2 hafta 2×3'ü aşma (DOMS)|
|3|Pull-up / bantlı|2× @1-2|compound|false|doubleProgression|skapular set; zorsa bant|
|4|Bantlı/Tek Kol Row|3×12-15 @0-1|accessory|false|doubleProgression|bitişte en zor|
|5|Half-Kneeling DB Press|3×8-10 @1-2|compound|false|doubleProgression|OHP'de semptomda dönüş yeri|
|6|DB Lateral Raise|3×12-20 @0-1|accessory|false|doubleProgression|omuz hizasında dur|
|7|Farmer's Carry|3×30-40 adım|accessory|false|timeQuality|en ağır 2 DB|
|8|Süperset Curl + Triceps|2×10-15 @0-1|accessory|false|doubleProgression|curl 10 kg başlangıç|
|9|Side Plank / Pallof|2×20-40sn|core|false|timeQuality|kalça düşerse bitti|

### 10.4 WarmupItem'lar (gün-özel)
- **Faz 1 (raise, her gün ortak):** ip/koşu 60-90sn; kol çevirme 10; çömeliş-kalkış 8; bacak sallama ön-arka 10/bacak.
- **Faz 2 (activate) Gün A:** knee-to-wall 10/taraf; 90/90 kalça 8/yön; band pull-apart 15.
- **Faz 2 Gün B:** yarım diz kalça fleksörü 8/taraf; bacak sallama yan+ön 10; open book 8/taraf; **OHP için** omuz dış rotasyon 15/kol + wall slide 10.
- **Faz 2 Gün C:** yarım diz kalça fleksörü 8/taraf; wall slide 10; omuz dış rotasyon 15/kol.
- **Faz 3 (potentiate):** ilk harekete 2 rampa seti (A: BW squat×8 + ~10kg×5; B: boş hinge×8 + hafif×5 + OHP boş pres×8; C: BW lunge×5/bacak + hafif×3/bacak).

### 10.5 CooldownItem (her gün ortak)
Pektoral germe 30sn×2/taraf; C6 nöral gliding 1×10 (uyuşma dönerse dur); chin tuck 1×10.

### 10.6 HealthCheckReminder (seed)
Ferritin (once, ~1 ay sonra), D vitamini (once), Genel check-up (yearly).

---

## 11. Tasarım / UX ilkeleri

- **Açıklık önce:** "Bugün" ekranı tek bakışta cevap verir; her ekranda "şimdi ne yapmalıyım" belli. Kayıt akışları minimum dokunuş.
- **Tanıdıklık:** Beslenme akışı MyFitnessPal'a yakın (gün görünümü, kategori, hızlı ekle) — öğrenme eğrisi düşük.
- **Dark mode** + Dynamic Type + VoiceOver uyumu + dokunsal geri bildirim.
- **Progressive disclosure:** Veri yoğun ama sade; ileri detay katmanlı.
- **Türkçe UI**, i18n-hazır. Metrik birimler varsayılan.
- **Tasarım sistemi:** ortak `DesignSystem` modülü (renk/typografi/spacing token'ları), tutarlı bileşenler.

---

## 12. Gizlilik & veri

- Sağlık verisi **cihazda + kullanıcının özel iCloud'unda** (CloudKit private DB). v1'de üçüncü-parti sunucu yok.
- Kullanıcı verisini **dışa aktarabilir** (CSV/JSON) ve silebilir.
- HealthKit izinleri açıkça sorulur; reddedilebilir, çekirdek çalışır.
- **Ürünleşme fazında** yeniden ele alınacaklar (v1'de değil): sunucu tarafı şifreleme, açık rıza akışı, GDPR/sağlık verisi uyumu, veri saklama politikası. Bölüm 13'e bağlı.

---

## 13. Gelecek fazlar / ürünleşme (mimaride yer bırak, inşa etme)

- **Hesap & kimlik:** Sign in with Apple + e-posta; UserProfile'ı bir Account'a bağlanabilir yap.
- **Backend:** Repository protokollerine `Remote*` implementasyonu (öneri: başlangıçta bir BaaS — ör. Supabase/CloudKit-public karması — değerlendirilecek). UI/ViewModel dokunulmadan takılabilmeli.
- **Çoklu kullanıcı & senkron:** cihazlar arası + hesap bazlı.
- **Abonelik:** StoreKit 2 ile paywall; ücretsiz/deneme + premium sınırları.
- **Uyarlanabilirlik (asıl "herkese"):** program/modül şablonları; kullanıcıların kendi programlarını ve (ileride) kendi tracker tiplerini tanımlaması. **v1'de sabit modüller**, ama entity ve UI mimarisi yeni modül/şablon eklemeye açık olsun.
- **Genişleme:** Apple Watch (canlı seans), iPad, Android (native tercih değişirse).

---

## 14. Fazlı build planı (Opus bunu izler)

Her milestone **derlenip çalışan** proje bırakır. Kullanıcı her aşamada görebilir/deneyebilir.

**M0 — İskelet**
- Xcode projesi, iOS 17+ hedefi, SwiftData + CloudKit kurulumu, modül/paket yapısı, TabView navigasyon, boş ekranlar, seed-loader iskeleti, Repository protokolleri + SwiftData implementasyonları (boş).
- *Kabul:* Proje derlenir, 5 sekme açılır, seed loader UserProfile+Program+günleri yükler (ekranda ham liste görülebilir).

**M1 — MVP çekirdeği: "Bugün" + Antrenman kaydı** ⭐
- Seed (Bölüm 10) tam yüklenir. "Bugün" ekranı: faz + sıradaki gün. Seans akışı: ısınma listesi → hareketler (hedef + önerilen ağırlık + güvenlik notu + set kaydı, önceki set ön-dolu) → soğuma → özet. Çift progresyon + OHP kapısı + deload (zamanlı) mantığı. Seans geçmişi.
- *Kabul:* US1, US2, US3, US9(deload) çalışır. Bir haftalık A/B/C döngüsü kaydedilebilir; öneriler Bölüm 9'a uygun; OHP semptom kapısı çalışır.

**M2 — Beslenme**
- Food + Recipe (doğrudan makro) kütüphanesi, MealCategory'ler, DailyNutritionLog gün görünümü (takvim), MealEntry hızlı ekleme, gün makro toplamı vs hedef.
- *Kabul:* US4, US5 çalışır. Kayıtlı kahvaltı ≤3 dokunuşla bugüne eklenir; toplam anlık; geçmiş bozulmaz.

**M3 — Metrikler, foto, yaşam, sağlık, postür**
- BodyMetric, ProgressPhoto (yükle+galeri), SleepLog, MoodLog, HealthCheckReminder(+opsiyonel BloodworkResult), PostureMetric giriş ekranları. Tıbbi-olmayan ibareler.
- *Kabul:* US6, US8 çalışır; tüm tracker'lara giriş yapılabilir; tahlil hatırlatması tetiklenir.

**M4 — Raporlar & grafikler**
- Swift Charts panosu (kilo, bel, hareket gücü, protein uyumu, uyku, ruh hali, postür), foto karşılaştırma, CSV/JSON export, tarih aralığı seçici.
- *Kabul:* US7 çalışır; en az belirtilen grafikler + export.

**M5 — Cila & sistem**
- Local notifications (seans/ölçüm/tahlil/öğün), Ayarlar (profil/hedef/program/hatırlatma/birim/export), CloudKit senkron doğrulaması, opsiyonel HealthKit okuma (D4), dark mode/erişilebilirlik geçişi, tasarım sistemi tutarlılığı, README/kurulum.
- *Kabul:* Bildirimler yönetilebilir/tetiklenir; iCloud yedek çalışır; erişilebilirlik temel geçer.

**(Sonraki — v1 değil)** Ürünleşme: hesap, backend, abonelik, çoklu kullanıcı (Bölüm 13).

---

## 15. Genel kabul kriterleri (definition of done)

- Uygulama iPhone (iOS 17+) simülatör ve gerçek cihazda derlenip çalışır.
- Seed veriyle ilk açılışta "Bugün" anlamlı; hiçbir çekirdek ekran boş/çökme değil.
- Tüm v1 modülleri (Bölüm 4 IN) uçtan uca çalışır; belirtilen US'ler karşılanır.
- Rehber motoru Bölüm 9'a uygun (özellikle çift progresyon + OHP kapısı + deload).
- Veri SwiftData'da kalıcı; CloudKit yedeği çalışır; CSV/JSON export çalışır.
- Sağlık/tahlil ekranlarında tıbbi-olmayan ibare mevcut; güvenlik durakları ilgili hareketlerde görünür.
- Türkçe UI; dark mode; temel VoiceOver/Dynamic Type.
- Mimari modüler; veri erişimi Repository protokolleri arkasında (backend geçişine hazır).
- Kod içi kullanıcı-görünür metin lokalize edilebilir; sabit "magic string" makro/ağırlık mantığı yok (kurallar merkezi).

---

## 16. Kurulum & araç zinciri (kullanıcı için — README'ye de koy)

Kullanıcı Swift bilmiyor; adımları elinden tutarak yaz.

1. **Xcode kur** (Mac App Store, en güncel). İlk açılışta iOS platformunu indir.
2. Projeyi aç (`.xcodeproj`/`.xcodeproj`), üstten bir **simülatör** seç (ör. iPhone 15/16), ▶ ile çalıştır — kod yazmadan uygulamayı görürsün.
3. **Kendi iPhone'unda çalıştırmak:** iPhone'u kabloyla bağla; Xcode'da Signing & Capabilities → "Personal Team" (ücretsiz Apple ID) seç; cihazı hedef seçip ▶. (Ücretsiz sertifika ~7 günde bir yeniden imzalama ister.)
4. **Kalıcı cihaz kurulumu + çevreye dağıtım:** **Apple Developer Program** ($99/yıl) — hazır olduğunda kaydol; sonra **TestFlight** ile yakın çevrene link'le dağıt. (v1 kişisel kullanım için şart değil; ürünleşince gerekli.)
5. **iCloud yedek:** cihazda aynı Apple ID ile iCloud açık olmalı; CloudKit private DB otomatik senkron eder.
6. **HealthKit (opsiyonel):** ilk kullanımında izin sorulur; reddedilebilir.

---

## 17. Açık noktalar / önerilen varsayılanlar (kullanıcı onayı bekleyen)

Aşağıdakileri Bölüm 2'deki kararlarla varsayılan aldım; kullanıcı değiştirmek isterse belirtir:

- **HealthKit'i v1'e alalım mı, v1.1'e mi?** Varsayılan: v1.1 (opsiyonel). — Değişebilir.
- **CSV mi JSON mu, yoksa ikisi mi export?** Varsayılan: ikisi. — Değişebilir.
- **Beslenme hedefi:** v1'de kişisel (protein 120 g); genel kullanıcı için düzenlenebilir alan. Kalori/karb/yağ hedefi girmek zorunlu değil, opsiyonel. — Onay bekler.
- **Bileşimli tarif (Food'lardan Recipe):** v1.1'e bırakıldı; MVP'de doğrudan-makro tarif. — Değişebilir.
- **Widget (ana ekran "bugünün seansı"):** v1'de yok, ürünleşmede değerlendirilecek. — İstenirse M5'e eklenir.

---

*Bu doküman v1 içindir. Onay/değişiklik sonrası Opus, Bölüm 14'teki M0'dan başlayarak inşa eder.*
