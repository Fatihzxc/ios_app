# M4 acceptance evidence

Immutable implementation acceptance: M4 repository and simulator contracts are GREEN at `f3b69a8a94dd052d527752e8e7f12dea81053412`. This is Stage A evidence, not a claim that M4 is already merged, M5 is complete, or the full product is ready for distribution. Physical-device and live-service checks remain NOT RUN.

The receipt below is the machine-checked historical record. Validation detects missing or inconsistent records; it does not authenticate GitHub or replace independent inspection of native results, actual attachments and pixels. Prose below explains the scope and historical failures.

## Immutable implementation receipt

```json
{
  "schema": "m4-acceptance-v1",
  "implementation_sha": "f3b69a8a94dd052d527752e8e7f12dea81053412",
  "run": 34580238289,
  "attempt": 1,
  "conclusion": "success",
  "jobs": {
    "full": [103201852919, "success"],
    "targeted_m4": [103201852997, "success"],
    "cold": [103201852621, "success"],
    "small": [103201852817, "success"]
  },
  "native_full": {"total": 1111, "success": 1108, "skipped": 3, "failure": 0, "warnings": 23},
  "small_success": 3,
  "targeted_native_success": 3,
  "artifact_ids": [10265060093, 10263997073, 10194309600, 10191864685, 10191506418],
  "zip": {
    "bytes": 60560,
    "sha256": "6d0fc968e87e18afaeb9152738a14423e3275c8856748953809a002382c84788",
    "manifest_sha256": "b41fa956e20de013e0a2abd18739e4f299fb6724f6315c56a8df302b9a10136c",
    "entries": 10,
    "verified_payloads": 9,
    "includes_photos": false
  },
  "m4_screenshots": 13,
  "cold_median_seconds": 0.13411,
  "cold_raw_sha256": "f51b43660d73dbc134aacffb78eb59b22f8190c024d37cf5a1c42967e3788cc5",
  "privacy_scan": "PASS",
  "evidence_review": "internal GPT-6 Astra/high; no new scoped findings",
  "physical": {
    "signed_two_device_cloudkit": "NOT RUN",
    "real_notification_delivery": "NOT RUN",
    "physical_photo_picker_share": "NOT RUN",
    "locked_device_file_protection": "NOT RUN",
    "voiceover_audio_graphs": "NOT RUN",
    "physical_performance": "NOT RUN",
    "testflight_distribution": "NOT RUN"
  },
  "prior_intermittent_root_causes": "UNRESOLVED",
  "successor_sha_and_run": "EXTERNAL SDD AND M5 HANDOFF"
}
```

## RED/GREEN task history

Each run link refers to the exact checkpoint in that cell. Initial static-contract and missing-type compiler failures are distinguished from discovered XCTest assertion failures; neither is mislabeled as runtime behavior proof. Historical tasks are not reopened by this recovery.

| Task | Initial RED checkpoint | Accepted task checkpoint | Evidence boundary |
| --- | --- | --- | --- |
| M4.0 | `2deec0aef11718a7e182b283d5fc3334ccf93a4c` · [33221143446](https://github.com/Fatihzxc/ios_app/actions/runs/33221143446) | `ea9a3c88ac3b0840c1d71e7cc00a5a83f1a62fc4` · [33225585439](https://github.com/Fatihzxc/ios_app/actions/runs/33225585439) | Planned static CI contract RED: missing full/focused guards and nonempty focused routing. |
| M4.1 | `639d86ab2186d65cd1035c8cf2c92130d6c003bc` · [33226937087](https://github.com/Fatihzxc/ios_app/actions/runs/33226937087) | `79ff95ffa66eebf23d2438c0ca9f097bd574b509` · [33232547025](https://github.com/Fatihzxc/ios_app/actions/runs/33232547025) | Missing ReportDateRange contract compiler RED; pure ranges/coverage. |
| M4.2 | `8f9698fee60bc29a18dfc6a4e781398d8d6300c7` · [33233551995](https://github.com/Fatihzxc/ios_app/actions/runs/33233551995) | `25183ed8fa1ff01144e89e4288aa6d7fdca77bbd` · [33238266652](https://github.com/Fatihzxc/ios_app/actions/runs/33238266652) | Initial static missing-production contract; body/strength dataset and repository. |
| M4.3 | `55c4db0f73b14dd20933756bf3eadd7e0a226a16` · [33239552531](https://github.com/Fatihzxc/ios_app/actions/runs/33239552531) | `89cf3f51f3a18c8b313d48190c41d66ae9445198` · [33242977994](https://github.com/Fatihzxc/ios_app/actions/runs/33242977994) | Initial static contract; observed protein denominator and target provenance. |
| M4.4 | `aa532efd5c577f68b584c07cce4471e1a3f3ae33` · [33243963360](https://github.com/Fatihzxc/ios_app/actions/runs/33243963360) | `992f4caeaa1c724cd166adefb2f2de88137479a9` · [33249527917](https://github.com/Fatihzxc/ios_app/actions/runs/33249527917) | Initial static contract; lifestyle gaps and partial phase history. |
| M4.5 | `50c8b0efd56f28f251ed713166be54b2b5c3fb20` · [33251466730](https://github.com/Fatihzxc/ios_app/actions/runs/33251466730) | `a4a91df4c41c83ffa9430ee4e06ad1b3d15ea477` · [33268123192](https://github.com/Fatihzxc/ios_app/actions/runs/33268123192) | Initial static contract; explicit private photo comparison share/cleanup. |
| M4.6 | `1d3bcb8f6287264e5debf1ebbdb94bea631c5db2` · [33270241061](https://github.com/Fatihzxc/ios_app/actions/runs/33270241061) | `4c8afdbb2cfd08bb32dabf8b869d018df913b46f` · [33276327655](https://github.com/Fatihzxc/ios_app/actions/runs/33276327655) | Initial static contract; versioned inventory and RFC4180 CSV. |
| M4.7 | `cd13b143da12056e3ab0bd74c208ff28bb271b66` · [33278085494](https://github.com/Fatihzxc/ios_app/actions/runs/33278085494) | `cd4cea187e8019f730b06108cac717483fbf3ebd` · [33533451542](https://github.com/Fatihzxc/ios_app/actions/runs/33533451542) | Initial static contract; JSON/ZIP/manifest/coordinator/export UI. |
| M4.8 | `05e7c246d834c5c02ba4bb8de9ffa73594ffa0ad` · [33539577741](https://github.com/Fatihzxc/ios_app/actions/runs/33539577741) | `5438485677acefb15926dfa6ec00b3d3dbcb1126` · [33577620838](https://github.com/Fatihzxc/ios_app/actions/runs/33577620838) | Missing ReportsDashboard compiler RED; final lifecycle correction supersedes earlier GREEN. |
| M4.9 | `3070351b113dd44302f631cb81448381bd88daad` · [33586939932](https://github.com/Fatihzxc/ios_app/actions/runs/33586939932) | `f3b69a8a94dd052d527752e8e7f12dea81053412` · [34580238289](https://github.com/Fatihzxc/ios_app/actions/runs/34580238289) | Five actual acceptance UI failures on required elements (677.641s), followed by integrated corrections below and final four-job GREEN. |

### Task review corrections and nonqualifying diagnostics

| Checkpoint | Observed result and final disposition |
| --- | --- |
| M4.2 `86b11aa6339f9240ea772d68d355e0b52f91cfbf` · [33237606733](https://github.com/Fatihzxc/ios_app/actions/runs/33237606733) | Actual repository assertions selected invalid session1752 rather than deterministic1751; accepted25183ed fixes this. Later `d7bf2471a69c907df3b58ef193eab7c6544e4465` /33238157252 missing `invalidSession` compile error is not behavior RED. |
| M4.3 `27091e335b0de4b7c8bde4e9dfd08d93a1ab6b23` · [33240288597](https://github.com/Fatihzxc/ios_app/actions/runs/33240288597) | Six builder passes; repository duplicate-local-day integrity assertions fail; final89cf3f5 accepted. |
| M4.4 `6d7de9e150c850e7dfe49791775d5a29f21411c3` · [33248974376](https://github.com/Fatihzxc/ios_app/actions/runs/33248974376) | Actual duplicate logical-group selection assertion fails; final992f4ca accepted. |
| M4.5 `9508950f4d63eb6b8fa58bb7a0c4f87d83c9dd35` · [33260931697](https://github.com/Fatihzxc/ios_app/actions/runs/33260931697) | Eight assertions across26 photo-share tests: released-store/coordinator cleanup, queued cancellation, fixed-ink caption wrapping; finala4a91df accepted. |
| M4.6 `3f52056e8202eabddf536e4849902cb1c375eb6f` · [33271492115](https://github.com/Fatihzxc/ios_app/actions/runs/33271492115) | Six schema passes then real exact CSV encoding assertion failure. Later `0378e71b37627245372acbbe5461074a097b6751` /33276113460 has async-autoclosure compiler errors, not three runtime failures; final4c8afdb accepted. |
| M4.7 `23eb8c41193085de5460fb89e82595e2157053f7` · [33524740234](https://github.com/Fatihzxc/ios_app/actions/runs/33524740234) | JSON4/ZIP22 passed; coordinator unsafeTemporaryPath/cleanup-permission unexpected failures are diagnostic recovery evidence, not automatically qualifying planned RED; finalcd4cea1 accepted. |
| M4.8 `ec7f38370cde77feb495f10910ae7d748137e3f6` · [33574677929](https://github.com/Fatihzxc/ios_app/actions/runs/33574677929) | Reports143/App8 pass then actual root UI expected fetch0 versus1. Final5438485 supersedes `2a606bee4a5c79d85451f566ce50e98f3def10ea` /33570729990. |

### M4.9 recovery and review sequence

| Change | RED / failure record | GREEN / disposition |
| --- | --- | --- |
| Initial integration | `d8e222f8df06463d3fd1371528b85a1e02d735dc` /33606727413: full timeout and known small native-container-label assertion; targeted steps passed but exports skipped. | Diagnostic only; not accepted. |
| Initial targeted-step budget | `f5a75fbc923425da547f68f23bb4f0d04e22012a` /[34237206016](https://github.com/Fatihzxc/ios_app/actions/runs/34237206016), job102097880291: targeted acceptance hits30-minute limit although all five UI tests pass984.504s and the trailing Release build reports success alongside timeout. | f69 changes only this step30→45minutes and its verifier contract after the actual timeout; selectors/tests/full360/general150 remain unchanged. This is a runner-budget correction, not behavioral RED or whole-run GREEN. |
| Frozen acceptance | `f69c305961330e40bc4fc0325e0263435dd1503c` /[34241435577](https://github.com/Fatihzxc/ios_app/actions/runs/34241435577): Nutrition transition intermittent in attempt1. | Bounded instrumentation on separate NEVERMERGE92fe branch did not establish a fix. One authorized unchanged attempt2 passed general1087+3skips but failed ZIP filename selection, not export bytes. |
| ZIP attachment selector | Actual attempt2 manifest reproduced `Expected one owned M4 round-trip ZIP attachment; found 0`;17 executable selector fixtures added before correction. | `ab718aacc135ec695bf985c8d180708e235caed8` /[34321027727](https://github.com/Fatihzxc/ios_app/actions/runs/34321027727): full1087Success3Skipped0Failure, ZIP/current owner verified. Chart finding remained; not whole-M4 acceptance. |
| CSV test decoder | `902abe5347117f91b1fbbda3ef95900bc996c8e4` /[34323729805](https://github.com/Fatihzxc/ios_app/actions/runs/34323729805): six real assertions in two added methods. | `411b069edc4405d0e608dbe74fe51993079c11d0` /[34326100143](https://github.com/Fatihzxc/ios_app/actions/runs/34326100143): focused86 and roundtrip8 pass/Release pass; cold process termination failed before measurement, so enclosing run remains failed. Encoder unchanged. |
| Cosmetic CI label | Local self-test reproduced display-only rename rejection. | `540fce905a144a815f79044447de7057fcf5d640` /[34327340599](https://github.com/Fatihzxc/ios_app/actions/runs/34327340599): focused/cold/small GREEN; actual selector/environment gates retained. Not a cold-process fix. |
| Chart label/plot | `bfb570cd51fd84a4bbf7ff39d197bcc63549e1ac` /[34437166893](https://github.com/Fatihzxc/ios_app/actions/runs/34437166893): five methods fail18 assertions, actual line1pt/bar16pt versus160pt; calibrations pass. | `8ab258fbb402e30de1bf83d709082af277071710` /[34439685246](https://github.com/Fatihzxc/ios_app/actions/runs/34439685246): separated endpoint rows/plot; later date-axis finding required correction. |
| Date axis | `40ebdf3d49463b759c4aa39ff603678b075d47be` /[34441139563](https://github.com/Fatihzxc/ios_app/actions/runs/34441139563): two new methods/six assertions fail, calibration passes. | `a57cfcbffc8951d952b32f5114524918bcf32c3f` /[34442566783](https://github.com/Fatihzxc/ios_app/actions/runs/34442566783): native GREEN; independent pixels then expose disappearing connectors. |
| Connector anchors | `46eacb770eb8d23348a187d0e6962a2224c50ded` /[34444191846](https://github.com/Fatihzxc/ios_app/actions/runs/34444191846): two methods24 connector-ink assertions fail. | `8446c72da1d3a10cabd2441242ed2ba4e85dd1d3` /[34445552749](https://github.com/Fatihzxc/ios_app/actions/runs/34445552749) preserves descendant anchors but remains failed with98nativeSuccess/1Failure/four AX5 date-probe assertions; actual pixels show restored leaders. The remaining false negative was investigated on NEVERMERGE92b /34447098337. `0b0fe6b99a9858ea03dd873cc86ddc4641817b6e` /[34449076476](https://github.com/Fatihzxc/ios_app/actions/runs/34449076476) changes only ROI bounds;99native/13chart pass,21ownedPNG/12unique reviewed. |
| Full Training transition | Same0b /[34450603797](https://github.com/Fatihzxc/ios_app/actions/runs/34450603797): full1104Success3Skipped1Failure; fifth dark/default warmup-skip absent before tap. | Cause UNRESOLVED. Final AX tree showed Today after primary action. Later passes are not a callback/route/presentation fix. No timeout/assertion weakening or speculative repair. |
| Lazy report composition | `858d91c1da10200a51d8f0cadf3450d564423b40` /[34457213659](https://github.com/Fatihzxc/ios_app/actions/runs/34457213659):101actual97pass4fail; root `d7fe1c561a442c4de8b644c4de0da24b940831a9` /[34459808395](https://github.com/Fatihzxc/ios_app/actions/runs/34459808395): constructor1 versus0. | `3639fafe2b87ac9ec31fa61eae9a3d30ee4f9615` /[34464102208](https://github.com/Fatihzxc/ios_app/actions/runs/34464102208): Reports146/App10 logs and actual-root UI pass, cached first-Progress creation/refresh preserved. |
| Post-rename cleanup retry | `97586fb0c4d272f8a4d59761329d59baeff83089` /[34465909201](https://github.com/Fatihzxc/ios_app/actions/runs/34465909201):147actual146pass1expectedfail. Earlier `f4ac29d96ff4f121f7b5b7ea351dd95da9097886` /[34465044647](https://github.com/Fatihzxc/ios_app/actions/runs/34465044647) missing makeDirectoryID compiler failure is nonqualifying. | `ce5fcb0e066d69d6cd20e9d303a3979336c67cf9` /[34467867412](https://github.com/Fatihzxc/ios_app/actions/runs/34467867412): coordinator47native,JSON4/ZIP23 logs, Release and generic unsigned iOS compile pass. Quarantine ownership marked immediately after rename, before later throwing steps. Not physical file-protection proof. |
| Full CI budget | Samece5 /[34468155512](https://github.com/Fatihzxc/ios_app/actions/runs/34468155512): general1108Success3Skipped and ZIP/screens pass, full job CANCELLED at six-hour platform limit; Cloud cancelled/hygiene skipped. | User-approved partition moves four unchanged targeted M4 steps into mandatory210min job; original full360/general150/cold/small/Cloud/hygiene retained. |
| Partition fail-closed verifier | `dd768818f816178ac2c64bba7ba0a77c4caafcd8` /[34579427204](https://github.com/Fatihzxc/ios_app/actions/runs/34579427204): expected static selector/budget contract RED. | Finalf3b /34580238289 all four jobs GREEN.33 negative workflow fixtures plus17 ZIP fixtures pass. Timing deviation retained: implementation began after local RED but before RED publication/hosted observation. Two review-discovered folded-YAML bypasses reproduced test-first and fixed before final publication. |
| Acceptance document | `00dc1829b0a572b5667c5ac8b8ab4f3858e3dcf4` /[34603123163](https://github.com/Fatihzxc/ios_app/actions/runs/34603123163), focused103275025457: prior14static gates pass, then only missing-document diagnostic/exit1, no native tests reached. | This document and its production verifier were created only after that hosted RED. The byte-changing successor SHA/run must be recorded externally, not self-embedded here. |

## Final GitHub Actions run

Implementation [run34580238289](https://github.com/Fatihzxc/ios_app/actions/runs/34580238289), attempt1, exactf3b, completed SUCCESS on2026-09-11. No cancellation or retry. Full job [103201852919](https://github.com/Fatihzxc/ios_app/actions/runs/34580238289/job/103201852919) ran08:39:22–12:56:17UTC (4h16m55). Mandatory M4 [103201852997](https://github.com/Fatihzxc/ios_app/actions/runs/34580238289/job/103201852997) ran1h29m20; cold103201852621 ran7m3; small103201852817 ran17m52. Focused job correctly skipped.

Hosted Xcode16.4 build16F6/XcodeGen2.46.0; iPhone16Pro simulator iOS18.5(22F77), UDID DC4CD8B3-4457-4153-9087-A0D7A2F9BFD9. Small uses iPhoneSE3 simulator18.5, UDID22A3039C-6A45-47F4-82D4-80C58CA94379. A native `isConcreteDevice` flag does not make a simulator physical.

Fresh-clone generated-project SHA256 `829dc48ff2f68cf41ac0371619021eb33dea38cbaaf768ba8000f7570b70afeb`. General test, Local Release, Cloud compile-only, hygiene and uploads all passed. Fifteen test invocations and sixteen builds succeeded in the full job; historically RED-named selectors now pass and are not fresh RED proof.

Full native result contains exactly one successful Test action and1111 actual typed ActionTestMetadata records:1108Success,3Skipped,0Failure,23warning summaries. Testables: App101; UI82(79Success3Skipped); Core54; Guidance80; Persistence244; Training113; Design26; Nutrition66; Safety5; HealthChecks27; Notifications27; Photos109; Metrics22; Sleep8; Reports147. Three skips are precisely the dedicated small-phone M3, M4 and Training cases, all separately passed in the same SHA's small job.

The full raw log is25891262bytes/93633lines, SHA256 `be4f95d5a425914e9a6134c02855a5cf988b62bbda5e1f6c29d4f710e1ed1707`. Eight CoreData editable-model checksum diagnostic error-text lines occur inside passing suites;1144 warning-text lines are not the native23warning count. Swift concurrency/deprecation and Node warnings remain. No warning-free/error-text-free claim is made.

Mandatory targeted M4 logs independently prove acceptance5pass, accessibility2pass+1dedicated-small skip, roundtrip8pass, large3pass; four TEST SUCCEEDED and four Local Release BUILD SUCCEEDED outcomes. Its8641375-byte log SHA256 is `98a158781b7a57a2d5020a1b84e624ea2eb2e6a6ca481c434e221c5f407bd640`. The runner overwrites the result bundle per invocation: the retained targeted native artifact owns ONLY the final three large tests. Earlier three invocations are log-only there; the full job separately owns their native/ZIP/screens evidence.

## Screenshot and artifact evidence

| Artifact ID / name | Provider bytes | Provider transport SHA256 |
| --- | ---: | --- |
| 10265060093 / HealthTrackingApp-xcresult | 162372313 | `76474a2b5c5f4efe6ee57feb0f62e66291650b1a923113364825fc16b5423988` |
| 10263997073 / M4-export-round-trip-evidence | 7836 | `1b96f7de4d438c86ef740aeb0992671f7faf58f669a5846e73e062cb432e354a` |
| 10194309600 / M4-acceptance-xcresult | 140290 | `9ca6522f866239c9cd5aced3471e1986d9519032f7f55f85a9543aea5ab2b149` |
| 10191864685 / HealthTrackingApp-small-phone-xcresult | 4700938 | `ceea5f726bb1d849a271efdb108531756aeb1ac25672ef2e91db9acb2156b99a` |
| 10191506418 / HealthTrackingApp-cold-launch-xcresult | 281618 | `4a08de9b94b95c8ee09d698ac1778340fd301a3fdd4204cfd5e4b730d9d18259` |

Provider transport digests above were read from GitHub metadata, not independently recomputed after extraction. Payload hashes below were independently calculated. No artifact from an earlier SHA substitutes for current ownership.

The full native root is `0~KU1UTIu4p-7VCyrMw3kMY2NWyYKUw8FhW6rl-boaeatv8VC8mwDsbmi-qW4xy9c5xXGTgLj4SVRZ2_4m5SP6Pw==`; tests reference `0~xg_0Tq2r2wNVkSrzttXE6UFYGIKG7x6zD33DCyqcxNY1YvyBHq84Fs58itHpQCntuDlaUbNKltqXGbmPXUdjEA==`. Strict legacy decoding consumed each selected object through EOF and counted actual typed metadata, not structural nodes.

Every PNG below is1206×2622, native keepAlways, associated with its exact successful test identifier/URL and simulator. Native payload, manifest UUID export and canonical file bytes agree. Controller and internal independent reviewer each viewed all13 actual images.

| Canonical file | Bytes | Independently computed SHA256 |
| --- | ---: | --- |
| m4-reports-light-default.png | 446640 | `20fdcc473a32e0cd6a885bc5249c4fa2d697a7ce3da56158a107eca7801ec165` |
| m4-reports-light-xxl.png | 496221 | `ca92f492c1c93ffd74192d406c3cbd6f2ef00118655f0b829f88a773269c3927` |
| m4-reports-light-ax3.png | 594587 | `a439912fecdccde78f9010116534e1c7ca3394da6197e90d5a1e6df94382e5fe` |
| m4-reports-light-ax5.png | 534001 | `3c0c10dfa6b97d1314e011a8d3e50013f07e2e83a20586549029f14cb41c353e` |
| m4-reports-dark-default.png | 534410 | `7a0031f4efc4eb0573888a50e5256cb6e02213b576eb274b0a303de63fdd0c05` |
| m4-reports-dark-xxl.png | 558606 | `e17f10def7bc982dbf38ba62971ce6b847329247e242a1a89d9c7720393353d2` |
| m4-reports-dark-ax3.png | 696944 | `44de094427a8384196910cc613650062133a70845588f732ba5d0413b9dfe26c` |
| m4-reports-dark-ax5.png | 582023 | `d74713abc1880713ebeaaa4d5a1c3d08fc97311911f53b32c5ccaa19023990c7` |
| m4-reports-reduce-motion.png | 465122 | `57faec178bddef9b74877fbb0048bf5806b9836e58c0ea4800367b23e0d0f6bf` |
| m4-reports-high-contrast.png | 466595 | `59b32a21a884a27482dc04d109ee5e6b930422e8aec2547ab4873107cc5c6dbb` |
| m4-reports-us7.png | 492370 | `289f5b83eff82f8fac1666af5d7cb4bf81ec22f36acba71dde05208eee7f14ca` |
| m4-reports-photo-share.png | 268860 | `066f0b938955949afd27b7df27bd97d99912ca29301d2614530d85051c97164d` |
| m4-reports-export-both.png | 258920 | `b6855dc0bb8bbe6e2070ba0406c4cc39676d074686eccd513d19cc1d8490c3c2` |

Matrix8 owner: `M4ReportsAccessibilityUITests/testDashboardLightDarkDefaultXXLAX3AX5Matrix()` (1248.795033s). Motion/contrast2 owner: `testReduceMotionAndHighContrastDashboardRemainOperable()` (144.821682s). US7, photo-share and export-both belong respectively to `testUS7DashboardUsesEveryRangeAndShowsHonestObservedEvidence()`, `testTwoReadyPhotosShareOnlyAfterExplicitUserAction()` and `testCSVJSONAndBothExportsUseRealShareAndCleanEveryArtifact()` in M4ReportsAcceptanceUITests. Retry/cancel tests also succeed but have zero attachments, not invented screenshot ownership.

Pixel scope: default and AX3/AX5 show readable wrapping summaries/ranges with ordinary viewport cropping; plots are largely offscreen. XXL endpoint rows are separated, with distinct shapes/values and descending connectors; lower plot/axes remain mostly below viewport. Reduce Motion shows four full endpoint labels and matching point/connector shapes, bottom axes offscreen. US7 retains strength plot, date labels/leaders, zero tick and expanded text table. High contrast shows honest phase provenance and full Export button. Photo-share shows selected fixture gallery items, not the generated comparison image. Export-both shows modules/format/photo-opt-in/Share; it is a photos-enabled UI scenario distinct from the photos-disabled ZIP fixture below.

Dedicated small artifact owns three750×1334 PNGs: M3 routes SHA256 `d301219404bee5408de52842a92a3753b4fd2c232046886bd9757b68ba9ece55`; M4 dashboard/export `5d47ce45a9515a83e82de00eadc864492611844b7e4afc831dcf20cf56605363`; Training session `ba213c9dfed0508d85a60bdbce3d061626544deb1b65c21b9969e29624fa2692`. Native/manifest/export/canonical bytes and all pixels independently reviewed. M4 screenshot shows phase/date/complete Export, no chart. Training variation/RIR/Save are visible with top viewport crop; M3 long labels wrap in separated cards.

Training full matrix additionally passed461.617453s with eight completed warmup-skip taps and eight owned images; independent reviewer viewed all8 and controller verified ownership/bytes. This does not resolve the earlier0b failure's root cause.

The matrix does NOT prove every fallback-table/export operation in all eight cells. Default-light US7 expands tables/ranges; separate acceptance cases generate/share/cancel/retry. Small AX5 opens the format control, not the entire sharing sequence. No blanket offscreen reachability, physical VoiceOver or Audio Graphs claim follows from screenshots.

## Export round trip and privacy

Current ZIP owner: `M4ExportRoundTripTests/testGeneratedZIPPassesPureInspectorManifestHashesAndAttachesHostedArtifact()`, Success0.203561s, sole keepAlways public.zip-archive. Native summary `0~NWDfYLOrMpVruIfOMyBk3Sq_w_e4Y4aJ0yefNBkc7hAGuMn8MzIMrPtXeE5EH5yiERzSGOeGYEwozBS2fT4LsQ==`; payload `0~H0wOktO6XfZfdq_25azawQhxnFNO5l4df27gV-jxcY_TQrVuejiiMCTXG9GfRWiIpD6aOcFTtAghdragUE3yLQ==`; attachment UUID41C83AB5-5E8D-423F-A9A2-55A3B03FE18C. Exact manifest owner/device/nonfailure/native filename association verified.

Native ZIP, gallery UUID export, full-artifact audit ZIP and separate-audit ZIP are byte-identical60560bytes with the receipt SHA256. `/usr/bin/unzip -t`, CRC, exact ten unique safe stored entries, nine payload sizes/SHA256 and both audit summaries pass. Manifest schema1, format bothZip, eight modules, includesPhotosfalse/photos[]; JSON range/module selection agrees. Current ownership is independently proved despite deterministic bytes matching older runs. A first local ad-hoc inspection used wrong manifest field names and raised KeyError; it was discarded, corrected to relativePath/byteSize and all checks rerun. It was not a product failure.

All eight round-trip methods pass: all24 record types preserve native JSON cells and shared ExportTableV1 equality; custom CSV decoder covers null/quoted-empty/formula text, Unicode, escaping, embedded CR/LF and malformed-input regressions; generated ZIP passes pure inspector and hosted external audit. No new SwiftData schema change: V2 has24 model types, V1 has23; WorkoutSessionProgressV2 remains v1.1. ReportsKit depends only on DesignSystem and GuidanceKit, not SwiftData/CloudKit/PhotosUI/ModelContext/Query; central Epley calculation is reused.

Privacy scan: PASS at immutablef3b. The Stage-A executable logging scan covers acceptance/round-trip/large-fixture sources; repository architecture and inherited privacy gates cover their explicitly listed source scopes. It is not a proof of every possible runtime log sink. No real health/photo data was needed: hosted fixtures are deterministic. User photo inclusion remains explicit opt-in; ownership/path/cleanup tests are not a signed-device data-protection claim.

## Performance evidence

Cold launch uses the unchanged median≤1second contract. Five samples `[0.13411, 0.204382, 0.14592, 0.127483, 0.105923]`, median0.13411; owned raw JSON3044bytes and receipt SHA256 independently checked. One seed preparation plus five unmeasured stabilization plus five measured fresh-process launches:11 ordered completed launch/terminate pairs with distinct PIDs. Five ten-phase vectors are finite/nonnegative/monotonic; final Today/sample agreement≤1microsecond.

Measurement is seeded/default-locale/simulator `HealthTrackingApp.init`→Today first-content publication using system uptime, not physical/cache-cold/first-frame/pre-main latency or a demonstrated performance improvement.

Large tests:10,000 time-series rows reduce deterministically/order-invariantly to365points (cap366) within20seconds;500photo metadata rows encode deterministically within20seconds;500photo ZIP cancellation finishes within8seconds and leaves an empty owned workspace. Targeted native case durations0.194941s,0.854944s and1.058082s are whole test durations, not raw isolated performance intervals. No real500photo-device benchmark is claimed.

## Review record

Controller implemented; only internal GPT-6 Astra/high review agents were used for the final correction/evidence sequence, per the user's newer instruction. Reviews independently checked actual native records, logs, owner chains, ZIP hashes/CRC, all13M4 images, Training8matrix and small/cold/large scopes. No new Critical/Important/Minor finding remained within these inspected scopes. Previous chart, CSV decoder, display-label, lazy-composition, cleanup and fail-closed YAML findings were corrected as recorded above.

This evidence review is not by itself whole-branch/main approval. External-agent/Fable review was NOT RUN and is not implied. The unresolved Nutrition/cold-process/Training intermittent causes are explicitly retained; later GREEN does not diagnose them.

## Physical and live-service boundary

The seven physical checks in the receipt are NOT RUN. Signed Mac/two physical iPhones on one iCloud account and distribution capabilities have not been supplied for those gates. Cloud scheme compile-only, protocol fakes, generic unsigned device compilation and simulator UI tests cannot discharge them. Their release acceptance belongs to the later M5/full requirement audit; they must never silently become PASS.

## Remote and finalization record

At Stage A, local `test/m4.9-ci-job-budget-fix`, GitHub and Gitea all resolved exactly to immutablef3b. Accepted M3 main remained `a104fcad8429009d47359e6aebb1a6ace20f12e6`; preserved milestone branch feat/m4-reports remained task8SHA5438485. No M4 merge is claimed by this snapshot.

Stage-B RED00dc182 was published create-only to GitHub and its exact ref read back. Gitea read-only checks on2026-09-11 timed out without resolving the new ref, so that mirror was pending/nonblocking; no unknown tip was overwritten. The user explicitly requires continued progress during Gitea outages.

This file's own byte-changing commit/run cannot be self-embedded. Its amended successor SHA, hosted GREEN, independent final review, preserved milestone ref, later `merge: complete M4 reports and export` main SHA and exact-main four-job results must be retained externally in the SDD ledger and later M5 trace/final handoff. Stage A is not a substitute for those gates. M5 and the final requirement-by-requirement FULL product audit remain mandatory.
