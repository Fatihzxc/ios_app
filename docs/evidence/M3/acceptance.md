# M3 acceptance evidence

Status: **M3.1–M3.12 repository, simulator, accessibility, privacy, and integration acceptance is GREEN at the immutable implementation candidate below. Physical-device and live-service claims remain explicitly NOT RUN.**

Accepted M3.12 implementation SHA: `88ceee1a58db6f8447155996ae62194fa837a8fe`

This record separates repository/simulator evidence from hardware and service evidence. A Cloud scheme compile, protocol fake, simulator screenshot, or notification planning test is not represented as proof of signed CloudKit transfer, a delivered system notification, a real photo selection, or physical-device behavior. The evidence-containing successor cannot name its own immutable SHA and hosted run without changing itself, so those finalization records remain external in GitHub Actions and the handoff.

## RED/GREEN task history

| Task | Hosted RED checkpoint | Accepted implementation checkpoint | Result represented here |
| --- | --- | --- | --- |
| M3.1 | `4d80eaee5a990b0a25eef5c9bdf14d6d099f72f3` · [run 32988601800](https://github.com/Fatihzxc/ios_app/actions/runs/32988601800) | `5812d374191915c22b1af993509a68f098b1f9cd` · [run 32989037363](https://github.com/Fatihzxc/ios_app/actions/runs/32989037363) | shared quick-entry state, validation, retry, undo, and accessible form contract |
| M3.2 | `bc4e3892f20a9a06316d9879b6abdc1a83c77fa4` · [run 32994474546](https://github.com/Fatihzxc/ios_app/actions/runs/32994474546) | `003595dd27c0b188f67158034f032bad0a62ff67` · [run 33021809750](https://github.com/Fatihzxc/ios_app/actions/runs/33021809750) | body metric repository, custom metric validation, one-screen entry, and Progress accessibility |
| M3.3 | `3fe808ae68078c4d62ae1b5366de8f50979d2efe` · [run 33025441330](https://github.com/Fatihzxc/ios_app/actions/runs/33025441330) | `adb50bc2809aae8cae241c901be6fe48da7eba92` · [run 33030819661](https://github.com/Fatihzxc/ios_app/actions/runs/33030819661) | same-local-day sleep and mood upsert with combined persistence |
| M3.4 | `5f03f3b4b4be9ab5abe2483c87a1e8b563eae747` · [run 33033823761](https://github.com/Fatihzxc/ios_app/actions/runs/33033823761) | `a17320876039e1faba361530dd00bfbc895d804c` · [run 33035632245](https://github.com/Fatihzxc/ios_app/actions/runs/33035632245) | posture, symptom journal, weekly entry, and stable Training event adapter |
| M3.5 | `74ec8bd76902b984b225379c266255f696e0da7c` · [run 33038731657](https://github.com/Fatihzxc/ios_app/actions/runs/33038731657) | `d63c0936a4d5396eacc64a1f9edcf4ab023312b5` · [run 33045141360](https://github.com/Fatihzxc/ios_app/actions/runs/33045141360) | calendar recurrence, due/pending/done states, successor creation, and permanent disclaimer |
| M3.6 | `320bac39208bcace30c4edaa75a4d53350660f8b` · [run 33044431242](https://github.com/Fatihzxc/ios_app/actions/runs/33044431242) | `79fc4335c93353751e532d615925120d7dfd57ea` · [run 33045177687](https://github.com/Fatihzxc/ios_app/actions/runs/33045177687) | exact bloodwork retries and 27/27 targeted HealthChecksKit tests passed; that workflow later failed in the broader suite, and final descendant run `33167202851` closes the full-suite record |
| M3.7 | `bd7422e9c7e93e828e2a81939865c91f03b4641d` · [run 33045010872](https://github.com/Fatihzxc/ios_app/actions/runs/33045010872) | `b1daa194c8b95268db79f832f84cfb2309118335` · [run 33049507882](https://github.com/Fatihzxc/ios_app/actions/runs/33049507882) | targeted local photo lifecycle passed before a superseding cancellation; final descendant run `33167202851` covers the complete path |
| M3.8 | `d0341b0a4190122891d9b247f4aaafad0428510b` · [run 33046023389](https://github.com/Fatihzxc/ios_app/actions/runs/33046023389) | `11cf02fec62207e37c9a2676a047e53a7a1c8e9e` · [run 33053054146](https://github.com/Fatihzxc/ios_app/actions/runs/33053054146) | targeted M3.7–M3.8 lifecycle/gallery suite passed before cancellation; final descendant run closes the full matrix |
| M3.9 | `273c475bfe7ab3bbb9d9b2e21353d89ffeea4a66` · [run 33050957974](https://github.com/Fatihzxc/ios_app/actions/runs/33050957974) | `85f596086065ed3c6e31c4c4eff45e34ebd37341` · [run 33090535166](https://github.com/Fatihzxc/ios_app/actions/runs/33090535166) | private-zone asset adapter, retry/backoff, cleanup, account change, token, and backfill contracts |
| M3.10 | `e923100899baa24f51931ba8d744357a81036a96` · [run 33052582351](https://github.com/Fatihzxc/ios_app/actions/runs/33052582351) | `7a2c6a68cf8c51dc21e95248706615c432ca1ac7` · [run 33114617946](https://github.com/Fatihzxc/ios_app/actions/runs/33114617946) | all four exact M3.10 targeted safety steps passed before a superseding cancellation; final descendant run closes the complete suite |
| M3.11 | `53e20e0b7d4b5d143cb597336d8a3de4be43cd64` · [run 33114622155](https://github.com/Fatihzxc/ios_app/actions/runs/33114622155) | product `2e021ffadfebcd7c3799994998d0fbc49e94862c`; integration hotfix `4161683b113366933622c8314f47e9b2a562002a` · [run 33135636945](https://github.com/Fatihzxc/ios_app/actions/runs/33135636945) | notification authorization, planning, reconciliation, routing, explicit UI permission, and bounded cleanup suspension |
| M3.12 | `14b8babe49027a6fbc26bf7004aa0c1278171396` · [run 33124715263](https://github.com/Fatihzxc/ios_app/actions/runs/33124715263) | `88ceee1a58db6f8447155996ae62194fa837a8fe` · [run 33167202851](https://github.com/Fatihzxc/ios_app/actions/runs/33167202851) | one lazy router, all Progress/Today routes, same-day edit/relaunch, picker access policy, AX matrix, screenshots, and privacy gate |

The M3.8–M3.10 original hosted RED branch runs stopped at an earlier inherited M3.6 targeted gate and are not mislabeled here as isolated behavior failures. Their task tests were frozen locally, their exact implementation checkpoints passed the named targeted steps where recorded, and the immutable final descendant exercised the integrated result. M3.6–M3.8 and M3.10 therefore retain both the exact intermediate workflow outcome and the later full GREEN instead of rewriting cancelled or broader-suite-failing runs as successes.

The evidence requirement itself was developed test-first. Commit `ff783a834a4f2d27e3b7aff736928e5092f5705b`, [run 33180587182](https://github.com/Fatihzxc/ios_app/actions/runs/33180587182), passed both qualifying behavior gates and every verifier self-test, then failed main job `98880490080` only with `Missing M3 acceptance evidence: docs/evidence/M3/acceptance.md`. Its cold-launch job `98880489850` and small-phone job `98880489984` remained GREEN.

## Final GitHub Actions run

- Final implementation run: [33167202851](https://github.com/Fatihzxc/ios_app/actions/runs/33167202851), attempt `1`, conclusion `success`.
- Main job: [98835340310](https://github.com/Fatihzxc/ios_app/actions/runs/33167202851/job/98835340310), conclusion `success`.
- Small-phone job: [98835340450](https://github.com/Fatihzxc/ios_app/actions/runs/33167202851/job/98835340450), conclusion `success`.
- Cold-launch job: [98835340564](https://github.com/Fatihzxc/ios_app/actions/runs/33167202851/job/98835340564), conclusion `success`.
- Hosted tools: Xcode `16.4` build `16F6`, XcodeGen `2.46.0`, iPhone 16 Pro simulator on iOS `18.5`; the compact job used the dedicated small-phone destination.
- Fresh-clone bootstrap passed twice for the accepted SHA with generated-project SHA-256 `13037c116f08931456b514549b6a51eff769491f6689cf5f62292b146dc9097c` and a clean tracked tree.
- Cloud scheme compile-only and repository hygiene passed. Compile-only remains configuration evidence, not synchronization evidence.

The full functional suite executed 839 tests with zero failures: HealthTrackingAppTests 70; HealthTrackingAppUITests 72 with two intentional skips; CoreModels 46; GuidanceKit 80; PersistenceKit 196; TrainingKit 112; DesignSystem 26; NutritionKit 66; HealthSafetyKit 5; HealthChecksKit 27; NotificationsKit 27; ProgressPhotosKit 82; MetricsKit 22; SleepMoodKit 8.

Before the full suite, the final run also passed these isolated gates: cleanup suspension regression; NotificationsKit 27/27; M3.12 acceptance UI 2/2; M3 accessibility 4 executed with the dedicated small-phone-only case skipped in the main job; HealthChecksKit 27/27; ProgressPhotosKit 82/82; HealthSafetyKit 5/5; DesignSystem 26/26; TrainingKit 112/112; app safety 70/70; notification composition 22/22; explicit notification permission UI 1/1. The small-phone job separately executed the compact AX5 route and exported its screenshot.

### Cold launch

The unchanged threshold was median `≤ 1.0 s`. Five fixed, isolated, new-process samples were `0.236809`, `0.185535`, `0.268405`, `0.198151`, and `0.157884` seconds; median `0.198151 s`. The raw JSON reports five unmeasured stabilization launches, `ProcessInfo.systemUptime`, start `HealthTrackingApp.init`, and end `TodayViewModel first content publication`. Its decompressed SHA-256 is `3eec16a37a9726b8044a909c96af74793d4d4a05862859c6c45ecc873756a5db`.

## Screenshot and artifact evidence

| Artifact | API size | Extracted-tree SHA-256 | Contents |
| --- | ---: | --- | --- |
| `9689212849` · `HealthTrackingApp-xcresult` | 122,960,240 bytes | `d63a85f11c5fc6536c99913e139e3e637e680f04ba48e323bc0e1640ee05cfe7` | full XCResult, 55 attachment records, canonical gallery |
| `9684192968` · `HealthTrackingApp-small-phone-xcresult` | 1,771,898 bytes | `ab65281477dc0b54c2e7cbdbd6b256089bcbbd8470185250e52cea941c8bbc8d` | compact AX5 XCResult and two canonical screenshots |
| `9684190776` · `HealthTrackingApp-cold-launch-xcresult` | 258,937 bytes | `760bc953aee194145c4a1290041c14e105bc77b2d5d6ae9f26cb1d66d73e7410` | cold-launch XCResult and raw phase evidence |

The main gallery manifest SHA-256 values are `76b9ce67d11b4fa28e5f32014b4e459006d2332fa467713f42345f96b7e06222` for JSON and `c61321832c2b6d4b17940f5016c41545551e8a70092d54164e1f4e99e789c48b` for TSV. The exporter produced exactly 33 expected M3 canonical names at `1206×2622`; the compact artifact adds `m3-progress-small-ax5` at `750×1334`. The compact manifest SHA-256 is `40b48a81eafedb58825482f93390807733c7f20edccd0964d3ccbaa95794967b`.

All 34 M3 images were reviewed in three contact sheets. The default, dark, XXL, AX3, AX5, Reduce Motion, high-contrast, lifecycle, gallery, US6, US8, and small-phone states rendered as the expected bounded-scroll simulator views without modal overlap or a missing action. `m3-posture-entry-dark` and `m3-posture-high-contrast` intentionally have the same pixel hash; their owner/name records remain distinct and the high-contrast route was independently exercised. No content-uniqueness claim is made for that pair.

| Canonical screenshot | SHA-256 |
| --- | --- |
| `m3-acceptance-us6-progress-light` | `c98ce25d6038c56d12f65d350f2d98b967c4bf0478ba76d7417047fb7ddab069` |
| `m3-acceptance-us8-today-light` | `e6b263efa8dfa0952966732f1dd32c82b79416726c5a64de37da1942b235292b` |
| `m3-bloodwork-detail-light` | `433a5a4e44e7c3494d07ab24999fa3bcd4b8ece53de14112890c8a3857d7cf4d` |
| `m3-bloodwork-editor-ax5` | `63bf5d34b63da8a3784036dd86fea4a6072144789154b687a854a44cc92e8b6f` |
| `m3-bloodwork-editor-dark-high-contrast` | `e2152aa571788266d8c84b56274ecb0ab70a42aaadd640b2bb114185ac55ec02` |
| `m3-bloodwork-empty-light` | `2f01393f53b7a4fd806081e73d51e268fa85318cd732f72c8e18421d1aa2dd79` |
| `m3-health-check-completed-light` | `65474d735dbb8d320179b251f9ffd1923e6a865b398ad550290e16d6d61eca4e` |
| `m3-health-check-detail-ax5` | `0bbb2fe40342d0e12b3065ba388e2ee8297f52de3535d1888f7cf0e6ac68f2ef` |
| `m3-health-check-progress-light` | `b06d59cf06b129a223189e8d1b2e78797f7700821eca37df527bf60bbd49daf3` |
| `m3-lifestyle-combined-light` | `ec029af1a1c48126fb9fe84f506490d0dec4046dcb7b2299433a3d30fc705caf` |
| `m3-lifestyle-entry-ax5` | `613bbfb128ca49c1e23e66e147abfa4e5c171e06e39b3bc4cd2e7df9f42e3cb7` |
| `m3-lifestyle-entry-dark` | `923c70ff71a374915a0ac4e97fc00cbf7166ca1fe30c241a9f00eee748e2efdb` |
| `m3-lifestyle-progress-light` | `6509a51c3d7506a561c8515480dcc215ebf347c10fe4b059a2d6ea9fe62da9ac` |
| `m3-metrics-entry-ax5` | `cdc9303d997ac7757a0713353d6448bb4f1286959a9366d5632f11270685c405` |
| `m3-metrics-entry-dark` | `ef1df72086971c40edefc0ee6628a94c35d46a8cb494ea3aa59ea0dbadf686d2` |
| `m3-metrics-progress-light` | `050f1a6765b612e940bb42e6f59aa2438c073691f54ee7750141fc176f78cc51` |
| `m3-photo-gallery-light` | `ae8bf5df2cf4ae22af812601b8126e2f03a16799201dfee555eb455836cf3cd1` |
| `m3-photo-local-lifecycle-light` | `0464b833dc27a21602d8571e09b1208d34bd906c18c20bdf34fff4ef02c5e016` |
| `m3-posture-entry-ax5` | `73c051c048441851ef5a661cf1168d1a1fc178b7f6b6e2c250fff5077a921958` |
| `m3-posture-entry-dark` | `2edcd224ef785271a6fc2acfa191b295d5a44099e1809711f2009c94275c7e6e` |
| `m3-posture-entry-light` | `0539d1a8caeb2d736c8e683edb02d84e094c145b0aa3b2eebf6ee195fb0306a1` |
| `m3-posture-high-contrast` | `2edcd224ef785271a6fc2acfa191b295d5a44099e1809711f2009c94275c7e6e` |
| `m3-posture-progress-light` | `038183d679284667867fd31868f772a37e876e713070cb2f58c93b0e610cc92d` |
| `m3-progress-dark-ax3` | `f1da66bb68047f1fa5e023ceb298a525aab7f437566e9448ef8a0e70116d0094` |
| `m3-progress-dark-ax5` | `08b23d5fb8a9191fa5ebdab96ca75cf0691d876ec71f8355cd44103eebee7523` |
| `m3-progress-dark-default` | `889fdf44730436804a8d8fb55fc434d7959946a8ca6a65afed0538e4a0f65974` |
| `m3-progress-dark-xxl` | `519a42b70e21f8fc6fd3268a8802b44110e55a2985d8097e1e4d939731f50bff` |
| `m3-progress-high-contrast` | `86c6ff622caf987616d3566bf2a23b964a7731de8e057725825d0a732a75f5b5` |
| `m3-progress-light-ax3` | `abc3f047126c4faade7c6898bc6dbd29662a813abe6db9f245328075972b918f` |
| `m3-progress-light-ax5` | `c513cea54de2090fb7a192b74d160b8cd6144be54978eecfc9f06b7168e5c138` |
| `m3-progress-light-default` | `c5d6b27fd25c271d3606c6e0ceceea148f0966d071534507d6ec97085f659b2d` |
| `m3-progress-light-xxl` | `3c071c1f63f7bcd9f8d1408659110f434510abe7fcd8b3bbd48e2e70ea092a02` |
| `m3-progress-reduce-motion` | `cdddbff90f17e70210ba09743eff0ab13c909afdac6ced98cdd3d8acc728bd9b` |
| `m3-progress-small-ax5` | `1a7a3ea98210eca39d08dc3ce399ac20fa8e45a10d791a50424e0b03faf7b00d` |

## Privacy scan

- Privacy scan: PASS
- The accepted verifier scanned M3 persistence repositories, tracker feature sources, Training session sources, notification composition, and photo code after stripping comments and string/regex literals. It rejected executable `print`, `debugPrint`, `NSLog`, `os_log`, `Logger`, analytics, and telemetry tokens.
- Repository hygiene and the static privacy gate passed in the final run. Protocol-fake CloudKit and notification tests use deterministic non-production payloads; no simulator result is elevated to a live-service claim.

## Review record

- Critical: 0; Important: 0; Minor: 0; verdict: READY
- Independent exact-tree review covered accepted implementation SHA `88ceee1a58db6f8447155996ae62194fa837a8fe`, including the final custom body-metric accessibility binding and the fail-closed verifier mutations.
- Fable review: NOT RUN

Fable capability was not exposed in this environment, so no Fable approval is implied. The contact-sheet review described above is a manual artifact inspection, not a physical-device accessibility audit.

## Remote record

Before the evidence checkpoint, the clean local branch and GitHub `test/m3.12-integration-acceptance-red` both resolved exactly to accepted implementation SHA `88ceee1a58db6f8447155996ae62194fa837a8fe`. The evidence RED was then pushed with an exact lease and GitHub resolved the branch to `ff783a834a4f2d27e3b7aff736928e5092f5705b` for run `33180587182`.

A bounded read-only Gitea check on 2026-08-28 returned `No route to host` for `192.168.10.12:3000`. Per the non-blocking remote policy, no unknown Gitea state was overwritten and GitHub evidence work continued. The evidence-containing successor, its hosted GREEN, the preserved milestone branch, and the later `main` merge are external completion records because this file cannot contain its own future commit identity.

## Device and external-service limits

The following remain honest repository-only limits:

- CloudKit signed two-device transfer: NOT RUN
- Real notification delivery: NOT RUN
- Physical iPhone installation, launch, haptic feel, VoiceOver audio, Switch Control, and Personal Team renewal: NOT RUN / BLOCKED
- Paid-team CloudKit container provisioning, account changes against a live private database, and production/development environment transfer: NOT RUN / BLOCKED
- Real Photos picker selection and broader-library permission prompt automation: NOT RUN by design
- TestFlight upload, processing, invitation, installation, and launch: NOT RUN / BLOCKED
- HealthKit authorization and live data exchange: NOT RUN / BLOCKED
