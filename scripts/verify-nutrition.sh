#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

python3 - "$repo_root" "${1:-}" <<'PY'
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path


class VerificationError(RuntimeError):
    pass


# M2 evidence is enabled only after an exact hosted GREEN candidate exists.
# The self-test always exercises the evidence contract; finalization flips this.
REQUIRE_EVIDENCE = False


def read(path: Path) -> str:
    if not path.is_file():
        raise VerificationError(f"Missing Nutrition contract file: {path}")
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise VerificationError(f"Unable to read {path}: {error}") from error


def require_tokens(path: Path, tokens, label: str) -> str:
    text = read(path)
    missing = sorted(token for token in tokens if token not in text)
    if missing:
        raise VerificationError(f"{label} is missing required contracts: {missing}")
    return text


def swift_sources(root: Path, relative: str):
    source_root = root / relative
    if not source_root.is_dir():
        raise VerificationError(f"Missing source boundary: {relative}")
    return sorted(source_root.rglob("*.swift"))


def verify_localization(path: Path):
    try:
        catalog = json.loads(read(path))
    except json.JSONDecodeError as error:
        raise VerificationError(f"Invalid Nutrition localization catalog: {error}") from error
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        raise VerificationError("Nutrition localization catalog needs a strings object.")
    required = {
        "nutrition.day.foodLibrary",
        "nutrition.day.foodLibrary.hint",
        "nutrition.day.recipeLibrary",
        "nutrition.day.recipeLibrary.hint",
        "nutrition.food.add",
        "nutrition.food.add.hint",
        "nutrition.food.delete",
        "nutrition.food.delete.hint",
        "nutrition.food.editor.cancel",
        "nutrition.food.editor.cancel.hint",
        "nutrition.food.editor.save",
        "nutrition.food.editor.save.hint",
        "nutrition.recipe.add",
        "nutrition.recipe.add.hint",
        "nutrition.recipe.remove",
        "nutrition.recipe.remove.hint",
        "nutrition.recipe.restore",
        "nutrition.recipe.restore.hint",
        "nutrition.recipe.editor.cancel",
        "nutrition.recipe.editor.cancel.hint",
        "nutrition.recipe.editor.save",
        "nutrition.recipe.editor.save.hint",
        "nutrition.quickAdd.confirm",
        "nutrition.quickAdd.confirm.hint",
    }
    missing = sorted(required - set(strings))
    if missing:
        raise VerificationError(f"Nutrition localization keys are missing: {missing}")
    invalid = []
    for key in sorted(required):
        unit = (
            strings.get(key, {})
            .get("localizations", {})
            .get("tr", {})
            .get("stringUnit", {})
        )
        value = unit.get("value")
        if unit.get("state") != "translated" or not isinstance(value, str) or not value.strip():
            invalid.append(key)
    if invalid:
        raise VerificationError(
            f"Nutrition Turkish accessibility/action translations are invalid: {invalid}"
        )


def verify_evidence(path: Path):
    text = read(path)
    required = {
        "# M2 acceptance evidence",
        "## Task history",
        "## Hosted acceptance detail",
        "## Screenshot and artifact review",
        "## Review and remote record",
        "## Device and external-service evidence",
        "Fable",
        "NOT RUN",
        "BLOCKED",
        "Critical",
        "Important",
        "READY",
    }
    missing = sorted(token for token in required if token not in text)
    if missing:
        raise VerificationError(f"M2 evidence is missing exact-data fields: {missing}")
    for task in range(1, 9):
        if f"M2.{task}" not in text:
            raise VerificationError(f"M2 evidence is missing task M2.{task}.")
    shas = set(re.findall(r"\b[0-9a-f]{40}\b", text))
    run_urls = set(re.findall(r"https://github\.com/[^\s)]+/actions/runs/\d+", text))
    if len(shas) < 16 or len(run_urls) < 16:
        raise VerificationError(
            "M2 evidence must record at least one RED/GREEN SHA and run pair per task."
        )


def verify(root: Path, require_evidence: bool):
    nutrition_root = root / "Packages/HealthTrackingModules/Sources/NutritionKit"
    training_root = root / "Packages/HealthTrackingModules/Sources/TrainingKit"
    day_view = nutrition_root / "Day/NutritionDayView.swift"
    day_domain = nutrition_root / "Domain/NutritionDay.swift"
    macros = nutrition_root / "Domain/NutritionMacros.swift"
    inputs = nutrition_root / "Domain/NutritionInputs.swift"
    snapshots = nutrition_root / "Snapshots/NutritionSnapshots.swift"
    day_view_model = nutrition_root / "Day/NutritionDayViewModel.swift"
    quick_view_model = nutrition_root / "QuickAdd/NutritionQuickAddViewModel.swift"
    quick_repository = nutrition_root / "Repository/MealEntryRepository.swift"
    food_library = nutrition_root / "FoodLibrary/FoodLibraryView.swift"
    food_editor = nutrition_root / "FoodLibrary/FoodEditorView.swift"
    recipe_library = nutrition_root / "RecipeLibrary/RecipeLibraryView.swift"
    recipe_editor = nutrition_root / "RecipeLibrary/RecipeEditorView.swift"
    persistence_repository = root / (
        "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/"
        "SwiftDataNutritionRepository.swift"
    )
    acceptance_tests = root / "HealthTrackingAppUITests/M2AcceptanceUITests.swift"
    accessibility_tests = root / (
        "HealthTrackingAppUITests/NutritionAccessibilityUITests.swift"
    )
    quick_ui_tests = root / "HealthTrackingAppUITests/NutritionQuickAddUITests.swift"
    workflow = root / ".github/workflows/ios.yml"
    test_script = root / "scripts/test-ios.sh"
    project = root / "project.yml"
    catalog = nutrition_root / "Resources/Localizable.xcstrings"

    require_tokens(day_domain, ["public struct NutritionDayKey"], "Local-day domain")
    require_tokens(macros, ["public struct NutritionMacros"], "Decimal macro domain")
    require_tokens(
        inputs,
        ["public struct FoodInput", "public struct RecipeInput", "MealEntryCreateRequest"],
        "Nutrition inputs",
    )
    require_tokens(snapshots, ["public struct MealEntrySnapshot"], "Meal snapshots")
    require_tokens(
        day_view_model,
        ["public struct NutritionDayPresentation"],
        "Nutrition day presentation",
    )
    require_tokens(
        quick_view_model,
        ["public final class NutritionQuickAddViewModel"],
        "Quick Add view model",
    )
    require_tokens(
        quick_repository,
        ["public protocol NutritionQuickAddRepository"],
        "Quick Add repository",
    )

    require_tokens(
        day_view,
        [
            "nutrition.day.food-library",
            "nutrition.day.recipe-library",
            "\(sectionIdentifier(section.category)).add",
            "nutrition.day.total",
        ],
        "Nutrition day accessibility UI",
    )
    require_tokens(
        food_library,
        [
            "nutrition.food.add",
            "nutrition.food.row.",
            "nutrition.food.delete.",
            "nutrition.food.library",
        ],
        "Food library accessibility UI",
    )
    require_tokens(
        food_editor,
        [
            "nutrition.food.field.name",
            "nutrition.food.field.brand",
            "nutrition.food.field.servingSize",
            "nutrition.food.field.servingUnit",
            "nutrition.food.field.calories",
            "nutrition.food.field.protein",
            "nutrition.food.field.carbs",
            "nutrition.food.field.fat",
            "nutrition.food.field.fiber",
            "nutrition.food.editor.cancel",
            "nutrition.food.editor.save",
            "AppColors.color(.stateDanger",
        ],
        "Food editor accessibility UI",
    )
    require_tokens(
        recipe_library,
        [
            "nutrition.recipe.filter",
            "nutrition.recipe.add",
            "nutrition.recipe.row.",
            "nutrition.recipe.remove.",
            "nutrition.recipe.archived.",
            "nutrition.recipe.restore.",
            "nutrition.recipe.library",
        ],
        "Recipe library accessibility UI",
    )
    require_tokens(
        recipe_editor,
        [
            "nutrition.recipe.field.name",
            "nutrition.recipe.field.category",
            "nutrition.recipe.field.servings",
            "nutrition.recipe.field.calories",
            "nutrition.recipe.field.protein",
            "nutrition.recipe.field.carbs",
            "nutrition.recipe.field.fat",
            "nutrition.recipe.field.note",
            "nutrition.recipe.editor.cancel",
            "nutrition.recipe.editor.save",
            "AppColors.color(.stateDanger",
        ],
        "Recipe editor accessibility UI",
    )

    require_tokens(
        acceptance_tests,
        [
            "testFoodCreateEditDeleteAndHistoricalSnapshotSurviveRelaunch",
            "testRecipeCreateEditArchiveRestoreAndHistoricalSnapshotSurviveRelaunch",
            "m2-acceptance-food-library",
            "m2-acceptance-food-snapshot-total",
            "m2-acceptance-recipe-archived",
            "m2-acceptance-recipe-snapshot-total",
            "m2-acceptance-recipe-restored",
        ],
        "M2 acceptance UI tests",
    )
    require_tokens(
        accessibility_tests,
        [
            "testAX5LibraryActionsExposeVoiceOverOrderLabelsAndTouchTargets",
            "testRecipeEditorDarkAX5UsesSemanticErrorAndOperableControls",
            "testQuickAddRemainsOperableWithReduceMotionAndIncreaseContrast",
            "m2-nutrition-voiceover-ax5",
            "m2-recipe-editor-dark-ax5",
            "m2-nutrition-reduce-motion-total",
            "m2-nutrition-high-contrast",
        ],
        "Nutrition accessibility UI tests",
    )
    require_tokens(
        quick_ui_tests,
        ["testCategoryRouteSavesInExactlyThreeTapsAndPersistsAfterRelaunch"],
        "Three-tap Quick Add UI test",
    )

    test_contracts = {
        "Packages/HealthTrackingModules/Tests/NutritionKitTests/NutritionDayContractTests.swift": [
            "testHoursWithinTheSameLocalDayResolveToOneImmutableKey",
            "testDSTDaysUseCalendarIntervalsInsteadOfFixedSeconds",
            "testTheSameInstantUsesTheInjectedTimezoneDeterministically",
        ],
        "Packages/HealthTrackingModules/Tests/NutritionKitTests/MealEntryResolutionTests.swift": [
            "testRecipeFoodAndAdhocResolutionUseTheirDistinctScalingContracts"
        ],
        "Packages/HealthTrackingModules/Tests/PersistenceKitTests/FoodRepositoryTests.swift": [
            "testDeletingReferencedAndUnreferencedFoodsPreservesMealSnapshots",
            "testUpdateAndDeleteSaveFailuresRollbackExistingFood",
        ],
        "Packages/HealthTrackingModules/Tests/PersistenceKitTests/RecipeRepositoryTests.swift": [
            "testReferencedRemoveArchivesAndRestorePreservesMealEntrySnapshot",
            "testUpdateDoesNotChangeExistingMealEntrySnapshot",
            "testHardDeleteArchiveAndRestoreSaveFailuresRollbackAtomically",
        ],
        "Packages/HealthTrackingModules/Tests/PersistenceKitTests/MealEntryRepositoryTests.swift": [
            "testArchivedRecipeAndDeletedFoodKeepHistoricalSnapshotsReadable",
            "testCreateUpdateAndDeleteSaveFailuresRollbackAtomically",
        ],
    }
    for relative, tokens in test_contracts.items():
        require_tokens(root / relative, tokens, f"Nutrition regression tests ({relative})")

    project_text = require_tokens(
        project,
        [
            "package: HealthTrackingModules/NutritionKitTests",
            "HealthTrackingAppUITests",
        ],
        "Local scheme test wiring",
    )
    if project_text.count("package: HealthTrackingModules/NutritionKitTests") != 1:
        raise VerificationError("Local scheme must wire NutritionKitTests exactly once.")

    require_tokens(
        test_script,
        ["verify-nutrition.sh\" --self-test", "verify-nutrition.sh\""],
        "Local Nutrition verifier wiring",
    )
    workflow_text = require_tokens(
        workflow,
        [
            "scripts/verify-nutrition.sh --self-test",
            "scripts/verify-nutrition.sh",
            "M2AcceptanceUITests",
            "NutritionAccessibilityUITests",
            "m2-acceptance-food-library",
            "m2-acceptance-food-snapshot-total",
            "m2-acceptance-recipe-archived",
            "m2-acceptance-recipe-snapshot-total",
            "m2-acceptance-recipe-restored",
            "m2-nutrition-voiceover-ax5",
            "m2-recipe-editor-dark-ax5",
            "m2-nutrition-reduce-motion-total",
            "m2-nutrition-high-contrast",
        ],
        "Hosted Nutrition verifier and screenshot wiring",
    )
    if "timeout-minutes: 70" not in workflow_text:
        raise VerificationError("The expanded M2 full suite needs its documented 70-minute step budget.")

    nutrition_sources = swift_sources(
        root, "Packages/HealthTrackingModules/Sources/NutritionKit"
    )
    training_sources = swift_sources(
        root, "Packages/HealthTrackingModules/Sources/TrainingKit"
    )
    for path in nutrition_sources:
        text = read(path)
        if re.search(r"(?m)^\s*import\s+SwiftData\s*$", text) or "ModelContext" in text:
            raise VerificationError(f"NutritionKit must not own SwiftData: {path}")
        if re.search(r"(?m)^\s*import\s+TrainingKit\s*$", text):
            raise VerificationError(f"NutritionKit must not import TrainingKit: {path}")
    for path in training_sources:
        if re.search(r"(?m)^\s*import\s+NutritionKit\s*$", read(path)):
            raise VerificationError(f"TrainingKit must not import NutritionKit: {path}")

    local_day_paths = nutrition_sources + [persistence_repository]
    for path in local_day_paths:
        text = read(path)
        if re.search(r"\b(?:86_400|86400)\b", text):
            raise VerificationError(f"Local-day code must not use fixed seconds: {path}")
        if "Calendar.current" in text:
            raise VerificationError(f"Local-day code must use an injected Calendar: {path}")

    verify_localization(catalog)
    if require_evidence:
        verify_evidence(root / "docs/evidence/M2/acceptance.md")


def write_fixture(root: Path):
    files = {
        "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionDay.swift": (
            "public struct NutritionDayKey {}\n"
        ),
        "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionMacros.swift": (
            "public struct NutritionMacros {}\n"
        ),
        "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionInputs.swift": (
            "public struct FoodInput {}\npublic struct RecipeInput {}\n"
            "public struct MealEntryCreateRequest {}\n"
        ),
        "Packages/HealthTrackingModules/Sources/NutritionKit/Snapshots/NutritionSnapshots.swift": (
            "public struct MealEntrySnapshot {}\n"
        ),
        "Packages/HealthTrackingModules/Sources/NutritionKit/Day/NutritionDayViewModel.swift": (
            "public struct NutritionDayPresentation {}\n"
        ),
        "Packages/HealthTrackingModules/Sources/NutritionKit/QuickAdd/NutritionQuickAddViewModel.swift": (
            "public final class NutritionQuickAddViewModel {}\n"
        ),
        "Packages/HealthTrackingModules/Sources/NutritionKit/Repository/MealEntryRepository.swift": (
            "public protocol NutritionQuickAddRepository {}\n"
        ),
        "Packages/HealthTrackingModules/Sources/NutritionKit/Day/NutritionDayView.swift": (
            "nutrition.day.food-library nutrition.day.recipe-library "
            "\\(sectionIdentifier(section.category)).add nutrition.day.total\n"
        ),
        "Packages/HealthTrackingModules/Sources/NutritionKit/FoodLibrary/FoodLibraryView.swift": (
            "nutrition.food.add nutrition.food.row. nutrition.food.delete. nutrition.food.library\n"
        ),
        "Packages/HealthTrackingModules/Sources/NutritionKit/FoodLibrary/FoodEditorView.swift": (
            "nutrition.food.field.name nutrition.food.field.brand "
            "nutrition.food.field.servingSize nutrition.food.field.servingUnit "
            "nutrition.food.field.calories nutrition.food.field.protein "
            "nutrition.food.field.carbs nutrition.food.field.fat nutrition.food.field.fiber "
            "nutrition.food.editor.cancel nutrition.food.editor.save AppColors.color(.stateDanger\n"
        ),
        "Packages/HealthTrackingModules/Sources/NutritionKit/RecipeLibrary/RecipeLibraryView.swift": (
            "nutrition.recipe.filter nutrition.recipe.add nutrition.recipe.row. "
            "nutrition.recipe.remove. nutrition.recipe.archived. nutrition.recipe.restore. "
            "nutrition.recipe.library\n"
        ),
        "Packages/HealthTrackingModules/Sources/NutritionKit/RecipeLibrary/RecipeEditorView.swift": (
            "nutrition.recipe.field.name nutrition.recipe.field.category "
            "nutrition.recipe.field.servings nutrition.recipe.field.calories "
            "nutrition.recipe.field.protein nutrition.recipe.field.carbs "
            "nutrition.recipe.field.fat nutrition.recipe.field.note "
            "nutrition.recipe.editor.cancel nutrition.recipe.editor.save "
            "AppColors.color(.stateDanger\n"
        ),
        "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataNutritionRepository.swift": (
            "let injectedCalendar = value\n"
        ),
        "Packages/HealthTrackingModules/Sources/TrainingKit/Today.swift": "struct Today {}\n",
        "HealthTrackingAppUITests/M2AcceptanceUITests.swift": (
            "testFoodCreateEditDeleteAndHistoricalSnapshotSurviveRelaunch "
            "testRecipeCreateEditArchiveRestoreAndHistoricalSnapshotSurviveRelaunch "
            "m2-acceptance-food-library m2-acceptance-food-snapshot-total "
            "m2-acceptance-recipe-archived m2-acceptance-recipe-snapshot-total "
            "m2-acceptance-recipe-restored\n"
        ),
        "HealthTrackingAppUITests/NutritionAccessibilityUITests.swift": (
            "testAX5LibraryActionsExposeVoiceOverOrderLabelsAndTouchTargets "
            "testRecipeEditorDarkAX5UsesSemanticErrorAndOperableControls "
            "testQuickAddRemainsOperableWithReduceMotionAndIncreaseContrast "
            "m2-nutrition-voiceover-ax5 m2-recipe-editor-dark-ax5 "
            "m2-nutrition-reduce-motion-total m2-nutrition-high-contrast\n"
        ),
        "HealthTrackingAppUITests/NutritionQuickAddUITests.swift": (
            "testCategoryRouteSavesInExactlyThreeTapsAndPersistsAfterRelaunch\n"
        ),
        "Packages/HealthTrackingModules/Tests/NutritionKitTests/NutritionDayContractTests.swift": (
            "testHoursWithinTheSameLocalDayResolveToOneImmutableKey "
            "testDSTDaysUseCalendarIntervalsInsteadOfFixedSeconds "
            "testTheSameInstantUsesTheInjectedTimezoneDeterministically\n"
        ),
        "Packages/HealthTrackingModules/Tests/NutritionKitTests/MealEntryResolutionTests.swift": (
            "testRecipeFoodAndAdhocResolutionUseTheirDistinctScalingContracts\n"
        ),
        "Packages/HealthTrackingModules/Tests/PersistenceKitTests/FoodRepositoryTests.swift": (
            "testDeletingReferencedAndUnreferencedFoodsPreservesMealSnapshots "
            "testUpdateAndDeleteSaveFailuresRollbackExistingFood\n"
        ),
        "Packages/HealthTrackingModules/Tests/PersistenceKitTests/RecipeRepositoryTests.swift": (
            "testReferencedRemoveArchivesAndRestorePreservesMealEntrySnapshot "
            "testUpdateDoesNotChangeExistingMealEntrySnapshot "
            "testHardDeleteArchiveAndRestoreSaveFailuresRollbackAtomically\n"
        ),
        "Packages/HealthTrackingModules/Tests/PersistenceKitTests/MealEntryRepositoryTests.swift": (
            "testArchivedRecipeAndDeletedFoodKeepHistoricalSnapshotsReadable "
            "testCreateUpdateAndDeleteSaveFailuresRollbackAtomically\n"
        ),
        "project.yml": (
            "HealthTrackingAppUITests\n"
            "- package: HealthTrackingModules/NutritionKitTests\n"
        ),
        "scripts/test-ios.sh": (
            '"$script_dir/verify-nutrition.sh" --self-test\n'
            '"$script_dir/verify-nutrition.sh"\n'
        ),
        ".github/workflows/ios.yml": (
            "scripts/verify-nutrition.sh --self-test\n"
            "scripts/verify-nutrition.sh\n"
            "timeout-minutes: 70\n"
            "M2AcceptanceUITests NutritionAccessibilityUITests\n"
            "m2-acceptance-food-library m2-acceptance-food-snapshot-total "
            "m2-acceptance-recipe-archived m2-acceptance-recipe-snapshot-total "
            "m2-acceptance-recipe-restored m2-nutrition-voiceover-ax5 "
            "m2-recipe-editor-dark-ax5 m2-nutrition-reduce-motion-total "
            "m2-nutrition-high-contrast\n"
        ),
    }
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    localization_keys = [
        "nutrition.day.foodLibrary",
        "nutrition.day.foodLibrary.hint",
        "nutrition.day.recipeLibrary",
        "nutrition.day.recipeLibrary.hint",
        "nutrition.food.add",
        "nutrition.food.add.hint",
        "nutrition.food.delete",
        "nutrition.food.delete.hint",
        "nutrition.food.editor.cancel",
        "nutrition.food.editor.cancel.hint",
        "nutrition.food.editor.save",
        "nutrition.food.editor.save.hint",
        "nutrition.recipe.add",
        "nutrition.recipe.add.hint",
        "nutrition.recipe.remove",
        "nutrition.recipe.remove.hint",
        "nutrition.recipe.restore",
        "nutrition.recipe.restore.hint",
        "nutrition.recipe.editor.cancel",
        "nutrition.recipe.editor.cancel.hint",
        "nutrition.recipe.editor.save",
        "nutrition.recipe.editor.save.hint",
        "nutrition.quickAdd.confirm",
        "nutrition.quickAdd.confirm.hint",
    ]
    strings = {
        key: {
            "localizations": {
                "tr": {"stringUnit": {"state": "translated", "value": f"{key} çevirisi"}}
            }
        }
        for key in localization_keys
    }
    catalog = root / (
        "Packages/HealthTrackingModules/Sources/NutritionKit/Resources/Localizable.xcstrings"
    )
    catalog.parent.mkdir(parents=True, exist_ok=True)
    catalog.write_text(json.dumps({"strings": strings}), encoding="utf-8")

    evidence_lines = [
        "# M2 acceptance evidence",
        "## Task history",
        "## Hosted acceptance detail",
        "## Screenshot and artifact review",
        "## Review and remote record",
        "Critical 0; Important 0; READY",
        "Fable NOT RUN",
        "## Device and external-service evidence",
        "BLOCKED",
    ]
    for task in range(1, 9):
        for kind in range(2):
            value = task * 2 + kind
            evidence_lines.append(
                f"M2.{task} `{value:040x}` "
                f"https://github.com/example/app/actions/runs/{1000 + value}"
            )
    evidence = root / "docs/evidence/M2/acceptance.md"
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text("\n".join(evidence_lines), encoding="utf-8")


def expect_failure(base: Path, label: str, expected: str, mutate):
    variant = base.parent / f"mutation-{label}"
    shutil.copytree(base, variant)
    mutate(variant)
    try:
        verify(variant, require_evidence=True)
    except VerificationError as error:
        if expected not in str(error):
            raise VerificationError(
                f"Mutation {label!r} failed for the wrong reason: {error}"
            ) from error
    else:
        raise VerificationError(f"Mutation {label!r} was not rejected.")


def replace_once(root: Path, relative: str, old: str, new: str):
    path = root / relative
    text = read(path)
    if old not in text:
        raise VerificationError(f"Self-test fixture is missing mutation token {old!r}.")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def self_test():
    with tempfile.TemporaryDirectory(prefix="verify-nutrition-") as temporary:
        base = Path(temporary) / "valid"
        write_fixture(base)
        verify(base, require_evidence=True)

        expect_failure(
            base,
            "product-id",
            "Nutrition day accessibility UI",
            lambda root: replace_once(
                root,
                "Packages/HealthTrackingModules/Sources/NutritionKit/Day/NutritionDayView.swift",
                "nutrition.day.food-library",
                "nutrition.day.missing-library",
            ),
        )
        expect_failure(
            base,
            "cross-import",
            "NutritionKit must not import TrainingKit",
            lambda root: (
                root
                / "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/CrossImport.swift"
            ).write_text("import TrainingKit\n", encoding="utf-8"),
        )
        expect_failure(
            base,
            "swiftdata-boundary",
            "NutritionKit must not own SwiftData",
            lambda root: (
                root
                / "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/LeakedStore.swift"
            ).write_text("import SwiftData\n", encoding="utf-8"),
        )
        expect_failure(
            base,
            "fixed-seconds",
            "Local-day code must not use fixed seconds",
            lambda root: (
                root
                / "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionDay.swift"
            ).write_text("public struct NutritionDayKey {}\nlet day = 86_400\n", encoding="utf-8"),
        )
        expect_failure(
            base,
            "global-calendar",
            "Local-day code must use an injected Calendar",
            lambda root: (
                root
                / "Packages/HealthTrackingModules/Sources/NutritionKit/Domain/NutritionDay.swift"
            ).write_text(
                "public struct NutritionDayKey {}\nlet calendar = Calendar.current\n",
                encoding="utf-8",
            ),
        )
        expect_failure(
            base,
            "semantic-danger",
            "Food editor accessibility UI",
            lambda root: replace_once(
                root,
                "Packages/HealthTrackingModules/Sources/NutritionKit/FoodLibrary/FoodEditorView.swift",
                "AppColors.color(.stateDanger",
                "Color.red",
            ),
        )
        expect_failure(
            base,
            "screenshot",
            "Hosted Nutrition verifier and screenshot wiring",
            lambda root: replace_once(
                root,
                ".github/workflows/ios.yml",
                "m2-nutrition-high-contrast",
                "m2-missing-high-contrast",
            ),
        )
        expect_failure(
            base,
            "workflow-timeout",
            "expanded M2 full suite",
            lambda root: replace_once(
                root,
                ".github/workflows/ios.yml",
                "timeout-minutes: 70",
                "timeout-minutes: 69",
            ),
        )

        def remove_localization(root: Path):
            path = root / (
                "Packages/HealthTrackingModules/Sources/NutritionKit/Resources/"
                "Localizable.xcstrings"
            )
            payload = json.loads(read(path))
            del payload["strings"]["nutrition.recipe.restore.hint"]
            path.write_text(json.dumps(payload), encoding="utf-8")

        expect_failure(
            base,
            "localization",
            "Nutrition localization keys are missing",
            remove_localization,
        )
        expect_failure(
            base,
            "scheme",
            "Local scheme test wiring",
            lambda root: replace_once(
                root,
                "project.yml",
                "HealthTrackingModules/NutritionKitTests",
                "HealthTrackingModules/MissingTests",
            ),
        )
        expect_failure(
            base,
            "evidence",
            "M2 evidence is missing exact-data fields",
            lambda root: replace_once(
                root,
                "docs/evidence/M2/acceptance.md",
                "READY",
                "PENDING",
            ),
        )
    print("Nutrition verifier self-tests passed.")


mode = sys.argv[2]
try:
    if mode == "":
        verify(Path(sys.argv[1]), require_evidence=REQUIRE_EVIDENCE)
        print("M2 Nutrition verification passed.")
    elif mode == "--self-test":
        self_test()
    else:
        raise SystemExit("Usage: verify-nutrition.sh [--self-test]")
except VerificationError as error:
    raise SystemExit(str(error)) from error
PY
