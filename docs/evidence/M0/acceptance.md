# M0 acceptance evidence

Status: **hosted M0 GREEN recorded; device/service-only evidence remains NOT RUN / BLOCKED**.

This file records reproducible evidence without treating a compile, simulator test, screenshot, or candidate claim as proof of device- and service-dependent behavior. The exact hosted-green code candidate and run are recorded below. The commit containing this evidence-only update cannot embed its own final SHA: changing the file changes that SHA. Its immutable exact-SHA Actions result therefore remains an external handoff record rather than a false self-reference.

## Hosted milestone record

| Milestone | Exact commit | Hosted run | Result represented here |
| --- | --- | --- | --- |
| M0.1 | `4bb90a94e696ade36d52c3d05158d8e88d77b693` | [30882222223](https://github.com/Fatihzxc/ios_app/actions/runs/30882222223) | Accepted |
| M0.2 | `55b69cbb09dcf1c61467b896ec370cf632cbeec4` | [30884748940](https://github.com/Fatihzxc/ios_app/actions/runs/30884748940) | Accepted |
| M0.3 | `ba42ca316d1bb263bed7d3fc5e3d04c641829c67` | [30887194374](https://github.com/Fatihzxc/ios_app/actions/runs/30887194374) | Accepted |
| M0.4 | `f09319aebaebaccde5373665bd90c98de3e84092` | [30888831267](https://github.com/Fatihzxc/ios_app/actions/runs/30888831267) | Accepted |
| M0.5 | `d8582b0cae18b20c587ed57238b01ce50d73f0fb` | [30901209302](https://github.com/Fatihzxc/ios_app/actions/runs/30901209302) | Accepted |
| M0.6 | `897b7890ff8ed87cd3e8d57702b06372e67f65c4` | [30904248974](https://github.com/Fatihzxc/ios_app/actions/runs/30904248974) | Accepted |
| M0.7 | `cdc20a4562282fbdfe3033d988e916d0b9906183` | [30988678698](https://github.com/Fatihzxc/ios_app/actions/runs/30988678698) | Accepted |
| M0.8 | `5f70e38f18483f5e62a7c79c752539331d780d4d` | [31181344995](https://github.com/Fatihzxc/ios_app/actions/runs/31181344995), job `92875111070` | Hosted GREEN |
| M0.9 RED | `c5bd2087507396f64958e0969377548c6daae9ec` | [31185878135](https://github.com/Fatihzxc/ios_app/actions/runs/31185878135), job `92890136005` | Qualifying RED: verifier fixture passed, then exactly 17 intended hint-contract gaps failed |
| M0.9 UI RED | `06bdf4aa7fc13ea2461ea24b08911588619e5cc7` | [31187313797](https://github.com/Fatihzxc/ios_app/actions/runs/31187313797), job `92895023007` | Two exact UI-query contract failures exposed invalid container-cardinality and single-gallery-control assumptions |
| M0.9 verified candidate | `3b4aa8766878f6229736359d542921273f558cf8` | [31189329816](https://github.com/Fatihzxc/ios_app/actions/runs/31189329816), job `92901832108` | Hosted GREEN |
| M0.9 evidence finalization | Commit containing this file | External exact-SHA run required | Evidence-only successor; no self-referential success claim |

The M0.9 GREEN runner used Xcode 16.4 (`16F6`), XcodeGen 2.46.0, and an iPhone 16 Pro simulator on iOS 18.5. Fresh-clone bootstrap generated the same project twice with SHA-256 `31a35eb7916f3c91f7e61c58d64d38430071176b1e43d0c49364ac11895760ae` and left tracked files unchanged.

## M0.8 baseline detail

The M0.8 hosted run passed these test counts: targeted app tests 22; UI tests 11 (8 app-shell + 3 design/accessibility); CoreModels 38; PersistenceKit 22; TrainingKit 11; DesignSystem 13. Local Release and Cloud compile-only also passed.

Artifact `8995235795` was `12,658,426` bytes. Its screenshot export contained 18 valid canonical source copies: 16 app-shell/state/path images and 2 design-system gallery images. The acceptance checks also validated title safe-area rows and status-bar masks. These screenshots demonstrate the tested simulator presentation only; they do not prove device signing, CloudKit, notifications, or HealthKit behavior.

## M0.9 acceptance matrix

| Gate | Candidate expectation | Evidence status |
| --- | --- | --- |
| Localization verifier self-tests and repository scan | All owner catalogs resolve; bounded Turkish accessibility-hint contracts pass | GREEN locally and in hosted run `31189329816` (102 catalog keys; 68 production Swift sources) |
| Requirements verifier self-tests and repository scan | Exact modules, models, schemes, actions, ignore rule, and production marker policy pass | GREEN locally and in hosted run `31189329816` |
| Fresh clone + bootstrap twice | Both generated-project content fingerprints are identical and tracked files remain unchanged | GREEN in hosted run `31189329816`; fingerprint recorded above |
| Local Debug | Full unit/UI suite, including 10 accessibility audit combinations and VoiceOver interaction smoke coverage | GREEN: app 22; UI 13 (accessibility 2, app-shell 8, title/safe-area 3); CoreModels 38; PersistenceKit 22; TrainingKit 11; DesignSystem 13 |
| Local Release | Unsigned simulator Release build | GREEN in hosted run `31189329816` |
| Cloud Debug | Compile only with signing disabled | GREEN in hosted run `31189329816`; never sync proof |
| Screenshot evidence | 18 M0.8 canonical images plus 2 M0.9 accessibility images, owner-checked and duplicate-safe | GREEN: artifact `8998614264` (`16,206,754` bytes) contains 20 canonical PNGs; every canonical/source pair is SHA-256 identical |
| Repository hygiene | verifier fixtures, secret-pattern scan, production marker scan, committed/worktree whitespace checks, and clean tracked tree | GREEN locally and in hosted run `31189329816` |

## Review record

Tracked independent reviews accepted M0.1 through M0.7. Exact-tree independent Codex reviews approved M0.8. Independent exact-tree review approved M0.9 candidate `3b4aa8766878f6229736359d542921273f558cf8` with no Critical, Important, or Minor findings after the hosted RED correction. The Fable tool is unavailable in the current environment, so a Fable review is **NOT RUN**; this is not represented as a failure or approval.

## Device and external-service evidence

The following remain **NOT RUN / BLOCKED** in this repository-only acceptance because they require user-controlled hardware, accounts, signing assets, service configuration, or distribution authority:

- Personal iPhone automatic signing, installation, launch, and seven-day Personal Team renewal behavior.
- Paid-team CloudKit entitlements, container provisioning, production/development environment selection, and same-iCloud-account multi-device synchronization.
- TestFlight archive upload, processing, invitation, installation, and launch.
- Real notification authorization and delivery.
- HealthKit authorization and live data read/write behavior.

The Local scheme intentionally has no CloudKit dependency. The Cloud scheme compiling successfully is useful configuration evidence, but it is not evidence that any record synchronized. Apple membership and device setup references are maintained in the repository [README](../../../README.md).
