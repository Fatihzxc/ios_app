#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

python3 - "$repo_root" "${1:-}" <<'PY'
from __future__ import annotations

import hashlib
import re
import sys
import tempfile
from pathlib import Path

FULL_JOB_GUARD = "${{ github.event_name != 'push' || !startsWith(github.ref_name, 'test/m4.') || startsWith(github.ref_name, 'test/m4.9-') }}"
FOCUSED_JOB_GUARD = "${{ github.event_name == 'push' && startsWith(github.ref_name, 'test/m4.') && !startsWith(github.ref_name, 'test/m4.9-') }}"
ROUTES = {
    "m4.0": ("HealthTrackingAppTests",), "m4.1": ("ReportsKitTests",),
    "m4.2": ("ReportsKitTests/BodyStrengthDatasetBuilderTests", "PersistenceKitTests/ReportsRepositoryTests"),
    "m4.3": ("ReportsKitTests/ProteinAdherenceBuilderTests", "PersistenceKitTests/ReportsRepositoryTests"),
    "m4.4": ("CoreModelsTests/PhaseTransitionLedgerTests", "ReportsKitTests/LifestylePhaseDatasetBuilderTests", "PersistenceKitTests/PhaseTransitionLedgerRepositoryTests"),
    "m4.5": ("ProgressPhotosKitTests/ProgressPhotoComparisonShareTests", "HealthTrackingAppUITests/ProgressPhotoGalleryUITests"),
    "m4.6": ("ReportsKitTests/ExportSchemaInventoryTests", "ReportsKitTests/RFC4180CSVEncoderTests", "PersistenceKitTests/ReportsExportRepositoryTests"),
    "m4.7": ("ReportsKitTests/JSONExportEncoderTests", "ReportsKitTests/StoredZIPWriterTests", "ReportsKitTests/ReportExportCoordinatorTests"),
    "m4.8": ("ReportsKitTests", "HealthTrackingAppTests/ReportsCompositionTests"),
}


def routed_run() -> str:
    lines = ["set -euo pipefail", 'case "$GITHUB_REF_NAME" in']
    for task, selectors in ROUTES.items():
        lines.append(f"  test/{task}-*)")
        lines.extend(f"    scripts/test-ios.sh --focused-testing {selector}" for selector in selectors)
        lines.append("    ;;")
    lines.extend(("  *)", '    echo "Unknown focused M4 branch: $GITHUB_REF_NAME" >&2', "    exit 1", "    ;;", "esac"))
    return "\n".join(lines)


ROUTED_RUN = routed_run()
CANONICAL_KEY = r"[A-Za-z][A-Za-z0-9_-]*"
YAML_KEY = rf"(?:{CANONICAL_KEY}|'{CANONICAL_KEY}'|\"{CANONICAL_KEY}\")"
RUNNER_SHA256 = "98065cbe584b6041011b52a253c05ed799467a4d5fe82611517ce13b29ec400c"


def normalize_key(raw: str) -> str:
    raw = raw.strip()
    if raw[:1] in {"'", '"'} and raw[-1:] == raw[:1]:
        return raw[1:-1]
    return raw


def canonical_direct_keys(text: str, indent: int, label: str) -> list[tuple[str, str]]:
    result = []
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if len(line) - len(line.lstrip(" ")) != indent:
            continue
        match = re.fullmatch(rf" {{{indent}}}({YAML_KEY})[ ]*:(?:[ ]*(.*))?", line)
        if match is None:
            raise ValueError(f"{label} must use canonical direct mapping syntax")
        result.append((normalize_key(match.group(1)), match.group(2) or ""))
    return result


def job_block(workflow: str, name: str) -> str:
    canonical_direct_keys(workflow, 2, "Workflow job key")
    canonical_direct_keys(workflow, 8, "Workflow step key")
    matches = []
    for match in re.finditer(rf"^  ({YAML_KEY})[ ]*:[ ]*$", workflow, re.MULTILINE):
        if normalize_key(match.group(1)) == name:
            matches.append(match)
    if len(matches) != 1:
        raise ValueError(f"Workflow job {name} must be unique")
    start = matches[0].end()
    next_job = re.search(r"^  \S", workflow[start:], re.MULTILINE)
    return workflow[start : start + next_job.start() if next_job else len(workflow)]


def direct_mapping(block: str, indent: int, label: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for key, value in canonical_direct_keys(block, indent, label):
        if key in values:
            raise ValueError(f"{label} must not duplicate key {key}")
        values[key] = value
    return values


def steps(job: str) -> list[tuple[dict[str, str], list[str]]]:
    lines = job.splitlines()
    try:
        start = lines.index("    steps:")
    except ValueError as error:
        raise ValueError("Focused M4 workflow job must define canonical steps") from error
    result = []
    index = start + 1
    while index < len(lines):
        header = re.fullmatch(rf"      - ({YAML_KEY})[ ]*:[ ]*(.*)", lines[index])
        if header is None:
            if lines[index].strip():
                raise ValueError("Focused M4 workflow steps must use canonical direct keys")
            index += 1
            continue
        header_key = normalize_key(header.group(1))
        if header_key not in {"name", "uses"}:
            raise ValueError("Focused M4 workflow steps must use name or uses headers")
        values, body = {header_key: header.group(2)}, [lines[index]]
        index += 1
        while index < len(lines) and not re.fullmatch(rf"      - ({YAML_KEY})[ ]*:[ ]*(.*)", lines[index]):
            line = lines[index]
            body.append(line)
            if line.strip() and len(line) - len(line.lstrip(" ")) == 8:
                child = re.fullmatch(rf"        ({YAML_KEY})[ ]*:(?:[ ]*(.*))?", line)
                if child is None:
                    raise ValueError("Focused M4 workflow steps must use canonical direct mapping syntax")
                key, value = normalize_key(child.group(1)), (child.group(2) or "")
                if key in values:
                    raise ValueError(f"Focused M4 workflow step must not duplicate key {key}")
                values[key] = value
            index += 1
        result.append((values, body))
    return result


def block_run(body: list[str]) -> str:
    try:
        start = body.index("        run: |")
    except ValueError as error:
        raise ValueError("Focused M4 routed step must use an executable run block") from error
    lines = body[start + 1:]
    if not lines or any(line and not line.startswith("          ") for line in lines):
        raise ValueError("Focused M4 routed step must use one canonical run block")
    return "\n".join(line[10:] if line else "" for line in lines).rstrip("\n")


def verify_focused_runner(runner: str) -> None:
    focused_case = """        --focused-testing)
            if (( $# != 2 )) || [[ -z \"$2\" ]]; then
                usage
                exit 2
            fi
            xcodebuild_test_arguments+=(\"-only-testing:$2\")
            ;;"""
    if focused_case not in runner or "--focused-testing TestIdentifier" not in runner:
        raise ValueError("scripts/test-ios.sh is missing the exact non-empty --focused-testing contract")
    if hashlib.sha256(runner.encode("utf-8")).hexdigest() != RUNNER_SHA256:
        raise ValueError("Focused runner must match the canonical ordered pipeline")
    parser_end = runner.index(focused_case) + len(focused_case)
    gates = (
        '"$script_dir/verify-localization.sh" --self-test',
        '"$script_dir/verify-localization.sh"',
        '"$script_dir/verify-requirements.sh" --self-test',
        '"$script_dir/verify-requirements.sh"',
        '"$script_dir/verify-today.sh" --self-test',
        '"$script_dir/verify-today.sh"',
        '"$script_dir/verify-haptics.sh" --self-test',
        '"$script_dir/verify-haptics.sh"',
        '"$script_dir/verify-nutrition.sh" --self-test',
        '"$script_dir/verify-nutrition.sh"',
        '"$script_dir/verify-trackers.sh" --self-test',
        '    "$script_dir/verify-m3-acceptance.sh" --self-test',
        '        "$script_dir/verify-m3-acceptance.sh"',
        '"$script_dir/verify-m4-reports.sh" --self-test',
        '"$script_dir/verify-m4-reports.sh"',
    )
    positions = []
    for command in gates:
        match = re.search(rf"^{re.escape(command)}$", runner, re.MULTILINE)
        if match is None:
            raise ValueError("Focused runner must execute every static verifier before bootstrap")
        positions.append(match.start())
    if not (parser_end < min(positions) and positions == sorted(positions)):
        raise ValueError("Focused runner must parse arguments before ordered static gates")
    bootstrap = runner.find('"$script_dir/bootstrap.sh"')
    debug = runner.find('xcodebuild "${xcodebuild_test_arguments[@]}"')
    release = runner.find("xcodebuild build", debug + 1)
    if not (max(positions) < bootstrap < debug < release and "-configuration Release" in runner[release:]):
        raise ValueError("Focused runner must execute gates, bootstrap, Debug test, then Local Release build")
    exits = [match.start() for match in re.finditer(r"^\s*exit\s+0\s*$", runner, re.MULTILINE)]
    legacy_bootstrap = '"$script_dir/verify-bootstrap-idempotence.sh"\n    exit 0'
    legacy_cloud = 'CODE_SIGNING_ALLOWED=NO\n    exit 0'
    if len(exits) != 2 or legacy_bootstrap not in runner or legacy_cloud not in runner:
        raise ValueError("Focused runner must not contain early-success or short-circuit exits")


def verify(root: Path) -> None:
    workflow = (root / ".github/workflows/ios.yml").read_text(encoding="utf-8")
    runner = (root / "scripts/test-ios.sh").read_text(encoding="utf-8")
    full_keys = direct_mapping(job_block(workflow, "test"), 4, "Full workflow job test")
    if full_keys.get("if") != FULL_JOB_GUARD or "continue-on-error" in full_keys:
        raise ValueError("Full workflow job test must use the exact M4-safe guard")
    focused = job_block(workflow, "test-m4-focused")
    keys = direct_mapping(focused, 4, "Focused M4 workflow job")
    if keys != {"if": FOCUSED_JOB_GUARD, "runs-on": "macos-15", "timeout-minutes": "60", "steps": ""}:
        raise ValueError("Focused M4 workflow job must use exact guard, macos-15, timeout 60, and steps")
    parsed_steps = steps(focused)
    if any("continue-on-error" in values for values, _ in parsed_steps):
        raise ValueError("Focused M4 workflow steps must not continue on error")
    if [values for values, _ in parsed_steps if values.get("uses") == "actions/checkout@v4"] != [{"uses": "actions/checkout@v4"}]:
        raise ValueError("Focused M4 workflow job must have one canonical checkout step")
    routed = [(values, body) for values, body in parsed_steps if values.get("name") == "Focused M4 routed static gates and tests"]
    if len(routed) != 1 or routed[0][0] != {"name": "Focused M4 routed static gates and tests", "run": "|"}:
        raise ValueError("Focused M4 workflow job must have one canonical routed step")
    if block_run(routed[0][1]) != ROUTED_RUN:
        raise ValueError("Focused M4 routed step must use every exact executable M4 selector")
    verify_focused_runner(runner)


def expect_failure(root: Path, expected: str) -> None:
    try:
        verify(root)
    except ValueError as error:
        if expected not in str(error):
            raise SystemExit(f"M4 focused CI mutation failed for the wrong reason; expected {expected!r}: {error}") from error
    else:
        raise SystemExit(f"M4 focused CI mutation escaped: {expected}")


def replace_once(path: Path, before: str, after: str) -> str:
    original = path.read_text(encoding="utf-8")
    if before not in original:
        raise SystemExit(f"M4 focused CI self-test mutation source is missing: {before}")
    path.write_text(original.replace(before, after, 1), encoding="utf-8")
    return original


def fixture_workflow() -> str:
    run = "\n".join("          " + line for line in ROUTED_RUN.splitlines())
    return f"""name: iOS
jobs:
  test:
    if: {FULL_JOB_GUARD}
    runs-on: macos-15
    timeout-minutes: 300
    steps:
      - uses: actions/checkout@v4
  test-m4-focused:
    if: {FOCUSED_JOB_GUARD}
    runs-on: macos-15
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - name: Focused M4 routed static gates and tests
        run: |
{run}
"""


def self_test(source_root: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="m4-focused-ci-verifier-") as directory:
        fixture = Path(directory)
        (fixture / "scripts").mkdir()
        (fixture / ".github/workflows").mkdir(parents=True)
        workflow, runner = fixture / ".github/workflows/ios.yml", fixture / "scripts/test-ios.sh"
        workflow.write_text(fixture_workflow(), encoding="utf-8")
        runner.write_text((source_root / "scripts/test-ios.sh").read_text(encoding="utf-8"), encoding="utf-8")
        verify(fixture)
        mutations = (
            (f"    if: {FULL_JOB_GUARD}", "    if: false", "exact M4-safe guard"),
            (f"    if: {FULL_JOB_GUARD}\n", f"    if: {FULL_JOB_GUARD}\n    \"\\x63ontinue-on-error\": true\n", "canonical direct mapping syntax"),
            (f"    if: {FULL_JOB_GUARD}\n", f"    if: {FULL_JOB_GUARD}\n    '\\x63ontinue-on-error': true\n", "canonical direct mapping syntax"),
            (f"    if: {FULL_JOB_GUARD}\n", f"    if: {FULL_JOB_GUARD}\n    \"\\u0063ontinue-on-error\": true\n", "canonical direct mapping syntax"),
            (f"    if: {FOCUSED_JOB_GUARD}", "    if: false", "exact guard, macos-15"),
            ("    runs-on: macos-15\n    timeout-minutes: 60", "    runs-on: ubuntu-latest\n    timeout-minutes: 1", "exact guard, macos-15"),
            ("    timeout-minutes: 60\n    steps:", "    timeout-minutes: 60\n    timeout-minutes: 1\n    steps:", "must not duplicate key timeout-minutes"),
            ("    timeout-minutes: 60\n    steps:", "    timeout-minutes: 60\n    continue-on-error: true\n    steps:", "exact guard, macos-15"),
            ("    timeout-minutes: 60\n    steps:", "    timeout-minutes: 60\n    \"continue-on-error\": true\n    steps:", "exact guard, macos-15"),
            ("    timeout-minutes: 60\n    steps:", "    timeout-minutes: 60\n    'continue-on-error': true\n    steps:", "exact guard, macos-15"),
            ("    timeout-minutes: 60\n    steps:", "    timeout-minutes: 60\n    continue-on-error : true\n    steps:", "exact guard, macos-15"),
            (f"    if: {FOCUSED_JOB_GUARD}\n", f"    if: {FOCUSED_JOB_GUARD}\n    \"if\": false\n", "must not duplicate key if"),
            (f"    if: {FOCUSED_JOB_GUARD}\n", f"    if: {FOCUSED_JOB_GUARD}\n    \"\\x69f\": false\n", "canonical direct mapping syntax"),
            ("    runs-on: macos-15\n", "    runs-on: macos-15\n    'runs-on': ubuntu-latest\n", "must not duplicate key runs-on"),
            ("    runs-on: macos-15\n", "    runs-on: macos-15\n    \"runs-\\x6fn\": ubuntu-latest\n", "canonical direct mapping syntax"),
            ("    timeout-minutes: 60\n    steps:", "    timeout-minutes: 60\n    \"timeout-minutes\": 1\n    steps:", "must not duplicate key timeout-minutes"),
            ("    timeout-minutes: 60\n    steps:", "    timeout-minutes: 60\n    \"timeout-\\x6dinutes\": 1\n    steps:", "canonical direct mapping syntax"),
            ("  test-m4-focused:\n", "  \"test-m4-focused\":\n    if: false\n  test-m4-focused:\n", "must be unique"),
            ("  test-m4-focused:\n", "  \"\\x74est-m4-focused\":\n    if: false\n  test-m4-focused:\n", "Workflow job key"),
            ("      - name: Focused M4 routed static gates and tests\n", "      - name: Focused M4 routed static gates and tests\n        continue-on-error: true\n", "must not continue on error"),
            ("      - name: Focused M4 routed static gates and tests\n", "      - name: Focused M4 routed static gates and tests\n        \"continue-on-error\": true\n", "must not continue on error"),
            ("      - name: Focused M4 routed static gates and tests\n", "      - name: Focused M4 routed static gates and tests\n        'continue-on-error': true\n", "must not continue on error"),
            ("      - name: Focused M4 routed static gates and tests\n", "      - name: Focused M4 routed static gates and tests\n        continue-on-error : true\n", "must not continue on error"),
            ("      - uses: actions/checkout@v4\n", "      - uses: actions/checkout@v4\n        \"\\x63ontinue-on-error\": true\n", "canonical direct mapping syntax"),
            ("scripts/test-ios.sh --focused-testing ReportsKitTests", "scripts/test-ios.sh --only-testing ReportsKitTests", "every exact executable M4 selector"),
            ("set -euo pipefail", "echo 'scripts/test-ios.sh --focused-testing HealthTrackingAppTests'", "every exact executable M4 selector"),
        )
        for before, after, expected in mutations:
            original = replace_once(workflow, before, after)
            expect_failure(fixture, expected)
            workflow.write_text(original, encoding="utf-8")
        for selectors in ROUTES.values():
            for selector in selectors:
                original = replace_once(workflow, selector, f"removed-{selector}")
                expect_failure(fixture, "every exact executable M4 selector")
                workflow.write_text(original, encoding="utf-8")
        original = replace_once(runner, "--focused-testing)", "--removed-focused-testing)")
        expect_failure(fixture, "exact non-empty --focused-testing contract")
        runner.write_text(original, encoding="utf-8")
        for before in (
            "if (( $# > 0 )); then\n",
            '            xcodebuild_test_arguments+=("-only-testing:$2")\n',
            '"$script_dir/bootstrap.sh"\n',
            'xcodebuild "${xcodebuild_test_arguments[@]}" \\\n',
            'xcodebuild build \\\n',
        ):
            original = replace_once(runner, before, "exit 0\n" + before)
            expect_failure(fixture, "canonical ordered pipeline")
            runner.write_text(original, encoding="utf-8")
        for before, after in (
            ('"$script_dir/verify-localization.sh" --self-test\n', 'if false; then\n    "$script_dir/verify-localization.sh" --self-test\nfi\n'),
            ('"$script_dir/verify-requirements.sh" --self-test\n', 'return 0\n"$script_dir/verify-requirements.sh" --self-test\n'),
            ('"$script_dir/bootstrap.sh"\n', 'exec true\n"$script_dir/bootstrap.sh"\n'),
            ('xcodebuild "${xcodebuild_test_arguments[@]}" \\\n', 'true || xcodebuild "${xcodebuild_test_arguments[@]}" \\\n'),
            ('xcodebuild build \\\n', 'if false; then\nxcodebuild build \\\nfi\n'),
        ):
            original = replace_once(runner, before, after)
            expect_failure(fixture, "canonical ordered pipeline")
            runner.write_text(original, encoding="utf-8")


root = Path(sys.argv[1])
mode = sys.argv[2]
if mode == "--self-test":
    self_test(root)
    print("M4 focused CI verifier self-tests passed.")
elif mode == "":
    verify(root)
    print("M4 reports verification passed.")
else:
    raise SystemExit("Usage: scripts/verify-m4-reports.sh [--self-test]")
PY
