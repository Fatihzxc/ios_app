#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

verify_repo() {
    local target_root="$1"
    python3 - "$target_root" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])

contracts = {
    "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionDay.swift": {
        "NutritionDayKey",
        "dateInterval(of: .day",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionInputs.swift": {
        "MealEntryCreateRequest",
        "MealEntrySourceRequest",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionMacros.swift": {
        "NutritionMacros",
        "MealEntryMacroResolver",
        "return resolvedMacros",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/Snapshots/NutritionSnapshots.swift": {
        "NutritionDayEntriesSnapshot",
        "MealEntrySourceSnapshot",
        "totalMacros",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/QuickAdd/NutritionQuickAddModels.swift": {
        "NutritionQuickAddRepository",
        "FrequentRecipeRanking",
        "NutritionQuickAddContext",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/QuickAdd/NutritionQuickAddViewModel.swift": {
        "projectedSnapshot",
        "requestID",
        "generation",
        "isCurrentSave",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/Day/NutritionDayViewModel.swift": {
        "selectedDay",
        "applyQuickAdd",
        "generation",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/Day/NutritionDayView.swift": {
        "nutrition.day.food-library",
        "nutrition.day.recipe-library",
        "nutrition.day.total",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/ManualEntry/NutritionManualEntryModels.swift": {
        "NutritionManualEntryMode",
        "NutritionManualEntryPhase",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/ManualEntry/NutritionManualEntryViewModel.swift": {
        "NutritionManualEntryViewModel",
        "createMealEntry",
        "requestID",
        "generation",
        ".food(",
        ".adhoc(",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/ManualEntry/NutritionManualEntryView.swift": {
        "NutritionManualEntryView",
        "accessibilityReduceMotion",
        "nutrition.manual.state.food-selection",
        "nutrition.manual.state.adhoc-entry",
        "nutrition.manual.category",
        "nutrition.manual.quantity",
        "nutrition.manual.confirm",
        "nutrition.manual.adhoc.name",
        "nutrition.manual.adhoc.quantity",
        "nutrition.manual.adhoc.calories",
        "nutrition.manual.adhoc.protein",
        "nutrition.manual.adhoc.carbs",
        "nutrition.manual.adhoc.fat",
        "nutrition.manual.adhoc.save",
        "nutrition.manual.retry",
        "nutrition.keyboard.dismiss",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/QuickAdd/NutritionQuickAddView.swift": {
        "nutrition.quick-add.manual.food",
        "nutrition.quick-add.manual.adhoc",
        "NutritionManualEntryView",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/FoodLibrary/FoodLibraryView.swift": {
        "nutrition.food.add",
        "nutrition.food.row.",
        "nutrition.food.delete.",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/FoodLibrary/FoodEditorView.swift": {
        "nutrition.food.editor.name",
        "nutrition.food.editor.serving-size",
        "nutrition.food.editor.calories",
        "nutrition.food.editor.save",
        "nutrition.food.editor.cancel",
        "nutrition.keyboard.dismiss",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/RecipeLibrary/RecipeLibraryView.swift": {
        "nutrition.recipe.add",
        "nutrition.recipe.row.",
        "nutrition.recipe.archive.",
        "nutrition.recipe.restore.",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/RecipeLibrary/RecipeEditorView.swift": {
        "nutrition.recipe.editor.name",
        "nutrition.recipe.editor.category",
        "nutrition.recipe.editor.servings",
        "nutrition.recipe.editor.calories",
        "nutrition.recipe.editor.save",
        "nutrition.recipe.editor.cancel",
        "nutrition.keyboard.dismiss",
    },
    "App/Application/AppDependencies.swift": {
        "nutritionManualEntryViewModel",
        "installM2Acceptance",
        "m2AcceptanceFoodID",
        "m2AcceptanceRecipeID",
    },
    "App/Application/AppBootstrapView.swift": {
        "nutritionManualEntryViewModel",
    },
    "App/Application/AppRootView.swift": {
        "nutritionManualEntryViewModel",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/Foundation/NutritionFoundationView.swift": {
        "manualEntryViewModel",
    },
    "App/Support/AppUITestLaunchConfiguration.swift": {
        "m2-acceptance",
    },
    "HealthTrackingAppUITests/M2AcceptanceUITests.swift": {
        "m2-acceptance-recipe-history",
        "m2-acceptance-mixed-sources",
        "nutrition.quick-add.confirm",
        "nutrition.manual.adhoc.save",
        "app.buttons[\"Kahvaltı\"]",
    },
    "HealthTrackingAppUITests/NutritionAccessibilityUITests.swift": {
        "m2-nutrition-ax5-adhoc",
        "m2-nutrition-dark-high-contrast-food",
        "m2-nutrition-reduce-motion",
    },
    "HealthTrackingAppUITests/NutritionQuickAddUITests.swift": {
        "testCategoryRecipeAndDefaultConfirmAreExactlyThreeTapsAndPersistAfterRelaunch",
        "nutrition-quick-add-saved-light",
        "nutrition.quick-add.confirm",
    },
    "Packages/HealthTrackingModules/Tests/NutritionKitTests/NutritionDayContractTests.swift": {
        "testDSTDaysUseCalendarIntervalsInsteadOfFixedSeconds",
        "testTheSameInstantUsesTheInjectedTimezoneDeterministically",
    },
    "Packages/HealthTrackingModules/Tests/NutritionKitTests/MealEntryResolutionTests.swift": {
        "testRecipeFoodAndAdhocResolutionUseTheirDistinctScalingContracts",
        "Ad-hoc values are already the final total",
    },
    "Packages/HealthTrackingModules/Tests/NutritionKitTests/QuickAddViewModelTests.swift": {
        "testConfirmPublishesOptimisticTotalsImmediatelyThenCanonicalSnapshot",
        "testFailureRollsBackExactlyAndRetryUsesTheSameRequestIDAndContext",
    },
    "Packages/HealthTrackingModules/Tests/NutritionKitTests/NutritionDayViewModelTests.swift": {
        "testPreviousNextAndPickerSelectionUseInjectedCalendarAcrossDST",
        "testPresentationDerivesCategoryTotalsDayTotalAndTargetedVersusUntargetedMacros",
        "testQuickAddSnapshotPublishesImmediatelyAndInvalidatesAnOlderSameDayLoad",
    },
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/FoodRepositoryTests.swift": {
        "testDeletingReferencedAndUnreferencedFoodsPreservesMealSnapshots",
    },
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/RecipeRepositoryTests.swift": {
        "testReferencedRemoveArchivesAndRestorePreservesMealEntrySnapshot",
        "testUpdateDoesNotChangeExistingMealEntrySnapshot",
    },
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/MealEntryRepositoryTests.swift": {
        "testRecipeFoodAndAdhocCreatePersistDistinctSourcesAndSelectedDay",
        "testArchivedRecipeAndDeletedFoodKeepHistoricalSnapshotsReadable",
    },
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/NutritionDayRepositoryTests.swift": {
        "testDuplicateLogicalDayFailsWithStableSortedIDsWithoutMutatingRows",
        "testSpringAndAutumnDSTDaysRemainDistinctCalendarIntervals",
    },
    "Packages/HealthTrackingModules/Tests/NutritionKitTests/ManualEntryViewModelTests.swift": {
        "NutritionManualEntryViewModel",
        "testAdhocMacrosAreFinalConsumedTotalsAndAreNotScaledAgain",
        "testFailedSaveRetriesWithTheSameRequestID",
        "testStaleLoadAndSaveCompletionsCannotOverwriteANewerIntent",
    },
}

texts = {}
missing = []
for relative_path, required_tokens in contracts.items():
    path = root / relative_path
    if not path.is_file():
        missing.append(relative_path)
        continue
    text = path.read_text(encoding="utf-8")
    texts[relative_path] = text
    absent = sorted(token for token in required_tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M2 contracts: {absent}")

if missing:
    raise SystemExit(f"Missing M2 production/test files: {sorted(missing)}")

required_support = {
    "project.yml": {
        "HealthTrackingAppUITests",
        "HealthTrackingModules/NutritionKitTests",
    },
    "scripts/test-ios.sh": {
        '"$script_dir/verify-nutrition.sh" --self-test',
        '"$script_dir/verify-nutrition.sh"',
        "-configuration Release",
    },
    ".github/workflows/ios.yml": {
        "scripts/verify-nutrition.sh --self-test",
        "scripts/verify-nutrition.sh",
        "M2AcceptanceUITests",
        "NutritionAccessibilityUITests",
        "m2-acceptance-recipe-history",
        "m2-acceptance-mixed-sources",
        "m2-nutrition-ax5-adhoc",
        "m2-nutrition-dark-high-contrast-food",
        "m2-nutrition-reduce-motion",
    },
    "Packages/HealthTrackingModules/Sources/NutritionKit/Resources/Localizable.xcstrings": {
        "nutrition.manual.food.action",
        "nutrition.manual.adhoc.action",
        "nutrition.manual.save",
        "nutrition.manual.retry",
    },
}

for relative_path, required_tokens in required_support.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M2 support file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    texts[relative_path] = text
    absent = sorted(token for token in required_tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M2 gate wiring: {absent}")

nutrition_root = root / "Packages/HealthTrackingModules/Sources/NutritionKit"
training_root = root / "Packages/HealthTrackingModules/Sources/TrainingKit"
nutrition_sources = sorted(nutrition_root.rglob("*.swift"))
training_sources = sorted(training_root.rglob("*.swift")) if training_root.is_dir() else []

for path in nutrition_sources:
    text = path.read_text(encoding="utf-8")
    if re.search(r"^\s*import\s+(SwiftData|TrainingKit)\s*$", text, re.MULTILINE):
        raise SystemExit(
            f"NutritionKit must not import persistence/cross-feature modules: {path.relative_to(root)}"
        )
    if re.search(r"(?:86_?400|86400)", text):
        raise SystemExit(
            f"Nutrition local-day code must not use fixed 24-hour seconds: {path.relative_to(root)}"
        )
    if re.search(r"\bCalendar\.current\b", text):
        raise SystemExit(
            f"Nutrition local-day code must use an injected calendar: {path.relative_to(root)}"
        )

for path in training_sources:
    if re.search(
        r"^\s*import\s+NutritionKit\s*$",
        path.read_text(encoding="utf-8"),
        re.MULTILINE,
    ):
        raise SystemExit(
            f"TrainingKit must not import NutritionKit: {path.relative_to(root)}"
        )

workflow = texts[".github/workflows/ios.yml"]
owner_blocks = {
    "M2AcceptanceUITests": (
        "m2_acceptance_expected",
        {
            "m2-acceptance-recipe-history",
            "m2-acceptance-mixed-sources",
        },
    ),
    "NutritionAccessibilityUITests": (
        "nutrition_accessibility_expected",
        {
            "m2-nutrition-ax5-adhoc",
            "m2-nutrition-dark-high-contrast-food",
            "m2-nutrition-reduce-motion",
        },
    ),
}
for owner, (variable, names) in owner_blocks.items():
    owner_index = workflow.find(f'"{owner}"')
    if owner_index < 0:
        raise SystemExit(f"Screenshot owner mapping is missing {owner}.")
    owner_mapping = workflow[owner_index:owner_index + 320]
    if f'"expected": {variable}' not in owner_mapping:
        raise SystemExit(f"Screenshot owner {owner} must use {variable}.")
    expected_match = re.search(
        rf"\b{re.escape(variable)}\s*=\s*\{{(?P<body>.*?)\}}",
        workflow,
        re.DOTALL,
    )
    if expected_match is None:
        raise SystemExit(f"Screenshot expected set is missing {variable}.")
    expected_body = expected_match.group("body")
    for name in names:
        if name not in expected_body:
            raise SystemExit(f"Screenshot owner {owner} is missing {name}.")

evidence = root / "docs/evidence/M2/acceptance.md"
if evidence.exists():
    evidence_text = evidence.read_text(encoding="utf-8")
    required_evidence_tokens = {
        "Accepted exact SHA",
        "Final GitHub Actions run",
        "RED/GREEN",
        "Cold launch",
        "Screenshot review",
        "Privacy/log scan",
        "Gitea",
    }
    absent = sorted(token for token in required_evidence_tokens if token not in evidence_text)
    if absent:
        raise SystemExit(f"M2 evidence is missing required sections: {absent}")
    if not re.search(r"Accepted exact SHA[^0-9a-f]+[0-9a-f]{40}\b", evidence_text):
        raise SystemExit("M2 evidence must contain one 40-character accepted exact SHA.")
    if not re.search(r"https://github\.com/[^\s)]+/actions/runs/\d+", evidence_text):
        raise SystemExit("M2 evidence must link the final GitHub Actions run.")

print("M2 nutrition verification passed.")
PY
}

self_test() {
    python3 - "$repo_root" <<'PY'
import subprocess
import sys
import tempfile
from pathlib import Path

script = Path(sys.argv[1]) / "scripts/verify-nutrition.sh"

contracts = {
    "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionDay.swift": "NutritionDayKey dateInterval(of: .day",
    "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionInputs.swift": "MealEntryCreateRequest MealEntrySourceRequest",
    "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionMacros.swift": "NutritionMacros MealEntryMacroResolver return resolvedMacros",
    "Packages/HealthTrackingModules/Sources/NutritionKit/Snapshots/NutritionSnapshots.swift": "NutritionDayEntriesSnapshot MealEntrySourceSnapshot totalMacros",
    "Packages/HealthTrackingModules/Sources/NutritionKit/QuickAdd/NutritionQuickAddModels.swift": "NutritionQuickAddRepository FrequentRecipeRanking NutritionQuickAddContext",
    "Packages/HealthTrackingModules/Sources/NutritionKit/QuickAdd/NutritionQuickAddViewModel.swift": "projectedSnapshot requestID generation isCurrentSave",
    "Packages/HealthTrackingModules/Sources/NutritionKit/Day/NutritionDayViewModel.swift": "selectedDay applyQuickAdd generation",
    "Packages/HealthTrackingModules/Sources/NutritionKit/Day/NutritionDayView.swift": "nutrition.day.food-library nutrition.day.recipe-library nutrition.day.total",
    "Packages/HealthTrackingModules/Sources/NutritionKit/ManualEntry/NutritionManualEntryModels.swift": "NutritionManualEntryMode NutritionManualEntryPhase",
    "Packages/HealthTrackingModules/Sources/NutritionKit/ManualEntry/NutritionManualEntryViewModel.swift": "NutritionManualEntryViewModel createMealEntry requestID generation .food( .adhoc(",
    "Packages/HealthTrackingModules/Sources/NutritionKit/ManualEntry/NutritionManualEntryView.swift": "NutritionManualEntryView accessibilityReduceMotion nutrition.manual.state.food-selection nutrition.manual.state.adhoc-entry nutrition.manual.category nutrition.manual.quantity nutrition.manual.confirm nutrition.manual.adhoc.name nutrition.manual.adhoc.quantity nutrition.manual.adhoc.calories nutrition.manual.adhoc.protein nutrition.manual.adhoc.carbs nutrition.manual.adhoc.fat nutrition.manual.adhoc.save nutrition.manual.retry nutrition.keyboard.dismiss",
    "Packages/HealthTrackingModules/Sources/NutritionKit/QuickAdd/NutritionQuickAddView.swift": "nutrition.quick-add.manual.food nutrition.quick-add.manual.adhoc NutritionManualEntryView",
    "Packages/HealthTrackingModules/Sources/NutritionKit/FoodLibrary/FoodLibraryView.swift": "nutrition.food.add nutrition.food.row. nutrition.food.delete.",
    "Packages/HealthTrackingModules/Sources/NutritionKit/FoodLibrary/FoodEditorView.swift": "nutrition.food.editor.name nutrition.food.editor.serving-size nutrition.food.editor.calories nutrition.food.editor.save nutrition.food.editor.cancel nutrition.keyboard.dismiss",
    "Packages/HealthTrackingModules/Sources/NutritionKit/RecipeLibrary/RecipeLibraryView.swift": "nutrition.recipe.add nutrition.recipe.row. nutrition.recipe.archive. nutrition.recipe.restore.",
    "Packages/HealthTrackingModules/Sources/NutritionKit/RecipeLibrary/RecipeEditorView.swift": "nutrition.recipe.editor.name nutrition.recipe.editor.category nutrition.recipe.editor.servings nutrition.recipe.editor.calories nutrition.recipe.editor.save nutrition.recipe.editor.cancel nutrition.keyboard.dismiss",
    "App/Application/AppDependencies.swift": "nutritionManualEntryViewModel installM2Acceptance m2AcceptanceFoodID m2AcceptanceRecipeID",
    "App/Application/AppBootstrapView.swift": "nutritionManualEntryViewModel",
    "App/Application/AppRootView.swift": "nutritionManualEntryViewModel",
    "Packages/HealthTrackingModules/Sources/NutritionKit/Foundation/NutritionFoundationView.swift": "manualEntryViewModel",
    "App/Support/AppUITestLaunchConfiguration.swift": "m2-acceptance",
    "HealthTrackingAppUITests/M2AcceptanceUITests.swift": "m2-acceptance-recipe-history m2-acceptance-mixed-sources nutrition.quick-add.confirm nutrition.manual.adhoc.save nutrition.keyboard.dismiss app.buttons[\"Kahvaltı\"]",
    "HealthTrackingAppUITests/NutritionAccessibilityUITests.swift": "m2-nutrition-ax5-adhoc m2-nutrition-dark-high-contrast-food m2-nutrition-reduce-motion nutrition.keyboard.dismiss",
    "HealthTrackingAppUITests/NutritionQuickAddUITests.swift": "testCategoryRecipeAndDefaultConfirmAreExactlyThreeTapsAndPersistAfterRelaunch nutrition-quick-add-saved-light nutrition.quick-add.confirm",
    "Packages/HealthTrackingModules/Tests/NutritionKitTests/NutritionDayContractTests.swift": "testDSTDaysUseCalendarIntervalsInsteadOfFixedSeconds testTheSameInstantUsesTheInjectedTimezoneDeterministically",
    "Packages/HealthTrackingModules/Tests/NutritionKitTests/MealEntryResolutionTests.swift": "testRecipeFoodAndAdhocResolutionUseTheirDistinctScalingContracts Ad-hoc values are already the final total",
    "Packages/HealthTrackingModules/Tests/NutritionKitTests/QuickAddViewModelTests.swift": "testConfirmPublishesOptimisticTotalsImmediatelyThenCanonicalSnapshot testFailureRollsBackExactlyAndRetryUsesTheSameRequestIDAndContext",
    "Packages/HealthTrackingModules/Tests/NutritionKitTests/NutritionDayViewModelTests.swift": "testPreviousNextAndPickerSelectionUseInjectedCalendarAcrossDST testPresentationDerivesCategoryTotalsDayTotalAndTargetedVersusUntargetedMacros testQuickAddSnapshotPublishesImmediatelyAndInvalidatesAnOlderSameDayLoad",
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/FoodRepositoryTests.swift": "testDeletingReferencedAndUnreferencedFoodsPreservesMealSnapshots",
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/RecipeRepositoryTests.swift": "testReferencedRemoveArchivesAndRestorePreservesMealEntrySnapshot testUpdateDoesNotChangeExistingMealEntrySnapshot",
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/MealEntryRepositoryTests.swift": "testRecipeFoodAndAdhocCreatePersistDistinctSourcesAndSelectedDay testArchivedRecipeAndDeletedFoodKeepHistoricalSnapshotsReadable",
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/NutritionDayRepositoryTests.swift": "testDuplicateLogicalDayFailsWithStableSortedIDsWithoutMutatingRows testSpringAndAutumnDSTDaysRemainDistinctCalendarIntervals",
    "Packages/HealthTrackingModules/Tests/NutritionKitTests/ManualEntryViewModelTests.swift": "NutritionManualEntryViewModel testAdhocMacrosAreFinalConsumedTotalsAndAreNotScaledAgain testFailedSaveRetriesWithTheSameRequestID testStaleLoadAndSaveCompletionsCannotOverwriteANewerIntent",
    "project.yml": "HealthTrackingAppUITests HealthTrackingModules/NutritionKitTests",
    "scripts/test-ios.sh": '"$script_dir/verify-nutrition.sh" --self-test\n"$script_dir/verify-nutrition.sh"\n-configuration Release',
    ".github/workflows/ios.yml": 'scripts/verify-nutrition.sh --self-test\nscripts/verify-nutrition.sh\nm2_acceptance_expected = {"m2-acceptance-recipe-history", "m2-acceptance-mixed-sources"}\nnutrition_accessibility_expected = {"m2-nutrition-ax5-adhoc", "m2-nutrition-dark-high-contrast-food", "m2-nutrition-reduce-motion"}\nowners = {\n"M2AcceptanceUITests": {"expected": m2_acceptance_expected},\n"NutritionAccessibilityUITests": {"expected": nutrition_accessibility_expected},\n}',
    "Packages/HealthTrackingModules/Sources/NutritionKit/Resources/Localizable.xcstrings": "nutrition.manual.food.action nutrition.manual.adhoc.action nutrition.manual.save nutrition.manual.retry nutrition.keyboard.dismiss",
}

def make_fixture(base: Path) -> None:
    for relative, content in contracts.items():
        path = base / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content + "\n", encoding="utf-8")
    training = base / "Packages/HealthTrackingModules/Sources/TrainingKit/Boundary.swift"
    training.parent.mkdir(parents=True, exist_ok=True)
    training.write_text("struct Boundary {}\n", encoding="utf-8")
    evidence = base / "docs/evidence/M2/acceptance.md"
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(
        "\n".join(
            [
                "Accepted exact SHA: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "Final GitHub Actions run: https://github.com/example/project/actions/runs/1",
                "RED/GREEN",
                "Cold launch",
                "Screenshot review",
                "Privacy/log scan",
                "Gitea",
            ]
        )
        + "\n",
        encoding="utf-8",
    )

def run(root: Path, expected=None) -> None:
    completed = subprocess.run(
        [str(script), "--verify-root", str(root)],
        cwd=script.parent.parent,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if expected is None:
        if completed.returncode != 0:
            raise SystemExit(f"M2 verifier fixture unexpectedly failed:\n{completed.stdout}")
    elif completed.returncode == 0 or expected not in completed.stdout:
        raise SystemExit(
            f"M2 verifier mutation did not fail closed for {expected!r}:\n{completed.stdout}"
        )

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    make_fixture(root)
    run(root)

    manual_view = root / "Packages/HealthTrackingModules/Sources/NutritionKit/ManualEntry/NutritionManualEntryView.swift"
    original = manual_view.read_text(encoding="utf-8")
    manual_view.write_text(original.replace("nutrition.manual.confirm", ""), encoding="utf-8")
    run(root, "nutrition.manual.confirm")
    manual_view.write_text(original, encoding="utf-8")

    boundary = root / "Packages/HealthTrackingModules/Sources/NutritionKit/Forbidden.swift"
    boundary.write_text("import SwiftData\n", encoding="utf-8")
    run(root, "must not import persistence/cross-feature modules")
    boundary.unlink()

    day_math = root / "Packages/HealthTrackingModules/Sources/NutritionKit/BadDay.swift"
    day_math.write_text("date.addingTimeInterval(86_400)\n", encoding="utf-8")
    run(root, "fixed 24-hour seconds")
    day_math.unlink()

    workflow = root / ".github/workflows/ios.yml"
    original = workflow.read_text(encoding="utf-8")
    workflow.write_text(
        original.replace("scripts/verify-nutrition.sh --self-test", ""),
        encoding="utf-8",
    )
    run(root, "verify-nutrition.sh --self-test")
    workflow.write_text(original, encoding="utf-8")

    evidence = root / "docs/evidence/M2/acceptance.md"
    valid_evidence = evidence.read_text(encoding="utf-8")
    evidence.unlink()
    run(root, "M2 evidence file is required")
    evidence.write_text(valid_evidence, encoding="utf-8")

    evidence.write_text("Accepted exact SHA: pending\n", encoding="utf-8")
    run(root, "M2 evidence is missing required sections")

print("M2 nutrition verifier self-tests passed.")
PY
}

case "${1:-}" in
    "") verify_repo "$repo_root" ;;
    --self-test) self_test ;;
    --verify-root)
        if (( $# != 2 )) || [[ -z "$2" ]]; then
            echo "Usage: $0 [--self-test|--verify-root PATH]" >&2
            exit 2
        fi
        verify_repo "$2"
        ;;
    *) echo "Usage: $0 [--self-test|--verify-root PATH]" >&2; exit 2 ;;
esac
