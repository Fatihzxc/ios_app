#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

verify_repo() {
    local target_root="$1"
    python3 - "$target_root" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])

required_tests = {
    "Packages/HealthTrackingModules/Tests/DesignSystemTests/QuickEntryMutationStateMachineTests.swift": {
        "QuickEntryMutationStateMachine",
        "requestID",
        "generation",
        "retrySave",
        "retryUndo",
        "completeSave",
        "completeUndo",
        "stale",
    },
    "Packages/HealthTrackingModules/Tests/DesignSystemTests/QuickEntryLayoutContractTests.swift": {
        "QuickEntryValidationIssue",
        "QuickEntryFormContract",
        "QuickEntryFormScaffold",
        "minimumActionHeight, 52",
        "quick-entry.keyboard.dismiss",
        "actionLayout(isAccessibilitySize: true)",
        "AppMotion.transition(reduceMotion: true)",
    },
}

for relative_path, tokens in required_tests.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.1 test file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.1 RED contracts: {absent}")

required_production = {
    "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryMutationStateMachine.swift": {
        "QuickEntryMutationAttempt",
        "QuickEntryMutationStateMachine",
        "generation += 1",
        "attempt == currentAttempt",
        "retrySave",
        "retryUndo",
        "expireUndo",
    },
    "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryValidationIssue.swift": {
        "QuickEntryValidationIssue",
        "fieldIdentifier",
        "localizedMessage",
        "accessibilityAnnouncement",
    },
    "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryFormScaffold.swift": {
        "QuickEntryFormScaffold",
        "minimumActionHeight: CGFloat = 52",
        "scrollDismissesKeyboard(.interactively)",
        "quick-entry.keyboard.dismiss",
        "accessibilityReduceMotion",
        "AppMotion.transition(reduceMotion:",
    },
}

for relative_path, tokens in required_production.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.1 production file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.1 production contracts: {absent}")

support = {
    "scripts/test-ios.sh": {
        '"$script_dir/verify-trackers.sh" --self-test',
        '"$script_dir/verify-trackers.sh"',
    },
    ".github/workflows/ios.yml": {
        "scripts/verify-trackers.sh --self-test",
        "scripts/verify-trackers.sh",
        "--only-testing DesignSystemTests",
    },
    "project.yml": {
        "HealthTrackingModules/DesignSystemTests",
    },
    "Packages/HealthTrackingModules/Sources/DesignSystem/Resources/Localizable.xcstrings": {
        "designSystem.quick-entry.keyboard.dismiss",
        "Klavyeyi kapat",
    },
}

for relative_path, tokens in support.items():
    path = root / relative_path
    if not path.is_file():
        raise SystemExit(f"Missing M3.1 support file: {relative_path}")
    text = path.read_text(encoding="utf-8")
    absent = sorted(token for token in tokens if token not in text)
    if absent:
        raise SystemExit(f"{relative_path} is missing M3.1 gate wiring: {absent}")

print("M3 tracker verification passed.")
PY
}

self_test() {
    python3 - "$repo_root" <<'PY'
import subprocess
import sys
import tempfile
from pathlib import Path

repo = Path(sys.argv[1])
script = repo / "scripts/verify-trackers.sh"

fixture_files = {
    "Packages/HealthTrackingModules/Tests/DesignSystemTests/QuickEntryMutationStateMachineTests.swift": " ".join(
        [
            "QuickEntryMutationStateMachine",
            "requestID",
            "generation",
            "retrySave",
            "retryUndo",
            "completeSave",
            "completeUndo",
            "stale",
        ]
    ),
    "Packages/HealthTrackingModules/Tests/DesignSystemTests/QuickEntryLayoutContractTests.swift": " ".join(
        [
            "QuickEntryValidationIssue",
            "QuickEntryFormContract",
            "QuickEntryFormScaffold",
            "minimumActionHeight, 52",
            "quick-entry.keyboard.dismiss",
            "actionLayout(isAccessibilitySize: true)",
            "AppMotion.transition(reduceMotion: true)",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryMutationStateMachine.swift": " ".join(
        [
            "QuickEntryMutationAttempt",
            "QuickEntryMutationStateMachine",
            "generation += 1",
            "attempt == currentAttempt",
            "retrySave",
            "retryUndo",
            "expireUndo",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryValidationIssue.swift": " ".join(
        [
            "QuickEntryValidationIssue",
            "fieldIdentifier",
            "localizedMessage",
            "accessibilityAnnouncement",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryFormScaffold.swift": " ".join(
        [
            "QuickEntryFormScaffold",
            "minimumActionHeight: CGFloat = 52",
            "scrollDismissesKeyboard(.interactively)",
            "quick-entry.keyboard.dismiss",
            "accessibilityReduceMotion",
            "AppMotion.transition(reduceMotion:",
        ]
    ),
    "Packages/HealthTrackingModules/Sources/DesignSystem/Resources/Localizable.xcstrings": " ".join(
        [
            "designSystem.quick-entry.keyboard.dismiss",
            "Klavyeyi kapat",
        ]
    ),
    "scripts/test-ios.sh": '\n'.join(
        [
            '"$script_dir/verify-trackers.sh" --self-test',
            '"$script_dir/verify-trackers.sh"',
        ]
    ),
    ".github/workflows/ios.yml": '\n'.join(
        [
            "scripts/verify-trackers.sh --self-test",
            "scripts/verify-trackers.sh",
            "scripts/test-ios.sh --only-testing DesignSystemTests",
        ]
    ),
    "project.yml": "HealthTrackingModules/DesignSystemTests",
}


def make_fixture(root: Path) -> None:
    for relative_path, content in fixture_files.items():
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content + "\n", encoding="utf-8")


def run(root: Path, expected: str | None = None) -> None:
    completed = subprocess.run(
        [str(script), "--verify-root", str(root)],
        cwd=repo,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if expected is None:
        if completed.returncode != 0:
            raise SystemExit(
                f"M3 tracker verifier fixture unexpectedly failed:\n{completed.stdout}"
            )
    elif completed.returncode == 0 or expected not in completed.stdout:
        raise SystemExit(
            f"M3 tracker mutation did not fail closed for {expected!r}:\n{completed.stdout}"
        )


with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    make_fixture(root)
    run(root)

    state_source = root / "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryMutationStateMachine.swift"
    original = state_source.read_text(encoding="utf-8")
    state_source.write_text(original.replace("attempt == currentAttempt", "attempt != currentAttempt"), encoding="utf-8")
    run(root, "attempt == currentAttempt")
    state_source.write_text(original, encoding="utf-8")

    scaffold = root / "Packages/HealthTrackingModules/Sources/DesignSystem/QuickEntry/QuickEntryFormScaffold.swift"
    original = scaffold.read_text(encoding="utf-8")
    scaffold.write_text(original.replace("minimumActionHeight: CGFloat = 52", "minimumActionHeight: CGFloat = 44"), encoding="utf-8")
    run(root, "minimumActionHeight: CGFloat = 52")
    scaffold.write_text(original, encoding="utf-8")

    scaffold.write_text(original.replace("quick-entry.keyboard.dismiss", ""), encoding="utf-8")
    run(root, "quick-entry.keyboard.dismiss")

print("M3 tracker verifier self-tests passed.")
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
    *)
        echo "Usage: $0 [--self-test|--verify-root PATH]" >&2
        exit 2
        ;;
esac
