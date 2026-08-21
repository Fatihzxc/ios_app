# HealthTrackingApp

HealthTrackingApp is a Turkish-first iOS health and training app. M0 supplies the local-first SwiftData and modular application foundation; M1 adds the complete guided foundation-training loop, deterministic guidance and its accessibility acceptance gates. Later milestones add nutrition, symptoms/reminders, reports and device-service integration.

## First setup

You need a Mac, Git, Homebrew, and XcodeGen 2.46.0 or newer. Before using the project:

1. Install the latest stable Xcode from the Mac App Store. The CI baseline is Xcode 16.4.
2. Open Xcode once so it can finish installing required components and accept its license.
3. In Xcode, open Settings > Components and install an iOS Simulator runtime. Apple documents this in [Downloading and installing additional Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components).

Then, in Terminal, copy and run:

```bash
git clone --branch main --single-branch https://github.com/Fatihzxc/ios_app.git
cd ios_app
brew install xcodegen
./scripts/bootstrap.sh
open HealthTrackingApp.xcodeproj
```

In Xcode, select the `HealthTrackingApp-Local` scheme and any available iPhone simulator, then press Run. The Local scheme stores data only in the app's local SwiftData store; it does not use CloudKit.

For the complete local acceptance check, run:

```bash
./scripts/test-ios.sh
```

This runs repository verifiers, Local Debug unit/UI tests (including accessibility audits), and a Local Release build. The result bundle is written to `.build/HealthTrackingApp.xcresult`. To compile the Cloud configuration without signing, run:

```bash
./scripts/test-ios.sh --cloud-compile-only
```

A successful Cloud compile proves only that the configuration builds. It does not prove that CloudKit is provisioned, reachable, or synchronizing data.

## M1 training

On launch, Today presents one current directive: start, resume or rest. Start a session from Today, or open Training and choose the ordered A/B/C day. The guided deck moves through warm-up, exercises, cooldown and summary; closing the deck preserves an in-progress session for the next launch. Training history supports opening a session, correcting a set and confirmed deletion.

Each exercise shows its measurement family, target, recommendation, RIR input, safety note and failure policy. Progression stays conservative when required RIR or OHP symptom information is absent. Scheduled/reactive deload and phase changes always require an explicit user choice. Haptics are supplementary to visible semantics and can be disabled persistently under Settings.

M1.16 covers VoiceOver reading order and focus, 52-point session controls, light/dark appearances, default through AX5 Dynamic Type, Reduce Motion, Increase Contrast, modern iPhone and a dedicated small-iPhone AX5 job. The full local command above runs the modern-simulator matrix. CI additionally selects an iPhone SE (3rd generation), or an iPhone 13 mini when available, for the canonical small-phone check.

Training guidance is deterministic product behavior, not medical diagnosis or individualized clinical advice. Stop the movement and seek appropriate professional care when symptoms or safety concerns require it.

## Run on a personal iPhone

1. Connect and trust the iPhone, then select it as the run destination in Xcode.
2. Open the app target's Signing & Capabilities tab, enable automatic signing, and choose your team.
3. Use `HealthTrackingApp-Local` first. If Xcode asks, enable Developer Mode on the iPhone and trust the developer certificate.
4. Build and run from Xcode.

A free Apple Account uses a Personal Team. Its provisioning profiles expire after seven days, so the app must then be built and installed again. Apple lists the current Personal Team limits in [Choosing a Membership](https://developer.apple.com/support/compare-memberships/).

The `HealthTrackingApp-Cloud` scheme additionally needs a paid Apple Developer Program membership, an App ID and provisioning profile with the iCloud/CloudKit capability, a CloudKit container you control, and the same iCloud account signed in wherever sync is tested. See Apple's [supported capabilities reference](https://developer.apple.com/help/account/reference/supported-capabilities-ios). Do not treat a successful build, launch, or single-device save as evidence of live sync; verify writes and cross-device reads separately in the intended CloudKit environment.

## Troubleshooting

- `xcodegen ... is required`: run `brew install xcodegen`, or `brew upgrade xcodegen` if the installed version is older than 2.46.0, then rerun `./scripts/bootstrap.sh`.
- No iPhone simulator is available: in Xcode, open Settings > Components and install an iOS Simulator runtime. Apple documents this in [Downloading and installing additional Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components).
- Signing fails on a device: select your own team, confirm the bundle identifier is available to that team, and use the Local scheme before attempting Cloud capabilities.
- Cloud capability or container errors: confirm active paid membership, entitlements, container ownership, provisioning, environment, and iCloud login. The Local scheme remains available without CloudKit.
- Generated-project problems: close Xcode, delete only `HealthTrackingApp.xcodeproj`, and rerun `./scripts/bootstrap.sh`. Edit `project.yml`, not generated project files.

## Current limits

M1 training is accepted only through repository and simulator evidence; the whole health product is not finished. Nutrition tracking, symptom/reminder workflows, reports and the final cross-milestone audit remain later milestones. TestFlight distribution, live multi-device CloudKit synchronization, notification delivery, HealthKit authorization/data exchange and haptic behavior on physical hardware are not established by simulator tests.
