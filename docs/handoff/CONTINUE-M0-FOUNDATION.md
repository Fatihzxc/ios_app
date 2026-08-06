# Autonomous Development Handoff: Health Tracking iOS App

This document is the complete continuation context for an autonomous coding agent. Read it fully before changing the repository. The user intends to start the next session with only a goal that references this file.

Suggested goal text:

> Continue and complete the Health Tracking iOS app work exactly as specified in `docs/handoff/CONTINUE-M0-FOUNDATION.md`. Work autonomously from the recorded checkpoint, preserve the TDD/review/commit contract, push every accepted checkpoint to both remotes, and do not stop while a safe in-scope next step remains.

## 1. Long-term objective

Implement the product described by `Saglik-Takip-App-Gereksinim-Dokumani-v1.md`.

The current branch is implementing the M0 foundation described by:

- `docs/superpowers/specs/2026-08-03-health-tracking-app-design.md`
- `docs/superpowers/plans/2026-08-03-health-tracking-app-roadmap.md`
- `docs/superpowers/plans/2026-08-03-m0-foundation-implementation.md`

Finish M0.8 and M0.9 first. M0 is not the whole product. After M0 acceptance, brainstorm and write a detailed implementation plan for the next roadmap milestone before writing its production code, then continue toward the full requirement document unless the user changes scope.

## 2. User's binding working contract

These rules override convenience:

1. Brainstorm before creative or behavior-changing work and maintain a detailed roadmap.
2. Execute from the approved roadmap; do not improvise a materially different architecture.
3. Use strict TDD for every behavior change:
   - write tests first;
   - commit and push a test-only exact SHA;
   - obtain a qualifying RED after project/test discovery;
   - only then write production code;
   - amend the same task commit and obtain exact-SHA GREEN.
4. Every implementation slice receives an independent review agent. If a finding is valid, the original implementer fixes it test-first, then a fresh reviewer performs a scoped re-review.
5. Commit and push every accepted checkpoint. Preserve the task's required commit shape.
6. GitHub Actions is authorized and is the macOS/Xcode verification source when the host is not a Mac.
7. Frontend direction must follow the already completed Claude Opus 5 xhigh design. Final M0.8 implementation/design fidelity must be reviewed by Claude Fable 5 medium. Never claim a Claude/Fable verdict if the call fails or the tool is unavailable.
8. Continue without needless approval pauses. Stop only for a real authority decision, unavailable required input/tool, or an unsafe/destructive ambiguity.
9. Preserve unrelated user work. Never use `git reset --hard` or discard unknown changes.

## 3. Repository and remote setup

Canonical repositories:

- GitHub: `https://github.com/Fatihzxc/ios_app.git`
- Gitea/LAN mirror: `http://192.168.100.12:3000/FO_FO_FO/app.git`

Active branch:

- `feat/m0-foundation`

Preferred setup when cloning from the LAN mirror:

```bash
git clone http://192.168.100.12:3000/FO_FO_FO/app.git app
cd app
git switch feat/m0-foundation
git remote rename origin gitea
git remote add origin https://github.com/Fatihzxc/ios_app.git
git fetch --all --prune
git branch --set-upstream-to=origin/feat/m0-foundation feat/m0-foundation
```

If cloning from GitHub instead, add the mirror:

```bash
git clone https://github.com/Fatihzxc/ios_app.git app
cd app
git switch feat/m0-foundation
git remote add gitea http://192.168.100.12:3000/FO_FO_FO/app.git
git fetch --all --prune
```

Before doing any work, verify:

```bash
git branch --show-current
git status --short
git rev-parse HEAD
git rev-parse origin/feat/m0-foundation
git rev-parse gitea/feat/m0-foundation
```

Expected: branch `feat/m0-foundation`, clean tracked tree, and both remotes at the same branch tip. The handoff document itself is included in that pushed tip, so use `git rev-parse HEAD` as the authoritative post-handoff SHA.

Before changing an accepted checkpoint, record its current SHA. Do not fetch immediately before force-pushing an amended commit, because that would move the remote-tracking lease baseline and could conceal a concurrent remote update.

For every amended checkpoint, use this safe sequence (Bash example; adapt variable syntax on PowerShell):

```bash
expected_old_sha="$(git rev-parse HEAD)"
test "$(git ls-remote origin refs/heads/feat/m0-foundation | cut -f1)" = "$expected_old_sha"
test "$(git ls-remote gitea refs/heads/feat/m0-foundation | cut -f1)" = "$expected_old_sha"

# Make and verify the intended changes, then amend once.
git add <only-intended-files>
git commit --amend --no-edit

git push --force-with-lease=refs/heads/feat/m0-foundation:${expected_old_sha} origin HEAD:refs/heads/feat/m0-foundation
git push --force-with-lease=refs/heads/feat/m0-foundation:${expected_old_sha} gitea HEAD:refs/heads/feat/m0-foundation
```

The two `ls-remote` comparisons are mandatory. They inspect live tips without changing local remote-tracking refs. If either remote differs from `expected_old_sha`, stop and reconcile the concurrent work; never overwrite it. If the first push succeeds but the second fails, stop and reconcile the second remote before doing more implementation work.

Do not change the branch's upstream away from GitHub unless the user asks.

## 4. Current checkpoint

Code checkpoint immediately before adding this handoff document:

- SHA: `fa77b6b59c6ce84bf5b8b756a2083b5187fdabb4`
- Subject: `feat(app): add five-tab foundation shell`
- M0.8 base: `cdc20a4562282fbdfe3033d988e916d0b9906183`
- Shape: exactly one amended M0.8 commit over the M0.7 base
- Tree before the handoff edit: clean
- GitHub and branch origin before the handoff edit: matched

The handoff file is intentionally amended into the same M0.8 work-in-progress commit so the one-commit M0.8 invariant remains intact. Continue using:

```bash
git add <only intended files>
git commit --amend --no-edit
```

Then force-push with lease to both remotes.

No M0.8c test or production change was left in the working tree when work was stopped. Resume at **M0.8c test-only RED**.

## 5. Completed history

The accepted branch history through M0.7 is:

```text
4bb90a94e696ade36d52c3d05158d8e88d77b693 build: bootstrap iOS project and macOS CI
55b69cbb09dcf1c61467b896ec370cf632cbeec4 feat(core): add shared domain values and validation
ba42ca316d1bb263bed7d3fc5e3d04c641829c67 feat(core): add program and training schema
f09319aebaebaccde5373665bd90c98de3e84092 feat(core): complete v1 persistence schema
d8582b0cae18b20c587ed57238b01ce50d73f0fb feat(persistence): add model container and training repository
897b7890ff8ed87cd3e8d57702b06372e67f65c4 feat(persistence): seed foundation program idempotently
cdc20a4562282fbdfe3033d988e916d0b9906183 feat(design): add accessible foundation design system
```

M0.1 through M0.7 passed their required tests and independent reviews. Do not reopen them without a demonstrated regression.

Important M0.7 boundary: M0.8 must not modify DesignSystem production sources. Use the existing components and semantic tokens, including `StatusPill(style: .info)` and the existing `FeatureStateView` APIs.

## 6. Completed M0.8 slices

### M0.8a: ordered phase repository contract — complete

Implemented:

- `TrainingRepository.fetchProgramPhases(programID:)`
- SwiftData filtering by exact program ID
- deterministic `orderIndex`, then UUID-string ordering
- real in-memory SwiftData contract coverage for empty, filtering, no leakage, and stable order

The review found and corrected a test weakness by querying a non-active target program while an active decoy program has an earlier phase. Fresh re-review passed with zero Critical/Important/Minor findings.

Final M0.8a evidence:

- RED: SHA `75affdd025fa441151414a9fbe2f520e9b83bff8`, run `31075034848`, job `92531084554`
- GREEN/review correction: SHA `d0bd4a87821f6769777285e77eecf20f89466649`, run `31076048627`, job `92534216292`
- Targeted PersistenceKit: 22/22
- Full Local at that point: 74/74

### M0.8b: value-only foundation ViewModel — complete

Implemented:

- public `@MainActor @Observable` `FoundationProgramViewModel`
- public pure `Equatable & Sendable` loading/content/empty/error state and summary snapshots
- copied profile/program/phase/day scalars; no model object escapes
- defensive phase/day ordering by `orderIndex`, then UUID
- genuine missing-program empty state
- stable error state with no technical error payload
- real loading and retry behavior
- localized blank-name fallback `Profilim` using `bundle: .module`
- `usesFallbackDisplayName` provenance
- TrainingKit-owned `FoundationUnitDisplayMode.metric/imperial`, avoiding a public CoreModels unit-type dependency
- tests proving source model mutation cannot alter an existing snapshot

The review found and corrected missing fallback provenance and unit mode. Fresh re-review passed with zero Critical/Important/Minor findings.

Final M0.8b evidence:

- Initial RED: SHA `5c7dcdb824592c294c01e4bd9faf28ce87be82d0`, run `31077416179`, job `92538381237`
- Review-correction RED: SHA `ae8be2b3a2cc43238802947c1493f0f087e83d13`, run `31078710328`, job `92542352030`
- Final GREEN code SHA before handoff: `fa77b6b59c6ce84bf5b8b756a2083b5187fdabb4`
- Final GREEN run: `31078954535`, job `92543117001`
- Targeted TrainingKit: 11/11
- Full Local: 85/85 = 1 UI + 38 CoreModels + 22 PersistenceKit + 11 TrainingKit + 13 DesignSystem
- Local Release: passed
- Gallery export: passed
- Cloud compile-only: passed
- Artifact: `8958788130`
- Artifact SHA-256: `7b0476e346af2cce2209fe2c5fc1bf45b9789de5fb8be01876be48bd89ef1506`

Current M0.8 code diff versus `cdc20a4` is intentionally limited to the repository method/tests, Training foundation value ViewModel/tests/resources, package/project test wiring, and the targeted workflow step.

### Embedded Claude Opus 5 xhigh M0.8 blueprint

The original task-specific Opus transcript lived in an ignored execution workspace, so the remaining binding visual/interaction rules are preserved here:

- Every tab owns its own `NavigationStack` and a persistent outer root container carrying `root.<tab>` in loading, content, empty, and error states.
- Tab symbols are fixed: `sun.max` Today, `dumbbell` Training, `fork.knife` Nutrition, `chart.bar` Progress, and `gearshape` Settings. Labels remain visible.
- Every root scrolls vertically. Use 20-point horizontal screen padding, 24-point section spacing, and only the existing semantic `bg.base`, `bg.raised`, and `bg.sunken` roles.
- No shadows, materials, blur, raw colors, one-line truncation, scale-to-fit text, fixed text heights, skeletons, shimmer, sample production data, shared navigation path, or programmatic tab switching.
- The app-local key/value row uses `ViewThatFits`: horizontal label/value at ordinary sizes and vertically stacked by AX3. It has explicit concise accessibility label/value and no button trait.
- Phase/day rows are static. They have no chevron, highlight, navigation, or button trait. Badge glyphs and decorative symbols are hidden from VoiceOver; the row exposes one concise accessibility label.
- The navigation title is each root's first heading. Section titles carry heading traits. Do not force focus on ordinary tab changes.
- Loading-to-shell, user-requested reload/retry transitions, and fatal configuration may move accessibility focus to the new state heading.
- Do not cap Dynamic Type. AX5 remains scrollable with 20-point gutters, including on a small iPhone.
- Reduce Motion removes slide, scale, and symbol effects; use instant/opacity changes while retaining the standard system progress control.
- Only real actions/navigation receive action traits or chevrons. Show at most one primary state action on a screen.
- Settings' gallery route remains pushed when switching away and back; it must never affect another tab's stack.

## 7. Immediate next task: M0.8c test-only RED

Do not write production environment/bootstrap code first.

### 7.1 Allowed RED files

Create:

- `HealthTrackingAppTests/AppEnvironmentTests.swift`
- `HealthTrackingAppTests/AppBootstrapModelTests.swift`

Modify only test/build wiring:

- `project.yml`: add a hosted iOS unit-test target depending on `HealthTrackingApp`; include it in the Local scheme
- `.github/workflows/ios.yml`: switch the targeted step from `TrainingKitTests` to `HealthTrackingAppTests`

Do not change `Package.swift`, app production sources, or catalogs in the RED commit.

### 7.2 AppEnvironment test contract

Production must eventually retain this wrapper signature:

```swift
static func resolve(
    processInfo: ProcessInfo = .processInfo,
    bundle: Bundle = .main
) throws -> AppEnvironment
```

The wrapper delegates to testable internal seams. Configuration parsing/orchestration and persistent-store path resolution are separate.

Tests must prove all of the following:

1. Exact `-ui-testing` wins before any plist, bundle-ID, or store lookup, even when plist values are absent or malformed.
2. Substrings/lookalikes do not activate UI testing.
3. `CloudKitEnabled` accepts only:
   - an actual Boolean;
   - exact String `YES`;
   - exact String `NO`.
4. Reject missing, numeric (including `NSNumber` where bridging could masquerade as Bool), lowercase, whitespace-padded, unresolved substitution, arbitrary String, and other typed values with stable `Equatable & Sendable` configuration errors.
5. When Cloud resolves false, `CloudKitContainerIdentifier` is never inspected. Prove this with a lazy provider/call counter. Missing, blank, non-String, and unresolved values must still resolve local.
6. When Cloud resolves true, the identifier must be a present nonblank String. Missing, blank, non-String, and unresolved substitution values are typed errors.
7. Store-path resolution receives injected values only:
   - optional Application Support base URL;
   - optional bundle identifier;
   - a directory-creation closure.
8. Assert the exact deterministic app directory and a stable store filename.
9. Cover unavailable Application Support, missing/blank bundle ID, and directory-creation failure without touching the real machine's Application Support directory.
10. UI testing bypasses store resolution, bundle-ID lookup, and directory creation entirely. Local and Cloud resolve the store URL exactly once.

The production wrapper alone supplies `FileManager` behavior.

### 7.3 Bootstrap test contract

Use a pure injected asynchronous load/factory closure with call counters and a controllable gate. No SwiftData or real filesystem is needed in these tests.

Tests must prove:

1. Initial state is loading.
2. Repeated or concurrent implicit `loadIfNeeded()` calls invoke the dependency-create/seed boundary exactly once.
3. Success becomes ready/content.
4. Failure becomes a stable error state with no technical payload.
5. Another implicit call after failure does not invoke the closure again.
6. Explicit retry is a real second attempt, visibly re-enters loading while suspended, then reaches success.

This injected boundary represents production dependency construction and seeding, so the tests prove one seed/load attempt per composition lifecycle.

### 7.4 Qualifying RED

Amend the existing M0.8 commit, push both remotes, and require GitHub Actions to complete checkout, XcodeGen, project/package/hosted-test discovery, then fail targeted `HealthTrackingAppTests` compilation because `AppEnvironment` and bootstrap symbols are missing.

Infrastructure, signing, billing, missing simulator, or host-target wiring failures are not qualifying.

Stop production work at RED and record exact SHA/run/job/error. Once the controller has verified that the RED qualifies, proceed autonomously to GREEN; no additional user approval is required.

## 8. M0.8c production/GREEN contract

Implement only typed environment, dependency ownership, and bootstrap composition. Do not build the five-tab UI in this slice beyond what compilation requires.

### AppEnvironment

- Typed environment must resolve UI testing, local, or Cloud configuration without fallback.
- UI testing uses in-memory persistence.
- Local and Cloud use the deterministic store URL.
- Cloud requires the private database identifier; Local never reads it.
- Every invalid value/path failure maps to a stable typed error. Do not expose raw filesystem/configuration error text.

### AppDependencies

Only `AppDependencies`, PersistenceKit, and CoreModels may know `ModelContainer`/`ModelContext`.

`AppDependencies` owns:

- the `ModelContainer`;
- one main-context `SwiftDataSeedLoader`;
- one `SwiftDataTrainingRepository` exposed through the protocol boundary.

It seeds exactly once per composition lifecycle before content is exposed.

### Bootstrap

- Testable `@MainActor` observable bootstrap model/coordinator uses the injected load/factory closure.
- Implicit loading is once-only; explicit retry is a new real attempt.
- Bootstrap loading UI is app-local native `ProgressView` plus app-catalog `Hazırlanıyor…`.
- Bootstrap loading must not use or modify `FeatureStateView`.
- Invalid environment configuration renders a dedicated app-local fatal configuration screen outside the tabs, with stable Turkish copy, no retry, no crash, and no local/in-memory fallback.
- Recoverable bootstrap failure may expose a real retry but never technical error details.
- Do not modify DesignSystem production sources.

GREEN requires:

- targeted hosted app tests;
- full Local test suite;
- Local Release;
- gallery export;
- Cloud compile-only;
- clean scope/leakage/catalog checks;
- independent review and fresh re-review if needed.

## 9. M0.8d: five-tab shell and screenshot evidence

Start only after M0.8c independent review passes.

### 9.1 Required composition

- `AppTab`: today, training, nutrition, progress, settings
- stable tab/root identifiers:
  - `tab.today` / `root.today`
  - `tab.training` / `root.training`
  - `tab.nutrition` / `root.nutrition`
  - `tab.progress` / `root.progress`
  - `tab.settings` / `root.settings`
- one independently owned `NavigationStack` per tab
- one shared `FoundationProgramViewModel` instance/state for Today and Training
- all roots vertically scrollable and usable at AX5 on a small iPhone

### 9.2 UI behavior

Today:

- title `Bugün`
- foundation summary with active program, profile/fallback provenance, and phase/day inventory
- ordinary non-action `Yakında` card using existing `StatusPill(style: .info)`
- no recommendation, exercise, session-start, or M1 action

Training:

- title `Antrenman`
- real value-snapshot profile/program cards
- ordered four phases and A/B/C days
- static rows with no chevrons or fake navigation
- app-local responsive key/value row; do not add a DesignSystem API
- format metric/imperial honestly from `FoundationUnitDisplayMode`

Nutrition:

- title `Beslenme`
- ordinary semantic informational card explaining records arrive later
- no `FeatureState.empty`, add button, fake records, or fake CTA

Progress:

- title `İlerleme`
- ordinary semantic informational card explaining measurements/charts arrive later
- no fake chart, axes, sample numbers, toolbar add, or fake CTA

Settings:

- title `Ayarlar`
- honest in-memory/local/iCloud-configured wording; never claim synchronization succeeded
- exactly one real `NavigationLink` to the existing DesignSystem gallery
- no fake toggle
- preserve the pushed Settings gallery path across tab round-trips; paths must not leak to other tabs

State handling:

- Today/Training repository loading uses unchanged `FeatureStateView(.loading)`.
- Genuine missing-program empty uses existing empty API and a real reload closure.
- Repository error uses existing error API and a real retry closure.
- Technical error details stay hidden.
- Nutrition/Progress informational-unavailable content is ordinary `AppCard` content, not a new FeatureState case.
- Fatal configuration remains app-local outside tabs.

All user-facing strings belong in correctly encoded Turkish String Catalogs. Package lookups use `bundle: .module`.

### 9.3 UI-test state injection

Replace `HealthTrackingAppUITests/BootstrapUITests.swift` with `AppShellUITests.swift`.

Debug UI-test controls may inject dependencies/outcomes only under the UI-testing environment. Never force arbitrary view state and never supply no-op action closures.

- `empty-once`: first real foundation load returns empty; tapping reload visibly shows loading, then real seeded content.
- `error-once`: first real foundation load fails; tapping retry visibly shows loading, then real seeded content.
- XCUITest asserts both transitions.
- A statically held state is allowed only for deterministic loading and fatal screenshots.
- Normal production paths must not receive fake data.

Tests must cover:

- five tabs and five distinct roots;
- exact ordered seed program/four phases/A-B-C labels/counts;
- deterministic relaunch in a fresh UI-testing process;
- Settings gallery push and isolated navigation path after tab round-trip;
- genuine loading/empty/error/fatal states and real transitions.

### 9.4 Screenshot/review matrix

At minimum export canonical attachments for:

- all five loaded roots in light and dark;
- bootstrap or Training loading;
- genuine empty;
- retryable error;
- fatal configuration;
- Settings gallery push;
- Settings tab round-trip/path isolation.

Update `.github/workflows/ios.yml` export mapping so missing canonical attachments fail CI. Download and visually inspect every canonical PNG for Turkish text, light/dark styling, four-phase/A-B-C order, no clipping/ellipsis/placeholder/fake action, honest persistence wording, and route isolation.

Final M0.8 gates:

- exact final SHA on both remotes;
- exactly one M0.8 commit over `cdc20a4` with subject `feat(app): add five-tab foundation shell`;
- full Local/Release/export/Cloud GREEN;
- no `ModelContext` or `import SwiftData` in feature views/ViewModels;
- no M0.8 DesignSystem production-source changes;
- valid catalogs and no mojibake;
- fresh full-task Codex review with zero Critical/Important;
- Claude Fable 5 medium implementation/design-fidelity review with zero Critical/Important.

## 10. M0.9 and M0 acceptance

After M0.8 closes, execute Task M0.9 from the tracked implementation plan using its own commit:

- exact subject: `test: add M0 acceptance gates and setup guide`
- accessibility smoke at large content sizes across all tabs
- VoiceOver-facing identifiers/labels/values/hints
- localization and requirements verification scripts with failing fixtures first
- novice README for Xcode/XcodeGen/Local/device/Cloud limitations
- `docs/evidence/M0/acceptance.md` with exact tools, test counts, hashes, Actions links, Fable verdicts, and honest `NOT RUN` device-only entries
- full clean-clone/bootstrap-twice verification
- Local Debug tests, Local Release, Cloud compile-only
- secret/TODO/placeholder/scope checks
- final full-M0 Fable review and correction loop

Cloud compile is not proof that Cloud synchronization works. Do not claim TestFlight, live Cloud sync, notifications, or HealthKit are complete at M0.

When M0 is accepted, continue the tracked product roadmap milestone by milestone. Each new milestone begins with brainstorming and a detailed implementation plan.

## 11. Verification and evidence discipline

The CI workflow is `.github/workflows/ios.yml` and runs on `macos-15` with Xcode 16.4.

On macOS, use the repository scripts directly. On Windows, do not claim local Swift/Xcode verification; use Windows-safe static checks plus exact-SHA GitHub Actions.

Useful commands:

```bash
git diff --check
git status --short
git rev-list --count cdc20a4562282fbdfe3033d988e916d0b9906183..HEAD
git log --oneline --decorate -5
gh run list --workflow ios.yml --branch feat/m0-foundation --limit 5
gh run view <run-id> --json status,conclusion,jobs,url,headSha
```

Leakage checks must distinguish approved persistence/composition locations from forbidden feature UI locations. Do not use a broad match as a substitute for inspection.

For every RED/GREEN pair, record:

- exact SHA;
- changed files;
- run and job IDs/URLs;
- exact qualifying failure or test counts;
- Release/export/Cloud gate results;
- artifact ID/hash when screenshots exist;
- HEAD/origin/gitea equality and clean-tree result;
- independent review verdict and finding disposition.

## 12. Known pitfalls

- `.superpowers/sdd/...` was a local ignored execution ledger and is not required on the next computer. Its binding M0.8 decisions are embedded in this document.
- Generated `.xcodeproj` files are disposable and ignored. `project.yml` is authoritative.
- Do not treat an infrastructure/billing/zero-step Actions failure as RED.
- Swift/Objective-C bridging can make numeric `NSNumber` values look Boolean; the environment parser must reject numeric config values explicitly.
- Local mode must not eagerly read or validate the Cloud container identifier.
- UI-test injection must exercise real load/retry behavior, not direct state assignment.
- App bootstrap loading and fatal configuration are app-local. Do not expand DesignSystem to implement them.
- The `Yakında` badge uses the existing `.info` style; do not add a neutral style or raw color.
- Technical `localizedDescription` values are never user-visible.
- Keep Turkish UTF-8 correct. PowerShell's default display can appear mojibaked even when bytes are valid; validate the catalog JSON and file encoding rather than trusting console rendering alone.
- Do not silently fall back from invalid Cloud configuration to local or in-memory storage.

## 13. First autonomous actions on the next computer

1. Clone/configure both remotes and switch to `feat/m0-foundation`.
2. Verify clean tree and equal branch tips on GitHub/Gitea.
3. Read the requirement, design spec, roadmap, M0 implementation plan, and this handoff completely.
4. Create/update an execution plan with M0.8c RED as the only in-progress step.
5. Use a test-first implementer for the hosted AppEnvironment/bootstrap tests in section 7.
6. Push the test-only amended commit to both remotes and wait for a qualifying hosted-test RED.
7. Continue through GREEN, independent review, and fresh re-review.
8. Repeat for M0.8d, then M0.9, then the next roadmap milestone.

Do not mark the overall goal complete merely because M0 or this handoff is complete. The goal is complete only when the scope in the user's goal and the full requirement document has genuinely been delivered and verified.
