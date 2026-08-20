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
    expected_products = ["CoreModels", "TrainingKit", "GuidanceKit", "PersistenceKit", "DesignSystem", "NutritionKit", "ReportsKit", "SettingsKit"]
    expected_product_declarations = [("library", name) for name in expected_products]
    if products != expected_product_declarations:
        errors.append(f"Package products must be exactly {expected_product_declarations}; found {products}")

    target_declarations = re.findall(
        r'\.(target|testTarget)\s*\(\s*name:\s*"([^"]+)"',
        package_text,
        re.S,
    )
    required_guidance_targets = [("target", "GuidanceKit"), ("testTarget", "GuidanceKitTests")]
    missing_guidance_targets = [
        declaration
        for declaration in required_guidance_targets
        if declaration not in target_declarations
    ]
    if missing_guidance_targets:
        errors.append(
            f"Package must declare GuidanceKit library/test targets; missing {missing_guidance_targets}"
        )

model_directory = root / "Packages/HealthTrackingModules/Sources/CoreModels/Models"
expected_models = [
    "AppReminder", "AppSetting", "BloodworkResult", "BodyMetric", "CooldownItem", "DailyNutritionLog",
    "ExerciseTemplate", "Food", "HealthCheckReminder", "MealEntry", "MoodLog", "PostureMetric", "Program",
    "ProgramPhase", "ProgramState", "ProgressPhoto", "Recipe", "SetLog", "SleepLog", "UserProfile",
    "WarmupItem", "WorkoutDayTemplate", "WorkoutSession",
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
        "DesignSystemTests",
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

if errors:
    raise SystemExit("\n".join(errors))
print("M0 requirements verification passed.")
PY
}

self_test() {
    self_test_fixture="$(mktemp -d)"
    trap 'rm -rf -- "$self_test_fixture"' EXIT
    local fixture="$self_test_fixture"
    mkdir -p "$fixture/Packages/HealthTrackingModules/Sources/CoreModels/Models" "$fixture/Packages/HealthTrackingModules/Sources/GuidanceKit" "$fixture/Packages/HealthTrackingModules/Sources/TrainingKit" "$fixture/App" "$fixture/docs/evidence/M0"
    cp "$repo_root/Packages/HealthTrackingModules/Package.swift" "$fixture/Packages/HealthTrackingModules/Package.swift"
    cp "$repo_root/project.yml" "$fixture/project.yml"
    cp "$repo_root/.gitignore" "$fixture/.gitignore"
    git -C "$fixture" init --quiet
    touch "$fixture/README.md" "$fixture/docs/evidence/M0/acceptance.md"
    for model in AppReminder AppSetting BloodworkResult BodyMetric CooldownItem DailyNutritionLog ExerciseTemplate Food HealthCheckReminder MealEntry MoodLog PostureMetric Program ProgramPhase ProgramState ProgressPhoto Recipe SetLog SleepLog UserProfile WarmupItem WorkoutDayTemplate WorkoutSession; do
        printf '@Model\npublic final class %s {}\n' "$model" > "$fixture/Packages/HealthTrackingModules/Sources/CoreModels/Models/$model.swift"
    done
    verify_repo "$fixture"
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
