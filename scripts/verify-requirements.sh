#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

verify_repo() {
    local target_root="$1"
    python3 - "$target_root" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
errors = []

package = root / "Packages/HealthTrackingModules/Package.swift"
project = root / "project.yml"
gitignore = root / ".gitignore"
if not package.is_file(): errors.append("Missing package manifest: Packages/HealthTrackingModules/Package.swift")
if not project.is_file(): errors.append("Missing XcodeGen project spec: project.yml")
if not gitignore.is_file(): errors.append("Missing .gitignore")

if package.is_file():
    package_text = package.read_text(encoding="utf-8")
    products_block = re.search(r'^    products:\s*\[\n(.*?)(?=^    targets:\s*\[)', package_text, re.M | re.S)
    products = re.findall(r'\.([A-Za-z][A-Za-z0-9_]*)\s*\(\s*name:\s*"([^"]+)"', products_block.group(1) if products_block else "")
    expected_products = [
        "CoreModels", "TrainingKit", "GuidanceKit", "PersistenceKit", "DesignSystem",
        "NutritionKit", "HealthSafetyKit", "HealthChecksKit", "ProgressPhotosKit", "MetricsKit",
        "SleepMoodKit", "ReportsKit", "SettingsKit",
    ]
    expected_product_declarations = [("library", name) for name in expected_products]
    if products != expected_product_declarations:
        errors.append(f"Package products must be exactly {expected_product_declarations}; found {products}")

    target_declarations = re.findall(
        r'\.(target|testTarget)\s*\(\s*name:\s*"([^"]+)"',
        package_text,
        re.S,
    )
    required_module_targets = [
        ("target", "GuidanceKit"),
        ("testTarget", "GuidanceKitTests"),
        ("target", "NutritionKit"),
        ("testTarget", "NutritionKitTests"),
        ("target", "HealthSafetyKit"),
        ("testTarget", "HealthSafetyKitTests"),
        ("target", "HealthChecksKit"),
        ("testTarget", "HealthChecksKitTests"),
        ("target", "ProgressPhotosKit"),
        ("testTarget", "ProgressPhotosKitTests"),
        ("target", "MetricsKit"),
        ("testTarget", "MetricsKitTests"),
        ("target", "SleepMoodKit"),
        ("testTarget", "SleepMoodKitTests"),
    ]
    missing_module_targets = [
        declaration
        for declaration in required_module_targets
        if declaration not in target_declarations
    ]
    if missing_module_targets:
        errors.append(
            f"Package must declare GuidanceKit, NutritionKit, HealthSafetyKit, HealthChecksKit, ProgressPhotosKit, MetricsKit and SleepMoodKit library/test targets; "
            f"missing {missing_module_targets}"
        )

model_directory = root / "Packages/HealthTrackingModules/Sources/CoreModels/Models"
expected_models = [
    "AppReminder", "AppSetting", "BloodworkResult", "BodyMetric", "CooldownItem", "DailyNutritionLog",
    "ExerciseTemplate", "Food", "HealthCheckReminder", "MealEntry", "MoodLog", "PostureMetric", "Program",
    "ProgramPhase", "ProgramState", "ProgressPhoto", "Recipe", "SetLog", "SleepLog", "UserProfile",
    "WarmupItem", "WorkoutDayTemplate", "WorkoutSession", "WorkoutSessionProgress",
]
models = []
if model_directory.is_dir():
    for source in model_directory.rglob("*.swift"):
        text = source.read_text(encoding="utf-8")
        models.extend(re.findall(r'@Model\s*(?:\n\s*)*(?:public\s+)?final\s+class\s+(\w+)', text))
else:
    errors.append("Missing CoreModels model directory.")
if sorted(models) != expected_models:
    errors.append(f"SwiftData model names must be exactly {expected_models}; found {sorted(models)}")

guidance_directory = root / "Packages/HealthTrackingModules/Sources/GuidanceKit"
forbidden_guidance_imports = {"SwiftUI", "SwiftData", "CloudKit", "UIKit"}
if guidance_directory.is_dir():
    for source in guidance_directory.rglob("*.swift"):
        imported_modules = set(
            re.findall(r'^\s*import\s+([A-Za-z][A-Za-z0-9_]*)\s*$', source.read_text(encoding="utf-8"), re.M)
        )
        forbidden = sorted(imported_modules & forbidden_guidance_imports)
        if forbidden:
            errors.append(
                f"GuidanceKit must remain platform/persistence independent; "
                f"{source.relative_to(root)} imports {forbidden}"
            )
else:
    errors.append("Missing GuidanceKit source directory.")

training_directory = root / "Packages/HealthTrackingModules/Sources/TrainingKit"
if training_directory.is_dir():
    for source in training_directory.rglob("*.swift"):
        source_text = source.read_text(encoding="utf-8")
        if re.search(r'^\s*import\s+SwiftData\s*$', source_text, re.M) or re.search(
            r'\bModelContext\b', source_text
        ):
            errors.append(
                f"TrainingKit must not expose persistence implementation details; "
                f"{source.relative_to(root)} references SwiftData/ModelContext"
            )
else:
    errors.append("Missing TrainingKit source directory.")

if project.is_file():
    project_text = project.read_text(encoding="utf-8")
    config_block = re.search(r'^configs:\n(.*?)(?=^packages:|\Z)', project_text, re.M | re.S)
    config_pairs = re.findall(r'^  ([^:\n]+):\s*(debug|release)\s*$', config_block.group(1) if config_block else "", re.M)
    expected_configs = [("Debug", "debug"), ("Release", "release"), ("Cloud Debug", "debug"), ("Cloud Release", "release")]
    if config_pairs != expected_configs:
        errors.append(f"Configurations must be exactly {expected_configs}; found {config_pairs}")
    project_lines = project_text.splitlines()
    try:
        schemes_start = project_lines.index("schemes:") + 1
    except ValueError:
        schemes_start = len(project_lines)
    scheme_lines = []
    for line in project_lines[schemes_start:]:
        if line and not line.startswith(" "):
            break
        scheme_lines.append(line)

    def bounded_mappings(lines, indent):
        prefix = " " * indent
        pattern = re.compile(rf'^{re.escape(prefix)}([^ :][^:]*):\s*$')
        mappings = []
        current = None
        for line in lines:
            match = pattern.match(line)
            if match:
                if current is not None:
                    mappings.append(current)
                current = [match.group(1), []]
            elif current is not None:
                current[1].append(line)
        if current is not None:
            mappings.append(current)
        return mappings

    schemes = bounded_mappings(scheme_lines, 2)
    scheme_names = [name for name, _ in schemes]
    expected_schemes = ["HealthTrackingApp-Local", "HealthTrackingApp-Cloud"]
    if scheme_names != expected_schemes:
        errors.append(f"Schemes must be exactly {expected_schemes}; found {scheme_names}")

    scheme_map = {name: lines for name, lines in schemes}
    def action_entries(scheme_name):
        return bounded_mappings(scheme_map.get(scheme_name, []), 4)
    def direct_config(action_lines):
        values = [match.group(1).strip() for line in action_lines if (match := re.match(r'^      config:\s*([^\n]+)$', line))]
        return values[0] if len(values) == 1 else None

    local_action_entries = action_entries("HealthTrackingApp-Local")
    cloud_action_entries = action_entries("HealthTrackingApp-Cloud")
    expected_local_actions = ["build", "run", "test", "archive"]
    expected_cloud_actions = ["build", "run", "archive"]
    local_action_names = [name for name, _ in local_action_entries]
    cloud_action_names = [name for name, _ in cloud_action_entries]
    if local_action_names != expected_local_actions:
        errors.append(f"Local scheme actions must be exactly {expected_local_actions}; found {local_action_names}")
    if cloud_action_names != expected_cloud_actions:
        errors.append(f"Cloud scheme actions must be exactly {expected_cloud_actions}; found {cloud_action_names}")
    local_actions = {name: lines for name, lines in local_action_entries}
    cloud_actions = {name: lines for name, lines in cloud_action_entries}
    local_package_test_targets = [
        match.group(1)
        for line in local_actions.get("test", [])
        if (match := re.match(r'^        - package:\s*HealthTrackingModules/([^\s]+)\s*$', line))
    ]
    expected_package_test_targets = [
        "CoreModelsTests", "GuidanceKitTests", "PersistenceKitTests", "TrainingKitTests",
        "DesignSystemTests", "NutritionKitTests", "HealthSafetyKitTests",
        "HealthChecksKitTests", "ProgressPhotosKitTests", "MetricsKitTests", "SleepMoodKitTests",
    ]
    if local_package_test_targets != expected_package_test_targets:
        errors.append(
            f"Local scheme package tests must be exactly {expected_package_test_targets}; "
            f"found {local_package_test_targets}"
        )
    local_configs = [direct_config(local_actions.get(section, [])) for section in ["run", "test", "archive"]]
    cloud_configs = [direct_config(cloud_actions.get(section, [])) for section in ["run", "archive"]]
    if local_configs != ["Debug", "Debug", "Release"]:
        errors.append("Local scheme must use exactly Debug run, Debug test, and Release archive contracts.")
    if cloud_configs != ["Cloud Debug", "Cloud Release"]:
        errors.append("Cloud scheme must use exactly Cloud Debug run and Cloud Release archive contracts.")
    if "test" in cloud_actions:
        errors.append("Cloud scheme must not declare a test action; it is compile-only.")

if gitignore.is_file():
    ignored = subprocess.run(
        ["git", "-C", str(root), "check-ignore", "--no-index", "--quiet", "HealthTrackingApp.xcodeproj/project.pbxproj"],
        check=False,
    ).returncode == 0
    if not ignored:
        errors.append("Generated HealthTrackingApp.xcodeproj must be actively ignored for a representative project path.")

production_roots = [root / "App", root / "Packages/HealthTrackingModules/Sources"]
marker = re.compile(r'\b(?:TODO|TBD|placeholder)\b', re.I)
for production_root in production_roots:
    if production_root.is_dir():
        for source in production_root.rglob("*.swift"):
            for line_number, line in enumerate(source.read_text(encoding="utf-8").splitlines(), start=1):
                if marker.search(line):
                    errors.append(f"Production marker in {source.relative_to(root)}:{line_number}")

if not (root / "README.md").is_file():
    errors.append("Missing required M0 README: README.md")
if not (root / "docs/evidence/M0/acceptance.md").is_file():
    errors.append("Missing required M0 acceptance evidence: docs/evidence/M0/acceptance.md")

def require_text_contract(relative_path, required_tokens):
    path = root / relative_path
    if not path.is_file():
        errors.append(f"Missing required M1 acceptance file: {relative_path}")
        return ""
    text = path.read_text(encoding="utf-8")
    missing_tokens = [token for token in required_tokens if token not in text]
    if missing_tokens:
        errors.append(
            f"M1 contract {relative_path} is missing required tokens: {missing_tokens}"
        )
    return text

m1_acceptance = require_text_contract(
    "HealthTrackingAppUITests/M1AcceptanceUITests.swift",
    [
        "testWeekABCAndAllTwentySevenSeedExercisesPublishMeasurementAndSafety",
        "testMissingRIRAndUnansweredOHPCannotPublishAnIncrease",
        "testFirstPerformanceIsBaselineAndOnlyARealImprovementIsPresentedAsPR",
        "testHapticKillSwitchPersistsAcrossRelaunch",
        "m1-acceptance-catalog",
        "m1-acceptance-progression-safety",
        "m1-acceptance-personal-records",
        "m1-acceptance-haptics-disabled",
    ],
)
expected_m1_exercises = [
    "Goblet Squat", "Chin-up", "DB Floor Press", "DB Romanian Deadlift",
    "Prone Y-T-W", "Face Pull (bant)", "Tek Bacak Calf Raise", "Plank / Pallof",
    "DB RDL (çift)", "Tek Kol DB Row", "Push-up", "DB Overhead Press",
    "Bulgarian Split Squat", "Glute Bridge / Hip Thrust", "Wall Slide", "Dead Bug",
    "Copenhagen Plank", "Reverse Lunge (DB)", "Nordic Hamstring Curl",
    "Pull-up / bantlı", "Bantlı / Tek Kol Row", "Half-Kneeling DB Press",
    "DB Lateral Raise", "Farmer's Carry", "Curl", "Triceps", "Side Plank / Pallof",
]
missing_exercises = [name for name in expected_m1_exercises if name not in m1_acceptance]
if missing_exercises:
    errors.append(
        f"M1 acceptance UI inventory must name all 27 exact seed exercises; missing {missing_exercises}"
    )

require_text_contract(
    "HealthTrackingAppUITests/TrainingAccessibilityUITests.swift",
    [
        "testVoiceOverOrderValuesActionsAndFiftyTwoPointSessionTargets",
        "testLightDarkAndDynamicTypeMatrixPassesSessionAudit",
        "testReduceMotionAndHighContrastFlowsRemainOperable",
        "testSmallPhoneAX5SessionRemainsOperable",
        "UICTContentSizeCategoryXXL",
        "UICTContentSizeCategoryAccessibilityXL",
        "UICTContentSizeCategoryAccessibilityXXXL",
        "performAccessibilityAudit",
        "scrollByShortDrag(",
        "with bounded drags",
    ],
)
training_accessibility_path = root / "HealthTrackingAppUITests/TrainingAccessibilityUITests.swift"
if training_accessibility_path.is_file():
    training_accessibility_text = training_accessibility_path.read_text(encoding="utf-8")
    forbidden_full_swipes = [
        token
        for token in ("app.swipeUp()", "app.swipeDown()")
        if token in training_accessibility_text
    ]
    if forbidden_full_swipes:
        errors.append(
            "AX5 positioning must use bounded short drags instead of full swipes; "
            f"found {forbidden_full_swipes}"
        )
require_text_contract(
    ".github/workflows/ios.yml",
    [
        "training_accessibility_expected",
        "m1_acceptance_expected",
        "test-small-phone",
        "scripts/select-simulator.sh --small",
        "m1-session-small-ax5",
        "HealthTrackingApp-small-phone-xcresult",
    ],
)
require_text_contract(
    "scripts/select-simulator.sh",
    ["--small", "iPhone SE (3rd generation)", "iPhone 13 mini"],
)
require_text_contract(
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift",
    ["today.accessibility.summary", ".accessibilityElement(children: .combine)"],
)
require_text_contract(
    "Packages/HealthTrackingModules/Sources/TrainingKit/Session/SetEntryBar.swift",
    [
        "@Environment(\\.dynamicTypeSize)",
        ".accessibility3",
        "minWidth: 52",
        "minHeight: 52",
        "minimumHeight: 52",
        "session.set.save.hint",
    ],
)
require_text_contract(
    "Packages/HealthTrackingModules/Sources/DesignSystem/Components/PrimaryActionButton.swift",
    [
        "minimumHeight: CGFloat = 44",
        ".frame(maxWidth: .infinity, minHeight: minimumHeight)",
        ".frame(minWidth: minimumHeight, minHeight: minimumHeight)",
    ],
)
require_text_contract(
    "Packages/HealthTrackingModules/Sources/TrainingKit/Session/TrainingSessionView.swift",
    ["@Environment(\\.accessibilityReduceMotion)", ".transition(", "0.12"],
)
for stage_file in [
    "WarmupStageView.swift",
    "ExerciseStageView.swift",
    "CooldownStageView.swift",
    "SessionSummaryView.swift",
]:
    required = ["@AccessibilityFocusState", ".accessibilityFocused("]
    if stage_file == "ExerciseStageView.swift":
        required.append("session.exercise.next.hint")
    require_text_contract(
        f"Packages/HealthTrackingModules/Sources/TrainingKit/Session/{stage_file}",
        required,
    )
require_text_contract(
    "App/Support/AppUITestLaunchConfiguration.swift",
    ["m1AcceptanceCatalog", "m1PRBaseline", "m1PRNew"],
)
require_text_contract(
    "App/Application/AppDependencies.swift",
    ["installM1AcceptanceCatalog", "installM1PersonalRecord"],
)
require_text_contract(
    "README.md",
    ["## M1 training", "M1.16"],
)
if not (root / "docs/evidence/M1/acceptance.md").is_file():
    errors.append("Missing required M1 acceptance evidence: docs/evidence/M1/acceptance.md")

coverage_contracts = {
    "HealthTrackingAppUITests/TrainingSessionFlowUITests.swift": [
        "testGuidedOrderTapBudgetsSafetyAndOptionalSummary",
        "testResumeRestoresTheSameMovementAcrossRelaunch",
        "testMissingRIRHistoryNeverDisplaysALoadIncrease",
    ],
    "HealthTrackingAppUITests/OHPSafetyFlowUITests.swift": [
        "testPriorQuestionPrecedesWarmupAndCurrentSymptomsRouteToHalfKneeling",
    ],
    "HealthTrackingAppUITests/DeloadFlowUITests.swift": [
        "testScheduledWeekShowsVisibleWarningAndAcceptedDeloadLoad",
        "testReactiveTechniqueReviewSuppressesOnlyTheCurrentWeekWithoutMutation",
    ],
    "HealthTrackingAppUITests/PhaseTransitionFlowUITests.swift": [
        "testStayKeepsChecklistAccessibleThenExplicitAndManualSelectionsPersist",
    ],
    "HealthTrackingAppUITests/TrainingHistoryUITests.swift": [
        "testHistoryEditDeleteAndMissingTemplateRecoveryUseRealRoutes",
    ],
    "Packages/HealthTrackingModules/Tests/TrainingKitTests/TrainingHapticControllerTests.swift": [
        "testSemanticEventsMapToExactFeedbackAndConditionalSuccessStaysSilent",
        "testSelectionUsesInjectedMonotonicClockAndOneHundredMillisecondThrottle",
        "testKillSwitchPersistsAcrossControllerReconstruction",
    ],
}
for relative_path, tokens in coverage_contracts.items():
    require_text_contract(relative_path, tokens)

if errors:
    raise SystemExit("\n".join(errors))
print("M0/M1 requirements verification passed.")
PY
}

self_test() {
    self_test_fixture="$(mktemp -d)"
    trap 'rm -rf -- "$self_test_fixture"' EXIT
    local fixture="$self_test_fixture"
    mkdir -p "$fixture/Packages/HealthTrackingModules/Sources/CoreModels/Models" "$fixture/Packages/HealthTrackingModules/Sources/GuidanceKit" "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit" "$fixture/App" "$fixture/docs/evidence/M0" "$fixture/docs/evidence/M1"
    cp "$repo_root/Packages/HealthTrackingModules/Package.swift" "$fixture/Packages/HealthTrackingModules/Package.swift"
    cp "$repo_root/project.yml" "$fixture/project.yml"
    cp "$repo_root/.gitignore" "$fixture/.gitignore"
    git -C "$fixture" init --quiet
    touch "$fixture/docs/evidence/M0/acceptance.md" "$fixture/docs/evidence/M1/acceptance.md"
    for model in AppReminder AppSetting BloodworkResult BodyMetric CooldownItem DailyNutritionLog ExerciseTemplate Food HealthCheckReminder MealEntry MoodLog PostureMetric Program ProgramPhase ProgramState ProgressPhoto Recipe SetLog SleepLog UserProfile WarmupItem WorkoutDayTemplate WorkoutSession WorkoutSessionProgress; do
        printf '@Model\npublic final class %s {}\n' "$model" > "$fixture/Packages/HealthTrackingModules/Sources/CoreModels/Models/$model.swift"
    done
    python3 - "$fixture" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
exercise_names = [
    "Goblet Squat", "Chin-up", "DB Floor Press", "DB Romanian Deadlift",
    "Prone Y-T-W", "Face Pull (bant)", "Tek Bacak Calf Raise", "Plank / Pallof",
    "DB RDL (çift)", "Tek Kol DB Row", "Push-up", "DB Overhead Press",
    "Bulgarian Split Squat", "Glute Bridge / Hip Thrust", "Wall Slide", "Dead Bug",
    "Copenhagen Plank", "Reverse Lunge (DB)", "Nordic Hamstring Curl",
    "Pull-up / bantlı", "Bantlı / Tek Kol Row", "Half-Kneeling DB Press",
    "DB Lateral Raise", "Farmer's Carry", "Curl", "Triceps", "Side Plank / Pallof",
]
contracts = {
    "README.md": ["## M1 training", "M1.16"],
    "HealthTrackingAppUITests/M1AcceptanceUITests.swift": [
        "testWeekABCAndAllTwentySevenSeedExercisesPublishMeasurementAndSafety",
        "testMissingRIRAndUnansweredOHPCannotPublishAnIncrease",
        "testFirstPerformanceIsBaselineAndOnlyARealImprovementIsPresentedAsPR",
        "testHapticKillSwitchPersistsAcrossRelaunch",
        "m1-acceptance-catalog",
        "m1-acceptance-progression-safety",
        "m1-acceptance-personal-records",
        "m1-acceptance-haptics-disabled",
        *exercise_names,
    ],
    "HealthTrackingAppUITests/TrainingAccessibilityUITests.swift": [
        "testVoiceOverOrderValuesActionsAndFiftyTwoPointSessionTargets",
        "testLightDarkAndDynamicTypeMatrixPassesSessionAudit",
        "testReduceMotionAndHighContrastFlowsRemainOperable",
        "testSmallPhoneAX5SessionRemainsOperable",
        "UICTContentSizeCategoryXXL",
        "UICTContentSizeCategoryAccessibilityXL",
        "UICTContentSizeCategoryAccessibilityXXXL",
        "performAccessibilityAudit",
        "scrollByShortDrag(",
        "with bounded drags",
    ],
    ".github/workflows/ios.yml": [
        "training_accessibility_expected",
        "m1_acceptance_expected",
        "test-small-phone",
        "scripts/select-simulator.sh --small",
        "m1-session-small-ax5",
        "HealthTrackingApp-small-phone-xcresult",
    ],
    "scripts/select-simulator.sh": [
        "--small", "iPhone SE (3rd generation)", "iPhone 13 mini",
    ],
    "Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift": [
        "today.accessibility.summary", ".accessibilityElement(children: .combine)",
    ],
    "Packages/HealthTrackingModules/Sources/TrainingKit/Session/SetEntryBar.swift": [
        "@Environment(\\.dynamicTypeSize)", ".accessibility3", "minWidth: 52",
        "minHeight: 52", "minimumHeight: 52", "session.set.save.hint",
    ],
    "Packages/HealthTrackingModules/Sources/DesignSystem/Components/PrimaryActionButton.swift": [
        "minimumHeight: CGFloat = 44",
        ".frame(maxWidth: .infinity, minHeight: minimumHeight)",
        ".frame(minWidth: minimumHeight, minHeight: minimumHeight)",
    ],
    "Packages/HealthTrackingModules/Sources/TrainingKit/Session/TrainingSessionView.swift": [
        "@Environment(\\.accessibilityReduceMotion)", ".transition(", "0.12",
    ],
    "Packages/HealthTrackingModules/Sources/TrainingKit/Session/WarmupStageView.swift": [
        "@AccessibilityFocusState", ".accessibilityFocused(",
    ],
    "Packages/HealthTrackingModules/Sources/TrainingKit/Session/ExerciseStageView.swift": [
        "@AccessibilityFocusState", ".accessibilityFocused(", "session.exercise.next.hint",
    ],
    "Packages/HealthTrackingModules/Sources/TrainingKit/Session/CooldownStageView.swift": [
        "@AccessibilityFocusState", ".accessibilityFocused(",
    ],
    "Packages/HealthTrackingModules/Sources/TrainingKit/Session/SessionSummaryView.swift": [
        "@AccessibilityFocusState", ".accessibilityFocused(",
    ],
    "App/Support/AppUITestLaunchConfiguration.swift": [
        "m1AcceptanceCatalog", "m1PRBaseline", "m1PRNew",
    ],
    "App/Application/AppDependencies.swift": [
        "installM1AcceptanceCatalog", "installM1PersonalRecord",
    ],
    "HealthTrackingAppUITests/TrainingSessionFlowUITests.swift": [
        "testGuidedOrderTapBudgetsSafetyAndOptionalSummary",
        "testResumeRestoresTheSameMovementAcrossRelaunch",
        "testMissingRIRHistoryNeverDisplaysALoadIncrease",
    ],
    "HealthTrackingAppUITests/OHPSafetyFlowUITests.swift": [
        "testPriorQuestionPrecedesWarmupAndCurrentSymptomsRouteToHalfKneeling",
    ],
    "HealthTrackingAppUITests/DeloadFlowUITests.swift": [
        "testScheduledWeekShowsVisibleWarningAndAcceptedDeloadLoad",
        "testReactiveTechniqueReviewSuppressesOnlyTheCurrentWeekWithoutMutation",
    ],
    "HealthTrackingAppUITests/PhaseTransitionFlowUITests.swift": [
        "testStayKeepsChecklistAccessibleThenExplicitAndManualSelectionsPersist",
    ],
    "HealthTrackingAppUITests/TrainingHistoryUITests.swift": [
        "testHistoryEditDeleteAndMissingTemplateRecoveryUseRealRoutes",
    ],
    "Packages/HealthTrackingModules/Tests/TrainingKitTests/TrainingHapticControllerTests.swift": [
        "testSemanticEventsMapToExactFeedbackAndConditionalSuccessStaysSilent",
        "testSelectionUsesInjectedMonotonicClockAndOneHundredMillisecondThrottle",
        "testKillSwitchPersistsAcrossControllerReconstruction",
    ],
}
for relative, tokens in contracts.items():
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(tokens) + "\n", encoding="utf-8")
PY
    verify_repo "$fixture"
    cp "$fixture/HealthTrackingAppUITests/TrainingAccessibilityUITests.swift" "$fixture/HealthTrackingAppUITests/TrainingAccessibilityUITests.valid.swift"
    printf '%s\n' 'app.swipeUp()' >> "$fixture/HealthTrackingAppUITests/TrainingAccessibilityUITests.swift"
    if verify_repo "$fixture" >"$fixture/m1-ax5-full-swipe.out" 2>&1; then
        echo "Requirements self-test expected an AX5 full-swipe regression failure." >&2
        return 1
    fi
    grep -Fq 'AX5 positioning must use bounded short drags instead of full swipes' "$fixture/m1-ax5-full-swipe.out"
    mv "$fixture/HealthTrackingAppUITests/TrainingAccessibilityUITests.valid.swift" "$fixture/HealthTrackingAppUITests/TrainingAccessibilityUITests.swift"
    cp "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift" "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.valid.swift"
    sed '/today\.accessibility\.summary/d' "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.valid.swift" > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift"
    if verify_repo "$fixture" >"$fixture/m1-today-summary.out" 2>&1; then
        echo "Requirements self-test expected a missing M1 Today summary contract failure." >&2
        return 1
    fi
    grep -Fq 'M1 contract Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift is missing required tokens' "$fixture/m1-today-summary.out"
    mv "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.valid.swift" "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/Today/TodayView.swift"
    cp "$fixture/Packages/HealthTrackingModules/Sources/DesignSystem/Components/PrimaryActionButton.swift" "$fixture/Packages/HealthTrackingModules/Sources/DesignSystem/Components/PrimaryActionButton.valid.swift"
    sed '/\.frame(minWidth: minimumHeight, minHeight: minimumHeight)/d' "$fixture/Packages/HealthTrackingModules/Sources/DesignSystem/Components/PrimaryActionButton.valid.swift" > "$fixture/Packages/HealthTrackingModules/Sources/DesignSystem/Components/PrimaryActionButton.swift"
    if verify_repo "$fixture" >"$fixture/m1-primary-action-size.out" 2>&1; then
        echo "Requirements self-test expected a missing M1 primary action sizing contract failure." >&2
        return 1
    fi
    grep -Fq 'M1 contract Packages/HealthTrackingModules/Sources/DesignSystem/Components/PrimaryActionButton.swift is missing required tokens' "$fixture/m1-primary-action-size.out"
    mv "$fixture/Packages/HealthTrackingModules/Sources/DesignSystem/Components/PrimaryActionButton.valid.swift" "$fixture/Packages/HealthTrackingModules/Sources/DesignSystem/Components/PrimaryActionButton.swift"
    mv "$fixture/docs/evidence/M1/acceptance.md" "$fixture/docs/evidence/M1/acceptance.valid.md"
    if verify_repo "$fixture" >"$fixture/m1-evidence.out" 2>&1; then
        echo "Requirements self-test expected a missing M1 evidence failure." >&2
        return 1
    fi
    grep -Fq 'Missing required M1 acceptance evidence: docs/evidence/M1/acceptance.md' "$fixture/m1-evidence.out"
    mv "$fixture/docs/evidence/M1/acceptance.valid.md" "$fixture/docs/evidence/M1/acceptance.md"
    python3 - "$fixture/Packages/HealthTrackingModules/Package.swift" <<'PY'
from pathlib import Path
path = Path(__import__('sys').argv[1])
path.write_text(path.read_text().replace('    targets: [', '        .executable(name: "Unexpected", targets: ["Unexpected"]),\n    targets: [', 1))
PY
    if verify_repo "$fixture" >"$fixture/product.out" 2>&1; then
        echo "Requirements self-test expected an extra product failure." >&2
        return 1
    fi
    grep -Fq 'Package products must be exactly' "$fixture/product.out"
    cp "$repo_root/Packages/HealthTrackingModules/Package.swift" "$fixture/Packages/HealthTrackingModules/Package.swift"
    python3 - "$fixture/project.yml" <<'PY'
from pathlib import Path
path = Path(__import__('sys').argv[1])
path.write_text(path.read_text().replace('    archive:\n      config: Release', '    archive:\n      config: Debug', 1))
PY
    if verify_repo "$fixture" >"$fixture/config.out" 2>&1; then
        echo "Requirements self-test expected a swapped scheme configuration failure." >&2
        return 1
    fi
    grep -Fq 'Local scheme must use exactly Debug run, Debug test, and Release archive contracts.' "$fixture/config.out"
    cp "$repo_root/project.yml" "$fixture/project.yml"
    python3 - "$fixture/project.yml" <<'PY'
from pathlib import Path
path = Path(__import__('sys').argv[1])
path.write_text(path.read_text().replace('    run:\n      config: Debug', '    run:', 1))
PY
    if verify_repo "$fixture" >"$fixture/missing-run.out" 2>&1; then
        echo "Requirements self-test expected a missing Local run config failure." >&2
        return 1
    fi
    grep -Fq 'Local scheme must use exactly Debug run, Debug test, and Release archive contracts.' "$fixture/missing-run.out"
    cp "$repo_root/project.yml" "$fixture/project.yml"
    printf '%s\n' '  Extra-Scheme:' '    run:' '      config: Debug' >> "$fixture/project.yml"
    if verify_repo "$fixture" >"$fixture/scheme.out" 2>&1; then
        echo "Requirements self-test expected an extra scheme failure." >&2
        return 1
    fi
    grep -Fq 'Schemes must be exactly' "$fixture/scheme.out"
    cp "$repo_root/project.yml" "$fixture/project.yml"
    python3 - "$fixture/project.yml" <<'PY'
from pathlib import Path
path = Path(__import__('sys').argv[1])
path.write_text(path.read_text().replace('    archive:\n      config: Cloud Release', '    test:\n      config: Cloud Debug\n    archive:\n      config: Cloud Release', 1))
PY
    if verify_repo "$fixture" >"$fixture/cloud-test.out" 2>&1; then
        echo "Requirements self-test expected a Cloud test action failure." >&2
        return 1
    fi
    grep -Fq 'Cloud scheme must not declare a test action; it is compile-only.' "$fixture/cloud-test.out"
    cp "$repo_root/project.yml" "$fixture/project.yml"
    python3 - "$fixture/project.yml" <<'PY'
from pathlib import Path
path = Path(__import__('sys').argv[1])
path.write_text(path.read_text().replace('        - package: HealthTrackingModules/GuidanceKitTests\n', '', 1))
PY
    if verify_repo "$fixture" >"$fixture/guidance-test-target.out" 2>&1; then
        echo "Requirements self-test expected a missing GuidanceKit scheme test target failure." >&2
        return 1
    fi
    grep -Fq 'Local scheme package tests must be exactly' "$fixture/guidance-test-target.out"
    cp "$repo_root/project.yml" "$fixture/project.yml"
    python3 - "$fixture/project.yml" <<'PY'
from pathlib import Path
path = Path(__import__('sys').argv[1])
path.write_text(path.read_text().replace('    archive:\n      config: Release', '    profile:\n      config: Release\n    archive:\n      config: Release', 1))
PY
    if verify_repo "$fixture" >"$fixture/extra-action.out" 2>&1; then
        echo "Requirements self-test expected an arbitrary extra Local action failure." >&2
        return 1
    fi
    grep -Fq "Local scheme actions must be exactly ['build', 'run', 'test', 'archive']" "$fixture/extra-action.out"
    cp "$repo_root/project.yml" "$fixture/project.yml"
    python3 - "$fixture/project.yml" <<'PY'
from pathlib import Path
path = Path(__import__('sys').argv[1])
path.write_text(path.read_text().replace('    archive:\n      config: Release', '    run:\n      config: Debug\n    archive:\n      config: Release', 1))
PY
    if verify_repo "$fixture" >"$fixture/duplicate-action.out" 2>&1; then
        echo "Requirements self-test expected a duplicate Local run action failure." >&2
        return 1
    fi
    grep -Fq "Local scheme actions must be exactly ['build', 'run', 'test', 'archive']" "$fixture/duplicate-action.out"
    cp "$repo_root/project.yml" "$fixture/project.yml"
    mkdir -p "$fixture/Packages/HealthTrackingModules/Sources/CoreModels/Models/Nested"
    printf '%s\n' '@Model' 'public final class ExtraNestedModel {}' '@Model' 'public final class SecondExtraNestedModel {}' > "$fixture/Packages/HealthTrackingModules/Sources/CoreModels/Models/Nested/ExtraModels.swift"
    if verify_repo "$fixture" >"$fixture/model.out" 2>&1; then
        echo "Requirements self-test expected nested extra model declarations to fail." >&2
        return 1
    fi
    grep -Fq 'SwiftData model names must be exactly' "$fixture/model.out"
    rm "$fixture/Packages/HealthTrackingModules/Sources/CoreModels/Models/Nested/ExtraModels.swift"
    printf '%s\n' 'import Foundation' 'import SwiftUI' > "$fixture/Packages/HealthTrackingModules/Sources/GuidanceKit/ForbiddenImport.swift"
    if verify_repo "$fixture" >"$fixture/guidance-import.out" 2>&1; then
        echo "Requirements self-test expected a forbidden GuidanceKit import failure." >&2
        return 1
    fi
    grep -Fq 'GuidanceKit must remain platform/persistence independent' "$fixture/guidance-import.out"
    rm "$fixture/Packages/HealthTrackingModules/Sources/GuidanceKit/ForbiddenImport.swift"
    printf '%s\n' 'import SwiftData' 'let context: ModelContext? = nil' > "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/PersistenceLeak.swift"
    if verify_repo "$fixture" >"$fixture/training-persistence.out" 2>&1; then
        echo "Requirements self-test expected a TrainingKit persistence leak failure." >&2
        return 1
    fi
    grep -Fq 'TrainingKit must not expose persistence implementation details' "$fixture/training-persistence.out"
    rm "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit/PersistenceLeak.swift"
    sed 's|^\(\*\.xcodeproj/\)$|# \1|' "$repo_root/.gitignore" > "$fixture/.gitignore"
    if verify_repo "$fixture" >"$fixture/commented-ignore.out" 2>&1; then
        echo "Requirements self-test expected a commented-only xcodeproj ignore rule failure." >&2
        return 1
    fi
    grep -Fq 'Generated HealthTrackingApp.xcodeproj must be actively ignored' "$fixture/commented-ignore.out"
    echo "Requirements verifier self-tests passed."
}

case "${1:-}" in
    "") verify_repo "$repo_root" ;;
    --self-test) self_test ;;
    *) echo "Usage: $0 [--self-test]" >&2; exit 2 ;;
esac
