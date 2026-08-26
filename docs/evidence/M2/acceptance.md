# M2 acceptance evidence

Status: **M2.1–M2.8 have accepted exact-SHA hosted GREEN evidence. The evidence-containing successor and the later `main` merge are verified externally because a commit cannot contain its own immutable SHA and run.**

This record distinguishes repository and simulator evidence from physical-device or service evidence. A Cloud-scheme compile is not CloudKit synchronization proof, and simulator screenshots are not physical-device proof.

## RED/GREEN task history

| Task | Qualifying RED | Accepted implementation | Result |
| --- | --- | --- | --- |
| M2.1 | `f9f3864fb57ccc9ca8eb050979eb71e9bbe35da7` · [run 32493069600](https://github.com/Fatihzxc/ios_app/actions/runs/32493069600), job `96805025192` | `d393b1d02d2e75f2e271ab749490c1f88be811f9` · [run 32493229012](https://github.com/Fatihzxc/ios_app/actions/runs/32493229012), job `96805538661` | local-day repository contracts |
| M2.2 | `5ff09fa09945b9dc2bbf4048e59857225b5074c6` · [run 32497506089](https://github.com/Fatihzxc/ios_app/actions/runs/32497506089), job `96819313097` | `a800ea6522f1b34e2a6a29ff919b5d4114109ae9` · [run 32502055737](https://github.com/Fatihzxc/ios_app/actions/runs/32502055737), job `96833774611` | decimal macros and optional targets |
| M2.3 | `2e19e0308947631a0966bffacf425ec131ef2210` · [run 32506028901](https://github.com/Fatihzxc/ios_app/actions/runs/32506028901), job `96846268408` | `e1e20fba71439cd7304bd4bcffb2ad92b1eb3dd2` · [run 32506641618](https://github.com/Fatihzxc/ios_app/actions/runs/32506641618), job `96873090842`; isolation successor `d88de88d03ae4ba7d9cf7810c83c04047992c8c0` · [run 32515129183](https://github.com/Fatihzxc/ios_app/actions/runs/32515129183) | food library and module isolation |
| M2.4 | `9869ebf3c879160d2be137f0fd7f42072f263208` · [run 32519024131](https://github.com/Fatihzxc/ios_app/actions/runs/32519024131), job `96886958298` | `79eb6b3f7b7b7b47d42a67b08916f72c431ac487` · [run 32520030748](https://github.com/Fatihzxc/ios_app/actions/runs/32520030748), job `96890019110` | recipe archive and restore |
| M2.5 | `c73ba8c3327a6a19e3381c482307ac7878a77a53` · [run 32524174611](https://github.com/Fatihzxc/ios_app/actions/runs/32524174611), job `96902623674` | `1f0387e8a693fa60bea50b3e502d0259b89cd977` · [run 32524733768](https://github.com/Fatihzxc/ios_app/actions/runs/32524733768), job `96920372226` | immutable meal snapshots |
| M2.6 | `bfa2e7156a3bcd02dee7f3857b503695f6cbd084` · [run 32531093988](https://github.com/Fatihzxc/ios_app/actions/runs/32531093988), job `96923085834` | `64e3db5b67f564755b2120879d4517e3e3304a11` · [run 32539033479](https://github.com/Fatihzxc/ios_app/actions/runs/32539033479), job `96945173844` | day UI and accessibility |
| M2.7 | `85085719081669fe66f0e27bce517a5c14fc5430` · [run 32541790786](https://github.com/Fatihzxc/ios_app/actions/runs/32541790786), job `96953075583` | `bc5e7bbf8977f3de08d30e923830be9527b5db0b` · [run 32545895755](https://github.com/Fatihzxc/ios_app/actions/runs/32545895755), jobs `96964129348` / `96964129202` / `96964129382` | exactly-three-tap quick add |
| M2.8 | `cc10412e336853236c9b8fffb2f940af4cae376e` · [run 32546213463](https://github.com/Fatihzxc/ios_app/actions/runs/32546213463), job `96964999687` | `81e22545d77158a2f8f14f59afde5076abf8272c` · [run 32961962686](https://github.com/Fatihzxc/ios_app/actions/runs/32961962686) | end-to-end acceptance, manual entry, accessibility, artifacts and audit |

M2.4 candidate `37f4257204b062db12d54cb99eb2b814eb1de2bd` was non-qualifying because its failure was test syntax rather than missing product behavior. M2.8 candidate `4ef396de8936862984b05385369b83b062b84fb5` exposed duplicate element queries and keyboard reachability; candidate `3fc42269b18225ad64da5b6e1a1fc785bbb4e792` proved that correction, then exposed one remaining generic category query and an Apple accessibility-audit timeout. Neither is labeled GREEN.

The evidence gate itself also used TDD. Test-only SHA `8b0df87117cbec13a09ccca081b86e301aa1b1b2`, [run 32967950861](https://github.com/Fatihzxc/ios_app/actions/runs/32967950861), job `98174671196`, failed at the static gate with `M2 evidence file is required`; the expensive sibling jobs were cancelled after the qualifying RED was captured. The production verifier now requires this file and retains its malformed-evidence mutation.

## Final GitHub Actions run

- Accepted exact SHA: `81e22545d77158a2f8f14f59afde5076abf8272c`
- Final GitHub Actions run: [32961962686](https://github.com/Fatihzxc/ios_app/actions/runs/32961962686), final conclusion `success`, attempt `2`
- Main job: `98156064399`, Xcode `16.4` build `16F6`, iPhone 16 Pro simulator on iOS `18.5`
- Small-phone job: `98156064107`, iPhone SE (3rd generation) simulator on iOS `18.5`
- Cold-launch jobs: attempt 1 `98156064331` retained as a real threshold failure; unchanged-SHA attempt 2 `98171975310` passed
- Main gates: M0/M1/M2 static gates, fresh-clone bootstrap, targeted app tests, full Debug and Release testing, screenshot export, Cloud scheme compile-only and repository hygiene all passed

The targeted app suite executed 38 tests with zero failures. The full run executed 493 tests: app 38; UI 48 with one intentional skip; CoreModels 46; GuidanceKit 80; PersistenceKit 121; TrainingKit 81; DesignSystem 13; NutritionKit 66. The two `M2AcceptanceUITests` and all three `NutritionAccessibilityUITests` passed. Recipe creation/archive/restore/relaunch and mixed food/ad-hoc deletion/relaunch therefore have hosted UI evidence, in addition to unit and persistence coverage.

## Cold launch

The threshold remained exactly `median ≤ 1.0 s`; neither code nor threshold changed between attempts. Attempt 1 honestly failed with samples `1.604273`, `1.162186`, `1.238844`, `1.129528`, `1.043737` seconds and median `1.162186 s`. The same exact SHA reran only the failed path and passed with samples `0.678567`, `1.189641`, `0.742053`, `0.807891`, `0.901799` seconds and median `0.807891 s`.

The successful raw phase medians were environment `0.001847 s`, container `0.088348 s`, dependencies `0.669528 s`, seed `0.683124 s`, and first Today content `0.807891 s`. Artifact `9606257726` is `201,788` bytes; its downloaded archive SHA-256 is `600fe5f867dadfd1316e4b8532a4578d5a869e8967e75d6c929b89c588385614`, extracted-tree digest `f041cec74c4237b01b3d26810e44b11fcaba195c23b8304fedc65c0f54609bba`, and raw JSON SHA-256 `5f7dd4e7d992fce244432c4ea1a1031bd41c0ec2462016877d1e827e858ead3d`.

## Screenshot review

Main artifact `9606057866` (`81,394,747` bytes) contains the XCResult and screenshot export. `manifest.tsv` contains 73 unique canonical names, every target exists, and no canonical hash is duplicated. The gallery tree digest is `6ae5d98d4a65f4127246e9215c0643a3c236691493427a34c9eb2f33d37e524a`; manifest SHA-256 values are `488ad42ab63febd49401d60837a76993bb84fadfb354153a1464625ba93a2baf` for JSON and `32323e2f39d6c8ff911593112b1778e8f5885300f6af22d746287d84058dc9e6` for TSV.

All 15 M2 canonical images are `1206×2622`, have distinct hashes, and were visually reviewed:

| Screenshot | SHA-256 |
| --- | --- |
| `nutrition-day-content-light` | `24d3584c846f63a6299c669c146ea10ad83d4884ae826551c754919017d43343` |
| `nutrition-day-empty-light` | `69b84feed94972e65be21512d7fab287d38f2cd4987a7ec367f03cf8da69f909` |
| `nutrition-day-error-dark` | `66bece1ed886119dbe931332638bed120ec09aaede1169509ee04313fe1248a6` |
| `nutrition-day-content-dark` | `2d0e57f06b14a9cd0b52439667464efc0c9ddb2905be91883420884e311ce965` |
| `nutrition-day-content-ax5` | `193ca8f11e8a0d63c278c95ac45f755571c73fac811361c4961c3f3bb70b5f47` |
| `nutrition-day-reduce-motion-light` | `2a224719eeae4d27b9a6abb46bbec8edda2d42769983878afee80bce33b0bb2c` |
| `nutrition-day-high-contrast-dark` | `153af413a2bc0e6c4f96bb31eb2dac9f071ea3b4ee59c3fb1c1b0231aa35f3e8` |
| `nutrition-quick-add-saved-light` | `0cfcd81adaa984d4c7a191b55c9f4acc184c9e6fd0393d0b207357a0e3147815` |
| `nutrition-quick-add-select-dark` | `bd5e14bc6f2b6cf547c3532b94514dc1072fc08646347a50eaf2dcbd87a89a5b` |
| `nutrition-quick-add-confirm-ax5` | `78d45341b2acf6fe9ca677764235d19da78741fe940607240fe384bcd85a4040` |
| `m2-acceptance-recipe-history` | `137023f0329156bc0696ef75739244fac52adde90316133ca660e411264369f2` |
| `m2-acceptance-mixed-sources` | `aad6bbb6f61f1190f863cc8a9eeb2b8d4ebc75d8108e64957db097ed8efccc88` |
| `m2-nutrition-ax5-adhoc` | `ffce85b12d49fbc5bc58be227fb633af7e84014d9244ca8f5c48a7c7bd8edbad` |
| `m2-nutrition-dark-high-contrast-food` | `056571ab7b03925df42298188528c69ad25fd36188e89ac2a27b2447f89b08b3` |
| `m2-nutrition-reduce-motion` | `d6d184154bfac1faa2f75bd4a7617a99363e389c9bd303c810b7c6cc773de975` |

The review found no clipped labels or controls, modal overlap, broken dark/high-contrast presentation, or AX5 operability regression. The formerly clipped empty-state card is complete. The recipe-history image shows retained totals after archive/restore/relaunch; the mixed-source image shows historical food snapshot totals after source deletion alongside the ad-hoc entry.

Small-phone artifact `9604403217` (`810,518` bytes) passed its one AX5 test. Its named `750×1334` screenshot SHA-256 is `957a63ee0116ea2a631b1071ea6977edc7fda08af849d9ff12e4153b5c68b785`, manifest SHA-256 `9c204310e8c67b846b15d994edfb0b75c56110c46807bc64d060f229a2d1b61c`, and extracted-tree digest `4b1b4f66ea4ad24894dd03fd004058b8921e5cc0e7c2749677433493f77d906b`. Visual review confirmed the complete Turkish performed-variant label, empty input and operable save flow.

## Acceptance matrix

| Gate | Evidence status |
| --- | --- |
| Food, recipe and ad-hoc CRUD plus relaunch | GREEN: M2 UI, unit and persistence tests |
| Saved recipe in at most three taps | GREEN: M2.7 and final M2.8 full suite |
| Snapshot immutability after edit/archive/delete | GREEN: hosted UI plus persistence tests |
| One logical local-day record and DST boundaries | GREEN |
| Optional targets and immediate canonical totals | GREEN |
| VoiceOver audits, AX5, Reduce Motion, high contrast and small phone | GREEN on simulators; physical-device ergonomics NOT RUN |
| Cold-launch median `≤1.0 s` | GREEN on unchanged-SHA rerun; first failed sample retained above |
| Fresh clone, Release, Cloud compile-only and hygiene | GREEN; compile-only is not synchronization proof |

## Privacy/log scan

The accepted tree and hosted static gate report no `SwiftData` or `TrainingKit` import inside NutritionKit, no reverse TrainingKit-to-NutritionKit import, no fixed 24-hour day math and no non-injected `Calendar.current` in nutrition code. A production-source scan found no `Logger`, `os_log`, `print`, `debugPrint`, `NSLog`, analytics, telemetry, `URLSession`, barcode/camera, `RecipeItem`, or HealthKit expansion. No health or personal payload logging claim is inferred from test output.

## Review and remote record

No unresolved Critical or Important issue remained after log and artifact review. Fable review is `NOT RUN`: no Fable capability was exposed in this environment, so no result is implied.

GitHub preserved the milestone branch and matched accepted SHA `81e22545d77158a2f8f14f59afde5076abf8272c` before the evidence TDD successor. A bounded Gitea check on 2026-08-26 succeeded, but Gitea was stale at `main` `7623b684ccf46a8ba401dfbc9bd07173ae7a1e88` and `feat/m2-nutrition` `5a56b55b0f3ffdc163c2e5f17215d34b5cb65140`. Final branch reconciliation, the non-fast-forward milestone merge into `main`, and exact merge-SHA CI are external completion records performed after this evidence-containing commit; a later Gitea outage does not block GitHub completion.

## Device and external-service limits

Physical-device haptics, paid-team CloudKit synchronization, TestFlight, live notification delivery and HealthKit are NOT RUN for M2. They are not acceptance claims in this document.
