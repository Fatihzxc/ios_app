#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

python3 - "$repo_root" "${1:-}" <<'PY'
from __future__ import annotations

import hashlib
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

FULL_JOB_GUARD = "${{ github.event_name != 'push' || !startsWith(github.ref_name, 'test/m4.') || startsWith(github.ref_name, 'test/m4.9-') }}"
FOCUSED_JOB_GUARD = "${{ github.event_name == 'push' && startsWith(github.ref_name, 'test/m4.') && !startsWith(github.ref_name, 'test/m4.9-') }}"
ROUTES = {
    "m4.0": ("HealthTrackingAppTests",), "m4.1": ("ReportsKitTests",),
    "m4.2": ("ReportsKitTests/BodyStrengthDatasetBuilderTests", "PersistenceKitTests/ReportsRepositoryTests"),
    "m4.3": ("ReportsKitTests/ProteinAdherenceBuilderTests", "PersistenceKitTests/ReportsRepositoryTests"),
    "m4.4": ("CoreModelsTests/PhaseTransitionLedgerTests", "ReportsKitTests/LifestylePhaseDatasetBuilderTests", "PersistenceKitTests/PhaseTransitionLedgerRepositoryTests", "TrainingKitTests/PhaseTransitionViewModelTests"),
    "m4.5": (
        "ProgressPhotosKitTests/ProgressPhotoComparisonShareTests",
        "ProgressPhotosKitTests/ProgressPhotoGalleryViewModelTests",
        "HealthTrackingAppUITests/ProgressPhotoGalleryUITests",
    ),
    "m4.6": ("ReportsKitTests/ExportSchemaInventoryTests", "ReportsKitTests/RFC4180CSVEncoderTests", "PersistenceKitTests/ReportsExportRepositoryTests"),
    "m4.7": (
        "ReportsKitTests/JSONExportEncoderTests",
        "ReportsKitTests/StoredZIPWriterTests",
        "ReportsKitTests/ReportExportCoordinatorTests",
    ),
    "m4.8": (
        "ReportsKitTests",
        "HealthTrackingAppTests/ReportsCompositionTests",
        "HealthTrackingAppUITests/M3AcceptanceUITests/testReportDashboardFetchLifecycleAcrossRootSheetDismissals",
    ),
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
TASK7_DEVICE_BUILD_GUARD = "${{ startsWith(github.ref_name, 'test/m4.7-') }}"
TASK7_DEVICE_BUILD_RUN = """set -euo pipefail
scripts/bootstrap.sh
xcodebuild build \\
  -project HealthTrackingApp.xcodeproj \\
  -scheme HealthTrackingApp-Local \\
  -configuration Debug \\
  -destination 'generic/platform=iOS' \\
  CODE_SIGNING_ALLOWED=NO \\
  CODE_SIGNING_REQUIRED=NO"""
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
    device = [
        (values, body)
        for values, body in parsed_steps
        if values.get("name") == "Compile Task 7 device filesystem branch"
    ]
    if len(device) != 1 or device[0][0] != {
        "name": "Compile Task 7 device filesystem branch",
        "if": TASK7_DEVICE_BUILD_GUARD,
        "run": "|",
    } or block_run(device[0][1]) != TASK7_DEVICE_BUILD_RUN:
        raise ValueError("Focused M4 workflow must compile the exact Task 7 device-only branch")
    verify_focused_runner(runner)


def target_dependencies(package: str, name: str) -> list[str]:
    match = re.search(
        rf'        \.target\(\s*\n            name: "{re.escape(name)}",\s*\n(.*?)^        \),',
        package,
        re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise ValueError(f"Package target {name} must exist")
    dependencies = re.search(r'dependencies: \[([^\]]*)\]', match.group(1))
    if dependencies is None:
        return []
    return re.findall(r'"([A-Za-z][A-Za-z0-9_]*)"', dependencies.group(1))


def swift_code_without_comments_and_literals(source: str) -> str:
    sanitized: list[str] = []
    index = 0
    length = len(source)

    def append_blank(character: str) -> None:
        sanitized.append(character if character in {"\r", "\n"} else " ")

    def consume_until(end: int) -> None:
        nonlocal index
        while index < end:
            append_blank(source[index])
            index += 1

    def line_end(after: int) -> int:
        carriage_return = source.find("\r", after)
        line_feed = source.find("\n", after)
        candidates = [position for position in (carriage_return, line_feed) if position != -1]
        return min(candidates) if candidates else length

    def bare_regex_end(start: int) -> int | None:
        probe = start + 1
        escaped = False
        in_character_class = False
        while probe < length and source[probe] not in {"\r", "\n"}:
            character = source[probe]
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == "[":
                in_character_class = True
            elif character == "]" and in_character_class:
                in_character_class = False
            elif character == "/" and not in_character_class:
                return probe + 1
            probe += 1
        return None

    def can_begin_bare_regex(at: int) -> bool:
        if at + 1 >= length or source[at + 1].isspace() or source[at + 1] in {"/", "*", "="}:
            return False
        if at == 0 or source[at - 1].isspace():
            return True
        return source[at - 1] in "=([{,:;!&|?+-*%^~<>"

    while index < length:
        if source.startswith("//", index):
            consume_until(line_end(index + 2))
            continue

        if source.startswith("/*", index):
            depth = 1
            append_blank(source[index])
            append_blank(source[index + 1])
            index += 2
            while index < length and depth:
                if source.startswith("/*", index):
                    append_blank(source[index])
                    append_blank(source[index + 1])
                    index += 2
                    depth += 1
                elif source.startswith("*/", index):
                    append_blank(source[index])
                    append_blank(source[index + 1])
                    index += 2
                    depth -= 1
                else:
                    append_blank(source[index])
                    index += 1
            continue

        hash_count = 0
        while index + hash_count < length and source[index + hash_count] == "#":
            hash_count += 1
        quote_index = index + hash_count
        if quote_index < length and source[quote_index] == '"':
            quote_count = 3 if source.startswith('"""', quote_index) else 1
            opening_length = hash_count + quote_count
            consume_until(index + opening_length)
            closing = '"' * quote_count + "#" * hash_count
            while index < length:
                if source.startswith(closing, index):
                    if hash_count or quote_count == 3:
                        consume_until(index + len(closing))
                        break
                    backslashes = 0
                    probe = index - 1
                    while probe >= 0 and source[probe] == "\\":
                        backslashes += 1
                        probe -= 1
                    if backslashes % 2 == 0:
                        consume_until(index + len(closing))
                        break
                append_blank(source[index])
                index += 1
            continue

        if hash_count and quote_index < length and source[quote_index] == "/":
            closing = "/" + "#" * hash_count
            closing_index = source.find(closing, quote_index + 1)
            if closing_index != -1:
                consume_until(closing_index + len(closing))
                continue

        if source[index] == "/" and can_begin_bare_regex(index):
            regex_end = bare_regex_end(index)
            if regex_end is not None:
                consume_until(regex_end)
                continue

        sanitized.append(source[index])
        index += 1

    return "".join(sanitized)


def swift_imported_modules(source: str) -> set[str]:
    code = swift_code_without_comments_and_literals(source)
    identifier = r"[A-Za-z_][A-Za-z0-9_]*"
    horizontal_space = r"[ \t\f\v]"
    token_space = r"[ \t\f\v\r\n]"
    token_space_characters = " \t\f\v\r\n"
    attribute = rf"@{identifier}(?:{horizontal_space}*\([^()\r\n]*\))?"
    import_start = re.compile(
        rf"(?:\A|(?<=[;\r\n])){horizontal_space}*"
        rf"(?:{attribute}[ \t\f\v\r\n]+)*"
        rf"import(?={token_space})"
    )
    token = re.compile(rf"`{identifier}`|{identifier}")
    scoped_kinds = {"typealias", "struct", "class", "enum", "protocol", "let", "var", "func"}
    modules: set[str] = set()

    for declaration in import_start.finditer(code):
        cursor = declaration.end()
        while cursor < len(code) and code[cursor] in token_space_characters:
            cursor += 1
        first = token.match(code, cursor)
        if first is None:
            continue
        root = first.group(0)
        if not root.startswith("`") and root in scoped_kinds:
            cursor = first.end()
            if cursor >= len(code) or code[cursor] not in token_space_characters:
                continue
            while cursor < len(code) and code[cursor] in token_space_characters:
                cursor += 1
            scoped_root = token.match(code, cursor)
            if scoped_root is None:
                continue
            root = scoped_root.group(0)
        modules.add(root[1:-1] if root.startswith("`") else root)

    return modules


def swift_model_context_mutates(source: str) -> bool:
    code = swift_code_without_comments_and_literals(source)
    identifier = r"[A-Za-z_][A-Za-z0-9_]*"
    contexts = {"modelContext"}
    contexts.update(
        re.findall(
            rf"\b({identifier})\s*:\s*(?:SwiftData\s*\.\s*)?ModelContext\b",
            code,
        )
    )
    alias_pattern = re.compile(
        rf"\b(?:let|var)\s+({identifier})"
        rf"(?:\s*:\s*(?:SwiftData\s*\.\s*)?ModelContext)?\s*=\s*"
        rf"(?:self\s*\.\s*)?({identifier})\b"
    )
    changed = True
    while changed:
        changed = False
        for alias, source_name in alias_pattern.findall(code):
            if source_name in contexts and alias not in contexts:
                contexts.add(alias)
                changed = True
    receiver = "|".join(re.escape(name) for name in sorted(contexts))
    return re.search(
        rf"\b(?:self\s*\.\s*)?(?:{receiver})\s*\.\s*"
        rf"(?:insert|delete|save|rollback)\s*\(",
        code,
    ) is not None


def balanced_brace_end(code: str, opening: int, label: str) -> int:
    depth = 1
    cursor = opening + 1
    while cursor < len(code) and depth:
        if code[cursor] == "{":
            depth += 1
        elif code[cursor] == "}":
            depth -= 1
        cursor += 1
    if depth:
        raise ValueError(f"{label} must have a complete body")
    return cursor - 1


def balanced_delimiter_end(
    code: str,
    opening: int,
    opening_character: str,
    closing_character: str,
    label: str,
) -> int:
    depth = 1
    cursor = opening + 1
    while cursor < len(code) and depth:
        if code[cursor] == opening_character:
            depth += 1
        elif code[cursor] == closing_character:
            depth -= 1
        cursor += 1
    if depth:
        raise ValueError(f"{label} must have a complete delimiter pair")
    return cursor - 1


def swift_xctest_suite_methods(
    source: str,
    suite_name: str,
    require_main_actor: bool,
    return_source: bool = False,
) -> dict[str, str]:
    code = swift_code_without_comments_and_literals(source)
    identifier = r"[A-Za-z_][A-Za-z0-9_]*"
    attribute = rf"@{identifier}(?:[ \t\f\v]*\([^()\r\n]*\))?"
    named_suite = re.compile(
        rf"\b(?:final[ \t\f\v\r\n]+)?class[ \t\f\v\r\n]+"
        rf"{re.escape(suite_name)}\b"
    )
    exact_suite = re.compile(
        rf"(?P<attributes>(?:{attribute}[ \t\f\v\r\n]+)*)"
        rf"\bfinal[ \t\f\v\r\n]+class[ \t\f\v\r\n]+"
        rf"{re.escape(suite_name)}[ \t\f\v\r\n]*"
        rf":[ \t\f\v\r\n]*XCTestCase\b[^{{}}]*\{{"
    )
    named_matches = list(named_suite.finditer(code))
    exact_matches = list(exact_suite.finditer(code))
    if len(named_matches) != 1 or len(exact_matches) != 1:
        raise ValueError(f"{suite_name} must define one expected concrete XCTestCase suite")
    suite = exact_matches[0]
    if require_main_actor and re.search(r"@MainActor\b", suite.group("attributes")) is None:
        raise ValueError(f"{suite_name} must define one expected concrete XCTestCase suite")
    opening = suite.end() - 1
    closing = balanced_brace_end(code, opening, f"Task 3 suite {suite_name}")
    suite_body = code[opening + 1 : closing]
    raw_suite_body = source[opening + 1 : closing]

    depths: list[int] = []
    depth = 0
    for character in suite_body:
        depths.append(depth)
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1

    declaration = re.compile(
        r"\bfunc[ \t\f\v\r\n]+(test[A-Za-z0-9_]*)[ \t\f\v]*"
        r"\([^)]*\)[^{]*\{",
        re.MULTILINE,
    )
    methods: dict[str, str] = {}
    for match in declaration.finditer(suite_body):
        if depths[match.start()] != 0:
            continue
        name = match.group(1)
        if name in methods:
            raise ValueError(f"Task 3 tests must not duplicate test method {name}")
        opening = match.end() - 1
        closing = balanced_brace_end(
            suite_body,
            opening,
            f"Task 3 test method {name}",
        )
        methods[name] = (
            raw_suite_body[opening + 1 : closing]
            if return_source
            else suite_body[opening + 1 : closing]
        )
    return methods


TASK3_BUILDER_TEST_BEHAVIORS = {
    "testEmptyLogIsMissingWhileActualZeroProteinEntryIsAnObservedMiss": (
        "ProteinAdherenceBuilder.build(days:",
        "entryCount: 0, proteinTotalG: 0, proteinTargetG: 100",
        "entryCount: 1, proteinTotalG: 0, proteinTargetG: 100",
        "XCTAssertEqual(report.observedDayCount, 1)",
        "XCTAssertEqual(report.targetDayCount, 1)",
        "XCTAssertEqual(report.hitDayCount, 0)",
        "XCTAssertEqual(report.excludedTargetlessDayCount, 0)",
        "XCTAssertEqual(report.adherencePercent, 0)",
    ),
    "testInvalidAndMissingTargetsAreExcludedAndZeroDenominatorIsNil": (
        "ProteinAdherenceBuilder.build(days:",
        "proteinTargetG: nil",
        "proteinTargetG: 0",
        "proteinTargetG: -1",
        "proteinTargetG: .nan",
        "proteinTargetG: .infinity",
        "XCTAssertEqual(report.observedDayCount, 5)",
        "XCTAssertEqual(report.targetDayCount, 0)",
        "XCTAssertEqual(report.hitDayCount, 0)",
        "XCTAssertEqual(report.excludedTargetlessDayCount, 5)",
        "XCTAssertNil(report.adherencePercent)",
        "XCTAssertEqual(report.provenance, .currentProfileAppliedToObservedDays)",
    ),
    "testAdherenceUsesOnlyObservedDaysWithValidCurrentProfileTarget": (
        "ProteinAdherenceBuilder.build(days:",
        "proteinTotalG: 99.999, proteinTargetG: 100",
        "proteinTotalG: 100, proteinTargetG: 100",
        "proteinTotalG: 150, proteinTargetG: 100",
        "entryCount: 0, proteinTotalG: 0, proteinTargetG: 100",
        "XCTAssertEqual(report.observedDayCount, 3)",
        "XCTAssertEqual(report.targetDayCount, 3)",
        "XCTAssertEqual(report.hitDayCount, 2)",
        "XCTUnwrap(report.adherencePercent)",
        "200.0 / 3.0",
        "accuracy: 0.000_000_000_001",
        "XCTAssertEqual(report.provenance, .currentProfileAppliedToObservedDays)",
    ),
    "testDuplicateObservedDayFailsWithStableIDsRegardlessOfInputOrder": (
        "ProteinAdherenceBuilder.build(days: records)",
        "for records in [[higher, lower], [lower, higher]]",
        "XCTAssertThrowsError",
        ".duplicateObservedDay(",
        "date: lower.date",
        "recordIDs: [lower.id, higher.id]",
    ),
    "testInvalidObservedDayFailureSelectsLowestStableID": (
        "proteinTotalG: -.infinity",
        "proteinTotalG: .nan",
        "ProteinAdherenceBuilder.build(days: records)",
        "for records in [[higher, lower], [lower, higher]]",
        "XCTAssertThrowsError",
        ".invalidObservedDay(id: lower.id)",
    ),
    "testProteinReportContractsAreEquatableAndSendable": (
        "assertEquatableSendable(ProteinTargetProvenance.self)",
        "assertEquatableSendable(ProteinAdherenceBuilderError.self)",
        "assertEquatableSendable(ProteinAdherenceReport.self)",
    ),
}

TASK3_REPOSITORY_TEST_BEHAVIORS = {
    "testNutritionProjectionUsesActualEntriesLocalDaysSnapshotsAndCurrentProfileWithoutMutation": (
        "UserProfile(",
        "proteinTargetG: 100",
        "mealEntry(",
        "proteinG: 0",
        "proteinG: 40",
        "proteinG: 70",
        "proteinG: 50",
        "SwiftDataReportsRepository(modelContext: reader, calendar: calendar)",
        "repository.fetchDashboardSource(in: interval)",
        "XCTAssertEqual(first, second)",
        r"XCTAssertEqual(first.nutritionDayRecords.map(\.id), [zeroDay.id, hitDay.id, missDay.id])",
        r"XCTAssertEqual(first.nutritionDayRecords.map(\.entryCount), [1, 2, 1])",
        r"XCTAssertEqual(first.nutritionDayRecords.map(\.proteinTotalG), [0, 110, 50])",
        r"XCTAssertEqual(first.nutritionDayRecords.map(\.proteinTargetG), [100, 100, 100])",
        "XCTAssertEqual(first.coverage.observedCount, 3)",
        "XCTAssertFalse(reader.hasChanges)",
        "XCTAssertEqual(try nutritionFieldSnapshot(in: container), before)",
    ),
    "testMissingOrInvalidCurrentProfileTargetProducesTargetlessObservedDays": (
        "let targets: [Double?] = [nil, .nan, 0, -1, .infinity]",
        "mealEntry(",
        "if let target",
        "UserProfile(proteinTargetG: target)",
        "fetchDashboardSource(in: broadInterval())",
        "XCTAssertEqual(source.nutritionDayRecords.count, 1)",
        "XCTAssertNil(source.nutritionDayRecords.first?.proteinTargetG)",
    ),
    "testNutritionDuplicateLogicalDayAndProfileAmbiguityFailDeterministically": (
        "duplicateDayInterval",
        "for reverse in [false, true]",
        "fetchDashboardSource(in: duplicateDayInterval)",
        ".duplicateNutritionDay(",
        "calendar.startOfDay(for: logs[0].date)",
        "nutritionLogIDs: [lowerLogID, higherLogID]",
        ".ambiguousUserProfiles(profileIDs: [lowerProfileID, higherProfileID])",
    ),
    "testSelectedNutritionEntryCorruptionAndMissingRelationshipFailWithStableTypedErrors": (
        "for reverse in [false, true]",
        "proteinG: -.infinity",
        "proteinG: .nan",
        "fetchDashboardSource(in: broadInterval())",
        ".invalidMealEntry(id: lowerID)",
        "log: nil",
        ".mealEntryMissingNutritionLog(id: orphanID)",
        "XCTAssertFalse(orphanReader.hasChanges)",
    ),
    "testSelectedNutritionIdentityCollisionsFailWithoutRebindingRows": (
        "sharedLogID",
        "fetchDashboardSource(in: broadInterval())",
        ".duplicateNutritionLogIDs(id: sharedLogID, count: 2)",
        "sharedEntryID",
        ".duplicateMealEntryIDs(id: sharedEntryID, count: 2)",
    ),
}

TASK4_LEDGER_TEST_BEHAVIORS = {
    "testKeyUsesExactVersionedPrefixAndLowercaseProgramIdentifier": (
        "PhaseTransitionLedgerV1.key(for: programID)",
        "XCTAssertEqual",
    ),
    "testEncodingSortsByTransitionDateAndIsByteDeterministic": (
        "PhaseTransitionLedgerV1(records:",
        ".encoded(for: programID)",
        "XCTAssertEqual(forward, reverse)",
        "XCTAssertEqual(decoded.records.map(\\.id)",
    ),
    "testMalformedAndUnknownSchemaPayloadsFailWithTypedErrors": (
        ".malformedPayload",
        ".unsupportedSchemaVersion(2)",
        "assertDecodeError",
    ),
    "testDuplicateIdentifiersAndLogicalTransitionsFailDeterministically": (
        ".duplicateRecordID(lowerID)",
        ".duplicateLogicalTransition(recordIDs: [lowerID, higherID])",
        "for records in [[duplicateLogical, first], [first, duplicateLogical]]",
    ),
    "testDuplicateLogicalGroupSelectionUsesProgramIDAcrossAllInputPermutations": (
        "XCTAssertEqual(lowerProgramID.uuidString",
        "XCTAssertLessThan(lowerProgramID.uuidString, higherProgramID.uuidString)",
        "XCTAssertGreaterThan(lowerRecordID.uuidString, higherDuplicateID.uuidString)",
        "let inputs = permutations(of:",
        "XCTAssertEqual(inputs.count, 24)",
        "for records in inputs",
        ".validated(for: lowerProgramID)",
        "recordIDs: [lowerRecordID, lowerDuplicateID]",
    ),
    "testEqualTransitionTimestampsFailBeforeChainValidationRegardlessOfIDOrInputOrder": (
        "for (firstID, secondID) in [(lowerID, higherID), (higherID, lowerID)]",
        "for records in [[first, second], [second, first]]",
        ".duplicateTransitionTimestamp(",
        "recordIDs: [lowerID, higherID]",
    ),
    "testInvalidCrossProgramAndBrokenChainRecordsFailClosed": (
        ".invalidRecord(id: invalid.id)",
        ".crossProgramRecord(",
        ".brokenTransitionChain(previousRecordID: valid.id, recordID: broken.id)",
    ),
    "testLedgerPublicContractsAreEquatableCodableAndSendable": (
        "assertCodableEquatableSendable(PhaseTransitionRecord.self)",
        "assertCodableEquatableSendable(PhaseTransitionLedgerV1.self)",
        "assertEquatableSendable(PhaseTransitionLedgerError.self)",
    ),
}

TASK4_LIFESTYLE_TEST_BEHAVIORS = {
    "testMissingLocalDaySplitsSeriesWhileStoredZeroRemainsObserved": (
        "moodScoreSeries.map",
        "[[4, 0], [7]]",
        "postureSymptomSeries.map",
        "[[2, 0]]",
    ),
    "testDSTGroupingUsesInjectedCalendarAndHalfOpenBoundsWithoutFixedDaySeconds": (
        "interval.start.addingTimeInterval(-0.001)",
        "date: interval.endExclusive",
        "[6, 7, 8]",
    ),
    "testStableOrderingAndDuplicateLocalDayFailureUseDateCreatedAtThenIdentifier": (
        "for input in [records, Array(records.reversed())]",
        ".duplicateLocalDay(",
        "recordIDs: [lowerID, higherID]",
    ),
    "testInvalidFiniteRangeAndCanonicalPhaseDataFailWithStableTypedErrors": (
        "hours: .nan",
        "score: 11",
        "score: -1",
        ".invalidPhase(id: invalidPhase.id)",
    ),
    "testLoneCurrentStateIsPartialEvidenceAndMonthMetadataNeverCreatesHistory": (
        ".partialCurrentState",
        "XCTAssertEqual(report.phaseSegments",
        "XCTAssertFalse(report.phaseTimelineProvenance == .actualTransitions)",
    ),
    "testActualLedgerTransitionsProduceClippedRealSegmentsWithExplicitProvenance": (
        ".actualTransitions",
        "phaseSegments.map(\\.startedAt)",
        "phaseSegments.map(\\.visibleStart)",
        "phaseSegments.map(\\.visibleEndExclusive)",
    ),
    "testPhaseRelationshipIdentityAndChainCorruptionFailDeterministically": (
        ".missingPhase(id: missingID)",
        "assertBuilderError",
    ),
    "testDuplicateTransitionIdentifierFailsBeforeChainValidation": (
        ".duplicateTransitionID(id: sharedID)",
        "for records in [transitions, Array(transitions.reversed())]",
    ),
    "testDuplicateLogicalTransitionUsesStableSortedIDsBeforeTimestampAmbiguity": (
        ".duplicateLogicalTransition(recordIDs: [lowerID, higherID])",
        "for records in [transitions, Array(transitions.reversed())]",
    ),
    "testEqualTransitionTimestampFailsWithStableIDsRegardlessOfIDOrInputOrder": (
        "for (firstID, secondID) in [(lowerID, higherID), (higherID, lowerID)]",
        "for input in [records, Array(records.reversed())]",
        ".duplicateTransitionTimestamp(",
        "recordIDs: [lowerID, higherID]",
    ),
    "testLifestylePhaseContractsAreImmutableEquatableAndSendable": (
        "assertEquatableSendable(LifestylePhaseReport.self)",
        "assertEquatableSendable(LifestylePhaseDatasetError.self)",
        "assertEquatableSendable(PhaseTimelineProvenance.self)",
    ),
}

TASK4_PERSISTENCE_TEST_BEHAVIORS = {
    "testActualPhaseChangeAppendsExplicitRecordAndPersistsStateAndLedgerTogether": (
        "XCTAssertEqual(saveCount, 1)",
        "PhaseTransitionRecord(",
        "let reopened = ModelContext(fixture.container)",
    ),
    "testSamePhaseIsTrueNoOpWithoutLedgerIDsTimestampChangeOrSave": (
        "XCTAssertEqual(recordIDCount, 0)",
        "XCTAssertEqual(settingIDCount, 0)",
        "XCTAssertEqual(saveCount, 0)",
    ),
    "testSamePhaseWithUnrelatedPendingMutationSucceedsWithoutAnySideEffect": (
        "XCTAssertEqual(rollbackCount, 0)",
        "XCTAssertTrue(fixture.context.hasChanges)",
        "XCTAssertEqual(saveCount, 0)",
    ),
    "testZeroDurationFirstTransitionFailsBeforeIDsMutationSaveOrRollback": (
        ".invalidPhaseTransitionDate(",
        "currentPhaseStartedAt: fixture.startedAt",
        "transitionedAt: fixture.startedAt",
        "XCTAssertEqual(rollbackCount, 0)",
    ),
    "testSequentialTransitionsAtSameTimestampRejectSecondWithoutPartialMutation": (
        ".invalidPhaseTransitionDate(",
        "currentPhaseStartedAt: transitionedAt",
        "XCTAssertEqual(recordIDCount, 1)",
        "XCTAssertEqual(setting.value, savedLedgerValue)",
    ),
    "testMalformedAndUnknownLedgerFailBeforeAnyStateMutation": (
        "for value in [",
        ".invalidPhaseTransitionLedger",
        "XCTAssertFalse(fixture.context.hasChanges)",
    ),
    "testInjectedSaveFailureRollsBackNewSettingAndEveryStateFieldExactly": (
        ".phaseTransitionSaveFailed",
        "fetchCount(FetchDescriptor<AppSetting>())",
        "XCTAssertFalse(fixture.context.hasChanges)",
    ),
    "testInjectedSaveFailureRestoresExistingSettingFieldsExactly": (
        "XCTAssertEqual(setting.value, originalValue)",
        "XCTAssertEqual(setting.updatedAt, originalUpdatedAt)",
        "persistedSetting",
    ),
    "testUnrelatedPendingMutationIsNeitherSavedNorDiscarded": (
        ".pendingContextChanges",
        "XCTAssertTrue(fixture.context.hasChanges)",
    ),
    "testDuplicateSettingStateAndPhaseIdentitiesFailDeterministically": (
        ".duplicatePhaseTransitionSettings",
        ".duplicateProgramStates",
        ".duplicateProgramPhases",
    ),
    "testCrossProgramTargetFailsWithoutCreatingLedger": (
        ".phaseNotFound(programID: fixture.program.id, phaseID: otherPhase.id)",
        "fetchCount(FetchDescriptor<AppSetting>())",
    ),
    "testReportsRepositoryProjectsLifestyleCurrentProgramAndActualLedgerReadOnly": (
        "XCTAssertEqual(first, second)",
        "XCTAssertFalse(reader.hasChanges)",
        "XCTAssertEqual(try persistenceSnapshot(reader), before)",
    ),
    "testLoneCurrentStateProjectsPartialEvidenceAndNeverInfersFromMonthFields": (
        "monthStart = 1",
        "monthEnd = 99",
        ".partialCurrentState",
    ),
    "testNoProgramStateAndNoLedgerProjectsHonestUnavailableEvidence": (
        "fixture.context.delete(fixture.state)",
        ".unavailable",
        "XCTAssertTrue(report.phaseSegments.isEmpty)",
    ),
    "testNoProgramStateWithValidNonemptyLedgerFailsStateLedgerMismatch": (
        "PhaseTransitionLedgerV1(records: [record]).encoded",
        ".phaseTransitionStateMismatch(programID: fixture.program.id)",
    ),
    "testNoProgramStateWithValidEmptyLedgerSettingFailsStateLedgerMismatch": (
        "value: emptyLedger()",
        ".phaseTransitionStateMismatch(programID: fixture.program.id)",
    ),
    "testNoProgramStateStillDecodesMalformedUnknownCrossProgramAndBrokenLedgers": (
        ".malformedPayload",
        ".unsupportedSchemaVersion(2)",
        ".crossProgramRecord(",
        ".brokenTransitionChain(",
    ),
    "testOutOfIntervalAndOtherProgramCorruptionDoesNotPoisonSelectedProjection": (
        "durationHours: .nan",
        "isActive: false",
        "XCTAssertTrue(source.sleepRecords.isEmpty)",
    ),
}

TASK4_TRAINING_VIEW_MODEL_TEST_BEHAVIORS = {
    "testConfirmingAlreadyCurrentPhaseIsExactNoOpWithoutTransitionHapticOrPublication": (
        "repository.programState?.currentPhaseId = nextID",
        "await viewModel.confirmTransition(at: confirmedAt)",
        "XCTAssertTrue(repository.activePhaseSelectionRequests.isEmpty)",
        "XCTAssertEqual(viewModel.state, before)",
        "XCTAssertTrue(hapticClient.feedback.isEmpty)",
    ),
}

TASK5_SHARE_TEST_BEHAVIORS = {
    "testDescriptorOrdersChronologicallyAndUsesPoseThenImageBytesForEqualDates": (
        "ProgressPhotoComparisonShareDescriptor(first: later, second: earlier)",
        "XCTAssertEqual(chronological.before, earlier)",
        "XCTAssertEqual(chronological.after, later)",
        "XCTAssertEqual(poseForward, poseReverse)",
        "XCTAssertEqual(poseForward.before, front)",
        "XCTAssertEqual(byteForward, byteReverse)",
    ),
    "testDescriptorRejectsDuplicateItemsAndExposesOnlyImageDateAndPose": (
        ".duplicateItems",
        "Mirror(reflecting: descriptor)",
        'Set(["before", "after"])',
        "Mirror(reflecting: shareItem)",
        'Set(["imageData", "date", "pose"])',
    ),
    "testGalleryFailsClosedUntilTwoDistinctDecodableFullImagesAreReady": (
        "XCTAssertFalse(viewModel.canShareComparison)",
        "XCTAssertThrowsError(try viewModel.makeComparisonShareDescriptor())",
        "second.imageRef: .corrupt",
        ".available(Data([0x00, 0x01]))",
        "XCTAssertEqual(viewModel.selectedPhotoIDs, [first.id, second.id])",
        "XCTAssertTrue(viewModel.canShareComparison)",
        "XCTAssertEqual(descriptor.before.imageData, firstJPEG)",
        "XCTAssertEqual(descriptor.after.imageData, secondJPEG)",
    ),
    "testSelectionAndLoadingNeverRenderWriteOrPresentBeforeExplicitShare": (
        "XCTAssertEqual(renderer.renderCount, 0)",
        "XCTAssertEqual(store.writeCount, 0)",
        "XCTAssertNil(coordinator.artifact)",
        "await coordinator.share",
        "try fixture.viewModel.makeComparisonShareDescriptor()",
        "XCTAssertEqual(renderer.renderCount, 1)",
        "XCTAssertEqual(store.writeCount, 1)",
        "XCTAssertEqual(coordinator.phase, .ready)",
    ),
    "testUIKitRendererRejectsEitherCorruptInput": (
        "first: corrupt, second: valid",
        "first: valid, second: corrupt",
        "renderer.render(descriptor)",
        ".corruptImage",
    ),
    "testUIKitRendererCreatesMetadataFreeJPEGWithoutPrivateSourceBytes": (
        "jpegWithTrailingTokens(",
        "for signature in forbiddenPrivacyMetadataSignatures",
        "for token in privateTokens",
        "UIKitProgressPhotoComparisonRenderer().render(descriptor)",
        "CGImageSourceGetType(source)",
        "UTType.jpeg.identifier",
        "kCGImagePropertyExifDictionary",
        "allowedIntrinsicExifKeys",
        "forbiddenPrivacyMetadataSignatures",
        'Data([0x45, 0x78, 0x69, 0x66, 0x00, 0x00])',
        "kCGImagePropertyGPSDictionary",
        "kCGImagePropertyIPTCDictionary",
        "kCGImagePropertyTIFFDictionary",
        "XCTAssertNil(output.range(of: Data(token.utf8)), token)",
    ),
    "testJPEGSanitizerRemovesPrivacySegmentsAndPreservesScanTail": (
        "JPEGPrivacySegmentSanitizer.sanitize(input)",
        "jpegSegment(marker: 0xe1",
        "jpegSegment(marker: 0xed",
        "jpegSegment(marker: 0xfe",
        "XCTAssertEqual(output.suffix(scanTail.count), scanTail)",
        "XCTAssertNil(output.range(of: payload))",
    ),
    "testJPEGSanitizerFailsClosedForMalformedOrTruncatedStreams": (
        "malformedStreams",
        "JPEGPrivacySegmentSanitizer.sanitize(stream)",
        "XCTAssertThrowsError",
        ".renderingFailed",
    ),
    "testTemporaryStoreUsesIsolatedCompleteProtectedDirectoryAndOwnedCleanup": (
        "ProgressPhotoComparisonTemporaryStore(",
        "XCTAssertEqual(fileSystem.createdDirectories, [root, ownedDirectory])",
        "XCTAssertEqual(fileSystem.protectedURLs, [root, ownedDirectory])",
        'ownedDirectory.appendingPathComponent("comparison.jpg")',
        "artifact.cleanup()",
        "XCTAssertEqual(fileSystem.removedURLs, [ownedDirectory])",
        "XCTAssertFalse(fileSystem.removedURLs.contains(",
    ),
    "testTemporaryStoreCleansAllocatedDirectoryAfterPartialWriteFailure": (
        "fileSystem.writeError = ShareFixtureError.writeFailed",
        "XCTAssertThrowsError(try store.writeOneUseJPEG",
        "XCTAssertEqual(fileSystem.removedURLs",
    ),
    "testCoordinatorCleansAfterCompletedCancelledFailedAndPresentationFailure": (
        "artifactID: try XCTUnwrap(coordinator.artifact?.id)",
        "activityDidFinish(",
        "error: ShareFixtureError.activityFailed",
        "coordinator.presentationDidFail(",
        "XCTAssertEqual(store.cleanupCount, 4)",
        "XCTAssertTrue(coordinator.hasRetryableError)",
    ),
    "testCoordinatorCleansOnDismissalReplacementAndRepeatedTerminalCallbacks": (
        "await coordinator.share { descriptor }",
        "XCTAssertEqual(store.cleanupCount, 1)",
        "coordinator.dismiss()",
        "artifactID: dismissedArtifactID",
        "XCTAssertEqual(store.cleanupCount, 2)",
        "XCTAssertNil(coordinator.artifact)",
    ),
    "testCoordinatorPreservesSelectionAndOffersRetryAfterRenderOrWriteFailure": (
        "let selectedIDs = fixture.viewModel.selectedPhotoIDs",
        "ShareFixtureError.renderFailed",
        "store.writeError = ShareFixtureError.writeFailed",
        "XCTAssertTrue(coordinator.hasRetryableError)",
        "XCTAssertEqual(fixture.viewModel.selectedPhotoIDs, selectedIDs)",
        "XCTAssertEqual(coordinator.phase, .ready)",
    ),
    "testDismissDuringSuspendedRenderInvalidatesOperationWithoutWritingOrPublishing": (
        "ShareSuspendingRenderer(",
        "await renderer.waitUntilSuspended(call: 1)",
        "coordinator.dismiss()",
        "renderer.resume(call: 1)",
        "await operation.value",
        "XCTAssertEqual(store.writeCount, 0)",
        "XCTAssertNil(coordinator.artifact)",
        "XCTAssertEqual(coordinator.phase, .idle)",
    ),
    "testNewerShareWinsWhenOlderSuspendedRenderResumes": (
        "await renderer.waitUntilSuspended(call: 1)",
        "await coordinator.share { descriptor }",
        "let newerArtifactID = try XCTUnwrap(coordinator.artifact?.id)",
        "renderer.resume(call: 1)",
        "XCTAssertEqual(store.writtenData, [newerJPEG])",
        "XCTAssertEqual(store.writeCount, 1)",
        "XCTAssertEqual(store.cleanupCount, 0)",
        "XCTAssertEqual(coordinator.artifact?.id, newerArtifactID)",
    ),
    "testExternalTaskCancellationDuringSuspendedRenderNeverWritesArtifact": (
        "await renderer.waitUntilSuspended(call: 1)",
        "operation.cancel()",
        "renderer.resume(call: 1)",
        "XCTAssertEqual(store.writeCount, 0)",
        "XCTAssertNil(coordinator.artifact)",
    ),
    "testQueuedCancelledShareCannotEnterAfterDismissalOrCallDescriptor": (
        "let gate = ShareEntryGate()",
        "await gate.waitUntilEntered()",
        "queuedShare.cancel()",
        "coordinator.dismiss()",
        "gate.open()",
        "XCTAssertEqual(descriptorCallCount, 0)",
        "XCTAssertEqual(renderer.renderCount, 1)",
        "XCTAssertEqual(store.writeCount, 1)",
        "XCTAssertEqual(store.cleanupCount, 1)",
        "XCTAssertNil(coordinator.artifact)",
    ),
    "testStaleActivityAndPresentationCallbacksCannotCleanNewerArtifact": (
        "let activityArtifactA = try XCTUnwrap(activityCoordinator.artifact)",
        "let activityArtifactB = try XCTUnwrap(activityCoordinator.artifact)",
        "activityCoordinator.activityDidFinish(",
        "artifactID: activityArtifactA.id",
        "XCTAssertEqual(activityCoordinator.artifact?.id, activityArtifactB.id)",
        "let presentationArtifactA = try XCTUnwrap(presentationCoordinator.artifact)",
        "let presentationArtifactB = try XCTUnwrap(presentationCoordinator.artifact)",
        "presentationCoordinator.presentationDidFail(",
        "artifactID: presentationArtifactA.id",
        "XCTAssertEqual(presentationCoordinator.artifact?.id, presentationArtifactB.id)",
    ),
    "testArtifactCleanupRetriesAfterTransientRemovalFailure": (
        "fileSystem.removeError = ShareFixtureError.cleanupFailed",
        "artifact.cleanup()",
        "XCTAssertEqual(fileSystem.removalAttempts, [ownedDirectory, ownedDirectory])",
        "XCTAssertEqual(fileSystem.removedURLs, [ownedDirectory])",
    ),
    "testCoordinatorRetainsFailedCleanupAndRetriesWithoutRepublishingArtifact": (
        "fileSystem.removeError = ShareFixtureError.cleanupFailed",
        "coordinator.dismiss()",
        "XCTAssertNil(coordinator.artifact)",
        "XCTAssertEqual(coordinator.phase, .failed)",
        "XCTAssertEqual(fileSystem.removalAttempts, [ownedDirectory, ownedDirectory])",
        "XCTAssertEqual(fileSystem.writes.count, 1)",
    ),
    "testPartialWriteCleanupFailureIsRetriedBeforeNextAllocation": (
        "fileSystem.writeError = ShareFixtureError.writeFailed",
        "fileSystem.removeError = ShareFixtureError.cleanupFailed",
        "XCTAssertThrowsError(try store.writeOneUseJPEG",
        "let artifact = try store.writeOneUseJPEG",
        "XCTAssertEqual(fileSystem.removalAttempts, [firstDirectory, firstDirectory])",
        "XCTAssertLessThan(retryIndex, allocationIndex)",
    ),
    "testPartialWriteCleanupOutlivesReleasedStoreWithoutAnotherWrite": (
        "fileSystem.writeError = ShareFixtureError.writeFailed",
        "fileSystem.removeError = ShareFixtureError.cleanupFailed",
        "weak var releasedStore = store",
        "XCTAssertThrowsError(",
        "store = nil",
        "XCTAssertNil(releasedStore)",
        "let didCleanUp = await waitUntil",
        "XCTAssertTrue(didCleanUp)",
        "XCTAssertEqual(fileSystem.removalAttempts, [ownedDirectory, ownedDirectory])",
        "XCTAssertEqual(fileSystem.writes.count, 1)",
    ),
    "testTerminalCleanupOutlivesReleasedCoordinatorAndStore": (
        "weak var releasedStore = store",
        "weak var releasedCoordinator = coordinator",
        "fileSystem.removeError = ShareFixtureError.cleanupFailed",
        "coordinator?.dismiss()",
        "coordinator = nil",
        "store = nil",
        "XCTAssertNil(releasedCoordinator)",
        "XCTAssertNil(releasedStore)",
        "let didCleanUp = await waitUntil",
        "XCTAssertTrue(didCleanUp)",
        "XCTAssertEqual(fileSystem.removalAttempts, [ownedDirectory, ownedDirectory])",
    ),
    "testStaleLifetimeRetryCannotDeleteNewArtifactAtReusedOwnedURL": (
        "let scheduler = ShareCleanupSchedulerFake()",
        "ProgressPhotoComparisonLifetimeCleanupRegistry(",
        'root.appendingPathComponent("not-an-owned-uuid"',
        "XCTAssertFalse(scheduler.hasScheduledOperation)",
        "registry.retainOwnedDirectory(ownedDirectory, under: root)",
        "registry.didCleanOwnedDirectory(ownedDirectory, under: root)",
        "XCTAssertEqual(scheduler.pendingOperationCount, 2)",
        "scheduler.runNext()",
        "XCTAssertEqual(nonOwnedCleanupCount, 0)",
        "XCTAssertEqual(newArtifactCleanupCount, 0)",
        "XCTAssertEqual(scheduler.pendingOperationCount, 1)",
        "XCTAssertEqual(newArtifactCleanupCount, 1)",
        "XCTAssertFalse(scheduler.hasScheduledOperation)",
    ),
    "testStoreSkipsCollidingDirectoryWithoutTouchingPreexistingContent": (
        "fileSystem.collisionDirectories = [collisionDirectory]",
        "fileSystem.sentinelContents[collisionDirectory] = sentinel",
        "let artifact = try store.writeOneUseJPEG",
        "XCTAssertEqual(fileSystem.sentinelContents[collisionDirectory], sentinel)",
        "XCTAssertFalse(fileSystem.protectedURLs.contains(collisionDirectory))",
        "XCTAssertFalse(fileSystem.removalAttempts.contains(collisionDirectory))",
    ),
    "testStoreFailsClosedAfterBoundedDirectoryCollisionsWithoutDeletingAny": (
        "fileSystem.collisionDirectories = Set(collisionDirectories)",
        "XCTAssertThrowsError(try store.writeOneUseJPEG",
        "XCTAssertEqual(fileSystem.createdDirectories.filter",
        "collisionDirectories",
        "XCTAssertTrue(fileSystem.writes.isEmpty)",
        "XCTAssertTrue(fileSystem.removalAttempts.isEmpty)",
    ),
    "testRendererUsesFixedDarkInkAndWrapsSupportedCaptionsOnWhiteInDarkAppearance": (
        "preferredContentSizeCategory: .large",
        "let baselineRaster = try rgbaRaster(baselineOutput)",
        "UITraitCollection(userInterfaceStyle: .dark)",
        "preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge",
        "UIKitProgressPhotoComparisonRenderer(",
        "let raster = try rgbaRaster(output)",
        "XCTAssertGreaterThan(raster.height, baselineRaster.height + 80)",
        "XCTAssertTrue(raster.isNearlyWhite(x: 8, y: 8))",
        "let ink = raster.darkPixels(",
        "XCTAssertGreaterThan(ink.count, 250)",
        "XCTAssertGreaterThanOrEqual(Set(ink.map(\\.y)).count, 56)",
    ),
}

TASK5_GALLERY_TEST_BEHAVIORS = {
    "testLargeGalleryDefersEveryThumbnailAndLoadsFullImagesOnlyForCompare": (
        "let firstFullJPEG = galleryJPEG(color: .red)",
        "let secondFullJPEG = galleryJPEG(color: .blue)",
        "first.imageRef: .available(firstFullJPEG)",
        "second.imageRef: .available(secondFullJPEG)",
        "XCTAssertEqual(repository.fullImageRequests, [second.imageRef, first.imageRef])",
        "XCTAssertEqual(viewModel.comparison?.before.assetState, .available(firstFullJPEG))",
        "XCTAssertEqual(viewModel.comparison?.after.assetState, .available(secondFullJPEG))",
    ),
    "testCompareFullImageFallbacksRetryProtectedDataWithoutThumbnailReuse": (
        "second.imageRef: .corrupt",
        "let thirdFullJPEG = galleryJPEG(color: .green)",
        "third.imageRef: .available(thirdFullJPEG)",
        "XCTAssertEqual(viewModel.comparison?.after.assetState, .available(thirdFullJPEG))",
    ),
    "testSuccessfulSyncReloadsExactMissingAndCorruptGalleryStatesInOpenLifecycle": (
        "let missingFullJPEG = galleryJPEG(color: .orange)",
        "let corruptFullJPEG = galleryJPEG(color: .purple)",
        "comparisonMissing.imageRef: .missing",
        "comparisonCorrupt.imageRef: .corrupt",
        "repository.fullImages[comparisonMissing.imageRef] = .available(missingFullJPEG)",
        "repository.fullImages[comparisonCorrupt.imageRef] = .available(corruptFullJPEG)",
    ),
}

TASK5_UI_TEST_BEHAVIORS = {
    "testShareAppearsForTwoReadyPhotosAndPresentsOnlyAfterExplicitTap": (
        "let share = app.buttons[",
        "XCTAssertFalse(share.exists)",
        "first.tap()",
        "second.tap()",
        "require(share,",
        "XCTAssertGreaterThanOrEqual(share.frame.height, 52)",
        "XCTAssertTrue(share.label.localizedCaseInsensitiveContains(\"paylaş\"))",
        "let activitySheet = app.descendants(matching: .any)[",
        "share.tap()",
        "app.descendants(matching: .any)[",
        "activitySheet.waitForExistence(timeout: 15)",
    ),
}

TASK5_TEST_ASSET_SHA256 = {
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/ProgressPhotoComparisonShareTests.swift": (
        "5de8d3f1574f144fd5926684d296cceaccc548885d1ea3bb96eb9ae9bd4b7340"
    ),
    "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/ProgressPhotoGalleryViewModelTests.swift": (
        "23d0089117316bdc439cf7cf8507745e92852b64feb7319ce0b241af6962cc11"
    ),
    "HealthTrackingAppUITests/ProgressPhotoGalleryUITests.swift": (
        "228e1c489759f93d5284975efefddc0171294cb7c38bc0e689fa9dd5fb67aae5"
    ),
}


def compact_swift_tokens(source: str) -> str:
    return re.sub(r"[ \t\f\v\r\n]+", "", source)


def compact_task5_swift(source: str) -> str:
    return compact_swift_tokens(swift_code_without_comments_and_literals(source))


def task5_call_uses_exact_literal(
    source: str,
    code: str,
    callee: str,
    literal: str,
) -> bool:
    target = json.dumps(literal)
    for match in re.finditer(rf"{re.escape(callee)}[ \t\f\v\r\n]*\(", code):
        opening = code.find("(", match.start())
        depth = 1
        cursor = opening + 1
        while cursor < len(code) and depth:
            if code[cursor] == "(":
                depth += 1
            elif code[cursor] == ")":
                depth -= 1
            cursor += 1
        if depth == 0 and target in source[match.start():cursor]:
            return True
    return False


def verify_meaningful_task3_tests(
    path: Path,
    suite_name: str,
    require_main_actor: bool,
    behavior_contracts: dict[str, tuple[str, ...]],
) -> None:
    methods = swift_xctest_suite_methods(
        path.read_text(encoding="utf-8"),
        suite_name,
        require_main_actor,
    )
    required_names = set(behavior_contracts)
    if len(methods) < len(required_names) or not required_names.issubset(methods):
        raise ValueError(
            f"{path.name} must retain a nonzero suite of meaningful Task 3 tests"
        )
    assertion = re.compile(r"\b(?:XCTAssert|assert)[A-Z][A-Za-z0-9_]*\s*\(")
    assertionless = sorted(name for name in required_names if assertion.search(methods[name]) is None)
    if assertionless:
        raise ValueError(
            f"{path.name} must retain meaningful Task 3 tests with assertions: {assertionless}"
        )
    for name, required_fragments in behavior_contracts.items():
        body = compact_swift_tokens(methods[name])
        missing = [
            fragment
            for fragment in required_fragments
            if compact_swift_tokens(fragment) not in body
        ]
        if missing:
            raise ValueError(
                f"{path.name} must retain behavioral Task 3 test contracts in {name}: "
                f"{missing}"
            )


def verify_meaningful_task4_tests(
    path: Path,
    suite_name: str,
    require_main_actor: bool,
    behavior_contracts: dict[str, tuple[str, ...]],
) -> None:
    methods = swift_xctest_suite_methods(
        path.read_text(encoding="utf-8"),
        suite_name,
        require_main_actor,
    )
    required_names = set(behavior_contracts)
    if len(methods) < len(required_names) or not required_names.issubset(methods):
        raise ValueError(
            f"{path.name} must retain a nonzero suite of meaningful Task 4 tests"
        )
    assertion = re.compile(r"\b(?:XCTAssert|assert)[A-Z][A-Za-z0-9_]*\s*\(")
    assertionless = sorted(name for name in required_names if assertion.search(methods[name]) is None)
    if assertionless:
        raise ValueError(
            f"{path.name} must retain meaningful Task 4 tests with assertions: {assertionless}"
        )
    for name, required_fragments in behavior_contracts.items():
        body = compact_swift_tokens(methods[name])
        missing = [
            fragment
            for fragment in required_fragments
            if compact_swift_tokens(fragment) not in body
        ]
        if missing:
            raise ValueError(
                f"{path.name} must retain behavioral Task 4 test contracts in {name}: "
                f"{missing}"
            )


def verify_meaningful_task5_tests(
    path: Path,
    suite_name: str,
    require_main_actor: bool,
    behavior_contracts: dict[str, tuple[str, ...]],
    require_exact_test_names: bool = False,
) -> None:
    methods = swift_xctest_suite_methods(
        path.read_text(encoding="utf-8"),
        suite_name,
        require_main_actor,
    )
    required_names = set(behavior_contracts)
    if (
        (require_exact_test_names and set(methods) != required_names)
        or (not require_exact_test_names and not required_names.issubset(methods))
    ):
        raise ValueError(
            f"{path.name} must retain a nonzero suite of meaningful Task 5 tests"
        )
    assertion_family = re.compile(
        r"\b(XCT(?:Assert[A-Z][A-Za-z0-9_]*|Fail))\s*\("
    )
    reachable_methods = {
        name: task5_reachable_direct_method_body(methods[name], path, name)
        for name in required_names
    }
    weak_assertions = sorted(
        name
        for name in required_names
        if len(set(assertion_family.findall(reachable_methods[name]))) < 2
    )
    if weak_assertions:
        raise ValueError(
            f"{path.name} must retain reachable direct behavior and independent "
            f"assertion families for Task 5: {weak_assertions}"
        )
    for name, required_fragments in behavior_contracts.items():
        body = compact_swift_tokens(reachable_methods[name])
        missing = [
            fragment
            for fragment in required_fragments
            if compact_swift_tokens(
                swift_code_without_comments_and_literals(fragment)
            ) not in body
        ]
        if missing:
            raise ValueError(
                f"{path.name} must retain behavioral Task 5 test contracts with "
                f"reachable direct behavior in "
                f"{name}: {missing}"
            )


def task5_skip_swift_space(code: str, cursor: int) -> int:
    while cursor < len(code) and code[cursor].isspace():
        cursor += 1
    return cursor


def task5_swift_keyword_at(code: str, cursor: int, keyword: str) -> bool:
    end = cursor + len(keyword)
    return (
        code[cursor:end] == keyword
        and (cursor == 0 or not (code[cursor - 1].isalnum() or code[cursor - 1] == "_"))
        and (end == len(code) or not (code[end].isalnum() or code[end] == "_"))
    )


def task5_control_body_opening(
    code: str,
    statement_start: int,
    keyword: str,
    name: str,
) -> int:
    cursor = statement_start + len(keyword)
    parentheses = 0
    brackets = 0
    while cursor < len(code):
        character = code[cursor]
        if character == "(":
            parentheses += 1
        elif character == ")":
            parentheses -= 1
        elif character == "[":
            brackets += 1
        elif character == "]":
            brackets -= 1
        elif character == "{" and parentheses == 0 and brackets == 0:
            return cursor
        elif character == "}" and parentheses == 0 and brackets == 0:
            break
        cursor += 1
    raise ValueError(f"Task 5 control statement in {name} must have a complete body")


def task5_if_statement_extent(
    code: str,
    if_start: int,
    name: str,
) -> tuple[int, int, int | None, int]:
    opening = task5_control_body_opening(code, if_start, "if", name)
    closing = balanced_brace_end(code, opening, f"Task 5 if statement in {name}")
    cursor = task5_skip_swift_space(code, closing + 1)
    if not task5_swift_keyword_at(code, cursor, "else"):
        return opening, closing, None, closing + 1

    else_start = cursor
    cursor = task5_skip_swift_space(code, cursor + len("else"))
    if task5_swift_keyword_at(code, cursor, "if"):
        _, _, _, statement_end = task5_if_statement_extent(code, cursor, name)
    elif cursor < len(code) and code[cursor] == "{":
        statement_end = balanced_brace_end(
            code,
            cursor,
            f"Task 5 else statement in {name}",
        ) + 1
    else:
        raise ValueError(f"Task 5 else statement in {name} must have a complete body")
    return opening, closing, else_start, statement_end


def task5_constant_boolean(condition: str) -> bool | None:
    compact = re.sub(r"[\s()]", "", condition)
    if compact in {"true", "!false"}:
        return True
    if compact in {"false", "!true"}:
        return False
    return None


def task5_blank_range(characters: list[str], start: int, end: int) -> None:
    for index in range(start, end):
        if characters[index] not in {"\r", "\n"}:
            characters[index] = " "


def task5_code_with_unreachable_constant_branches_removed(
    method: str,
    name: str,
) -> str:
    reachable = list(method)
    constant_condition = r"[ \t\f\v\r\n()!]*(?:true|false)[ \t\f\v\r\n()]*"
    constant_if = re.compile(rf"\bif\b(?P<condition>{constant_condition})\{{")
    for match in constant_if.finditer(method):
        selected_then = task5_constant_boolean(match.group("condition"))
        if selected_then is None:
            continue
        opening, closing, else_start, statement_end = task5_if_statement_extent(
            method,
            match.start(),
            name,
        )
        if selected_then:
            if else_start is not None:
                task5_blank_range(reachable, else_start, statement_end)
        else:
            task5_blank_range(
                reachable,
                opening if else_start is not None else match.start(),
                closing + 1,
            )

    constant_while = re.compile(rf"\bwhile\b(?P<condition>{constant_condition})\{{")
    for match in constant_while.finditer(method):
        if task5_constant_boolean(match.group("condition")) is not False:
            continue
        opening = method.find("{", match.start(), match.end())
        closing = balanced_brace_end(
            method,
            opening,
            f"Task 5 constant-unreachable while block in {name}",
        )
        task5_blank_range(reachable, match.start(), closing + 1)

    constant_guard = re.compile(
        rf"\bguard\b(?P<condition>{constant_condition})else\s*\{{"
    )
    for match in constant_guard.finditer(method):
        if task5_constant_boolean(match.group("condition")) is not True:
            continue
        opening = method.find("{", match.start(), match.end())
        closing = balanced_brace_end(
            method,
            opening,
            f"Task 5 constant-unreachable guard else block in {name}",
        )
        task5_blank_range(reachable, match.start(), closing + 1)
    return "".join(reachable)


def task5_code_without_escaped_identifiers(code: str, name: str) -> str:
    lexical = list(code)
    cursor = 0
    while cursor < len(code):
        if code[cursor] != "`":
            cursor += 1
            continue
        closing = code.find("`", cursor + 1)
        if closing == -1:
            raise ValueError(
                f"Task 5 test {name} must use complete escaped identifiers"
            )
        task5_blank_range(lexical, cursor, closing + 1)
        cursor = closing + 1
    return "".join(lexical)


def task5_reachable_direct_method_body(method: str, path: Path, name: str) -> str:
    lexical_method = task5_code_without_escaped_identifiers(method, name)
    if re.search(r"\bXCTSkip(?:If|Unless)?\s*\(", lexical_method):
        raise ValueError(
            f"{path.name} Task 5 test {name} must retain reachable direct behavior "
            "without XCTest skips"
        )
    if re.search(r"\b(?:return|throw)\b", lexical_method):
        raise ValueError(
            f"{path.name} Task 5 test {name} must retain reachable direct behavior "
            "without terminal statements in the bound method body"
        )

    reachable_code = task5_code_with_unreachable_constant_branches_removed(
        lexical_method,
        name,
    )
    return reachable_code


def swift_named_type_body(code: str, type_name: str) -> str:
    declaration = re.search(
        rf"\b(?:struct|class|enum|protocol)\s+{re.escape(type_name)}\b[^{{}}]*\{{",
        code,
    )
    if declaration is None:
        raise ValueError(f"Task 5 type {type_name} must exist")
    opening = declaration.end() - 1
    closing = balanced_brace_end(code, opening, f"Task 5 type {type_name}")
    return code[opening + 1 : closing]


def swift_named_type_bodies(source: str, type_name: str) -> tuple[str, str]:
    code = swift_code_without_comments_and_literals(source)
    declaration = re.search(
        rf"\b(?:struct|class|enum|protocol)\s+{re.escape(type_name)}\b[^{{}}]*\{{",
        code,
    )
    if declaration is None:
        raise ValueError(f"Task 6 type {type_name} must exist")
    opening = declaration.end() - 1
    closing = balanced_brace_end(code, opening, f"Task 6 type {type_name}")
    return code[opening + 1 : closing], source[opening + 1 : closing]


def swift_named_array_initializer_calls(
    source: str,
    type_name: str,
    property_name: str,
    callee: str,
) -> list[str]:
    code_body, raw_body = swift_named_type_bodies(source, type_name)
    declaration = re.search(
        rf"\b(?:private\s+|fileprivate\s+|internal\s+|public\s+)?"
        rf"static\s+let\s+{re.escape(property_name)}\s*=\s*\[",
        code_body,
    )
    if declaration is None:
        raise ValueError(
            f"Task 6 {type_name}.{property_name} must have one array initializer"
        )
    opening = declaration.end() - 1
    closing = balanced_delimiter_end(
        code_body,
        opening,
        "[",
        "]",
        f"Task 6 {type_name}.{property_name}",
    )
    code_initializer = code_body[opening + 1 : closing]
    raw_initializer = raw_body[opening + 1 : closing]
    calls: list[str] = []
    for call in re.finditer(rf"\b{re.escape(callee)}\s*\(", code_initializer):
        call_opening = code_initializer.find("(", call.start(), call.end())
        call_closing = balanced_delimiter_end(
            code_initializer,
            call_opening,
            "(",
            ")",
            f"Task 6 {type_name}.{property_name} {callee} call",
        )
        calls.append(raw_initializer[call.start() : call_closing + 1])
    return calls


def swift_real_raw_fragment_present(
    code_scope: str,
    raw_scope: str,
    fragment: str,
) -> bool:
    expected_structure = compact_swift_tokens(
        swift_code_without_comments_and_literals(fragment)
    )
    cursor = 0
    while True:
        occurrence = raw_scope.find(fragment, cursor)
        if occurrence == -1:
            return False
        code_segment = code_scope[occurrence : occurrence + len(fragment)]
        if compact_swift_tokens(code_segment) == expected_structure:
            return True
        cursor = occurrence + 1


def swift_direct_raw_enum_cases(source: str, type_name: str) -> dict[str, list[str]]:
    code = swift_code_without_comments_and_literals(source)
    declaration = re.search(
        rf"\benum\s+{re.escape(type_name)}\b[^{{}}]*\{{",
        code,
    )
    if declaration is None:
        raise ValueError(f"Task 6 enum {type_name} must exist")
    opening = declaration.end() - 1
    closing = balanced_brace_end(code, opening, f"Task 6 enum {type_name}")
    code_body = code[opening + 1 : closing]
    raw_body = source[opening + 1 : closing]

    depths: list[int] = []
    depth = 0
    for character in code_body:
        depths.append(depth)
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1

    cases: dict[str, list[str]] = {}
    declaration_pattern = re.compile(
        r"\bcase[ \t\f\v\r\n]+([A-Za-z_][A-Za-z0-9_]*)"
        r"[ \t\f\v\r\n]*="
    )
    for match in declaration_pattern.finditer(code_body):
        if depths[match.start()] != 0:
            continue
        cursor = match.end()
        while cursor < len(raw_body) and raw_body[cursor].isspace():
            cursor += 1
        literal = re.match(r'"(?:[^"\\]|\\.)*"', raw_body[cursor:])
        if literal is None:
            cases.setdefault(match.group(1), []).append("")
            continue
        cases.setdefault(match.group(1), []).append(literal.group(0))
    return cases


def swift_unique_function_body(
    code: str,
    function_name: str,
    signature_fragment: str,
) -> str:
    declaration = re.compile(
        rf"\bfunc[ \t\f\v\r\n]+{re.escape(function_name)}\b[^{{}}]*\{{"
    )
    expected_signature = compact_swift_tokens(signature_fragment)
    matches = [
        match
        for match in declaration.finditer(code)
        if expected_signature in compact_swift_tokens(match.group(0))
    ]
    if len(matches) != 1:
        raise ValueError(
            f"Task 6 function {function_name} must have one expected declaration"
        )
    opening = matches[0].end() - 1
    closing = balanced_brace_end(
        code,
        opening,
        f"Task 6 function {function_name}",
    )
    return code[opening + 1 : closing]


def swift_unique_function_bodies(
    source: str,
    function_name: str,
    signature_fragment: str,
) -> tuple[str, str]:
    code = swift_code_without_comments_and_literals(source)
    declaration = re.compile(
        rf"\bfunc[ \t\f\v\r\n]+{re.escape(function_name)}\b[^{{}}]*\{{"
    )
    expected_signature = compact_swift_tokens(signature_fragment)
    matches = [
        match
        for match in declaration.finditer(code)
        if expected_signature in compact_swift_tokens(match.group(0))
    ]
    if len(matches) != 1:
        raise ValueError(
            f"Task 6 function {function_name} must have one expected declaration"
        )
    opening = matches[0].end() - 1
    closing = balanced_brace_end(
        code,
        opening,
        f"Task 6 function {function_name}",
    )
    return code[opening + 1 : closing], source[opening + 1 : closing]


def swift_unique_initializer_body(
    code: str,
    type_name: str,
    signature_fragment: str,
) -> str:
    type_body = swift_named_type_body(code, type_name)
    declaration = re.compile(r"\binit\b[^{{}}]*\{")
    expected_signature = compact_swift_tokens(signature_fragment)
    matches = [
        match
        for match in declaration.finditer(type_body)
        if expected_signature in compact_swift_tokens(match.group(0))
    ]
    if len(matches) != 1:
        raise ValueError(
            f"Task 6 {type_name} initializer must have one expected declaration"
        )
    opening = matches[0].end() - 1
    closing = balanced_brace_end(
        type_body,
        opening,
        f"Task 6 {type_name} initializer",
    )
    return type_body[opening + 1 : closing]


def task5_stored_let_names(code: str, type_name: str) -> set[str]:
    body = swift_named_type_body(code, type_name)
    return set(
        re.findall(
            r"\b(?:public\s+)?let\s+([A-Za-z_][A-Za-z0-9_]*)\s*:",
            body,
        )
    )


def verify_task5_assets(
    root: Path,
    enforce_test_asset_digests: bool = True,
) -> None:
    module = root / "Packages/HealthTrackingModules"
    share_test = module / "Tests/ProgressPhotosKitTests/ProgressPhotoComparisonShareTests.swift"
    gallery_test = module / "Tests/ProgressPhotosKitTests/ProgressPhotoGalleryViewModelTests.swift"
    ui_test = root / "HealthTrackingAppUITests/ProgressPhotoGalleryUITests.swift"
    missing_tests = [
        str(path.relative_to(root))
        for path in (share_test, gallery_test, ui_test)
        if not path.is_file()
    ]
    if missing_tests:
        raise ValueError(f"Task 5 test contracts are missing: {missing_tests}")
    verify_meaningful_task5_tests(
        share_test,
        "ProgressPhotoComparisonShareTests",
        True,
        TASK5_SHARE_TEST_BEHAVIORS,
        require_exact_test_names=True,
    )
    verify_meaningful_task5_tests(
        gallery_test,
        "ProgressPhotoGalleryViewModelTests",
        True,
        TASK5_GALLERY_TEST_BEHAVIORS,
    )
    verify_meaningful_task5_tests(
        ui_test,
        "ProgressPhotoGalleryUITests",
        False,
        TASK5_UI_TEST_BEHAVIORS,
    )
    if enforce_test_asset_digests:
        for path in (share_test, gallery_test, ui_test):
            relative = str(path.relative_to(root))
            actual_digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if TASK5_TEST_ASSET_SHA256.get(relative) != actual_digest:
                raise ValueError(
                    f"Task 5 test asset digest mismatch: {relative}"
                )

    progress_root = module / "Sources/ProgressPhotosKit"
    required_sources = (
        progress_root / "Share/ProgressPhotoComparisonShareDomain.swift",
        progress_root / "Share/UIKitProgressPhotoComparisonRenderer.swift",
        progress_root / "Share/ProgressPhotoComparisonShareCoordinator.swift",
        progress_root / "Gallery/ProgressPhotoGalleryViewModel.swift",
        progress_root / "Gallery/ProgressPhotoGalleryView.swift",
        progress_root / "Resources/Localizable.xcstrings",
        module / "Sources/DesignSystem/Platform/SystemActivityView.swift",
    )
    missing_sources = [
        str(path.relative_to(root)) for path in required_sources if not path.is_file()
    ]
    if missing_sources:
        raise ValueError(f"Task 5 production contracts are missing: {missing_sources}")

    tracker_verifier = root / "scripts/verify-trackers.sh"
    renderer_allowlist_entry = (
        '"Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Share/'
        'UIKitProgressPhotoComparisonRenderer.swift",'
    )
    if (
        not tracker_verifier.is_file()
        or tracker_verifier.read_text(encoding="utf-8").count(
            renderer_allowlist_entry
        ) != 1
    ):
        raise ValueError(
            "Task 5 UIKit renderer must be the one exact added M3 named-adapter allowlist path"
        )

    domain_source = required_sources[0].read_text(encoding="utf-8")
    domain_code = swift_code_without_comments_and_literals(domain_source)
    if task5_stored_let_names(domain_code, "ProgressPhotoShareItem") != {
        "imageData",
        "date",
        "pose",
    }:
        raise ValueError("Task 5 share item boundary must contain only imageData, date, and pose")
    if task5_stored_let_names(
        domain_code,
        "ProgressPhotoComparisonShareDescriptor",
    ) != {"before", "after"}:
        raise ValueError("Task 5 descriptor boundary must contain only before and after share items")
    item_body = swift_named_type_body(domain_code, "ProgressPhotoShareItem")
    descriptor_body = swift_named_type_body(
        domain_code,
        "ProgressPhotoComparisonShareDescriptor",
    )
    forbidden_boundary = re.compile(
        r"\b(?:note|assetID|imageRef|sourceURL|fileURL|path|"
        r"ProgressPhotoSnapshot|ProgressPhotoGalleryItem)\b",
        re.IGNORECASE,
    )
    if forbidden_boundary.search(item_body) or forbidden_boundary.search(descriptor_body):
        raise ValueError("Task 5 share boundary must never contain notes, IDs, paths, URLs, or models")
    domain_compact = compact_swift_tokens(domain_code)
    for fragment in (
        "case duplicateItems",
        "if lhs.date != rhs.date",
        "poseRank(lhs.pose)",
        "lhs.imageData.lexicographicallyPrecedes(rhs.imageData)",
        "guard first != second else",
    ):
        if compact_task5_swift(fragment) not in domain_compact:
            raise ValueError(
                "Task 5 descriptor must reject duplicates and deterministically order "
                "date, pose, then image bytes without opaque IDs"
            )

    view_model_code = swift_code_without_comments_and_literals(
        required_sources[3].read_text(encoding="utf-8")
    )
    view_model_compact = compact_swift_tokens(view_model_code)
    for fragment in (
        "public var canShareComparison: Bool",
        "public func makeComparisonShareDescriptor() throws",
        "guard selectedPhotoIDs.count == 2",
        "Set(selectedPhotoIDs).count == 2",
        "case let .available(beforeData)",
        "case let .available(afterData)",
        "return !beforeData.isEmpty && !afterData.isEmpty",
        "ProgressPhotoShareItem(imageData: beforeData, date: comparison.before.snapshot.date, pose: comparison.before.snapshot.pose)",
        "ProgressPhotoShareItem(imageData: afterData, date: comparison.after.snapshot.date, pose: comparison.after.snapshot.pose)",
        "comparisonAssetStates[id] = comparisonGalleryState(from: result)",
        "try ProgressPhotoComparisonImageValidation.validate(bytes)",
    ):
        if compact_task5_swift(fragment) not in view_model_compact:
            raise ValueError(
                "Task 5 gallery must fail closed until exactly two selected full images "
                "are independently decodable"
            )
    if "ProgressPhotoComparisonImageValidation.validate(descriptor)" in view_model_compact:
        raise ValueError(
            "Task 5 gallery must use load-time validation instead of repeatedly decoding "
            "immutable full images during share availability evaluation"
        )

    renderer_source = required_sources[1].read_text(encoding="utf-8")
    renderer_code = swift_code_without_comments_and_literals(renderer_source)
    renderer_compact = compact_swift_tokens(renderer_code)
    for fragment in (
        "decode(descriptor.before.imageData)",
        "decode(descriptor.after.imageData)",
        "CGImageDestinationCreateWithData",
        "UTType.jpeg.identifier",
        "CGImageDestinationAddImage(destination, image, properties as CFDictionary)",
        "CGImageDestinationFinalize(destination)",
    ):
        if compact_task5_swift(fragment) not in renderer_compact:
            raise ValueError(
                "Task 5 renderer must independently decode both images and emit one "
                "fresh metadata-free JPEG"
            )
    if re.search(r"\b(?:note|assetID|imageRef|ProgressPhotoSnapshot)\b", renderer_code):
        raise ValueError("Task 5 renderer must never read model notes or opaque identifiers")
    if any(
        key in renderer_code
        for key in (
            "kCGImagePropertyExifDictionary",
            "kCGImagePropertyGPSDictionary",
            "kCGImagePropertyIPTCDictionary",
            "kCGImagePropertyTIFFDictionary",
        )
    ):
        raise ValueError("Task 5 renderer must not copy private metadata dictionaries")
    for fragment in (
        "UIColor.white.setFill()",
        "UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)",
        "UIColor(red: 0.18, green: 0.20, blue: 0.23, alpha: 1)",
        "paragraph.lineBreakMode = .byWordWrapping",
        "private let captionHorizontalInset: CGFloat = 20",
        "paneWidth: paneWidth - captionHorizontalInset * 2",
        "x: originX + captionHorizontalInset",
        "width: paneWidth - captionHorizontalInset * 2",
        "text.boundingRect(",
        "options: [.usesLineFragmentOrigin, .usesFontLeading]",
        "let captionHeight = max(beforeCaption.height, afterCaption.height)",
        "imageOriginY: outerPadding + captionHeight + imageSpacing",
        "private let traitCollection: UITraitCollection",
        "traitCollection ?? UITraitCollection.current",
        "UIFontMetrics(forTextStyle: .title2).scaledFont(",
        "UIFontMetrics(forTextStyle: .body).scaledFont(",
        "compatibleWith: traitCollection",
        ".font: titleFont",
        ".font: detailFont",
    ):
        if compact_task5_swift(fragment) not in renderer_compact:
            raise ValueError(
                "Task 5 renderer must measure wrapped localized captions and retain "
                "fixed dark ink on its fixed white background"
            )
    if any(
        compact_task5_swift(fragment) in renderer_compact
        for fragment in ("UIColor.label", "UIColor.secondaryLabel", ".byTruncatingTail")
    ):
        raise ValueError(
            "Task 5 renderer must not use dynamic semantic ink or truncate supported captions"
        )
    if (
        renderer_compact.count(compact_task5_swift("scaledFont(")) != 2
        or renderer_compact.count(
            compact_task5_swift("compatibleWith: traitCollection")
        ) != 2
    ):
        raise ValueError(
            "Task 5 renderer must measure and draw exact accessibility-scaled "
            "caption fonts for its explicit trait collection"
        )
    if renderer_compact.count(
        compact_task5_swift("x: originX + captionHorizontalInset")
    ) != 2:
        raise ValueError(
            "Task 5 renderer must measure wrapped localized captions with unclipped inset ink"
        )
    for fragment in (
        "let encodedJPEG = try encodeMetadataFreeJPEG(composite)",
        "let sanitizedJPEG = try JPEGPrivacySegmentSanitizer.sanitize(encodedJPEG)",
        "try ProgressPhotoComparisonImageValidation.validate(sanitizedJPEG)",
        "return sanitizedJPEG",
        "guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8",
        "if (0xe1...0xef).contains(marker) || marker == 0xfe",
        "guard segmentLength >= 2",
        "guard segmentEnd <= bytes.count",
        "output.append(contentsOf: bytes[markerStart..<segmentEnd])",
        "guard scanEnd == bytes.count",
    ):
        if compact_task5_swift(fragment) not in renderer_compact:
            raise ValueError(
                "Task 5 JPEG sanitizer must remove APP1-APP15 and COM metadata, "
                "preserve the scan tail, and fail closed on malformed streams"
            )

    coordinator_source = required_sources[2].read_text(encoding="utf-8")
    coordinator_code = swift_code_without_comments_and_literals(coordinator_source)
    coordinator_compact = compact_swift_tokens(coordinator_code)
    for fragment in (
        "func createExclusiveDirectory(at url: URL) throws",
        "withIntermediateDirectories: false",
        "private let maximumDirectoryAttempts = 8",
        "for _ in 0..<maximumDirectoryAttempts",
        "try fileSystem.createExclusiveDirectory(at: candidate)",
        "catch where Self.isDirectoryCollision(error)",
        "allocatedOwnedDirectory = ownedDirectory",
        "try fileSystem.applyCompleteFileProtection(at: rootDirectory)",
        "try fileSystem.applyCompleteFileProtection(at: ownedDirectory)",
        'ownedDirectory.appendingPathComponent("comparison.jpg")',
        "try fileSystem.writeAtomically(data, to: fileURL)",
        "private var pendingOwnedDirectories: [URL] = []",
        "guard retryPendingOwnedDirectoryCleanup() else",
        "rememberPendingOwnedDirectory(allocatedOwnedDirectory)",
        "final class ProgressPhotoComparisonLifetimeCleanupRegistry",
        "static let shared = ProgressPhotoComparisonLifetimeCleanupRegistry()",
        "private let retryDelaysNanoseconds: [UInt64]",
        "30_000_000_000",
        "scheduler.schedule(afterNanoseconds:",
        "let token: UUID",
        "scheduledTokens[directory] = entry.token",
        "self?.retry(directory, token: entry.token)",
        "guard scheduledTokens[directory] == token else { return }",
        "entry.token == token",
        "guard Self.isExactOwnedChild(directory, under: root) else { return }",
        "directory.deletingLastPathComponent().standardizedFileURL == rootDirectory",
        "let identifier = UUID(uuidString: directory.lastPathComponent)",
        "retainLifetimeCleanup(for: allocatedOwnedDirectory)",
        "cleanupRegistry.retainOwnedDirectory(",
        "lifetimeCleanupRegistry.retainOwnedDirectory(",
        "try cleanupAction()\ndidCleanUp = true",
        "artifact.cleanup()",
        "private var generation: UInt64 = 0",
        "generation += 1",
        "let operationGeneration = generation",
        "let renderedData = try await renderer.render(descriptor)",
        "try ensureCurrent(operationGeneration)",
        "private var pendingCleanupArtifacts: [ProgressPhotoOneUseArtifact] = []",
        "let pending = pendingCleanupArtifacts",
        "for artifact in pending where !artifact.cleanup()",
        "public func activityDidFinish(artifactID: UUID, completed: Bool, error: Error?)",
        "public func presentationDidFail(artifactID: UUID)",
        "guard artifact?.id == artifactID else { return }",
        "public func dismiss()",
        "cleanupCurrentAndPendingArtifacts()",
        "try Task.checkCancellation()",
        "guard !Task.isCancelled else { return }",
    ):
        if compact_task5_swift(fragment) not in coordinator_compact:
            raise ValueError(
                "Task 5 coordinator/store must retain isolated protection, one-use "
                "ownership, generation cancellation, exclusive allocation, and retryable "
                "idempotent cleanup"
            )
    if coordinator_compact.count(compact_task5_swift("try ensureCurrent(operationGeneration)")) < 3:
        raise ValueError(
            "Task 5 coordinator must guard every operation boundary with its current generation"
        )
    share_method_start = coordinator_compact.find(
        compact_task5_swift("public func share(")
    )
    share_method_end = coordinator_compact.find(
        compact_task5_swift("public func activityDidFinish("),
        share_method_start,
    )
    share_method = coordinator_compact[share_method_start:share_method_end]
    cancellation_preflight = share_method.find(
        compact_task5_swift("guard !Task.isCancelled else { return }")
    )
    generation_mutation = share_method.find(
        compact_task5_swift("generation += 1"),
        cancellation_preflight + 1,
    )
    if (
        share_method_start < 0
        or share_method_end < 0
        or cancellation_preflight < 0
        or generation_mutation < 0
        or cancellation_preflight > generation_mutation
    ):
        raise ValueError(
            "Task 5 coordinator must reject already-cancelled queued shares before "
            "mutating generation or cleanup state"
        )
    if coordinator_compact.count(
        compact_task5_swift(
            "guard Self.isExactOwnedChild(directory, under: root) else { return }"
        )
    ) != 2:
        raise ValueError(
            "Task 5 lifetime cleanup must accept only exact UUID child ownership"
        )
    if coordinator_compact.count(
        compact_task5_swift("guard artifact?.id == artifactID else { return }")
    ) != 2:
        raise ValueError(
            "Task 5 completion and presentation callbacks must each guard exact artifact identity"
        )
    if "try?" in coordinator_compact:
        raise ValueError("Task 5 cleanup must never silently abandon an owned artifact")
    if "removeItemIfExists(at:rootDirectory)" in coordinator_compact:
        raise ValueError("Task 5 cleanup must never delete the shared root or non-owned paths")

    activity_source = required_sources[6].read_text(encoding="utf-8")
    activity_code = swift_code_without_comments_and_literals(activity_source)
    activity_compact = compact_swift_tokens(activity_code)
    if "activityItems:[activityItemURL]" not in activity_compact:
        raise ValueError("Task 5 activity sheet must receive exactly the final JPEG URL")
    if re.search(r"activityItems\s*:\s*\[[^\]]*,", activity_code):
        raise ValueError("Task 5 activity sheet must never receive captions or extra items")
    for fragment in (
        "completionWithItemsHandler",
        "private let artifactID: UUID",
        "onCompletion(artifactID, completed, error)",
        "onPresentationFailure(artifactID)",
        'view.accessibilityIdentifier = accessibilityIdentifier',
    ):
        if compact_task5_swift(fragment) not in activity_compact:
            raise ValueError("Task 5 system activity lifecycle must report completion and presentation failure")

    gallery_source = required_sources[4].read_text(encoding="utf-8")
    gallery_code = swift_code_without_comments_and_literals(gallery_source)
    gallery_compact = compact_swift_tokens(gallery_code)
    for fragment in (
        "if viewModel.canShareComparison",
        "await shareCoordinator.share",
        "try viewModel.makeComparisonShareDescriptor()",
        ".frame(maxWidth: .infinity, minHeight: 52)",
        ".accessibilityIdentifier()",
        ".accessibilityLabel(localized())",
        ".accessibilityHint(localized())",
        "SystemActivityView(",
        "artifactID: artifact.id",
        "accessibilityIdentifier:",
        ".accessibilityElement(children: .contain)",
        "shareCoordinator.activityDidFinish(artifactID: artifactID, completed: completed, error: error)",
        "shareCoordinator.presentationDidFail(artifactID: artifactID)",
        ".onDisappear",
        "@State private var shareTask: Task<Void, Never>?",
        "shareTask = Task { @MainActor in",
        "shareTask?.cancel()",
        "shareCoordinator.dismiss()",
    ):
        if compact_task5_swift(fragment) not in gallery_compact:
            raise ValueError(
                "Task 5 gallery must expose the explicit localized 52-point share "
                "button and route every presentation lifecycle terminal"
            )
    if gallery_compact.count(compact_task5_swift("shareTask?.cancel()")) < 3:
        raise ValueError(
            "Task 5 gallery must own and cancel queued share work on replacement, "
            "dismissal, and disappearance"
        )
    disappearance = gallery_compact.find(compact_task5_swift(".onDisappear"))
    disappearance_cancel = gallery_compact.find(
        compact_task5_swift("shareTask?.cancel()"),
        disappearance,
    )
    disappearance_dismiss = gallery_compact.find(
        compact_task5_swift("shareCoordinator.dismiss()"),
        disappearance,
    )
    if (
        disappearance < 0
        or disappearance_cancel < 0
        or disappearance_dismiss < 0
        or disappearance_cancel > disappearance_dismiss
    ):
        raise ValueError(
            "Task 5 gallery must cancel its owned queued share before disappearance cleanup"
        )
    for callee, literal in (
        (".accessibilityIdentifier", "photos.compare.share"),
        ("localized", "photos.compare.share.label"),
        ("localized", "photos.compare.share.hint"),
        (".accessibilityIdentifier", "photos.compare.share.sheet"),
    ):
        if not task5_call_uses_exact_literal(
            gallery_source,
            gallery_code,
            callee,
            literal,
        ):
            raise ValueError(
                "Task 5 gallery must expose the explicit localized 52-point share "
                "button and route every presentation lifecycle terminal"
            )

    localizations = json.loads(required_sources[5].read_text(encoding="utf-8"))
    strings = localizations.get("strings", {})
    for key in (
        "photos.compare.share",
        "photos.compare.share.label",
        "photos.compare.share.hint",
        "photos.compare.share.error",
    ):
        value = (
            strings.get(key, {})
            .get("localizations", {})
            .get("tr", {})
            .get("stringUnit", {})
            .get("value")
        )
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"Task 5 localization must define a nonempty Turkish value for {key}")

    model_count = 0
    for source_root in (root / "App", module / "Sources"):
        if not source_root.exists():
            continue
        for source in source_root.rglob("*.swift"):
            code = swift_code_without_comments_and_literals(
                source.read_text(encoding="utf-8")
            )
            model_count += len(re.findall(r"@Model\b", code))
    if model_count != 24:
        raise ValueError(f"Task 5 must preserve exactly 24 @Model declarations; found {model_count}")


def verify_reports_architecture(root: Path) -> None:
    required_sources = (
        "DateRange/ReportDateRange.swift",
        "Domain/ReportsDashboardSource.swift",
        "Repository/ReportsRepository.swift",
        "Presentation/ReportsDashboardViewModel.swift",
    )
    reports_root = root / "Packages/HealthTrackingModules/Sources/ReportsKit"
    missing = [relative for relative in required_sources if not (reports_root / relative).is_file()]
    if missing:
        raise ValueError(f"ReportsKit Task 1 production contracts are missing: {missing}")

    package_path = root / "Packages/HealthTrackingModules/Package.swift"
    if not package_path.is_file():
        raise ValueError("ReportsKit package manifest is missing")
    package = package_path.read_text(encoding="utf-8")
    if target_dependencies(package, "ReportsKit") != ["DesignSystem", "GuidanceKit"]:
        raise ValueError("ReportsKit must depend exactly on DesignSystem and GuidanceKit")
    if "ReportsKit" not in target_dependencies(package, "PersistenceKit"):
        raise ValueError("PersistenceKit must depend on ReportsKit for repository implementation")

    task2_sources = (
        reports_root / "Domain/BodyStrengthReport.swift",
        reports_root / "Builders/BodyStrengthDatasetBuilder.swift",
        root / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift",
    )
    missing_task2 = [str(path.relative_to(root)) for path in task2_sources if not path.is_file()]
    if missing_task2:
        raise ValueError(f"Reports Task 2 production contracts are missing: {missing_task2}")

    report_source = task2_sources[0].read_text(encoding="utf-8")
    report_code = swift_code_without_comments_and_literals(report_source)
    if re.search(r'\bvolumeKg\s*:\s*Double\s*\?', report_code) is None:
        raise ValueError("Report strength volume must represent missing data as optional")

    builder_source = task2_sources[1].read_text(encoding="utf-8")
    builder_code = swift_code_without_comments_and_literals(builder_source)
    epley_calls = re.findall(r'\bEpleyEstimate\s*\.\s*calculate\s*\(', builder_code)
    if len(epley_calls) != 1:
        raise ValueError("Body/strength builder must call canonical GuidanceKit Epley exactly once")
    if re.search(r'/\s*30(?:\.0*)?\b', builder_code):
        raise ValueError("Body/strength builder must not contain a local Epley formula")
    duplicate_check = re.search(r'\brejectLogicalDuplicateSets\s*\(', builder_code)
    warmup_exclusion = re.search(r'!\s*\$0\s*\.\s*isWarmup\b', builder_code)
    if (
        duplicate_check is None
        or warmup_exclusion is None
        or duplicate_check.start() > warmup_exclusion.start()
    ):
        raise ValueError("Body/strength builder must reject duplicates before warmup exclusion")

    nil_to_zero = re.compile(r'\?\?\s*0(?:\.0*)?\b')
    for source in task2_sources[1:]:
        code = swift_code_without_comments_and_literals(source.read_text(encoding="utf-8"))
        if nil_to_zero.search(code):
            raise ValueError(
                f"Reports Task 2 must not coerce missing values to zero: {source.relative_to(root)}"
            )

    repository_code = swift_code_without_comments_and_literals(
        task2_sources[2].read_text(encoding="utf-8")
    )
    if swift_model_context_mutates(task2_sources[2].read_text(encoding="utf-8")):
        raise ValueError("SwiftDataReportsRepository must remain read-only")

    task3_sources = (
        reports_root / "Domain/ProteinAdherenceReport.swift",
        reports_root / "Builders/ProteinAdherenceBuilder.swift",
    )
    missing_task3 = [str(path.relative_to(root)) for path in task3_sources if not path.is_file()]
    if missing_task3:
        raise ValueError(f"Reports Task 3 production contracts are missing: {missing_task3}")

    protein_report_code = swift_code_without_comments_and_literals(
        task3_sources[0].read_text(encoding="utf-8")
    )
    if (
        re.search(r'\bcase\s+currentProfileAppliedToObservedDays\b', protein_report_code) is None
        or re.search(r'\badherencePercent\s*:\s*Double\s*\?', protein_report_code) is None
    ):
        raise ValueError("Protein report must preserve optional adherence and exact current-profile provenance")

    protein_builder_code = swift_code_without_comments_and_literals(
        task3_sources[1].read_text(encoding="utf-8")
    )
    observed_filter = re.search(
        r'\blet\s+observedDays\s*=\s*days\s*\.\s*filter\s*\{[^}]*'
        r'entryCount\s*>\s*0[^}]*\}',
        protein_builder_code,
    )
    target_filter = re.search(
        r'\blet\s+targetDays\s*=\s*observedDays\s*\.\s*filter\s*\{',
        protein_builder_code,
    )
    valid_target = re.search(
        r'\bproteinTargetG\s*\.\s*map\s*\{\s*\$0\s*\.\s*isFinite\s*'
        r'&&\s*\$0\s*>\s*0(?:\.0*)?\s*\}\s*==\s*true\b',
        protein_builder_code,
    )
    hit_comparison = re.search(
        r'\bproteinTotalG\s*>=\s*target\b',
        protein_builder_code,
    )
    target_denominator = re.search(
        r'Double\s*\(\s*hitDays\s*\.\s*count\s*\)\s*/\s*'
        r'Double\s*\(\s*targetDays\s*\.\s*count\s*\)',
        protein_builder_code,
    )
    scaled_percentage = re.search(
        r'Double\s*\(\s*hitDays\s*\.\s*count\s*\)\s*/\s*'
        r'Double\s*\(\s*targetDays\s*\.\s*count\s*\)\s*\*\s*100(?:\.0*)?\b',
        protein_builder_code,
    )
    if observed_filter is None or target_filter is None:
        raise ValueError("Protein adherence denominator must use actual observed entry days with valid targets")
    if valid_target is None:
        raise ValueError("Protein adherence target must be finite and greater than zero")
    if hit_comparison is None:
        raise ValueError("Protein adherence protein hit must include equality")
    if target_denominator is None:
        raise ValueError("Protein adherence denominator must use actual observed entry days")
    if scaled_percentage is None:
        raise ValueError("Protein adherence percentage scale must multiply by 100")

    task3_tests = (
        root
        / "Packages/HealthTrackingModules/Tests/ReportsKitTests/ProteinAdherenceBuilderTests.swift",
        root
        / "Packages/HealthTrackingModules/Tests/PersistenceKitTests/ReportsRepositoryTests.swift",
    )
    missing_task3_tests = [
        str(path.relative_to(root)) for path in task3_tests if not path.is_file()
    ]
    if missing_task3_tests:
        raise ValueError(f"Task 3 test contracts are missing: {missing_task3_tests}")
    verify_meaningful_task3_tests(
        task3_tests[0],
        "ProteinAdherenceBuilderTests",
        False,
        TASK3_BUILDER_TEST_BEHAVIORS,
    )
    verify_meaningful_task3_tests(
        task3_tests[1],
        "ReportsRepositoryTests",
        True,
        TASK3_REPOSITORY_TEST_BEHAVIORS,
    )

    if re.search(r'\bCalendar\s*\.\s*current\b', repository_code):
        raise ValueError("SwiftDataReportsRepository must use its injected calendar")
    if (
        re.search(r'\bcalendar\s*:\s*Calendar\b', repository_code) is None
        or re.search(r'\bguard\s*!\s*entries\s*\.\s*isEmpty\s*else\s*\{\s*continue\s*\}', repository_code) is None
    ):
        raise ValueError("Nutrition projection must inject Calendar and skip empty nutrition logs")

    for source in (task3_sources[1], task2_sources[2]):
        code = swift_code_without_comments_and_literals(source.read_text(encoding="utf-8"))
        if nil_to_zero.search(code):
            raise ValueError(
                f"Reports Task 3 must not coerce missing protein targets to zero: {source.relative_to(root)}"
            )

    task4_sources = (
        reports_root / "Domain/LifestylePhaseReport.swift",
        reports_root / "Builders/LifestylePhaseDatasetBuilder.swift",
        root / "Packages/HealthTrackingModules/Sources/CoreModels/Values/PhaseTransitionLedger.swift",
        root / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataTrainingRepository.swift",
        root / "Packages/HealthTrackingModules/Sources/TrainingKit/Phase/PhaseTransitionViewModel.swift",
    )
    missing_task4 = [str(path.relative_to(root)) for path in task4_sources if not path.is_file()]
    if missing_task4:
        raise ValueError(f"Reports Task 4 production contracts are missing: {missing_task4}")
    task4_tests = (
        root / "Packages/HealthTrackingModules/Tests/CoreModelsTests/PhaseTransitionLedgerTests.swift",
        root / "Packages/HealthTrackingModules/Tests/ReportsKitTests/LifestylePhaseDatasetBuilderTests.swift",
        root / "Packages/HealthTrackingModules/Tests/PersistenceKitTests/PhaseTransitionLedgerRepositoryTests.swift",
        root / "Packages/HealthTrackingModules/Tests/TrainingKitTests/FoundationProgramViewModelTests.swift",
    )
    missing_task4_tests = [str(path.relative_to(root)) for path in task4_tests if not path.is_file()]
    if missing_task4_tests:
        raise ValueError(f"Task 4 test contracts are missing: {missing_task4_tests}")
    verify_meaningful_task4_tests(
        task4_tests[0],
        "PhaseTransitionLedgerTests",
        False,
        TASK4_LEDGER_TEST_BEHAVIORS,
    )
    verify_meaningful_task4_tests(
        task4_tests[1],
        "LifestylePhaseDatasetBuilderTests",
        False,
        TASK4_LIFESTYLE_TEST_BEHAVIORS,
    )
    verify_meaningful_task4_tests(
        task4_tests[2],
        "PhaseTransitionLedgerRepositoryTests",
        True,
        TASK4_PERSISTENCE_TEST_BEHAVIORS,
    )
    verify_meaningful_task4_tests(
        task4_tests[3],
        "PhaseTransitionViewModelTests",
        True,
        TASK4_TRAINING_VIEW_MODEL_TEST_BEHAVIORS,
    )

    ledger_code = swift_code_without_comments_and_literals(task4_sources[2].read_text(encoding="utf-8"))
    if re.search(r'@Model\b', ledger_code):
        raise ValueError("Phase transition ledger must remain a Codable CoreModels value, not a model")
    if (
        "phase-transition-ledger.v1." not in task4_sources[2].read_text(encoding="utf-8")
        or re.search(r'\bcurrentSchemaVersion\s*=\s*1\b', ledger_code) is None
    ):
        raise ValueError("Phase transition ledger must retain its exact V1 key and schema version")
    ledger_compact = compact_swift_tokens(ledger_code)
    ledger_checks = (
        "throwPhaseTransitionLedgerError.duplicateRecordID",
        "throwPhaseTransitionLedgerError.duplicateLogicalTransition",
        "throwPhaseTransitionLedgerError.duplicateTransitionTimestamp",
        "throwPhaseTransitionLedgerError.brokenTransitionChain",
    )
    ledger_positions = [ledger_compact.find(fragment) for fragment in ledger_checks]
    if any(position < 0 for position in ledger_positions) or ledger_positions != sorted(ledger_positions):
        raise ValueError("Phase transition ledger must enforce duplicate ID, logical, timestamp, then chain precedence")
    logical_key_start = ledger_compact.find("privatestaticfunclogicalKeyOrderedBefore")
    logical_key_order = (
        "iflhs.programID!=rhs.programID{returnuuidOrderedBefore(lhs.programID,rhs.programID)}",
        "iflhs.transitionedAt!=rhs.transitionedAt{returnlhs.transitionedAt<rhs.transitionedAt}",
        "iflhs.fromStartedAt!=rhs.fromStartedAt{returnlhs.fromStartedAt<rhs.fromStartedAt}",
        "iflhs.fromPhaseID!=rhs.fromPhaseID{returnuuidOrderedBefore(lhs.fromPhaseID,rhs.fromPhaseID)}",
        "returnuuidOrderedBefore(lhs.toPhaseID,rhs.toPhaseID)",
    )
    logical_key_positions = [
        ledger_compact.find(fragment, logical_key_start) for fragment in logical_key_order
    ]
    if (
        logical_key_start < 0
        or any(position < 0 for position in logical_key_positions)
        or logical_key_positions != sorted(logical_key_positions)
    ):
        raise ValueError(
            "Phase transition ledger logical-key ordering must compare every field with program ID first"
        )
    if "fromStartedAt>=$0.transitionedAt" not in ledger_compact:
        raise ValueError("Phase transition ledger must reject zero-duration records")

    lifestyle_domain_code = swift_code_without_comments_and_literals(
        task4_sources[0].read_text(encoding="utf-8")
    )
    if (
        re.search(r'\bcase\s+partialCurrentState\b', lifestyle_domain_code) is None
        or re.search(r'\bcase\s+actualTransitions\b', lifestyle_domain_code) is None
        or re.search(r'\bsymptomScore\s*:\s*Int\s*\?', lifestyle_domain_code) is None
        or re.search(r'\bscore\s*:\s*Int\s*\?', lifestyle_domain_code) is None
    ):
        raise ValueError("Lifestyle and phase report must preserve optional zeros and exact provenance")

    training_code = swift_code_without_comments_and_literals(
        task4_sources[3].read_text(encoding="utf-8")
    )
    training_compact = compact_swift_tokens(training_code)
    training_order = (
        "guardstate.currentPhaseId!=phaseIDelse{returnstate}",
        "guard!modelContext.hasChangeselse",
        "guarddate.timeIntervalSinceReferenceDate.isFinite,date>state.phaseStartedAtelse",
        "letrecordID=phaseTransitionRecordID()",
    )
    training_positions = [training_compact.find(fragment) for fragment in training_order]
    if any(position < 0 for position in training_positions) or training_positions != sorted(training_positions):
        raise ValueError("Training phase mutation must no-op before pending checks and enforce strict time before IDs")
    for fragment in (
        "letoriginalPhaseID=state.currentPhaseId",
        "letoriginalPhaseStartedAt=state.phaseStartedAt",
        "letoriginalStateUpdatedAt=state.updatedAt",
        "originalSetting=(existing,existing.value,existing.updatedAt)",
        "setting.value=tryledger.encoded(for:programID)",
        "state.currentPhaseId=phaseID",
        "state.phaseStartedAt=date",
        "trysaveOperation()",
        "state.currentPhaseId=originalPhaseID",
        "originalSetting.model.value=originalSetting.value",
        "rollbackOperation()",
    ):
        if fragment not in training_compact:
            raise ValueError("Training phase mutation must retain one-save exact snapshot restoration and rollback")

    lifestyle_builder_code = swift_code_without_comments_and_literals(
        task4_sources[1].read_text(encoding="utf-8")
    )
    lifestyle_builder_compact = compact_swift_tokens(lifestyle_builder_code)
    builder_checks = (
        "throwLifestylePhaseDatasetError.duplicateTransitionID",
        "throwLifestylePhaseDatasetError.duplicateLogicalTransition",
        "throwLifestylePhaseDatasetError.duplicateTransitionTimestamp",
        "throwLifestylePhaseDatasetError.brokenTransitionChain",
    )
    builder_positions = [lifestyle_builder_compact.find(fragment) for fragment in builder_checks]
    if any(position < 0 for position in builder_positions) or builder_positions != sorted(builder_positions):
        raise ValueError("Lifestyle builder must enforce duplicate ID, logical, timestamp, then chain precedence")
    for fragment in (
        "calendar.date(byAdding:.day,value:1,to:previous.localDay)",
        "record.score.map",
        "record.symptomScore.map",
        ".partialCurrentState",
        ".actualTransitions",
    ):
        if fragment not in lifestyle_builder_compact:
            raise ValueError("Lifestyle builder must retain gap, explicit-zero, partial, and actual provenance behavior")
    if "monthStart" in lifestyle_builder_code or "monthEnd" in lifestyle_builder_code:
        raise ValueError("Lifestyle builder must never infer phase history from month metadata")

    reports_repository_compact = compact_swift_tokens(
        swift_code_without_comments_and_literals(task2_sources[2].read_text(encoding="utf-8"))
    )
    ledger_decode = reports_repository_compact.find("PhaseTransitionLedgerV1.decode")
    absent_state = reports_repository_compact.find("guardletstate=states.firstelse")
    if ledger_decode < 0 or absent_state < 0 or ledger_decode >= absent_state:
        raise ValueError("Reports repository must decode selected ledger before deciding state is unavailable")
    for fragment in (
        "guardledger==nilelse",
        "phaseTransitionStateMismatch(programID:program.id)",
    ):
        if fragment not in reports_repository_compact:
            raise ValueError("Reports repository must reject any ledger setting when ProgramState is absent")

    phase_view_model_compact = compact_swift_tokens(
        swift_code_without_comments_and_literals(task4_sources[4].read_text(encoding="utf-8"))
    )
    view_model_order = (
        "guardpreviousPhaseID!=phaseIDelse{return}",
        "repository.setActiveProgramPhase",
        "guardupdatedState.currentPhaseId!=previousPhaseIDelse{return}",
        "haptics?.handle(.phaseTransition",
    )
    view_model_positions = [phase_view_model_compact.find(fragment) for fragment in view_model_order]
    if any(position < 0 for position in view_model_positions) or view_model_positions != sorted(view_model_positions):
        raise ValueError("PhaseTransitionViewModel must suppress same-phase publication and transition haptics")

    forbidden_imports = {"CloudKit", "PersistenceKit", "PhotosUI", "SwiftData"}
    for source in reports_root.rglob("*.swift"):
        text = source.read_text(encoding="utf-8")
        code = swift_code_without_comments_and_literals(text)
        imports = swift_imported_modules(text)
        forbidden = sorted(imports & forbidden_imports)
        if forbidden:
            raise ValueError(
                f"ReportsKit must remain persistence/photo independent; "
                f"{source.relative_to(root)} imports {forbidden}"
            )
        if re.search(r'\bModelContext\b', code):
            raise ValueError(f"ReportsKit must not reference ModelContext: {source.relative_to(root)}")
        if re.search(r'\bCalendar\s*\.\s*current\b', code):
            raise ValueError(f"ReportsKit must use injected calendars: {source.relative_to(root)}")
        if re.search(r'\b(?:86_400|86400)\b', code):
            raise ValueError(f"ReportsKit must not use fixed-day second arithmetic: {source.relative_to(root)}")


def expect_architecture_failure(root: Path, expected: str) -> None:
    try:
        verify_reports_architecture(root)
    except ValueError as error:
        if expected not in str(error):
            raise SystemExit(
                f"ReportsKit architecture mutation failed for the wrong reason; expected {expected!r}: {error}"
            ) from error
    else:
        raise SystemExit(f"ReportsKit architecture mutation escaped: {expected}")


def reports_architecture_self_test(source_root: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="m4-reports-architecture-verifier-") as directory:
        fixture = Path(directory)
        source_package = source_root / "Packages/HealthTrackingModules/Package.swift"
        package = fixture / "Packages/HealthTrackingModules/Package.swift"
        package.parent.mkdir(parents=True)
        shutil.copyfile(source_package, package)
        reports_root = fixture / "Packages/HealthTrackingModules/Sources/ReportsKit"
        for relative in (
            "DateRange/ReportDateRange.swift",
            "Domain/ReportsDashboardSource.swift",
            "Repository/ReportsRepository.swift",
            "Presentation/ReportsDashboardViewModel.swift",
            "Domain/BodyStrengthReport.swift",
            "Builders/BodyStrengthDatasetBuilder.swift",
            "Domain/ProteinAdherenceReport.swift",
            "Builders/ProteinAdherenceBuilder.swift",
            "Domain/LifestylePhaseReport.swift",
            "Builders/LifestylePhaseDatasetBuilder.swift",
        ):
            path = reports_root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            contents = "import Foundation\n"
            if relative == "Domain/BodyStrengthReport.swift":
                contents += "struct Point { let volumeKg: Double? }\n"
            if relative == "Builders/BodyStrengthDatasetBuilder.swift":
                contents += (
                    "try rejectLogicalDuplicateSets(relevant)\n"
                    "let eligible = relevant.filter { !$0.isWarmup }\n"
                    "let estimate = EpleyEstimate.calculate(weightKg: weight, reps: reps)\n"
                )
            if relative == "Domain/ProteinAdherenceReport.swift":
                contents += (
                    "enum ProteinTargetProvenance { case currentProfileAppliedToObservedDays }\n"
                    "struct ProteinAdherenceReport { let adherencePercent: Double? }\n"
                )
            if relative == "Builders/ProteinAdherenceBuilder.swift":
                contents += (
                    "let observedDays = days.filter { $0.entryCount > 0 }\n"
                    "let targetDays = observedDays.filter { "
                    "$0.proteinTargetG.map { $0.isFinite && $0 > 0 } == true }\n"
                    "let hitDays = targetDays.filter { day in "
                    "let target = day.proteinTargetG!; return day.proteinTotalG >= target }\n"
                    "let adherencePercent = targetDays.isEmpty ? nil : "
                    "Double(hitDays.count) / Double(targetDays.count) * 100\n"
                )
            if relative == "Domain/LifestylePhaseReport.swift":
                contents += (
                    "enum PhaseTimelineProvenance {\n"
                    "case partialCurrentState\n"
                    "case actualTransitions\n"
                    "}\n"
                    "struct Mood { let score: Int? }\n"
                    "struct Posture { let symptomScore: Int? }\n"
                )
            path.write_text(contents, encoding="utf-8")

        for relative in (
            "Domain/LifestylePhaseReport.swift",
            "Builders/LifestylePhaseDatasetBuilder.swift",
        ):
            shutil.copyfile(
                source_root / "Packages/HealthTrackingModules/Sources/ReportsKit" / relative,
                reports_root / relative,
            )

        task3_repository_contents = (
            "import Foundation\n"
            "struct RepositoryFixture {\n"
            "let calendar: Calendar\n"
            "init(calendar: Calendar) { self.calendar = calendar }\n"
            "func project() { for entries in allEntries { "
            "guard !entries.isEmpty else { continue } } }\n"
            "func phaseProjection() { "
            "let ledger = PhaseTransitionLedgerV1.decode(value, for: program.id); "
            "guard let state = states.first else { "
            "guard ledger == nil else { throw ReportsRepositoryIntegrityError."
            "phaseTransitionStateMismatch(programID: program.id) }; return } }\n"
            "}\n"
        )
        task2_repository = (
            fixture
            / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift"
        )
        task2_repository.parent.mkdir(parents=True, exist_ok=True)
        task2_repository.write_text(task3_repository_contents, encoding="utf-8")

        ledger = fixture / "Packages/HealthTrackingModules/Sources/CoreModels/Values/PhaseTransitionLedger.swift"
        ledger.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(
            source_root / "Packages/HealthTrackingModules/Sources/CoreModels/Values/PhaseTransitionLedger.swift",
            ledger,
        )
        training = fixture / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataTrainingRepository.swift"
        shutil.copyfile(
            source_root / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataTrainingRepository.swift",
            training,
        )
        phase_view_model = fixture / "Packages/HealthTrackingModules/Sources/TrainingKit/Phase/PhaseTransitionViewModel.swift"
        phase_view_model.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(
            source_root / "Packages/HealthTrackingModules/Sources/TrainingKit/Phase/PhaseTransitionViewModel.swift",
            phase_view_model,
        )

        for relative in (
            "Tests/ReportsKitTests/ProteinAdherenceBuilderTests.swift",
            "Tests/PersistenceKitTests/ReportsRepositoryTests.swift",
            "Tests/CoreModelsTests/PhaseTransitionLedgerTests.swift",
            "Tests/ReportsKitTests/LifestylePhaseDatasetBuilderTests.swift",
            "Tests/PersistenceKitTests/PhaseTransitionLedgerRepositoryTests.swift",
            "Tests/TrainingKitTests/FoundationProgramViewModelTests.swift",
        ):
            source = source_root / "Packages/HealthTrackingModules" / relative
            destination = fixture / "Packages/HealthTrackingModules" / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)

        verify_reports_architecture(fixture)

        mutation_source = reports_root / "DateRange/ReportDateRange.swift"
        scoped_symbols = {
            "SwiftData": "ModelContext",
            "CloudKit": "CKContainer",
            "PhotosUI": "PHPickerConfiguration",
            "PersistenceKit": "SwiftDataReportsRepository",
        }

        original = mutation_source.read_text(encoding="utf-8")
        mutation_source.write_text(
            original
            + r'''
let bareRegexImportDecoy = /import CloudKit/
let bareRegexSemicolonImportDecoy = /foo; import PhotosUI/
let extendedRegexImportDecoy = #/import SwiftData/#
let extendedRegexSemicolonImportDecoy = ##/foo; import PersistenceKit/##
let multilineExtendedRegexImportDecoy = #/
foo
import SwiftData
/#
let multilineImportTokensRegexDecoy = #/
import
`SwiftData`
import struct
`PhotosUI`.PHPickerConfiguration
/#
''',
            encoding="utf-8",
        )
        verify_reports_architecture(fixture)
        mutation_source.write_text(original, encoding="utf-8")

        import_mutations = []
        for module, symbol in scoped_symbols.items():
            import_mutations.extend(
                (
                    f"import {module}\n",
                    f"import `{module}`\n",
                    f"import\n{module}\n",
                    f"import\n`{module}`\n",
                    f"import\r\n`{module}`\r\n",
                    f"@preconcurrency import {module}\n",
                    f"@_implementationOnly import {module}\n",
                    f"@_exported import {module}\n",
                    f"import struct {module}.{symbol}\n",
                    f"import struct `{module}`.{symbol}\n",
                    f"import struct\n{module}.{symbol}\n",
                    f"import struct\r\n`{module}`.{symbol}\r\n",
                    f"import /* multiline import comment\ncontinued */ {module}\n",
                    (
                        "import struct /* multiline scope comment\r\n"
                        f"continued */ `{module}`.{symbol}\r\n"
                    ),
                    f"@_spi(Testing) import `{module}`\n",
                    (
                        "@preconcurrency /* attribute boundary */\n"
                        "    import /* import boundary */ class "
                        f"/* scope boundary */ {module}.{symbol} // trailing comment\n"
                    ),
                    (
                        "@_implementationOnly /* attribute boundary */\r\n"
                        "    import /* import boundary */ class "
                        f"/* scope boundary */ `{module}`.{symbol} // trailing comment\r\n"
                    ),
                    f"let precedingDeclaration = 0; import `{module}`\n",
                    f"let quotient = numerator / denominator\nimport `{module}`\n",
                    f"let quotient = numerator / denominator; import struct `{module}`.{symbol}\n",
                )
            )

        for mutation in import_mutations:
            original = mutation_source.read_text(encoding="utf-8")
            mutation_source.write_text(original + mutation, encoding="utf-8")
            expect_architecture_failure(fixture, "persistence/photo independent")
            mutation_source.write_text(original, encoding="utf-8")

        original = mutation_source.read_text(encoding="utf-8")
        mutation_source.write_text(
            original
            + '''
// @preconcurrency import SwiftData
/*
@_implementationOnly import CloudKit
import struct PhotosUI.PHPickerConfiguration
/* nested comment with @_exported import PersistenceKit */
*/
let regularImportDecoy = "@_exported import PersistenceKit"
let multilineImportDecoy = """
import SwiftData
"""
let rawImportDecoy = #"import CloudKit"#
let rawMultilineImportDecoy = #"""
import PhotosUI
"""#
''',
            encoding="utf-8",
        )
        verify_reports_architecture(fixture)
        mutation_source.write_text(original, encoding="utf-8")

        for mutation, expected in (
            ("let context: ModelContext\n", "must not reference ModelContext"),
            ("let calendar = Calendar.current\n", "must use injected calendars"),
            ("let seconds = 86_400\n", "must not use fixed-day second arithmetic"),
        ):
            original = mutation_source.read_text(encoding="utf-8")
            mutation_source.write_text(original + mutation, encoding="utf-8")
            expect_architecture_failure(fixture, expected)
            mutation_source.write_text(original, encoding="utf-8")

        missing_source = reports_root / "Repository/ReportsRepository.swift"
        missing_source.unlink()
        expect_architecture_failure(fixture, "production contracts are missing")
        missing_source.write_text("import Foundation\n", encoding="utf-8")

        task2_builder = reports_root / "Builders/BodyStrengthDatasetBuilder.swift"
        original_builder = task2_builder.read_text(encoding="utf-8")
        task2_builder.unlink()
        expect_architecture_failure(fixture, "Task 2 production contracts are missing")
        task2_builder.write_text(original_builder, encoding="utf-8")

        task2_repository.unlink()
        expect_architecture_failure(fixture, "Task 2 production contracts are missing")
        task2_repository.write_text(task3_repository_contents, encoding="utf-8")

        task2_builder.write_text(
            original_builder.replace("EpleyEstimate.calculate", "LocalEstimate.calculate"),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "must call canonical GuidanceKit Epley exactly once")
        task2_builder.write_text(original_builder, encoding="utf-8")

        task2_builder.write_text(
            original_builder.replace(
                "try rejectLogicalDuplicateSets(relevant)\n"
                "let eligible = relevant.filter { !$0.isWarmup }",
                "let eligible = relevant.filter { !$0.isWarmup }\n"
                "try rejectLogicalDuplicateSets(eligible)",
            ),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "must reject duplicates before warmup exclusion")
        task2_builder.write_text(original_builder, encoding="utf-8")

        task2_builder.write_text(
            original_builder
            + "let unused = EpleyEstimate.calculate(weightKg: weight, reps: reps)\n",
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "must call canonical GuidanceKit Epley exactly once")
        task2_builder.write_text(original_builder, encoding="utf-8")

        task2_builder.write_text(
            original_builder + "let local = weight * (1 + Double(reps) / 30)\n",
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "must not contain a local Epley formula")
        task2_builder.write_text(original_builder, encoding="utf-8")

        task2_report = reports_root / "Domain/BodyStrengthReport.swift"
        original_report = task2_report.read_text(encoding="utf-8")
        task2_report.write_text(original_report.replace("Double?", "Double"), encoding="utf-8")
        expect_architecture_failure(fixture, "must represent missing data as optional")
        task2_report.write_text(original_report, encoding="utf-8")

        for source in (task2_builder, task2_repository):
            original = source.read_text(encoding="utf-8")
            source.write_text(original + "let coerced = missing ?? 0\n", encoding="utf-8")
            expect_architecture_failure(fixture, "must not coerce missing values to zero")
            source.write_text(original, encoding="utf-8")

        task2_repository.write_text(
            task3_repository_contents
            + "func mutate() { let alias = modelContext; try alias.save() }\n",
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "must remain read-only")
        task2_repository.write_text(task3_repository_contents, encoding="utf-8")

        task2_repository.write_text(
            task3_repository_contents
            + "func harmless(_ values: inout Set<UUID>) { values.insert(UUID()) }\n",
            encoding="utf-8",
        )
        verify_reports_architecture(fixture)
        task2_repository.write_text(task3_repository_contents, encoding="utf-8")

        for mutation in (
            "func mutate() { let first = modelContext; let second = first; "
            "second.insert(AppSetting()) }\n",
            "func mutateHelper(_ context: ModelContext) { context.delete(AppSetting()) }\n",
        ):
            task2_repository.write_text(
                task3_repository_contents + mutation,
                encoding="utf-8",
            )
            expect_architecture_failure(fixture, "must remain read-only")
            task2_repository.write_text(task3_repository_contents, encoding="utf-8")

        task3_report = reports_root / "Domain/ProteinAdherenceReport.swift"
        original_task3_report = task3_report.read_text(encoding="utf-8")
        task3_report.unlink()
        expect_architecture_failure(fixture, "Task 3 production contracts are missing")
        task3_report.write_text(original_task3_report, encoding="utf-8")

        task3_builder = reports_root / "Builders/ProteinAdherenceBuilder.swift"
        original_task3_builder = task3_builder.read_text(encoding="utf-8")
        task3_builder.write_text(
            original_task3_builder.replace(
                "Double(hitDays.count) / Double(targetDays.count)",
                "Double(hitDays.count) / Double(calendarDayCount)",
            ),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "denominator must use actual observed entry days")
        task3_builder.write_text(original_task3_builder, encoding="utf-8")

        task2_repository.write_text(
            task3_repository_contents.replace(
                "guard !entries.isEmpty else { continue }",
                "if entries.isEmpty { appendSyntheticZeroDay() }",
            ),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "skip empty nutrition logs")
        task2_repository.write_text(task3_repository_contents, encoding="utf-8")

        task3_builder.write_text(
            original_task3_builder + "let coercedTarget = missingTarget ?? 0\n",
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "must not coerce missing protein targets to zero")
        task3_builder.write_text(original_task3_builder, encoding="utf-8")

        original_package = package.read_text(encoding="utf-8")
        package.write_text(
            original_package.replace(
                'dependencies: ["DesignSystem", "GuidanceKit"]',
                'dependencies: ["DesignSystem"]',
                1,
            ),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "depend exactly on DesignSystem and GuidanceKit")
        package.write_text(original_package, encoding="utf-8")
        package.write_text(
            original_package.replace('"ProgressPhotosKit", "ReportsKit",', '"ProgressPhotosKit",', 1),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "PersistenceKit must depend on ReportsKit")


def replace_named_test_bodies(
    source: str,
    names: set[str],
    replacement: str,
) -> str:
    code = swift_code_without_comments_and_literals(source)
    declaration = re.compile(
        r"\bfunc[ \t\f\v\r\n]+(test[A-Za-z0-9_]*)[ \t\f\v]*"
        r"\([^)]*\)[^{]*\{",
        re.MULTILINE,
    )
    replacements: list[tuple[int, int]] = []
    found: set[str] = set()
    for match in declaration.finditer(code):
        name = match.group(1)
        if name not in names:
            continue
        opening = match.end() - 1
        depth = 1
        cursor = opening + 1
        while cursor < len(code) and depth:
            if code[cursor] == "{":
                depth += 1
            elif code[cursor] == "}":
                depth -= 1
            cursor += 1
        if depth:
            raise SystemExit(f"Task 3 mutation method {name} has an incomplete body")
        replacements.append((opening + 1, cursor - 1))
        found.add(name)
    if found != names:
        raise SystemExit(f"Task 3 mutation methods are missing: {sorted(names - found)}")
    mutated = source
    for start, end in sorted(replacements, reverse=True):
        mutated = mutated[:start] + replacement + mutated[end:]
    return mutated


def wrap_named_test_body(
    source: str,
    name: str,
    prefix: str,
    suffix: str,
) -> str:
    code = swift_code_without_comments_and_literals(source)
    declaration = re.compile(
        rf"\bfunc[ \t\f\v\r\n]+{re.escape(name)}[ \t\f\v]*"
        r"\([^)]*\)[^{]*\{",
        re.MULTILINE,
    )
    matches = list(declaration.finditer(code))
    if len(matches) != 1:
        raise SystemExit(f"Task 5 mutation method must be unique: {name}")
    opening = matches[0].end() - 1
    closing = balanced_brace_end(code, opening, f"Task 5 mutation method {name}")
    return (
        source[: opening + 1]
        + prefix
        + source[opening + 1 : closing]
        + suffix
        + source[closing:]
    )


def task3_real_asset_self_test(source_root: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="m4-task3-real-assets-verifier-") as directory:
        fixture = Path(directory)
        shutil.copytree(
            source_root / "Packages/HealthTrackingModules",
            fixture / "Packages/HealthTrackingModules",
        )
        task4_placeholders = {
            "Sources/ReportsKit/Domain/LifestylePhaseReport.swift": (
                "enum PhaseTimelineProvenance { case partialCurrentState; case actualTransitions }\n"
                "struct Mood { let score: Int? }\nstruct Posture { let symptomScore: Int? }\n"
            ),
            "Sources/ReportsKit/Builders/LifestylePhaseDatasetBuilder.swift": "import Foundation\n",
            "Sources/CoreModels/Values/PhaseTransitionLedger.swift": (
                'let key = "phase-transition-ledger.v1."\n'
                "struct PhaseTransitionLedgerV1 { static let currentSchemaVersion = 1 }\n"
            ),
        }
        for relative, contents in task4_placeholders.items():
            path = fixture / "Packages/HealthTrackingModules" / relative
            if not path.is_file():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(contents, encoding="utf-8")
        training = fixture / "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataTrainingRepository.swift"
        training_text = training.read_text(encoding="utf-8")
        if "guard state.currentPhaseId != phaseID else { return state }" not in training_text:
            training.write_text(
                training_text
                + "\nfunc task4NoOpFixture() { guard state.currentPhaseId != phaseID else { return state } }\n",
                encoding="utf-8",
            )
        verify_reports_architecture(fixture)

        builder_test = (
            fixture
            / "Packages/HealthTrackingModules/Tests/ReportsKitTests/ProteinAdherenceBuilderTests.swift"
        )
        repository_test = (
            fixture
            / "Packages/HealthTrackingModules/Tests/PersistenceKitTests/ReportsRepositoryTests.swift"
        )
        builder = (
            fixture
            / "Packages/HealthTrackingModules/Sources/ReportsKit/Builders/ProteinAdherenceBuilder.swift"
        )

        original_builder_test = builder_test.read_text(encoding="utf-8")
        builder_test_names = set(TASK3_BUILDER_TEST_BEHAVIORS)
        repository_test_names = set(TASK3_REPOSITORY_TEST_BEHAVIORS)
        builder_test.unlink()
        expect_architecture_failure(fixture, "Task 3 test contracts are missing")
        builder_test.write_text(original_builder_test, encoding="utf-8")

        builder_test.write_text("", encoding="utf-8")
        expect_architecture_failure(fixture, "expected concrete XCTestCase suite")
        builder_test.write_text(original_builder_test, encoding="utf-8")

        builder_test.write_text(
            re.sub(r"\bfunc\s+test", "func renamed", original_builder_test),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "meaningful Task 3 tests")
        builder_test.write_text(original_builder_test, encoding="utf-8")

        builder_test.write_text(
            re.sub(r"\bXCTAssert", "disabledAssert", original_builder_test),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "meaningful Task 3 tests")
        builder_test.write_text(original_builder_test, encoding="utf-8")

        builder_test.write_text(
            original_builder_test.replace(
                "final class ProteinAdherenceBuilderTests: XCTestCase",
                "final class ProteinAdherenceBuilderTests",
            ),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "expected concrete XCTestCase suite")
        builder_test.write_text(original_builder_test, encoding="utf-8")

        builder_test.write_text(
            original_builder_test
            + "\nfinal class ProteinAdherenceBuilderTests: XCTestCase {}\n",
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "expected concrete XCTestCase suite")
        builder_test.write_text(original_builder_test, encoding="utf-8")

        builder_test.write_text(
            replace_named_test_bodies(
                original_builder_test,
                builder_test_names,
                "\n        XCTAssertTrue(true)\n    ",
            ),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "behavioral Task 3 test contracts")
        builder_test.write_text(original_builder_test, encoding="utf-8")

        global_builder_decoys = "\n".join(
            f"func {name}() {{ XCTAssertTrue(true) }}"
            for name in sorted(builder_test_names)
        )
        builder_test.write_text(
            re.sub(r"\bfunc\s+test", "func renamed", original_builder_test)
            + "\n"
            + global_builder_decoys
            + "\n",
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "nonzero suite of meaningful Task 3 tests")
        builder_test.write_text(original_builder_test, encoding="utf-8")

        original_repository_test = repository_test.read_text(encoding="utf-8")
        repository_test.unlink()
        expect_architecture_failure(fixture, "Task 3 test contracts are missing")
        repository_test.write_text(original_repository_test, encoding="utf-8")

        repository_test.write_text(
            original_repository_test.replace(
                "final class ReportsRepositoryTests: XCTestCase",
                "final class ReportsRepositoryTests",
            ),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "expected concrete XCTestCase suite")
        repository_test.write_text(original_repository_test, encoding="utf-8")

        repository_test.write_text(
            original_repository_test.replace("@MainActor\n", "", 1),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "expected concrete XCTestCase suite")
        repository_test.write_text(original_repository_test, encoding="utf-8")

        repository_test.write_text(
            original_repository_test
            + "\n@MainActor\nfinal class ReportsRepositoryTests: XCTestCase {}\n",
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "expected concrete XCTestCase suite")
        repository_test.write_text(original_repository_test, encoding="utf-8")

        repository_test.write_text(
            replace_named_test_bodies(
                original_repository_test,
                repository_test_names,
                "\n        XCTAssertTrue(true)\n    ",
            ),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "behavioral Task 3 test contracts")
        repository_test.write_text(original_repository_test, encoding="utf-8")

        global_repository_decoys = "\n".join(
            f"func {name}() {{ XCTAssertTrue(true) }}"
            for name in sorted(repository_test_names)
        )
        repository_test.write_text(
            re.sub(r"\bfunc\s+test", "func renamed", original_repository_test)
            + "\n"
            + global_repository_decoys
            + "\n",
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "nonzero suite of meaningful Task 3 tests")
        repository_test.write_text(original_repository_test, encoding="utf-8")

        behavior_mutations = (
            (
                builder_test,
                "XCTAssertEqual(report.observedDayCount, 1)",
                "XCTAssertEqual(report.observedDayCount, 999)",
            ),
            (
                builder_test,
                "XCTAssertNil(report.adherencePercent)",
                "XCTAssertNotNil(report.adherencePercent)",
            ),
            (builder_test, "200.0 / 3.0", "20.0 / 3.0"),
            (builder_test, ".duplicateObservedDay(", ".removedDuplicateObservedDay("),
            (
                builder_test,
                ".invalidObservedDay(id: lower.id)",
                ".invalidObservedDay(id: higher.id)",
            ),
            (
                builder_test,
                "assertEquatableSendable(ProteinAdherenceReport.self)",
                "assertEquatableSendable(String.self)",
            ),
            (
                repository_test,
                "XCTAssertEqual(first.nutritionDayRecords.map(\\.proteinTotalG), [0, 110, 50])",
                "XCTAssertEqual(first.nutritionDayRecords.map(\\.proteinTotalG), [0, 0, 0])",
            ),
            (
                repository_test,
                "XCTAssertEqual(first, second)",
                "XCTAssertNotEqual(first, second)",
            ),
            (
                repository_test,
                "XCTAssertEqual(try nutritionFieldSnapshot(in: container), before)",
                "XCTAssertNotEqual(try nutritionFieldSnapshot(in: container), before)",
            ),
            (
                repository_test,
                "XCTAssertNil(source.nutritionDayRecords.first?.proteinTargetG)",
                "XCTAssertNotNil(source.nutritionDayRecords.first?.proteinTargetG)",
            ),
            (
                repository_test,
                ".ambiguousUserProfiles(profileIDs: [lowerProfileID, higherProfileID])",
                ".removedAmbiguousProfiles(profileIDs: [lowerProfileID, higherProfileID])",
            ),
            (
                repository_test,
                ".mealEntryMissingNutritionLog(id: orphanID)",
                ".removedMissingNutritionLog(id: orphanID)",
            ),
            (
                repository_test,
                ".duplicateMealEntryIDs(id: sharedEntryID, count: 2)",
                ".duplicateMealEntryIDs(id: sharedEntryID, count: 3)",
            ),
        )
        for path, before, after in behavior_mutations:
            original = replace_once(path, before, after)
            expect_architecture_failure(fixture, "behavioral Task 3 test contracts")
            path.write_text(original, encoding="utf-8")

        original_builder = replace_once(
            builder,
            "$0.isFinite && $0 > 0",
            "$0 != 0",
        )
        expect_architecture_failure(fixture, "finite and greater than zero")
        builder.write_text(original_builder, encoding="utf-8")

        original_builder = replace_once(
            builder,
            "day.proteinTotalG >= target",
            "day.proteinTotalG > target",
        )
        expect_architecture_failure(fixture, "protein hit must include equality")
        builder.write_text(original_builder, encoding="utf-8")

        original_builder = replace_once(
            builder,
            "Double(hitDays.count) / Double(targetDays.count) * 100",
            "Double(hitDays.count) / Double(targetDays.count)",
        )
        expect_architecture_failure(fixture, "percentage scale must multiply by 100")
        builder.write_text(original_builder, encoding="utf-8")


def task4_real_asset_self_test(source_root: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="m4-task4-real-assets-verifier-") as directory:
        fixture = Path(directory)
        shutil.copytree(
            source_root / "Packages/HealthTrackingModules",
            fixture / "Packages/HealthTrackingModules",
        )
        verify_reports_architecture(fixture)

        module = fixture / "Packages/HealthTrackingModules"
        test_specs = (
            (
                module / "Tests/CoreModelsTests/PhaseTransitionLedgerTests.swift",
                "PhaseTransitionLedgerTests",
                False,
                TASK4_LEDGER_TEST_BEHAVIORS,
            ),
            (
                module / "Tests/ReportsKitTests/LifestylePhaseDatasetBuilderTests.swift",
                "LifestylePhaseDatasetBuilderTests",
                False,
                TASK4_LIFESTYLE_TEST_BEHAVIORS,
            ),
            (
                module / "Tests/PersistenceKitTests/PhaseTransitionLedgerRepositoryTests.swift",
                "PhaseTransitionLedgerRepositoryTests",
                True,
                TASK4_PERSISTENCE_TEST_BEHAVIORS,
            ),
            (
                module / "Tests/TrainingKitTests/FoundationProgramViewModelTests.swift",
                "PhaseTransitionViewModelTests",
                True,
                TASK4_TRAINING_VIEW_MODEL_TEST_BEHAVIORS,
            ),
        )
        for path, suite_name, _, behaviors in test_specs:
            original = path.read_text(encoding="utf-8")
            path.unlink()
            expect_architecture_failure(fixture, "Task 4 test contracts are missing")
            path.write_text(original, encoding="utf-8")

            path.write_text("", encoding="utf-8")
            expect_architecture_failure(fixture, "expected concrete XCTestCase suite")
            path.write_text(original, encoding="utf-8")

            path.write_text(
                original.replace(
                    f"final class {suite_name}: XCTestCase",
                    f"final class {suite_name}",
                    1,
                ),
                encoding="utf-8",
            )
            expect_architecture_failure(fixture, "expected concrete XCTestCase suite")
            path.write_text(original, encoding="utf-8")

            renamed = original
            for name in behaviors:
                renamed = renamed.replace(f"func {name}", f"func renamed{name}", 1)
            path.write_text(renamed, encoding="utf-8")
            expect_architecture_failure(fixture, "nonzero suite of meaningful Task 4 tests")
            path.write_text(original, encoding="utf-8")

            path.write_text(
                replace_named_test_bodies(
                    original,
                    set(behaviors),
                    "\n        XCTAssertTrue(true)\n    ",
                ),
                encoding="utf-8",
            )
            expect_architecture_failure(fixture, "behavioral Task 4 test contracts")
            path.write_text(original, encoding="utf-8")

        ledger = module / "Sources/CoreModels/Values/PhaseTransitionLedger.swift"
        builder = module / "Sources/ReportsKit/Builders/LifestylePhaseDatasetBuilder.swift"
        training = module / "Sources/PersistenceKit/Repositories/SwiftDataTrainingRepository.swift"
        repository = module / "Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift"
        view_model = module / "Sources/TrainingKit/Phase/PhaseTransitionViewModel.swift"
        for path, expected in (
            (ledger, "Reports Task 4 production contracts are missing"),
            (builder, "Reports Task 4 production contracts are missing"),
            (training, "Reports Task 4 production contracts are missing"),
            (view_model, "Reports Task 4 production contracts are missing"),
            (repository, "Reports Task 2 production contracts are missing"),
        ):
            original = path.read_text(encoding="utf-8")
            path.unlink()
            expect_architecture_failure(fixture, expected)
            path.write_text(original, encoding="utf-8")

        for before, after in (
            (
                "throw PhaseTransitionLedgerError.duplicateRecordID(duplicate.key)",
                "throw PhaseTransitionLedgerError.invalidRecord(id: duplicate.key)",
            ),
            (
                "throw PhaseTransitionLedgerError.duplicateLogicalTransition(",
                "throw PhaseTransitionLedgerError.removedDuplicateLogicalTransition(",
            ),
            (
                "throw PhaseTransitionLedgerError.duplicateTransitionTimestamp(",
                "throw PhaseTransitionLedgerError.removedDuplicateTransitionTimestamp(",
            ),
            (
                "throw PhaseTransitionLedgerError.brokenTransitionChain(",
                "throw PhaseTransitionLedgerError.removedBrokenTransitionChain(",
            ),
            ("$0.fromStartedAt >= $0.transitionedAt", "$0.fromStartedAt > $0.transitionedAt"),
        ):
            original = replace_once(ledger, before, after)
            expected = (
                "reject zero-duration records"
                if "fromStartedAt" in before
                else "duplicate ID, logical, timestamp, then chain precedence"
            )
            expect_architecture_failure(fixture, expected)
            ledger.write_text(original, encoding="utf-8")

        program_comparator = (
            "        if lhs.programID != rhs.programID {\n"
            "            return uuidOrderedBefore(lhs.programID, rhs.programID)\n"
            "        }\n"
        )
        for replacement in (
            "",
            (
                "        if lhs.programID != rhs.programID {\n"
                "            return uuidOrderedBefore(rhs.programID, lhs.programID)\n"
                "        }\n"
            ),
        ):
            original = replace_once(ledger, program_comparator, replacement)
            expect_architecture_failure(
                fixture,
                "logical-key ordering must compare every field with program ID first",
            )
            ledger.write_text(original, encoding="utf-8")

        for before, after, expected in (
            (
                "throw LifestylePhaseDatasetError.duplicateTransitionID(id: duplicate.key)",
                "throw LifestylePhaseDatasetError.invalidTransition(id: duplicate.key)",
                "duplicate ID, logical, timestamp, then chain precedence",
            ),
            (
                "throw LifestylePhaseDatasetError.duplicateLogicalTransition(",
                "throw LifestylePhaseDatasetError.removedDuplicateLogicalTransition(",
                "duplicate ID, logical, timestamp, then chain precedence",
            ),
            (
                "throw LifestylePhaseDatasetError.duplicateTransitionTimestamp(",
                "throw LifestylePhaseDatasetError.removedDuplicateTransitionTimestamp(",
                "duplicate ID, logical, timestamp, then chain precedence",
            ),
            (
                "throw LifestylePhaseDatasetError.brokenTransitionChain(",
                "throw LifestylePhaseDatasetError.removedBrokenTransitionChain(",
                "duplicate ID, logical, timestamp, then chain precedence",
            ),
            (
                "calendar.date(byAdding: .day, value: 1, to: previous.localDay)",
                "nil",
                "gap, explicit-zero, partial, and actual provenance behavior",
            ),
            (
                "record.score.map {",
                "record.score.flatMap {",
                "gap, explicit-zero, partial, and actual provenance behavior",
            ),
            (
                "record.symptomScore.map {",
                "record.symptomScore.flatMap {",
                "gap, explicit-zero, partial, and actual provenance behavior",
            ),
            (
                ".partialCurrentState",
                ".unavailable",
                "gap, explicit-zero, partial, and actual provenance behavior",
            ),
            (
                ".actualTransitions",
                ".unavailable",
                "gap, explicit-zero, partial, and actual provenance behavior",
            ),
        ):
            original = replace_once(builder, before, after)
            expect_architecture_failure(fixture, expected)
            builder.write_text(original, encoding="utf-8")
        original_builder = builder.read_text(encoding="utf-8")
        builder.write_text(original_builder + "\nlet inferred = phase.monthStart + phase.monthEnd\n", encoding="utf-8")
        expect_architecture_failure(fixture, "never infer phase history from month metadata")
        builder.write_text(original_builder, encoding="utf-8")

        original = replace_once(
            training,
            "        guard state.currentPhaseId != phaseID else { return state }\n",
            "",
        )
        expect_architecture_failure(fixture, "no-op before pending checks and enforce strict time before IDs")
        training.write_text(original, encoding="utf-8")

        same_phase = "        guard state.currentPhaseId != phaseID else { return state }\n"
        pending = (
            "        guard !modelContext.hasChanges else {\n"
            "            throw TrainingRepositoryOperationError.pendingContextChanges\n"
            "        }\n"
        )
        original = training.read_text(encoding="utf-8")
        if same_phase + pending not in original:
            raise SystemExit("Task 4 verifier mutation source is missing same-phase/pending order")
        training.write_text(original.replace(same_phase + pending, pending + same_phase, 1), encoding="utf-8")
        expect_architecture_failure(fixture, "no-op before pending checks and enforce strict time before IDs")
        training.write_text(original, encoding="utf-8")

        for before, after, expected in (
            (
                "date > state.phaseStartedAt",
                "date >= state.phaseStartedAt",
                "no-op before pending checks and enforce strict time before IDs",
            ),
            (
                "let originalPhaseID = state.currentPhaseId",
                "let removedOriginalPhaseID = state.currentPhaseId",
                "one-save exact snapshot restoration and rollback",
            ),
            (
                "try saveOperation()",
                "_ = saveOperation",
                "one-save exact snapshot restoration and rollback",
            ),
            (
                "state.currentPhaseId = originalPhaseID",
                "state.currentPhaseId = phaseID",
                "one-save exact snapshot restoration and rollback",
            ),
            (
                "originalSetting.model.value = originalSetting.value",
                "originalSetting.model.value = setting.value",
                "one-save exact snapshot restoration and rollback",
            ),
            (
                "rollbackOperation()",
                "_ = rollbackOperation",
                "one-save exact snapshot restoration and rollback",
            ),
        ):
            original = replace_once(training, before, after)
            expect_architecture_failure(fixture, expected)
            training.write_text(original, encoding="utf-8")

        key_line = "        let key = PhaseTransitionLedgerV1.key(for: program.id)\n"
        early_return = "        guard let state = states.first else { return (projectedPhases, nil, []) }\n"
        original = replace_once(repository, key_line, early_return + key_line)
        expect_architecture_failure(fixture, "decode selected ledger before deciding state is unavailable")
        repository.write_text(original, encoding="utf-8")

        original = replace_once(
            repository,
            "PhaseTransitionLedgerV1.decode(setting.value, for: program.id)",
            "PhaseTransitionLedgerV1.removedDecode(setting.value, for: program.id)",
        )
        expect_architecture_failure(fixture, "decode selected ledger before deciding state is unavailable")
        repository.write_text(original, encoding="utf-8")

        original_repository = repository.read_text(encoding="utf-8")
        repository.write_text(
            original_repository + "\nfunc mutate() { modelContext.insert(AppSetting()) }\n",
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "must remain read-only")
        repository.write_text(original_repository, encoding="utf-8")

        original = replace_once(
            view_model,
            "        guard previousPhaseID != phaseID else { return }\n",
            "",
        )
        expect_architecture_failure(fixture, "suppress same-phase publication and transition haptics")
        view_model.write_text(original, encoding="utf-8")
        original = view_model.read_text(encoding="utf-8")
        late_guard = "            guard updatedState.currentPhaseId != previousPhaseID else { return }\n"
        haptic = "            haptics?.handle(.phaseTransition(isConfirmed: isConfirmed))\n"
        if late_guard not in original or haptic not in original:
            raise SystemExit("Task 4 verifier mutation source is missing ViewModel no-haptic guard")
        view_model.write_text(
            original.replace(late_guard, "", 1).replace(haptic, haptic + late_guard, 1),
            encoding="utf-8",
        )
        expect_architecture_failure(fixture, "suppress same-phase publication and transition haptics")
        view_model.write_text(original, encoding="utf-8")

        verify_reports_architecture(fixture)


def expect_task5_failure(root: Path, expected: str) -> None:
    try:
        verify_task5_assets(root)
    except ValueError as error:
        if expected not in str(error):
            raise SystemExit(
                f"Task 5 real-asset mutation failed for the wrong reason; "
                f"expected {expected!r}: {error}"
            ) from error
    else:
        raise SystemExit(f"Task 5 real-asset mutation escaped: {expected}")


def task5_real_asset_self_test(source_root: Path) -> None:
    production_sources = (
        source_root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Share/ProgressPhotoComparisonShareDomain.swift",
        source_root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Share/UIKitProgressPhotoComparisonRenderer.swift",
        source_root / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Share/ProgressPhotoComparisonShareCoordinator.swift",
        source_root / "Packages/HealthTrackingModules/Sources/DesignSystem/Platform/SystemActivityView.swift",
    )
    # The test-only RED commit deliberately has no Task-5 production yet. The
    # real verification below still checks the committed tests first and then
    # fails decisively on the missing production contract. Once production is
    # present, this self-test pressure-tests the actual checked-in assets.
    if any(not path.is_file() for path in production_sources):
        return

    with tempfile.TemporaryDirectory(prefix="m4-task5-real-assets-verifier-") as directory:
        fixture = Path(directory)
        for relative in ("Packages", "App", "HealthTrackingAppUITests", "scripts"):
            source = source_root / relative
            if source.exists():
                shutil.copytree(source, fixture / relative)
        verify_task5_assets(fixture)

        share_test = fixture / "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/ProgressPhotoComparisonShareTests.swift"
        gallery_test = fixture / "Packages/HealthTrackingModules/Tests/ProgressPhotosKitTests/ProgressPhotoGalleryViewModelTests.swift"
        ui_test = fixture / "HealthTrackingAppUITests/ProgressPhotoGalleryUITests.swift"
        domain = fixture / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Share/ProgressPhotoComparisonShareDomain.swift"
        renderer = fixture / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Share/UIKitProgressPhotoComparisonRenderer.swift"
        coordinator = fixture / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Share/ProgressPhotoComparisonShareCoordinator.swift"
        view_model = fixture / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoGalleryViewModel.swift"
        gallery = fixture / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Gallery/ProgressPhotoGalleryView.swift"
        activity = fixture / "Packages/HealthTrackingModules/Sources/DesignSystem/Platform/SystemActivityView.swift"
        localization = fixture / "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Resources/Localizable.xcstrings"
        tracker_verifier = fixture / "scripts/verify-trackers.sh"

        original_share_test = share_test.read_text(encoding="utf-8")
        share_test.unlink()
        expect_task5_failure(fixture, "Task 5 test contracts are missing")
        share_test.write_text(original_share_test, encoding="utf-8")

        share_test.write_text("", encoding="utf-8")
        expect_task5_failure(fixture, "expected concrete XCTestCase suite")
        share_test.write_text(original_share_test, encoding="utf-8")

        share_test.write_text(original_share_test + "\n", encoding="utf-8")
        expect_task5_failure(fixture, "Task 5 test asset digest")
        share_test.write_text(original_share_test, encoding="utf-8")

        renamed_tests = original_share_test
        for name in TASK5_SHARE_TEST_BEHAVIORS:
            renamed_tests = renamed_tests.replace(f"func {name}", f"func renamed{name}", 1)
        share_test.write_text(renamed_tests, encoding="utf-8")
        expect_task5_failure(fixture, "nonzero suite of meaningful Task 5 tests")
        share_test.write_text(original_share_test, encoding="utf-8")

        share_test.write_text(
            replace_named_test_bodies(
                original_share_test,
                set(TASK5_SHARE_TEST_BEHAVIORS),
                "\n        XCTAssertTrue(true)\n    ",
            ),
            encoding="utf-8",
        )
        expect_task5_failure(fixture, "independent assertion families")
        share_test.write_text(original_share_test, encoding="utf-8")

        helper_decoys = "\n".join(
            f"func {name}() {{ XCTAssertTrue(true) }}"
            for name in sorted(TASK5_SHARE_TEST_BEHAVIORS)
        )
        share_test.write_text(renamed_tests + "\n" + helper_decoys + "\n", encoding="utf-8")
        expect_task5_failure(fixture, "nonzero suite of meaningful Task 5 tests")
        share_test.write_text(original_share_test, encoding="utf-8")

        share_test.write_text(
            original_share_test
            + "\n@MainActor final class ProgressPhotoComparisonShareTests: XCTestCase {}\n",
            encoding="utf-8",
        )
        expect_task5_failure(fixture, "one expected concrete XCTestCase suite")
        share_test.write_text(original_share_test, encoding="utf-8")

        duplicate_method = (
            "    func testExternalTaskCancellationDuringSuspendedRenderNeverWritesArtifact() "
            "async throws { XCTAssertTrue(true); XCTAssertNil(nil as Int?) }\n\n"
        )
        share_test.write_text(
            original_share_test.replace(
                "    private func readyGalleryFixture() async -> (",
                duplicate_method + "    private func readyGalleryFixture() async -> (",
                1,
            ),
            encoding="utf-8",
        )
        expect_task5_failure(fixture, "must not duplicate test method")
        share_test.write_text(original_share_test, encoding="utf-8")

        for decoy in (
            "// operation.cancel()",
            '_ = "operation.cancel()"',
        ):
            share_test.write_text(
                original_share_test.replace("operation.cancel()", decoy, 1),
                encoding="utf-8",
            )
            expect_task5_failure(fixture, "behavioral Task 5 test contracts")
        share_test.write_text(original_share_test, encoding="utf-8")

        share_test.write_text(
            original_share_test.replace(
                (
                    "    func testExternalTaskCancellationDuringSuspendedRenderNeverWritesArtifact() "
                    "async throws {\n"
                ),
                (
                    "    func testExternalTaskCancellationDuringSuspendedRenderNeverWritesArtifact() "
                    "async throws {\n        return\n"
                ),
                1,
            ),
            encoding="utf-8",
        )
        expect_task5_failure(fixture, "reachable direct behavior")
        share_test.write_text(original_share_test, encoding="utf-8")

        share_test.write_text(
            wrap_named_test_body(
                original_share_test,
                "testExternalTaskCancellationDuringSuspendedRenderNeverWritesArtifact",
                "\n        if false {\n",
                "\n        }\n",
            ),
            encoding="utf-8",
        )
        expect_task5_failure(fixture, "reachable direct behavior")
        share_test.write_text(original_share_test, encoding="utf-8")

        for dead_wrapper_prefix, dead_wrapper_suffix in (
            ("\n        if 1 == 2 {\n", "\n        }\n"),
            ("\n        if Bool(false) {\n", "\n        }\n"),
            ("\n        for _ in 0..<0 {\n", "\n        }\n"),
            ("\n        while 1 == 2 {\n", "\n        }\n"),
            (
                "\n        switch true {\n        case false:\n",
                "\n        default:\n            break\n        }\n",
            ),
            (
                "\n        let decoy = { () async throws -> Void in\n",
                "\n        }\n        _ = decoy\n",
            ),
            (
                "\n        func decoy() async throws {\n",
                "\n        }\n        _ = decoy\n",
            ),
        ):
            share_test.write_text(
                wrap_named_test_body(
                    original_share_test,
                    "testExternalTaskCancellationDuringSuspendedRenderNeverWritesArtifact",
                    dead_wrapper_prefix,
                    dead_wrapper_suffix,
                ),
                encoding="utf-8",
            )
            expect_task5_failure(fixture, "Task 5 test asset digest")
        share_test.write_text(original_share_test, encoding="utf-8")

        for early_exit in (
            "\n        guard false else { return }\n",
            "\n        throw XCTSkip()\n",
            "\n        try XCTSkipIf(true)\n",
            "\n        try XCTSkipUnless(false)\n",
        ):
            share_test.write_text(
                wrap_named_test_body(
                    original_share_test,
                    "testExternalTaskCancellationDuringSuspendedRenderNeverWritesArtifact",
                    early_exit,
                    "",
                ),
                encoding="utf-8",
            )
            expect_task5_failure(fixture, "reachable direct behavior")
        share_test.write_text(original_share_test, encoding="utf-8")

        round5_nested_expression_exits = (
            "\n        if (if true { true } else { false }) { return }\n",
            (
                "\n        if (switch true { case true: true; "
                "case false: false }) { return }\n"
            ),
            "\n        while (if true { true } else { false }) { return }\n",
            (
                "\n        for _ in (if true { [1] } else { [] }) { "
                "return }\n"
            ),
            "\n        if if true { true } else { false } { return }\n",
            (
                "\n        if switch true { case true: true; case false: false } "
                "{ return }\n"
            ),
            (
                "\n        if true && (if true { true } else { false }) { "
                "return }\n"
            ),
            "\n        if Bool(if true { true } else { false }) { return }\n",
            (
                "\n        while switch true { case true: true; "
                "case false: false } { return }\n"
            ),
            (
                "\n        for _ in if true { [1] } else { [] } { "
                "return }\n"
            ),
        )
        escaped_swift_keywords = (
            "if", "else", "guard", "while", "for", "switch", "do",
            "repeat", "catch", "defer", "func", "class", "struct",
            "enum", "actor", "protocol", "extension",
        )
        round5_escaped_identifier_exits = tuple(
            f"\n        let `{keyword}` = true; if `{keyword}` {{ return }}\n"
            for keyword in escaped_swift_keywords
        ) + tuple(
            f"\n        if fixture.`{keyword}` {{ return }}\n"
            for keyword in escaped_swift_keywords
        ) + (
            "\n        if fixture.actor { return }\n",
            (
                "\n        if \\Fixture.`class` == \\Fixture.`class` { "
                "return }\n"
            ),
            (
                "\n        if Bool(\\Fixture.`extension` == "
                "\\Fixture.`extension`) { return }\n"
            ),
        )

        for unconditional_nested_exit in (
            "\n        if true { return }\n",
            "\n        if\n            true\n        {\n            return\n        }\n",
            "\n        if !false { return }\n",
            "\n        do { return }\n",
            "\n        repeat { return } while false\n",
            "\n        if false { } else { return }\n",
            "\n        if !true { } else { return }\n",
            "\n        if ( false ) { } else { return }\n",
            (
                "\n        if\n            (\n                ! true\n            )\n"
                "        {\n        }\n        else\n        {\n            return\n        }\n"
            ),
            "\n        if false { } else if true { return } else { }\n",
            "\n        if false { } else if false { } else { return }\n",
            "\n        if true { if false { } else { return } }\n",
            "\n        do { if false { } else { return } }\n",
            "\n        repeat { if !true { } else { return } } while false\n",
            (
                "\n        do { repeat { if false { } else { return } } "
                "while false }\n"
            ),
            (
                "\n        repeat { do { if !true { } else { return } } } "
                "while false\n"
            ),
            "\n        while true { return }\n",
            "\n        while ( true ) { return }\n",
            "\n        while !false { return }\n",
            "\n        do { while true { return } }\n",
            "\n        for _ in 0..<1 { return }\n",
            "\n        switch true { case true: return; default: break }\n",
            "\n        if 1 == 1 { return }\n",
            (
                "\n        if [true].allSatisfy({ value in return value }) { "
                "return }\n"
            ),
            "\n        if ({ true }()) { return }\n",
            (
                "\n        if [\"ok\": true].allSatisfy({ _, value in return value }) "
                "{ return }\n"
            ),
            (
                "\n        while [true].contains(where: { value in return value }) "
                "{ return }\n"
            ),
        ) + round5_nested_expression_exits + round5_escaped_identifier_exits:
            share_test.write_text(
                wrap_named_test_body(
                    original_share_test,
                    "testExternalTaskCancellationDuringSuspendedRenderNeverWritesArtifact",
                    unconditional_nested_exit,
                    "",
                ),
                encoding="utf-8",
            )
            expect_task5_failure(fixture, "reachable direct behavior")
        share_test.write_text(original_share_test, encoding="utf-8")

        for prohibited_nested_terminal in (
            (
                "\n        let legitimateClosure: (Int) -> Int = { value in\n"
                "            return value\n"
                "        }\n"
                "        _ = legitimateClosure(1)\n"
            ),
            (
                "\n        func legitimateLocal(_ value: Int) -> Int {\n"
                "            return value\n"
                "        }\n"
                "        _ = legitimateLocal(1)\n"
            ),
            (
                "\n        do {\n"
                "            let closure = { return 1 }\n"
                "            func local() -> Int { return closure() }\n"
                "            _ = local()\n"
                "        }\n"
            ),
            (
                "\n        repeat {\n"
                "            let closure = { return 1 }\n"
                "            func local() -> Int { return closure() }\n"
                "            _ = local()\n"
                "        } while false\n"
            ),
            (
                "\n        if true {\n"
                "            let closure = { return 1 }\n"
                "            func local() -> Int { return closure() }\n"
                "            _ = local()\n"
                "        } else { return }\n"
            ),
            "\n        if false { return } else { _ = 1 }\n",
            "\n        while false { return }\n",
            (
                "\n        if [true].allSatisfy({ value in return value }) {\n"
                "            let closure = { return 1 }\n"
                "            _ = closure()\n"
                "        }\n"
            ),
            (
                "\n        if ({ true }()) {\n"
                "            func local() -> Int { return 1 }\n"
                "            _ = local()\n"
                "        }\n"
            ),
        ):
            share_test.write_text(
                wrap_named_test_body(
                    original_share_test,
                    "testExternalTaskCancellationDuringSuspendedRenderNeverWritesArtifact",
                    prohibited_nested_terminal,
                    "",
                ),
                encoding="utf-8",
            )
            expect_task5_failure(fixture, "reachable direct behavior")
        share_test.write_text(original_share_test, encoding="utf-8")

        for legitimate_nested_structure in (
            (
                "\n        let closure: (Int) -> Int = { value in value }\n"
                "        _ = closure(1)\n"
            ),
            (
                "\n        func local(_ value: Int) -> Int { value }\n"
                "        _ = local(1)\n"
            ),
            (
                "\n        struct Local {\n"
                "            func value(_ input: Int) -> Int { input }\n"
                "        }\n"
                "        _ = Local().value(1)\n"
            ),
            (
                "\n        do {\n"
                "            let closure = { 1 }\n"
                "            func local() -> Int { closure() }\n"
                "            _ = local()\n"
                "        }\n"
            ),
            (
                "\n        repeat {\n"
                "            let closure = { 1 }\n"
                "            _ = closure()\n"
                "        } while false\n"
            ),
            (
                "\n        if [true].allSatisfy({ value in value }) {\n"
                "            let closure = { 1 }\n"
                "            _ = closure()\n"
                "        }\n"
            ),
            (
                "\n        let nestedIf = "
                "(if true { true } else { false })\n"
                "        XCTAssertTrue(nestedIf)\n"
            ),
            (
                "\n        let nestedSwitch = switch true {\n"
                "        case true: true\n"
                "        case false: false\n"
                "        }\n"
                "        XCTAssertTrue(nestedSwitch)\n"
            ),
            (
                "\n        let task = Task { 1 }\n"
                "        let sendable: @Sendable () -> Int = { 1 }\n"
                "        _ = (task, sendable())\n"
            ),
            (
                "\n        let `func` = true\n"
                "        let `class` = true\n"
                "        XCTAssertTrue(`func` && `class`)\n"
            ),
            (
                "\n        let `return` = 1\n"
                "        let `throw` = 2\n"
                "        let `XCTSkip` = 3\n"
                "        XCTAssertEqual(`return` + `throw` + `XCTSkip`, 6)\n"
            ),
            (
                "\n        let escapedReturnKeyPath = \\Fixture.`return`\n"
                "        let escapedThrowKeyPath = \\Fixture.`throw`\n"
                "        _ = (escapedReturnKeyPath, escapedThrowKeyPath)\n"
            ),
            (
                "\n        let fixture = (actor: true, `func`: true)\n"
                "        XCTAssertTrue(fixture.actor && fixture.`func`)\n"
            ),
            (
                "\n        _ = \"return throw\"\n"
                "        // return; throw\n"
            ),
        ):
            share_test.write_text(
                wrap_named_test_body(
                    original_share_test,
                    "testExternalTaskCancellationDuringSuspendedRenderNeverWritesArtifact",
                    legitimate_nested_structure,
                    "",
                ),
                encoding="utf-8",
            )
            verify_task5_assets(fixture, enforce_test_asset_digests=False)
        share_test.write_text(original_share_test, encoding="utf-8")

        original_gallery_test = gallery_test.read_text(encoding="utf-8")
        gallery_test.write_text(
            original_gallery_test.replace(
                "first.imageRef: .available(firstFullJPEG)",
                "first.imageRef: .available(Data([11]))",
                1,
            ),
            encoding="utf-8",
        )
        expect_task5_failure(fixture, "behavioral Task 5 test contracts")
        gallery_test.write_text(original_gallery_test, encoding="utf-8")

        original_ui_test = ui_test.read_text(encoding="utf-8")
        ui_test.write_text(
            original_ui_test.replace(
                "func testShareAppearsForTwoReadyPhotosAndPresentsOnlyAfterExplicitTap",
                "func renamedShareTest",
                1,
            ),
            encoding="utf-8",
        )
        expect_task5_failure(fixture, "meaningful Task 5 tests")
        ui_test.write_text(original_ui_test, encoding="utf-8")

        for path in (domain, renderer, coordinator, activity):
            original = path.read_text(encoding="utf-8")
            path.unlink()
            expect_task5_failure(fixture, "Task 5 production contracts are missing")
            path.write_text(original, encoding="utf-8")

            path.write_text("", encoding="utf-8")
            expect_task5_failure(fixture, "Task 5")
            path.write_text(original, encoding="utf-8")

        original = replace_once(
            domain,
            "    public let pose: ProgressPhotoPose\n",
            "    public let pose: ProgressPhotoPose\n    public let note: String?\n",
        )
        expect_task5_failure(fixture, "only imageData, date, and pose")
        domain.write_text(original, encoding="utf-8")

        original = replace_once(
            domain,
            "lhs.imageData.lexicographicallyPrecedes(rhs.imageData)",
            "false",
        )
        expect_task5_failure(fixture, "deterministically order")
        domain.write_text(original, encoding="utf-8")

        original = replace_once(
            view_model,
            """    public var canShareComparison: Bool {
        guard selectedPhotoIDs.count == 2,
              Set(selectedPhotoIDs).count == 2,
              let comparison,
              case let .available(beforeData) = comparison.before.assetState,
              case let .available(afterData) = comparison.after.assetState else {
            return false
        }
        return !beforeData.isEmpty && !afterData.isEmpty
    }
""",
            """    public var canShareComparison: Bool {
        (try? makeComparisonShareDescriptor()) != nil
    }
""",
        )
        expect_task5_failure(fixture, "fail closed")
        view_model.write_text(original, encoding="utf-8")

        original = replace_once(
            view_model,
            "ProgressPhotoComparisonImageValidation.validate(bytes)",
            "_ = bytes",
        )
        expect_task5_failure(fixture, "independently decodable")
        view_model.write_text(original, encoding="utf-8")

        original = replace_once(
            renderer,
            "decode(descriptor.after.imageData)",
            "decode(descriptor.before.imageData)",
        )
        expect_task5_failure(fixture, "independently decode both images")
        renderer.write_text(original, encoding="utf-8")

        original = replace_once(
            renderer,
            "let sanitizedJPEG = try JPEGPrivacySegmentSanitizer.sanitize(encodedJPEG)",
            "let sanitizedJPEG = encodedJPEG",
        )
        expect_task5_failure(fixture, "JPEG sanitizer")
        renderer.write_text(original, encoding="utf-8")

        original = replace_once(
            renderer,
            "if (0xe1...0xef).contains(marker) || marker == 0xfe",
            "if false",
        )
        expect_task5_failure(fixture, "JPEG sanitizer")
        renderer.write_text(original, encoding="utf-8")

        original = replace_once(
            renderer,
            "guard scanEnd == bytes.count",
            "guard scanEnd <= bytes.count",
        )
        expect_task5_failure(fixture, "JPEG sanitizer")
        renderer.write_text(original, encoding="utf-8")

        original = replace_once(
            renderer,
            """UIColor(
                    red: 0.07,
                    green: 0.08,
                    blue: 0.10,
                    alpha: 1
                )""",
            "UIColor.label",
        )
        expect_task5_failure(fixture, "fixed dark ink")
        renderer.write_text(original, encoding="utf-8")

        original = replace_once(
            renderer,
            "paragraph.lineBreakMode = .byWordWrapping",
            "paragraph.lineBreakMode = .byTruncatingTail",
        )
        expect_task5_failure(fixture, "measure wrapped localized captions")
        renderer.write_text(original, encoding="utf-8")

        original = replace_once(
            renderer,
            "x: originX + captionHorizontalInset",
            "x: originX",
        )
        expect_task5_failure(fixture, "measure wrapped localized captions")
        renderer.write_text(original, encoding="utf-8")

        original = replace_once(
            renderer,
            "traitCollection ?? UITraitCollection.current",
            "UITraitCollection.current",
        )
        expect_task5_failure(fixture, "measure wrapped localized captions")
        renderer.write_text(original, encoding="utf-8")

        original = replace_once(
            renderer,
            "compatibleWith: traitCollection",
            "compatibleWith: UITraitCollection()",
        )
        expect_task5_failure(fixture, "accessibility-scaled caption fonts")
        renderer.write_text(original, encoding="utf-8")

        original = replace_once(
            coordinator,
            "            try ensureCurrent(operationGeneration)\n            let artifact",
            "            let artifact",
        )
        expect_task5_failure(fixture, "current generation")
        coordinator.write_text(original, encoding="utf-8")

        original = replace_once(
            coordinator,
            (
                "    ) async {\n"
                "        guard !Task.isCancelled else { return }"
            ),
            (
                "    ) async {\n"
                "        _ = Task.isCancelled\n"
                "        // guard !Task.isCancelled else { return }"
            ),
        )
        expect_task5_failure(fixture, "already-cancelled queued shares")
        coordinator.write_text(original, encoding="utf-8")

        original = replace_once(
            coordinator,
            "                    retainLifetimeCleanup(for: allocatedOwnedDirectory)",
            (
                "                    _ = allocatedOwnedDirectory\n"
                "                    // retainLifetimeCleanup(for: allocatedOwnedDirectory)"
            ),
        )
        expect_task5_failure(fixture, "retryable idempotent cleanup")
        coordinator.write_text(original, encoding="utf-8")

        original = replace_once(
            coordinator,
            "                    cleanupRegistry.retainOwnedDirectory(",
            "                    cleanupRegistry.didCleanOwnedDirectory(",
        )
        expect_task5_failure(fixture, "retryable idempotent cleanup")
        coordinator.write_text(original, encoding="utf-8")

        original = replace_once(
            coordinator,
            "        guard Self.isExactOwnedChild(directory, under: root) else { return }",
            "        _ = directory\n        _ = root",
        )
        expect_task5_failure(fixture, "exact UUID child ownership")
        coordinator.write_text(original, encoding="utf-8")

        original = replace_once(
            coordinator,
            "        guard scheduledTokens[directory] == token else { return }",
            "        _ = token",
        )
        expect_task5_failure(fixture, "retryable idempotent cleanup")
        coordinator.write_text(original, encoding="utf-8")

        original = replace_once(
            coordinator,
            "        30_000_000_000,",
            "        10_000_000_000,",
        )
        expect_task5_failure(fixture, "retryable idempotent cleanup")
        coordinator.write_text(original, encoding="utf-8")

        original = replace_once(
            coordinator,
            "try fileSystem.createExclusiveDirectory(at: candidate)",
            (
                "try fileSystem.createDirectory(at: candidate)\n"
                "                // try fileSystem.createExclusiveDirectory(at: candidate)"
            ),
        )
        expect_task5_failure(fixture, "exclusive allocation")
        coordinator.write_text(original, encoding="utf-8")

        original = replace_once(
            coordinator,
            "            try cleanupAction()\n            didCleanUp = true",
            "            didCleanUp = true\n            try cleanupAction()",
        )
        expect_task5_failure(fixture, "retryable idempotent cleanup")
        coordinator.write_text(original, encoding="utf-8")

        original = replace_once(
            coordinator,
            "rememberPendingOwnedDirectory(allocatedOwnedDirectory)",
            "_ = allocatedOwnedDirectory",
        )
        expect_task5_failure(fixture, "retryable idempotent cleanup")
        coordinator.write_text(original, encoding="utf-8")

        original = replace_once(
            coordinator,
            "guard artifact?.id == artifactID else { return }",
            "_ = artifactID",
        )
        expect_task5_failure(fixture, "exact artifact identity")
        coordinator.write_text(original, encoding="utf-8")

        original = replace_once(
            activity,
            "onCompletion(artifactID, completed, error)",
            "onCompletion(UUID(), completed, error)",
        )
        expect_task5_failure(fixture, "system activity lifecycle")
        activity.write_text(original, encoding="utf-8")

        original = replace_once(
            gallery,
            "artifactID: artifact.id",
            "artifactID: UUID()",
        )
        expect_task5_failure(fixture, "explicit localized 52-point share button")
        gallery.write_text(original, encoding="utf-8")

        original = replace_once(
            gallery,
            "                    shareTask = Task { @MainActor in",
            "                    Task { @MainActor in",
        )
        expect_task5_failure(fixture, "explicit localized 52-point share button")
        gallery.write_text(original, encoding="utf-8")

        original = replace_once(
            gallery,
            "            shareTask?.cancel()\n            shareTask = nil\n            shareCoordinator.dismiss()",
            "            shareTask = nil\n            shareCoordinator.dismiss()",
        )
        expect_task5_failure(fixture, "own and cancel queued share work")
        gallery.write_text(original, encoding="utf-8")

        original = coordinator.read_text(encoding="utf-8")
        if "artifact.cleanup()" not in original:
            raise SystemExit("Task 5 cleanup mutation source is missing")
        coordinator.write_text(
            original.replace("artifact.cleanup()", "_ = artifact.fileURL"),
            encoding="utf-8",
        )
        expect_task5_failure(fixture, "idempotent cleanup")
        coordinator.write_text(original, encoding="utf-8")

        original = coordinator.read_text(encoding="utf-8")
        coordinator.write_text(
            original + "\nfunc unsafeCleanup() throws { try fileSystem.removeItemIfExists(at: rootDirectory) }\n",
            encoding="utf-8",
        )
        expect_task5_failure(fixture, "never delete the shared root")
        coordinator.write_text(original, encoding="utf-8")

        original = replace_once(
            activity,
            "activityItems: [activityItemURL]",
            'activityItems: [activityItemURL, "private caption"]',
        )
        expect_task5_failure(fixture, "exactly the final JPEG URL")
        activity.write_text(original, encoding="utf-8")

        original = replace_once(
            gallery,
            '.accessibilityIdentifier("photos.compare.share")',
            '.accessibilityIdentifier("renamed.share")',
        )
        expect_task5_failure(fixture, "explicit localized 52-point share button")
        gallery.write_text(original, encoding="utf-8")

        original = replace_once(
            gallery,
            ".accessibilityElement(children: .contain)",
            ".accessibilityElement(children: .ignore)",
        )
        expect_task5_failure(fixture, "explicit localized 52-point share button")
        gallery.write_text(original, encoding="utf-8")

        original_localization = localization.read_text(encoding="utf-8")
        localized = json.loads(original_localization)
        del localized["strings"]["photos.compare.share.hint"]
        localization.write_text(json.dumps(localized), encoding="utf-8")
        expect_task5_failure(fixture, "photos.compare.share.hint")
        localization.write_text(original_localization, encoding="utf-8")

        original = replace_once(
            tracker_verifier,
            (
                '            "Packages/HealthTrackingModules/Sources/ProgressPhotosKit/Share/'
                'UIKitProgressPhotoComparisonRenderer.swift",\n'
            ),
            "",
        )
        expect_task5_failure(fixture, "one exact added M3 named-adapter allowlist path")
        tracker_verifier.write_text(original, encoding="utf-8")

        original_domain = domain.read_text(encoding="utf-8")
        domain.write_text(original_domain + "\n@Model final class Task5ModelDecoy {}\n", encoding="utf-8")
        expect_task5_failure(fixture, "exactly 24 @Model declarations")
        domain.write_text(original_domain, encoding="utf-8")

        verify_task5_assets(fixture)


TASK6_TEST_SUITES = {
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/ExportSchemaInventoryTests.swift": (
        "ExportSchemaInventoryTests",
        False,
        {
            "testInventoryEnumeratesExactlyTwentyFourRecordsInFixedModuleOrder",
            "testEveryModuleUsesOneFixedTypedUnionWithCanonicalLeadingColumns",
            "testEveryRecordDeclaresExactPersistentProjectionAndDocumentedPrivacyTransform",
            "testTableRejectsDuplicateUnknownMissingAndWrongTypedCells",
            "testCanonicalTableRejectsPrimaryTimestampThatDisagreesWithTypedRecordCell",
            "testSnapshotPreservesExactRequestAndOrdersTablesWithoutInventingAllModules",
            "testSnapshotRejectsUnselectedOrMalformedExtraTablesUnlessRowsAreReferencedConfig",
        },
        "ExportSchemaV1",
    ),
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/RFC4180CSVEncoderTests.swift": (
        "RFC4180CSVEncoderTests",
        False,
        {
            "testEncodesRFC4180EscapesUnicodeNullEmptyAndCanonicalScalars",
            "testFormulaNeutralizationAndInverseAreUnambiguousForEveryLeadingScalar",
            "testRejectsEveryNonFiniteDecimalBeforeReturningBytes",
            "testSortsRowsByRecordTypePrimaryTimestampUUIDAndProducesDeterministicBytes",
            "testEmptyTableContainsStableHeaderAndFinalCRLF",
            "testDecimalScientificPolicyAndFinalTieBreakAreCanonical",
        },
        "RFC4180CSVEncoder",
    ),
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/ReportsExportRepositoryTests.swift": (
        "ReportsExportRepositoryTests",
        True,
        {
            "testInventoryUsesAllTwentyFourRealModelTypesAndProjectsEveryRecord",
            "testHalfOpenRangeIncludesExactStartAndJustBeforeEndOnly",
            "testSelectedTrainingAddsOnlyTransitiveReferencedConfiguration",
            "testSelectedTrainingFailsClosedOnProgressChecklistReferenceTypeAndDay",
            "testSelectedTrainingExerciseReferencesMatchSessionDayAndIgnoreOutOfRangeRows",
            "testSelectedTrainingMissingReferencesPreserveActualSourceProvenance",
            "testRelevantCorruptionFailsInCanonicalUUIDOrderAcrossInsertionOrders",
            "testSelectedNutritionExportsAllSelectedFoodAndRecipeConfiguration",
            "testSelectedNutritionFailsClosedOnMealReferencesAndDuplicateConfiguration",
            "testExplicitProfileAndSystemConfigurationUsesSelectedScope",
            "testProgramStateRequiredReferencesFailClosedWhenSelectedOrTransitivelyReferenced",
            "testIrrelevantCorruptProgressPayloadDoesNotPoisonButSelectedPayloadFailsTyped",
            "testEmptySelectionAndSelectedEmptyModuleRemainDistinct",
        },
        "fetchExportSnapshot",
    ),
}

TASK6_TEST_ASSET_SHA256 = {
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/ExportSchemaInventoryTests.swift": (
        "9e82c60e959a7ee5157ea3c1c0385114520af16d6a81c9f811abee745b9c07d0"
    ),
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/RFC4180CSVEncoderTests.swift": (
        "0560295aa9e71f19e5cc7a23e67b26ef5efc17d3aca6d98aecce518a0fc3a34a"
    ),
    "Packages/HealthTrackingModules/Tests/PersistenceKitTests/ReportsExportRepositoryTests.swift": (
        "e1f6aac5922db82cdfb53171076cb163fa0460ac476610f24e45b1e8d49be99a"
    ),
}

TASK6_RECORD_CASES = {
    "userProfile": "user_profile",
    "program": "program",
    "programPhase": "program_phase",
    "programState": "program_state",
    "workoutDayTemplate": "workout_day_template",
    "exerciseTemplate": "exercise_template",
    "warmupItem": "warmup_item",
    "cooldownItem": "cooldown_item",
    "workoutSession": "workout_session",
    "setLog": "set_log",
    "workoutSessionProgress": "workout_session_progress",
    "food": "food",
    "recipe": "recipe",
    "dailyNutritionLog": "daily_nutrition_log",
    "mealEntry": "meal_entry",
    "bodyMetric": "body_metric",
    "postureMetric": "posture_metric",
    "sleepLog": "sleep_log",
    "moodLog": "mood_log",
    "healthCheckReminder": "health_check_reminder",
    "bloodworkResult": "bloodwork_result",
    "progressPhoto": "progress_photo",
    "appReminder": "app_reminder",
    "appSetting": "app_setting",
}

TASK6_MODULE_CASES = {
    "profileProgram": "profile_program",
    "training": "training",
    "nutrition": "nutrition",
    "metrics": "metrics",
    "lifestyle": "lifestyle",
    "health": "health",
    "photos": "photos",
    "system": "system",
}

TASK6_PRODUCTION_PATHS = (
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/ExportSchemaV1.swift",
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/ExportSnapshotV1.swift",
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/RFC4180CSVEncoder.swift",
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift",
)

TASK6_PRODUCTION_ASSET_SHA256 = {
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/ExportSchemaV1.swift": (
        "a1622d72d05179f1e584145f8a2dffe10aa35df5f6949033700ca0e25eb255ab"
    ),
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/ExportSnapshotV1.swift": (
        "d88703ee02e4b5d797a9bcdd35393f1e721e141cbea3202693b60b6e7a2c74a1"
    ),
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/RFC4180CSVEncoder.swift": (
        "97fdf5b29135ebd245fc48a852100f207609befdd33404adcbbad65209b12314"
    ),
    "Packages/HealthTrackingModules/Sources/PersistenceKit/Repositories/SwiftDataReportsRepository.swift": (
        "7c0ef896f096e677acf947868d12a5100567c25db6f6862e196aba10866a2bc1"
    ),
}


def verify_task6_test_contracts(
    root: Path,
    enforce_test_asset_digests: bool = True,
) -> None:
    for relative, (suite, main_actor, expected_methods, production_token) in TASK6_TEST_SUITES.items():
        path = root / relative
        if not path.is_file():
            raise ValueError(f"Task 6 test contract is missing: {relative}")
        source = path.read_text(encoding="utf-8")
        methods = swift_xctest_suite_methods(
            source,
            suite,
            main_actor,
        )
        if set(methods) != expected_methods:
            raise ValueError(f"Task 6 {suite} must retain every exact behavior test")
        for name, body in methods.items():
            if re.search(r"\bXCTExpectFailure\s*\(", body):
                raise ValueError(
                    f"Task 6 test {suite}.{name} must retain reachable direct behavior"
                )
            reachable = task5_reachable_direct_method_body(body, path, name)
            if not re.search(r"\bXCTAssert[A-Za-z0-9_]*\s*\(", reachable):
                raise ValueError(
                    f"Task 6 test {suite}.{name} must assert real behavior with "
                    "reachable direct behavior"
                )
        if production_token not in swift_code_without_comments_and_literals(source):
            raise ValueError(f"Task 6 {suite} must exercise {production_token}")
    if enforce_test_asset_digests:
        for relative in TASK6_TEST_SUITES:
            path = root / relative
            actual_digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if TASK6_TEST_ASSET_SHA256.get(relative) != actual_digest:
                raise ValueError(f"Task 6 test asset digest mismatch: {relative}")


def verify_task6_assets(root: Path) -> None:
    verify_task6_test_contracts(root)
    missing = [relative for relative in TASK6_PRODUCTION_PATHS if not (root / relative).is_file()]
    if missing:
        raise ValueError(f"Task 6 production contracts are missing: {missing}")

    schema_path = root / TASK6_PRODUCTION_PATHS[0]
    snapshot_path = root / TASK6_PRODUCTION_PATHS[1]
    encoder_path = root / TASK6_PRODUCTION_PATHS[2]
    repository_path = root / TASK6_PRODUCTION_PATHS[3]
    schema_source = schema_path.read_text(encoding="utf-8")
    snapshot_source = snapshot_path.read_text(encoding="utf-8")
    encoder_source = encoder_path.read_text(encoding="utf-8")
    repository_source = repository_path.read_text(encoding="utf-8")
    schema_code = swift_code_without_comments_and_literals(schema_source)
    snapshot_code = swift_code_without_comments_and_literals(snapshot_source)
    encoder_code = swift_code_without_comments_and_literals(encoder_source)
    repository_code = swift_code_without_comments_and_literals(repository_source)

    for source, label in (
        (schema_source, "schema"),
        (snapshot_source, "snapshot"),
        (encoder_source, "CSV encoder"),
    ):
        forbidden = swift_imported_modules(source) & {
            "CoreModels", "PersistenceKit", "SwiftData",
        }
        if forbidden:
            raise ValueError(
                f"Task 6 ReportsKit {label} must remain persistence-neutral: {sorted(forbidden)}"
            )

    record_cases = swift_direct_raw_enum_cases(schema_source, "ExportRecordTypeV1")
    if set(record_cases) != set(TASK6_RECORD_CASES):
        raise ValueError("Task 6 schema must enumerate exactly the 24 model record types")
    for case_name, raw_value in TASK6_RECORD_CASES.items():
        if record_cases.get(case_name) != [json.dumps(raw_value)]:
            raise ValueError("Task 6 record inventory must use exact stable raw identifiers")

    module_cases = swift_direct_raw_enum_cases(schema_source, "ExportModuleV1")
    if set(module_cases) != set(TASK6_MODULE_CASES):
        raise ValueError("Task 6 schema must enumerate exactly eight fixed modules")
    for case_name, raw_value in TASK6_MODULE_CASES.items():
        if module_cases.get(case_name) != [json.dumps(raw_value)]:
            raise ValueError("Task 6 module inventory must use exact stable raw identifiers")

    schema_compact = compact_swift_tokens(schema_code)
    for fragment in (
        "case null", "case text(String)", "case integer(Int64)",
        "case decimal(Double)", "case boolean(Bool)", "case timestamp(Date)",
        "case uuid(UUID)", "duplicateColumn", "duplicateCell", "unknownCell",
        "rowWidthMismatch", "cellTypeMismatch", "nullInRequiredColumn",
        "public static func columns(for module: ExportModuleV1)",
    ):
        if compact_swift_tokens(fragment) not in schema_compact:
            raise ValueError("Task 6 typed schema must fail closed on every row/column invariant")
    leading_calls = swift_named_array_initializer_calls(
        schema_source,
        "ExportSchemaV1",
        "leadingColumns",
        "column",
    )
    expected_leading_calls = (
        'column("record_type", .text, false)',
        'column("id", .uuid, false)',
        'column("created_at", .timestamp, false)',
        'column("updated_at", .timestamp, false)',
    )
    if [compact_swift_tokens(call) for call in leading_calls] != [
        compact_swift_tokens(call) for call in expected_leading_calls
    ]:
        raise ValueError("Task 6 typed schema must use exact canonical leading columns")

    snapshot_compact = compact_swift_tokens(snapshot_code)
    for fragment in (
        "public let schemaVersion: Int", "self.schemaVersion = 1",
        "public let interval: ReportDateInterval",
        "public let selectedModules: [ExportModuleV1]",
        "public let tables: [ExportTableV1]",
        "missingSelectedModule", "ExportModuleV1.allCases",
    ):
        if compact_swift_tokens(fragment) not in snapshot_compact:
            raise ValueError("Task 6 snapshot must preserve the exact versioned request and table order")
    if re.search(r"\b(?:Date\.now|Date\s*\(\s*\))", snapshot_code):
        raise ValueError("Task 6 snapshot must not contain generation wall-clock state")

    encoder_compact = compact_swift_tokens(encoder_code)
    formula_code, _ = swift_named_type_bodies(encoder_source, "CSVFormulaTextCodecV1")
    neutralize_code, _ = swift_unique_function_bodies(
        encoder_source,
        "neutralize",
        "_ value: String",
    )
    restore_code, _ = swift_unique_function_bodies(
        encoder_source,
        "restore",
        "_ value: String",
    )
    formula_scalar_code, _ = swift_unique_function_bodies(
        encoder_source,
        "isFormulaScalar",
        "_ first: Unicode.Scalar",
    )
    timestamp_code, timestamp_raw = swift_unique_function_bodies(
        encoder_source,
        "timestamp",
        "_ value: Date",
    )
    table_encode_code, table_encode_raw = swift_unique_function_bodies(
        encoder_source,
        "encode",
        "_ table: ExportTableV1",
    )
    escape_code, escape_raw = swift_unique_function_bodies(
        encoder_source,
        "escape",
        "_ value: String, forceQuote: Bool",
    )
    for fragment in (
        "guard value.isFinite else", "value.uuidString.lowercased()",
        "Locale(identifier:", "TimeZone(secondsFromGMT: 0)",
        "value.replacingOccurrences(of: , with: )",
        "public static func restore", "Data(output.utf8)",
    ):
        if compact_swift_tokens(fragment) not in encoder_compact:
            raise ValueError("Task 6 CSV must be canonical RFC 4180 and reversibly formula-safe")
    scoped_raw_fragments = (
        ('let recordSeparator = "\\r\\n"', table_encode_code, table_encode_raw),
        ('Locale(identifier: "en_US_POSIX")', timestamp_code, timestamp_raw),
        (
            'formatter.dateFormat = "yyyy-MM-dd\'T\'HH:mm:ss.SSSSSS\'Z\'"',
            timestamp_code,
            timestamp_raw,
        ),
        (
            'value.replacingOccurrences(of: "\\\"", with: "\\\"\\\"")',
            escape_code,
            escape_raw,
        ),
    )
    if any(
        not swift_real_raw_fragment_present(scoped_code, scoped_raw, fragment)
        for fragment, scoped_code, scoped_raw in scoped_raw_fragments
    ):
        raise ValueError(
            "Task 6 canonical RFC 4180 CSV must retain exact scalar and formula encodings"
        )
    neutralize_compact = compact_swift_tokens(neutralize_code)
    restore_compact = compact_swift_tokens(restore_code)
    formula_scalar_compact = compact_swift_tokens(formula_scalar_code)
    for fragment, scoped_code in (
        ("guard let first = value.unicodeScalars.first", neutralize_compact),
        ("first.value == 0x27", neutralize_compact),
        ("isFormulaScalar(first)", neutralize_compact),
        ("let scalars = value.unicodeScalars", restore_compact),
        ("String(scalars[remainderIndex...])", restore_compact),
        ("remainder.unicodeScalars.first?.value == 0x27", restore_compact),
        ("_ first: Unicode.Scalar", compact_swift_tokens(formula_code)),
        (
            "[0x3D, 0x2B, 0x2D, 0x40, 0x09, 0x0D].contains(first.value)",
            formula_scalar_compact,
        ),
    ):
        if compact_swift_tokens(fragment) not in scoped_code:
            raise ValueError(
                "Task 6 canonical RFC 4180 CSV must retain exact scalar and formula encodings"
            )
    if encoder_compact.count(compact_swift_tokens("guard value.isFinite else")) != 2:
        raise ValueError(
            "Task 6 canonical RFC 4180 CSV must validate every decimal before returning bytes"
        )
    if "Calendar.current" in encoder_code or "Locale.current" in encoder_code:
        raise ValueError("Task 6 CSV must never use current locale/calendar state")

    inventory_body = swift_named_type_body(repository_code, "ReportsExportModelInventoryV1")
    for model_name in (
        "UserProfile", "Program", "ProgramPhase", "ProgramState",
        "WorkoutDayTemplate", "ExerciseTemplate", "WarmupItem", "CooldownItem",
        "WorkoutSession", "SetLog", "WorkoutSessionProgress", "Food", "Recipe",
        "DailyNutritionLog", "MealEntry", "BodyMetric", "PostureMetric", "SleepLog",
        "MoodLog", "HealthCheckReminder", "BloodworkResult", "ProgressPhoto",
        "AppReminder", "AppSetting",
    ):
        if len(re.findall(rf"\b{model_name}\s*\.\s*self\b", inventory_body)) != 1:
            raise ValueError("Task 6 persistence inventory must bind all 24 real model metatypes")

    repository_compact = compact_swift_tokens(repository_code)
    fetch_export_compact = compact_swift_tokens(swift_unique_function_body(
        repository_code,
        "fetchExportSnapshot",
        "modules: Set<ExportModuleV1>",
    ))
    progress_export_compact = compact_swift_tokens(swift_unique_function_body(
        repository_code,
        "exportRow",
        "_ progress: WorkoutSessionProgress",
    ))
    photo_export_compact = compact_swift_tokens(swift_unique_function_body(
        repository_code,
        "exportRow",
        "_ photo: ProgressPhoto",
    ))
    progress_validation_compact = compact_swift_tokens(swift_unique_function_body(
        repository_code,
        "validateExportProgressChecklistReferences",
        "_ progress: WorkoutSessionProgress",
    ))
    progress_reference_compact = compact_swift_tokens(swift_unique_function_body(
        repository_code,
        "validateExportProgressReference",
        "progressID: UUID",
    ))
    program_state_validation_compact = compact_swift_tokens(swift_unique_function_body(
        repository_code,
        "validateExportProgramStateReferences",
        "_ states: [ProgramState]",
    ))
    training_exercise_validation_compact = compact_swift_tokens(swift_unique_function_body(
        repository_code,
        "validateExportTrainingExerciseReference",
        "_ exercise: ExerciseTemplate",
    ))
    canonical_export_records_compact = compact_swift_tokens(swift_unique_function_body(
        repository_code,
        "canonicalExportRecords",
        "_ records: [Record]",
    ))
    selected_profile_program_compact = compact_swift_tokens(swift_unique_function_body(
        repository_code,
        "appendSelectedProfileProgramRows",
        "profiles: [UserProfile]",
    ))
    referenced_training_config_compact = compact_swift_tokens(swift_unique_function_body(
        repository_code,
        "appendReferencedTrainingConfiguration",
        "referencedProgramIDs: Set<UUID>",
    ))
    for fragment, scoped_code in (
        ("WorkoutSessionProgressCodec.decode(progress.completedWarmupItemIdsData)", progress_export_compact),
        ("WorkoutSessionProgressCodec.decode(progress.completedCooldownItemIdsData)", progress_export_compact),
        ("interval.contains(record.updatedAt)", fetch_export_compact),
        ("!photo.imageRef.isEmpty", photo_export_compact),
        ("referencedProgramIDs", fetch_export_compact),
        ("referencedWorkoutDayTemplateSources", fetch_export_compact),
        ("referencedExerciseTemplateSources", fetch_export_compact),
        ("selectedModules.contains(.system)", fetch_export_compact),
        ("configScope: .referenced", repository_compact),
    ):
        if compact_swift_tokens(fragment) not in scoped_code:
            raise ValueError(
                "Task 6 persistence mapper must range-filter, decode codecs, sanitize photos, "
                "and close referenced configuration transitively"
            )
    for forbidden in (
        ".base64EncodedString",
        ".text(photo.imageRef)", "ExportCellV1.text(progress.completedWarmupItemIdsData",
        "ExportCellV1.text(progress.completedCooldownItemIdsData",
    ):
        if compact_swift_tokens(forbidden) in repository_compact:
            raise ValueError("Task 6 snapshot mapping must be read-only and never emit opaque private blobs")
    if (
        repository_compact.count(compact_swift_tokens("configScope: .referenced")) != 8
        or repository_compact.count(compact_swift_tokens("configScope: .selected")) != 12
    ):
        raise ValueError(
            "Task 6 persistence mapper must range-filter, decode codecs, sanitize photos, "
            "and close referenced configuration transitively"
        )
    if swift_model_context_mutates(repository_source):
        raise ValueError("Task 6 snapshot mapping must be read-only and never emit opaque private blobs")

    export_table_initializer_compact = compact_swift_tokens(swift_unique_initializer_body(
        schema_code,
        "ExportTableV1",
        "module: ExportModuleV1",
    ))
    progress_issue_compact = compact_swift_tokens(swift_named_type_body(
        repository_code,
        "ReportsExportProgressReferenceIssueV1",
    ))
    training_exercise_issue_compact = compact_swift_tokens(swift_named_type_body(
        repository_code,
        "ReportsExportTrainingExerciseReferenceIssueV1",
    ))
    review_contracts = {
        "canonical primary timestamp integrity": all(
            compact_swift_tokens(fragment) in export_table_initializer_compact
            for fragment in (
                "definition.primaryTimestampColumn",
                "canonicalPrimaryTimestamp == row.primaryTimestamp",
                "primaryTimestampMismatch",
            )
        ),
        "Unicode-scalar formula prefix handling": all((
            compact_swift_tokens("guard let first = value.unicodeScalars.first")
            in neutralize_compact,
            compact_swift_tokens("let scalars = value.unicodeScalars")
            in restore_compact,
            compact_swift_tokens("String(scalars[remainderIndex...])")
            in restore_compact,
            compact_swift_tokens("_ first: Unicode.Scalar")
            in compact_swift_tokens(formula_code),
            compact_swift_tokens("contains(first.value)") in formula_scalar_compact,
        )),
        "all selected nutrition configuration": all(
            compact_swift_tokens(fragment) in fetch_export_compact
            for fragment in (
                "rejectExportDuplicateIDs(foods, type: .food, id: \.id)",
                "rejectExportDuplicateIDs(recipes, type: .recipe, id: \.id)",
                "foods.map { try exportRow($0, configScope: .selected) }",
                "recipes.map { try exportRow($0, configScope: .selected) }",
            )
        ),
        "typed progress checklist references": all((
            fetch_export_compact.count(compact_swift_tokens(
                "validateExportProgressChecklistReferences("
            )) == 1,
            all(
                compact_swift_tokens(fragment) in progress_validation_compact
                for fragment in (
                    "WorkoutSessionProgressCodec.decode("
                    "progress.completedWarmupItemIdsData)",
                    "WorkoutSessionProgressCodec.decode("
                    "progress.completedCooldownItemIdsData)",
                )
            ),
            progress_validation_compact.count(compact_swift_tokens(
                "validateExportProgressReference("
            )) == 2,
            all(
                compact_swift_tokens(fragment) in progress_reference_compact
                for fragment in (
                    "wrongMatches.isEmpty ? .missing : .wrongRecordType(wrongType)",
                    "record[keyPath: workoutDay]?.id",
                    "actualWorkoutDayID == expectedWorkoutDayID",
                    "wrongRecordType(wrongType)",
                    "missingWorkoutDay",
                    "wrongWorkoutDay",
                )
            ),
            all(
                compact_swift_tokens(fragment) in progress_issue_compact
                for fragment in (
                    "case missing",
                    "case wrongRecordType(ExportRecordTypeV1)",
                    "case missingWorkoutDay",
                    "case wrongWorkoutDay(expected: UUID, actual: UUID)",
                )
            ),
        )),
        "required ProgramState references": all((
            selected_profile_program_compact.count(compact_swift_tokens(
                "validateExportProgramStateReferences("
            )) == 1,
            referenced_training_config_compact.count(compact_swift_tokens(
                "validateExportProgramStateReferences("
            )) == 1,
            all(
                compact_swift_tokens(fragment) in program_state_validation_compact
                for fragment in (
                    "resolveExportReference(state.programId, in: programs",
                    "resolveExportReference(state.currentPhaseId, in: phases",
                    "phase.program?.id",
                    "phaseProgramID == state.programId",
                    "programStatePhaseProgramMismatch",
                )
            ),
        )),
        "reference diagnostic provenance": all((
            compact_swift_tokens("ExportReferenceProvenanceV1") in repository_compact,
            fetch_export_compact.count(
                compact_swift_tokens("sourceType: source.sourceType")
            ) == 2,
            fetch_export_compact.count(
                compact_swift_tokens("sourceID: source.sourceID")
            ) == 2,
        )),
        "training exercise session-day integrity": all((
            fetch_export_compact.count(compact_swift_tokens(
                "validateExportTrainingExerciseReference("
            )) == 2,
            all(
                compact_swift_tokens(fragment) in training_exercise_validation_compact
                for fragment in (
                    "exercise.workoutDayTemplate?.id",
                    "actualWorkoutDayID == session.workoutDayTemplateId",
                    "sourceType: sourceType",
                    "sourceID: sourceID",
                    "exerciseTemplateID: exercise.id",
                    "invalidTrainingExerciseReference",
                )
            ),
            all(
                compact_swift_tokens(fragment) in training_exercise_issue_compact
                for fragment in (
                    "case missingWorkoutDay",
                    "case wrongWorkoutDay(expected: UUID, actual: UUID)",
                )
            ),
        )),
        "canonical fetched-record ordering": all((
            fetch_export_compact.count(
                compact_swift_tokens("canonicalExportRecords(")
            ) == 24
            and all(
                compact_swift_tokens(
                    "canonicalExportRecords(try modelContext.fetch("
                    f"FetchDescriptor<{model}>()), id: \\.id)"
                ) in fetch_export_compact
                for model in (
                    "UserProfile", "Program", "ProgramPhase", "ProgramState",
                    "WorkoutDayTemplate", "ExerciseTemplate", "WarmupItem",
                    "CooldownItem", "WorkoutSession", "SetLog",
                    "WorkoutSessionProgress", "Food", "Recipe",
                    "DailyNutritionLog", "MealEntry", "BodyMetric",
                    "PostureMetric", "SleepLog", "MoodLog",
                    "HealthCheckReminder", "BloodworkResult", "ProgressPhoto",
                    "AppReminder", "AppSetting",
                )
            ),
            compact_swift_tokens("records.sorted") in canonical_export_records_compact,
            compact_swift_tokens(
                "uuidOrderedBefore($0[keyPath: id], $1[keyPath: id])"
            ) in canonical_export_records_compact,
        )),
    }
    missing_review_contracts = [
        name for name, present in review_contracts.items() if not present
    ]
    if missing_review_contracts:
        raise ValueError(
            "Task 6 review production contracts are missing: "
            f"{missing_review_contracts}"
        )
    for relative in TASK6_PRODUCTION_PATHS:
        path = root / relative
        actual_digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if TASK6_PRODUCTION_ASSET_SHA256.get(relative) != actual_digest:
            raise ValueError(f"Task 6 production asset digest mismatch: {relative}")


def expect_task6_failure(root: Path, expected: str) -> None:
    try:
        verify_task6_assets(root)
    except ValueError as error:
        if expected not in str(error):
            raise SystemExit(
                f"Task 6 real-asset mutation failed for wrong reason; expected {expected!r}: {error}"
            ) from error
    else:
        raise SystemExit(f"Task 6 real-asset mutation escaped: {expected}")


def task6_real_asset_self_test(source_root: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="m4-task6-real-assets-") as directory:
        fixture = Path(directory)
        relative_paths = tuple(TASK6_TEST_SUITES) + TASK6_PRODUCTION_PATHS
        for relative in relative_paths:
            source = source_root / relative
            destination = fixture / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            if source.is_file():
                shutil.copy2(source, destination)
        verify_task6_assets(fixture)

        for relative in relative_paths:
            path = fixture / relative
            original = path.read_bytes()
            path.unlink()
            expected = "test contract is missing" if relative in TASK6_TEST_SUITES else "production contracts are missing"
            expect_task6_failure(fixture, expected)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(original)

        for relative, (suite, _, _, _) in TASK6_TEST_SUITES.items():
            path = fixture / relative
            original = replace_once(path, f"final class {suite}", f"final class Removed{suite}")
            expect_task6_failure(fixture, "expected concrete XCTestCase suite")
            path.write_text(original, encoding="utf-8")
            original = path.read_text(encoding="utf-8")
            path.write_text(original.replace("XCTAssert", "Task6RemovedAssert"), encoding="utf-8")
            expect_task6_failure(fixture, "must assert real behavior")
            path.write_text(original, encoding="utf-8")

        rfc_test = fixture / (
            "Packages/HealthTrackingModules/Tests/ReportsKitTests/"
            "RFC4180CSVEncoderTests.swift"
        )
        original_rfc_test = rfc_test.read_text(encoding="utf-8")
        bound_rfc_method = (
            "testFormulaNeutralizationAndInverseAreUnambiguousForEveryLeadingScalar"
        )
        for prefix, suffix in (
            ("\n        return\n", ""),
            ("\n        throw XCTSkip()\n", ""),
            ("\n        XCTExpectFailure()\n", ""),
            ("\n        if false {\n", "\n        }\n"),
        ):
            rfc_test.write_text(
                wrap_named_test_body(
                    original_rfc_test,
                    bound_rfc_method,
                    prefix,
                    suffix,
                ),
                encoding="utf-8",
            )
            expect_task6_failure(fixture, "reachable direct behavior")
        rfc_test.write_text(original_rfc_test, encoding="utf-8")

        for digest_decoy in (
            "\n// Task 6 canonical-test comment decoy.\n",
            "\nprivate let task6UnusedHelper = { XCTAssertTrue(true) }\n",
        ):
            rfc_test.write_text(original_rfc_test + digest_decoy, encoding="utf-8")
            expect_task6_failure(fixture, "Task 6 test asset digest")
        rfc_test.write_text(original_rfc_test, encoding="utf-8")

        rfc_test.write_text(
            wrap_named_test_body(
                original_rfc_test,
                bound_rfc_method,
                "\n        let neverCalled = {\n",
                "\n        }\n        _ = neverCalled\n",
            ),
            encoding="utf-8",
        )
        expect_task6_failure(fixture, "Task 6 test asset digest")
        rfc_test.write_text(original_rfc_test, encoding="utf-8")

        schema = fixture / TASK6_PRODUCTION_PATHS[0]
        original = replace_once(
            schema,
            'case appSetting = "app_setting"',
            'case appSetting = "wrong" // case appSetting = "app_setting"',
        )
        expect_task6_failure(fixture, "exact stable raw identifiers")
        schema.write_text(original, encoding="utf-8")

        original = replace_once(schema, 'case appSetting = "app_setting"', 'case removedSetting = "app_setting"')
        expect_task6_failure(fixture, "exactly the 24 model record types")
        schema.write_text(original, encoding="utf-8")

        original = replace_once(
            schema,
            'column("record_type", .text, false)',
            'column("wrong_record_type", .text, false) '
            '// column("record_type", .text, false)',
        )
        expect_task6_failure(fixture, "exact canonical leading columns")
        schema.write_text(original, encoding="utf-8")

        original = replace_once(
            schema,
            "canonicalPrimaryTimestamp == row.primaryTimestamp",
            "true",
        )
        expect_task6_failure(fixture, "canonical primary timestamp integrity")
        schema.write_text(original, encoding="utf-8")

        encoder = fixture / TASK6_PRODUCTION_PATHS[2]
        for before, after, expected in (
            ("guard value.isFinite else", "guard true else", "canonical RFC 4180"),
            (
                'let recordSeparator = "\\r\\n"',
                'let recordSeparator = "\\n"',
                "canonical RFC 4180",
            ),
            (
                "public static func restore",
                "public static func removedRestore",
                "function restore must have one expected declaration",
            ),
        ):
            original = replace_once(encoder, before, after)
            expect_task6_failure(fixture, expected)
            encoder.write_text(original, encoding="utf-8")

        for before, after in (
            (
                "guard let first = value.unicodeScalars.first else",
                "guard let first = value.first else",
            ),
            (
                "String(scalars[remainderIndex...])",
                "String(value[remainderIndex...])",
            ),
            (
                'let recordSeparator = "\\r\\n"',
                'let recordSeparator = "\\n" '
                '// let recordSeparator = "\\r\\n"',
            ),
        ):
            original = replace_once(encoder, before, after)
            expect_task6_failure(fixture, "canonical RFC 4180")
            encoder.write_text(original, encoding="utf-8")

        repository = fixture / TASK6_PRODUCTION_PATHS[3]
        original_repository = repository.read_text(encoding="utf-8")
        repository.write_text(
            original_repository.replace(
                "selectedModules.contains(.system)",
                "true",
                1,
            )
            + "\nprivate func task6UnusedSystemDecoy() { "
            + "_ = selectedModules.contains(.system) }\n",
            encoding="utf-8",
        )
        expect_task6_failure(
            fixture,
            "range-filter, decode codecs, sanitize photos",
        )
        repository.write_text(original_repository, encoding="utf-8")

        for before, after, expected in (
            (
                "WorkoutSessionProgressCodec.decode(progress.completedWarmupItemIdsData)",
                "Set<UUID>()",
                "range-filter, decode codecs, sanitize photos",
            ),
            (
                "interval.contains(record.updatedAt)",
                "true",
                "range-filter, decode codecs, sanitize photos",
            ),
            (
                "!photo.imageRef.isEmpty",
                "true",
                "range-filter, decode codecs, sanitize photos",
            ),
            (
                "configScope: .referenced",
                "configScope: .selected",
                "range-filter, decode codecs, sanitize photos",
            ),
        ):
            original = replace_once(repository, before, after)
            expect_task6_failure(fixture, expected)
            repository.write_text(original, encoding="utf-8")

        original = replace_once(
            repository,
            "WorkoutSessionProgressCodec.decode(\n"
            "                progress.completedWarmupItemIdsData\n"
            "            )",
            "Set<UUID>()",
        )
        expect_task6_failure(fixture, "typed progress checklist references")
        repository.write_text(original, encoding="utf-8")

        for before, after, expected in (
            (
                "contentsOf: try foods.map { try exportRow($0, configScope: .selected) }",
                "contentsOf: []",
                "range-filter, decode codecs, sanitize photos",
            ),
            (
                "contentsOf: try recipes.map { try exportRow($0, configScope: .selected) }",
                "contentsOf: []",
                "range-filter, decode codecs, sanitize photos",
            ),
            (
                "try validateExportProgressChecklistReferences(",
                "try task6RemovedProgressChecklistValidation(",
                "typed progress checklist references",
            ),
            (
                "actualWorkoutDayID == expectedWorkoutDayID",
                "true",
                "typed progress checklist references",
            ),
            (
                "phaseProgramID == state.programId",
                "true",
                "required ProgramState references",
            ),
        ):
            original = replace_once(repository, before, after)
            expect_task6_failure(fixture, expected)
            repository.write_text(original, encoding="utf-8")

        for occurrence in (1, 2):
            original = replace_nth_once(
                repository,
                "try validateExportProgramStateReferences(",
                "try task6RemovedProgramStateValidation(",
                occurrence,
            )
            expect_task6_failure(fixture, "required ProgramState references")
            repository.write_text(original, encoding="utf-8")

        for occurrence in (1, 2):
            original = replace_nth_once(
                repository,
                "sourceID: source.sourceID",
                "sourceID: targetID",
                occurrence,
            )
            expect_task6_failure(fixture, "reference diagnostic provenance")
            repository.write_text(original, encoding="utf-8")

        original = replace_once(
            repository,
            "        let progressRecords = canonicalExportRecords(\n"
            "            try modelContext.fetch(FetchDescriptor<WorkoutSessionProgress>()), "
            "id: \\.id\n"
            "        )",
            "        let progressRecords = try modelContext.fetch(\n"
            "            FetchDescriptor<WorkoutSessionProgress>()\n"
            "        )",
        )
        expect_task6_failure(fixture, "canonical fetched-record ordering")
        repository.write_text(original, encoding="utf-8")

        original = replace_once(
            repository,
            "uuidOrderedBefore($0[keyPath: id], $1[keyPath: id])",
            "uuidOrderedBefore($1[keyPath: id], $0[keyPath: id])",
        )
        expect_task6_failure(fixture, "canonical fetched-record ordering")
        repository.write_text(original, encoding="utf-8")

        original_repository = repository.read_text(encoding="utf-8")
        selected_state_validation = (
            "        try validateExportProgramStateReferences(\n"
            "            states,\n"
            "            programs: programs,\n"
            "            phases: phases\n"
            "        )"
        )
        repository.write_text(
            original_repository.replace(
                selected_state_validation,
                "        if false {\n"
                + selected_state_validation
                + "\n        }",
                1,
            ),
            encoding="utf-8",
        )
        expect_task6_failure(fixture, "Task 6 production asset digest")
        repository.write_text(original_repository, encoding="utf-8")

        referenced_state_validation = (
            "        try validateExportProgramStateReferences(\n"
            "            selectedStates,\n"
            "            programs: programs,\n"
            "            phases: phases\n"
            "        )"
        )
        progress_validation = (
            "                try validateExportProgressChecklistReferences(\n"
            "                    progress,\n"
            "                    session: session,\n"
            "                    warmups: warmups,\n"
            "                    cooldowns: cooldowns\n"
            "                )"
        )
        nutrition_configuration = (
            "            try rejectExportDuplicateIDs(foods, type: .food, id: \\.id)\n"
            "            try rejectExportDuplicateIDs(recipes, type: .recipe, id: \\.id)\n"
            "            rowsByModule[.nutrition, default: []].append(\n"
            "                contentsOf: try foods.map { try exportRow($0, configScope: .selected) }\n"
            "            )\n"
            "            rowsByModule[.nutrition, default: []].append(\n"
            "                contentsOf: try recipes.map { try exportRow($0, configScope: .selected) }\n"
            "            )"
        )
        exercise_day_guard = (
            "        guard actualWorkoutDayID == session.workoutDayTemplateId else {\n"
            "            throw ReportsExportRepositoryError.invalidTrainingExerciseReference(\n"
            "                sourceType: sourceType,\n"
            "                sourceID: sourceID,\n"
            "                exerciseTemplateID: exercise.id,\n"
            "                reason: .wrongWorkoutDay(\n"
            "                    expected: session.workoutDayTemplateId,\n"
            "                    actual: actualWorkoutDayID\n"
            "                )\n"
            "            )\n"
            "        }"
        )
        for before, after in (
            (
                referenced_state_validation,
                "        if 1 == 2 {\n"
                + referenced_state_validation
                + "\n        }",
            ),
            (
                progress_validation,
                "                let task6UnusedProgressValidation = {\n"
                + progress_validation
                + "\n                }\n"
                "                _ = task6UnusedProgressValidation",
            ),
            (
                nutrition_configuration,
                "            if false {\n"
                + nutrition_configuration
                + "\n            }",
            ),
            (
                exercise_day_guard,
                "        if false {\n"
                + exercise_day_guard
                + "\n        }",
            ),
        ):
            original = replace_once(repository, before, after)
            expect_task6_failure(fixture, "Task 6 production asset digest")
            repository.write_text(original, encoding="utf-8")

        repository.write_text(
            original_repository
            + "\nprivate let task6UnusedProductionHelper = { true }\n",
            encoding="utf-8",
        )
        expect_task6_failure(fixture, "Task 6 production asset digest")
        repository.write_text(original_repository, encoding="utf-8")

        original_encoder = encoder.read_text(encoding="utf-8")
        for before, after in (
            (
                '        if isFormulaScalar(first) { return "\'" + value }',
                "        if false {\n"
                + '        if isFormulaScalar(first) { return "\'" + value }'
                + "\n        }",
            ),
            (
                "        if let protected = remainder.unicodeScalars.first, "
                "isFormulaScalar(protected) {\n"
                "            return remainder\n"
                "        }",
                "        if 1 == 2 {\n"
                "        if let protected = remainder.unicodeScalars.first, "
                "isFormulaScalar(protected) {\n"
                "            return remainder\n"
                "        }\n"
                "        }",
            ),
        ):
            original = replace_once(encoder, before, after)
            expect_task6_failure(fixture, "Task 6 production asset digest")
            encoder.write_text(original, encoding="utf-8")
        encoder.write_text(original_encoder, encoding="utf-8")

        for relative in TASK6_PRODUCTION_PATHS:
            production = fixture / relative
            original_production = production.read_text(encoding="utf-8")
            production.write_text(
                original_production
                + "\nprivate let task6UnusedBoundProductionHelper = { true }\n",
                encoding="utf-8",
            )
            expect_task6_failure(fixture, "Task 6 production asset digest")
            production.write_text(original_production, encoding="utf-8")


TASK7_TEST_SUITES = {
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/JSONExportEncoderTests.swift": (
        "JSONExportEncoderTests",
        False,
        {
            "testEncodesExactVersionedNativeShapeAndCanonicalScalars",
            "testPreservesNullVersusEmptyAndOriginalFormulaLikeUnicodeText",
            "testOrdersModulesTablesRowsAndProducesDeterministicSortedKeyBytes",
            "testRejectsEveryNonFiniteDecimalAndInvalidTimestampBeforeReturningBytes",
        },
        "JSONExportEncoderV1",
    ),
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/StoredZIPWriterTests.swift": (
        "StoredZIPWriterTests",
        False,
        {
            "testCRC32IEEEEmptyAndKnownVector",
            "testWritesCanonicalStoredHeadersDescriptorsCentralDirectoryAndSortedUTF8Names",
            "testRejectsDuplicateTraversalAbsoluteBackslashColonNULAndMalformedNamesBeforeOutput",
            "testRejectsSourceSymlinkDirectoryDestinationSymlinkAndDestinationAliasingInput",
            "testSourceDescriptorRejectsValidationToOpenSymlinkSwap",
            "testRejectsEveryInjectableZIP32LimitBeforeTruncation",
            "testCancellationAndStreamingFailureRemovePartialAndNeverPublishDestination",
            "testPartialRemovalFailureRetriesAutomaticallyWithoutAnotherArchive",
            "testStreamsBoundedChunksAndEquivalentTreesProduceIdenticalBytes",
            "testNeverOverwritesExistingDestination",
            "testAtomicNoReplacePublicationPreservesDestinationCreatedAtPublishBoundary",
            "testPublicationNeverUsesReplacementStagingPathBytes",
            "testPublicationNeverFollowsDestinationParentSwapOutsideHeldDirectory",
            "testStageUnlinkFailureStopsBeforeSensitiveWriteAndAutomaticallyCleansZeroBytePartial",
            "testStageHardLinkBeforeUnlinkFailsBeforeBytesAndCleansExactZeroByteInode",
            "testHardLinkEarlyFailureSynchronouslyRestoresPrivateParentFlagsBeforeReturning",
            "testStageMoveBetweenOpenAndUnlinkIsRejectedBeforePrivateBytesAreWritten",
            "testPublicationDoesNotExposeBytesWhenParentMovesAfterFinalValidationBeforeClone",
            "testPublicationCreateWindowKeepsParentAppendOnlyThroughDescriptorClone",
            "testPostOpenMetadataFailureRetainsAndCleansExactZeroByteStage",
            "testTerminalStageRecoveryNeverDeletesASecondNameForRetainedInode",
            "testStandaloneRestoreFailureRetainsExactDescriptorUntilTransientRetry",
            "testStandaloneRestoreCapacityRejectsBeforeSixtyFifthDirectoryMutation",
        },
        "StoredZIPWriter",
    ),
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/ReportExportCoordinatorTests.swift": (
        "ReportExportCoordinatorTests",
        True,
        {
            "testRejectsInvalidRequestsBeforeAllocationOrFetchAndFetchesOneExactSnapshot",
            "testEachFormatProducesExactOrderedShareLayoutWithoutCrossFormatArtifacts",
            "testBothZipManifestHasDeterministicHashesSizesMediaAndNoSelfHashOrPrivateState",
            "testPhotosAreExplicitZIPOnlyCandidatesAndStatusesAreCanonicalWithoutPrivateReferences",
            "testZIPReleasesPhotoPayloadDataBeforeStreamingArchiveEntries",
            "testUnexpectedProviderFailureAndCancellationCleanOwnedWorkspace",
            "testAllocationMarkerPublicationDoesNotBlockMainActorProgressOrCancellation",
            "testPayloadGenerationCancellationAcquiresMainActorAndCleansUUIDArtifacts",
            "testRecursiveCleanupDoesNotBlockMainActorAndEventuallyRemovesExactOwnedDirectory",
            "testTemporaryStoreProtectsContainedAllocationRetriesCollisionAndCleanupFailure",
            "testTemporaryCleanupOutlivesStoreAndMarkerIdentityPreventsStaleDeletion",
            "testArtifactTokenRetainsRealAllocationCleanupAfterStoreAndAllocationRelease",
            "testFileManagerAtomicWriteNeverOverwritesAndLeavesNoSidecarOnSuccessOrFailure",
            "testTemporaryStoreRetainsMarkerBoundCleanupWhenSetupFailureRemovalFails",
            "testTemporaryCleanupRetriesTransientMarkerReadFailureThenRemovesExactOwnedDirectory",
            "testTemporaryWriteRejectsExistingNestedSymlinkWithoutWritingOutsideOwnedDirectory",
            "testTemporaryCleanupRejectsOwnedSymlinkSwapEvenWhenMarkerIsCopied",
            "testTemporaryCleanupRejectsRootSymlinkSwapWithReproducedOwnedPathAndMarker",
            "testTemporaryWriteRejectsRootSwapAtOperationBoundaryWithoutExternalWrite",
            "testTemporaryWriteRejectsOwnedSwapAtOperationBoundaryWithoutExternalWrite",
            "testTemporaryWriteRejectsNestedSwapAtOperationBoundaryWithoutExternalWrite",
            "testTemporaryCleanupRejectsOwnedReplacementAfterMarkerReadWithoutDeletingIt",
            "testTemporaryCleanupRejectsRootReplacementAfterMarkerReadWithoutDeletingIt",
            "testPartialMarkerWriteFailureRetainsExactCleanupAfterStoreRelease",
            "testReusedURLKeepsOldAndNewCleanupRetriesIndependentAfterTokenAndStoreRelease",
            "testLifetimeCleanupRegistryStopsAfterFinitePermanentFailuresAndReleasesOperation",
            "testNilCreationRecoveryKeepsAllSixtyFourCapacityReservations",
            "testNextAllocationRecoversTerminalMarkerOwnedDirectoryWithoutRetainedClosure",
            "testViewModelDefaultsEightModulesPhotoResetAndSelectionSurvivesFailureRetryAndCleanup",
            "testViewModelDelayedProgressCancellationAndSupersessionIgnoreStaleCompletion",
            "testViewModelFormatChangeInvalidatesInFlightPhotoZIPAndCleansStaleCompletion",
            "testViewModelModuleChangeCleansReadyArtifactAndRequiresExplicitRegeneration",
            "testPayloadStageUnlinkFailureStopsBeforeDataWriteAndAutomaticallyCleansResidue",
            "testPayloadStageHardLinkBeforeUnlinkNeverReceivesPrivateBytesAndIsCleaned",
            "testPayloadStageReplacementAtPreUnlinkBoundaryIsNeverDeleted",
            "testDescriptorDirectoryEnumerationDoesNotAdvanceTheCallersCleanupCursor",
            "testPrivateNamespaceLeaseRejectsRootOwnedAndNestedMovesWhileAllocationIsLive",
            "testCleanupLeaseRejectsNestedMoveAtRecursiveCleanupBoundary",
            "testRecursiveCleanupRejectsQuarantineReplacementBetweenMetadataAndOpen",
            "testRecursiveCleanupRejectsQuarantineReplacementBetweenMetadataAndUnlink",
            "testPostMkdirPathInspectionFailureRetainsCleanupAuthorization",
            "testPostMkdirIdentityFailureRetainsCleanupAuthorization",
            "testDescriptorMkdirOpenFailureRetainsExactCleanupAuthorization",
            "testDescriptorPostSecurityFailureRetainsExactCleanupAuthorization",
            "testCleanupRecoveryCapacityRejectsBeforeCreatingSixtyFifthOwnedDirectory",
            "testViewModelDropsPermanentlyFailingTokensAfterRegistryHandoffAndRemainsResponsive",
        },
        "ReportExportCoordinator",
    ),
}

TASK7_TEST_ASSET_SHA256 = {
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/JSONExportEncoderTests.swift": (
        "d232fb5a4ef7a4b70b81d2d563913d7688fa9c54c2081f3a3737b893ddee0bfc"
    ),
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/StoredZIPWriterTests.swift": (
        "861e2554ec075586706fd008690d2777055818cdeb2f897e4e89513931fba48b"
    ),
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/ReportExportCoordinatorTests.swift": (
        "f4ed898e4aed79d631c4cbdf1d8a3b8b675e950d611c3c31b777567eb3111045"
    ),
}

# Swift semantics cannot be proven by a lexical scanner. These controller-owned
# hashes are the immutable trust boundary for the complete canonical XCTest sources,
# including literals, declarations, identifiers, helpers, and nested behavior. The
# operational TASK7_TEST_ASSET_SHA256 map may be rebound only inside copied-real
# mutation self-tests; this trusted map must never be rebound there.
TASK7_TRUSTED_CANONICAL_TEST_SOURCE_SHA256 = {
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/JSONExportEncoderTests.swift": (
        "d232fb5a4ef7a4b70b81d2d563913d7688fa9c54c2081f3a3737b893ddee0bfc"
    ),
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/StoredZIPWriterTests.swift": (
        "861e2554ec075586706fd008690d2777055818cdeb2f897e4e89513931fba48b"
    ),
    "Packages/HealthTrackingModules/Tests/ReportsKitTests/ReportExportCoordinatorTests.swift": (
        "f4ed898e4aed79d631c4cbdf1d8a3b8b675e950d611c3c31b777567eb3111045"
    ),
}

TASK7_PRODUCTION_PATHS = (
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/JSONExportEncoderV1.swift",
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/CRC32.swift",
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/StoredZIPWriter.swift",
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/ExportManifestV1.swift",
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/DescriptorBoundFileSystem.swift",
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/ReportExportCoordinator.swift",
    "Packages/HealthTrackingModules/Sources/ReportsKit/Presentation/ReportExportViewModel.swift",
    "Packages/HealthTrackingModules/Sources/ReportsKit/Presentation/ReportExportView.swift",
)

TASK7_PRODUCTION_ASSET_SHA256: dict[str, str] = {
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/JSONExportEncoderV1.swift": (
        "fe4f9e311da10f976ff6c7a011a4ee3792f0671487edbe87b0b46bbf5a66a68e"
    ),
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/CRC32.swift": (
        "baa88ef6ef3b56d8ad65b5dd26975962d6e8508c87071d2fd39d229791a74e11"
    ),
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/StoredZIPWriter.swift": (
        "e1ab72642fad5aa36aaa82a1feb1940aa0b5b359fd5c4d156ae34bd2f559d8aa"
    ),
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/ExportManifestV1.swift": (
        "aef595aaed9246e01d2cefbcc247af5316ff0b19c5d18ef9a91b328afbda5bb2"
    ),
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/DescriptorBoundFileSystem.swift": (
        "a0254320d15bc961e7e637d98f5523ad5cec9c674c70491b81ac7905729ab3c1"
    ),
    "Packages/HealthTrackingModules/Sources/ReportsKit/Export/ReportExportCoordinator.swift": (
        "52f47cdcd231fff2a84a4bc398e8472cc2a4e4754dbcf5323d3dda7fb062feab"
    ),
    "Packages/HealthTrackingModules/Sources/ReportsKit/Presentation/ReportExportViewModel.swift": (
        "ee31f6e2283ae529cdcafa72dc5c2ea5430135677dabf52066712bb2211ca4a5"
    ),
    "Packages/HealthTrackingModules/Sources/ReportsKit/Presentation/ReportExportView.swift": (
        "bd211ac5148c8c9160863930f88163c157b8231b4ab4db4320c53e351d0641dd"
    ),
}

TASK7_LOCALIZATION_KEYS = {
    "reports.export.title",
    "reports.export.range",
    "reports.export.modules",
    "reports.export.format",
    "reports.export.format.csv",
    "reports.export.format.json",
    "reports.export.format.both",
    "reports.export.photos",
    "reports.export.action",
    "reports.export.retry",
    "reports.export.cancel",
    "reports.export.progress",
    "reports.export.share",
    "reports.export.error",
}


def task7_blank_unexecuted_assertion_wrappers(code: str, name: str) -> str:
    reachable = list(code)
    wrapper_patterns = (
        re.compile(
            r"\bfunc[ \t\f\v\r\n]+(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
            r"[ \t\f\v\r\n]*\([^)]*\)[^{]*\{"
        ),
        re.compile(
            r"\b(?:let|var)[ \t\f\v\r\n]+(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
            r"[^=\r\n]*=[ \t\f\v\r\n]*\{"
        ),
    )
    occupied: list[tuple[int, int]] = []
    for pattern in wrapper_patterns:
        for match in pattern.finditer(code):
            if any(start <= match.start() < end for start, end in occupied):
                continue
            opening = code.find("{", match.start(), match.end())
            closing = balanced_brace_end(
                code,
                opening,
                f"Task 7 assertion wrapper in {name}",
            )
            wrapper_name = match.group("name")
            tail = code[closing + 1 :]
            if re.search(rf"\b{re.escape(wrapper_name)}[ \t\f\v\r\n]*\(", tail):
                continue
            task5_blank_range(reachable, match.start(), closing + 1)
            occupied.append((match.start(), closing + 1))

    closure_array = re.compile(
        r"\b(?:let|var)[ \t\f\v\r\n]+(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
        r"[^=\r\n]*=[ \t\f\v\r\n]*\[[ \t\f\v\r\n]*\{"
    )
    for match in closure_array.finditer(code):
        array_opening = code.find("[", match.start(), match.end())
        array_closing = balanced_delimiter_end(
            code,
            array_opening,
            "[",
            "]",
            f"Task 7 closure array in {name}",
        )
        wrapper_name = match.group("name")
        tail = code[array_closing + 1 :]
        executes_directly = re.search(
            rf"\b{re.escape(wrapper_name)}[ \t\f\v\r\n]*"
            rf"(?:\[[^\]]+\][ \t\f\v\r\n]*)?\(",
            tail,
        ) or re.search(
            rf"\b{re.escape(wrapper_name)}[ \t\f\v\r\n]*\."
            r"[ \t\f\v\r\n]*(?:forEach|map|compactMap|flatMap)[ \t\f\v\r\n]*\{",
            tail,
        )
        if executes_directly:
            continue
        cursor = array_opening + 1
        while cursor < array_closing:
            closure_opening = code.find("{", cursor, array_closing)
            if closure_opening == -1:
                break
            closure_closing = balanced_brace_end(
                code,
                closure_opening,
                f"Task 7 anonymous assertion wrapper in {name}",
            )
            task5_blank_range(reachable, closure_opening, closure_closing + 1)
            cursor = closure_closing + 1
    return "".join(reachable)


def task7_depth_zero_code(code: str) -> str:
    direct = list(code)
    depth = 0
    for index, character in enumerate(code):
        if character == "{":
            depth += 1
            direct[index] = " "
            continue
        if character == "}":
            depth = max(0, depth - 1)
            direct[index] = " "
            continue
        if depth > 0 and character not in {"\r", "\n"}:
            direct[index] = " "
    return "".join(direct)


def task7_has_direct_terminal(code: str) -> bool:
    return re.search(r"\b(?:return|throw)\b", task7_depth_zero_code(code)) is not None


def task7_reject_deterministic_early_terminal(code: str, path: Path, name: str) -> None:
    depths: list[int] = []
    depth = 0
    for character in code:
        depths.append(depth)
        if character == "{":
            depth += 1
        elif character == "}":
            depth = max(0, depth - 1)

    def top_level(match: re.Match[str]) -> bool:
        return depths[match.start()] == 0

    def reject() -> None:
        raise ValueError(
            f"Task 7 test {path.name}.{name} must retain reachable direct behavior "
            "without deterministic early terminal control"
        )

    for match in filter(top_level, re.finditer(r"\bdo\b", code)):
        opening = task5_control_body_opening(code, match.start(), "do", name)
        closing = balanced_brace_end(code, opening, f"Task 7 do statement in {name}")
        if task7_has_direct_terminal(code[opening + 1 : closing]):
            reject()

    repeat_condition_positions: set[int] = set()
    for match in filter(top_level, re.finditer(r"\brepeat\b", code)):
        opening = task5_control_body_opening(code, match.start(), "repeat", name)
        closing = balanced_brace_end(code, opening, f"Task 7 repeat statement in {name}")
        if task7_has_direct_terminal(code[opening + 1 : closing]):
            reject()
        condition_start = task5_skip_swift_space(code, closing + 1)
        if task5_swift_keyword_at(code, condition_start, "while"):
            repeat_condition_positions.add(condition_start)

    for keyword in ("if", "while", "guard"):
        for match in filter(top_level, re.finditer(rf"\b{keyword}\b", code)):
            if keyword == "while" and match.start() in repeat_condition_positions:
                continue
            opening = task5_control_body_opening(code, match.start(), keyword, name)
            condition = code[match.end() : opening]
            if keyword == "guard":
                condition = re.sub(r"\belse[ \t\f\v\r\n]*$", "", condition)
            selected = task5_constant_boolean(condition)
            body = code[opening + 1 : balanced_brace_end(
                code,
                opening,
                f"Task 7 {keyword} statement in {name}",
            )]
            if keyword == "if" and selected is True and task7_has_direct_terminal(body):
                reject()
            if keyword == "while" and selected is True:
                reject()
            if keyword == "guard" and selected is False:
                reject()

    for match in filter(top_level, re.finditer(r"\bswitch\b", code)):
        opening = task5_control_body_opening(code, match.start(), "switch", name)
        expression = re.sub(r"[\s()]", "", code[match.end() : opening])
        if re.fullmatch(r"(?:true|false|-?[0-9]+)", expression) is None:
            continue
        closing = balanced_brace_end(code, opening, f"Task 7 switch statement in {name}")
        body = task7_depth_zero_code(code[opening + 1 : closing])
        selected_case = re.search(
            rf"\bcase[ \t\f\v\r\n]+{re.escape(expression)}[ \t\f\v\r\n]*:"
            rf"(?P<body>.*?)(?=\bcase\b|\bdefault\b|\Z)",
            body,
            re.DOTALL,
        )
        if selected_case and re.search(r"\b(?:return|throw)\b", selected_case.group("body")):
            reject()


def task7_control_body_kinds(code: str, name: str) -> dict[int, str]:
    openings: dict[int, str] = {}
    for keyword in (
        "if", "else", "guard", "while", "for", "switch",
        "do", "catch", "repeat", "defer",
    ):
        for match in re.finditer(rf"\b{keyword}\b", code):
            if match.start() > 0 and code[match.start() - 1] == "#":
                continue
            try:
                opening = task5_control_body_opening(
                    code,
                    match.start(),
                    keyword,
                    name,
                )
            except ValueError:
                continue
            openings.setdefault(opening, keyword)
    return openings


def task7_control_body_openings(code: str, name: str) -> set[int]:
    return set(task7_control_body_kinds(code, name))


def task7_method_owned_code(code: str, name: str) -> str:
    """Blank every nested closure/function/type body, retaining method-owned control flow."""
    control_openings = task7_control_body_openings(code, name)
    pairs: dict[int, int] = {}
    stack: list[int] = []
    for index, character in enumerate(code):
        if character == "{":
            stack.append(index)
        elif character == "}":
            if not stack:
                raise ValueError(f"Task 7 test {name} has an unmatched closing brace")
            pairs[stack.pop()] = index
    if stack:
        raise ValueError(f"Task 7 test {name} has an incomplete nested body")

    owned = list(code)
    excluded_until = -1
    for opening in sorted(pairs):
        if opening < excluded_until:
            continue
        if opening in control_openings:
            continue
        closing = pairs[opening]
        task5_blank_range(owned, opening, closing + 1)
        excluded_until = closing + 1
    return "".join(owned)


def task7_constant_boolean(condition: str) -> bool | None:
    selected = task5_constant_boolean(condition)
    if selected is not None:
        return selected
    compact = re.sub(r"[\s()]", "", condition)
    comparison = re.fullmatch(r"(-?[0-9]+)(==|!=|<=|>=|<|>)(-?[0-9]+)", compact)
    if comparison is None:
        return None
    lhs = int(comparison.group(1))
    rhs = int(comparison.group(3))
    return {
        "==": lhs == rhs,
        "!=": lhs != rhs,
        "<=": lhs <= rhs,
        ">=": lhs >= rhs,
        "<": lhs < rhs,
        ">": lhs > rhs,
    }[comparison.group(2)]


def task7_is_statically_empty_iteration(clause: str) -> bool:
    match = re.search(r"\bin\b(?P<expression>.*)\Z", clause, re.DOTALL)
    if match is None:
        return False
    expression = re.sub(r"\s", "", match.group("expression"))
    while expression.startswith("(") and expression.endswith(")"):
        expression = expression[1:-1]
    if expression == "[]":
        return True
    if re.fullmatch(
        r"(?:Array<[^<>{}()\[\]]+>|\[[^\[\]{}()]+\])\(\)",
        expression,
    ):
        return True
    stride = re.fullmatch(
        r"stride\(from:(-?[0-9]+),to:(-?[0-9]+),by:(-?[0-9]+)\)",
        expression,
    )
    if stride is not None:
        start, end, step = (int(stride.group(index)) for index in (1, 2, 3))
        if step > 0:
            return start >= end
        if step < 0:
            return start <= end
        return False
    half_open = re.fullmatch(r"(-?[0-9]+)\.\.<(-?[0-9]+)", expression)
    if half_open is not None:
        return int(half_open.group(1)) >= int(half_open.group(2))
    closed = re.fullmatch(r"(-?[0-9]+)\.\.\.(-?[0-9]+)", expression)
    return closed is not None and int(closed.group(1)) > int(closed.group(2))


def task7_is_statically_nil_switch_expression(expression: str) -> bool:
    compact = re.sub(r"[\s()]", "", expression)
    nil_source = r"(?:nil|Optional(?:<[^<>]+>)?\.none)"
    if re.fullmatch(nil_source, compact):
        return True
    optional_target = (
        r"(?:[A-Za-z_][A-Za-z0-9_.]*(?:<[^<>]+>)?\?"
        r"|\[[^\[\]<>]+\]\?"
        r"|Optional<[^<>]+>)"
    )
    return re.fullmatch(
        rf"{nil_source}as{optional_target}",
        compact,
    ) is not None


def task7_has_reachable_outer_loop_break(code: str, name: str) -> bool:
    """A break owned by a nested loop/switch cannot terminate the outer while."""
    reachable = task5_code_with_unreachable_constant_branches_removed(code, name)
    kinds = task7_control_body_kinds(reachable, name)
    pairs: dict[int, int] = {}
    stack: list[int] = []
    for index, character in enumerate(reachable):
        if character == "{":
            stack.append(index)
        elif character == "}":
            if not stack:
                raise ValueError(f"Task 7 test {name} has an unmatched closing brace")
            pairs[stack.pop()] = index
    if stack:
        raise ValueError(f"Task 7 test {name} has an incomplete nested body")

    outer_owned = list(reachable)
    excluded_until = -1
    for opening in sorted(pairs):
        if opening < excluded_until:
            continue
        if kinds.get(opening) not in {"while", "for", "repeat", "switch"}:
            continue
        closing = pairs[opening]
        task5_blank_range(outer_owned, opening, closing + 1)
        excluded_until = closing + 1
    return re.search(r"\bbreak\b", "".join(outer_owned)) is not None


def task7_reject_method_owned_bypasses(code: str, path: Path, name: str) -> None:
    def reject(detail: str) -> None:
        raise ValueError(
            f"Task 7 test {path.name}.{name} must retain reachable direct behavior "
            f"without {detail}"
        )

    terminal = re.search(r"\b(?:return|throw)\b", code)
    if terminal is not None:
        reject("method-owned early return or throw")

    repeat_condition_positions: set[int] = set()
    for match in re.finditer(r"\brepeat\b", code):
        try:
            opening = task5_control_body_opening(code, match.start(), "repeat", name)
            closing = balanced_brace_end(
                code,
                opening,
                f"Task 7 repeat statement in {name}",
            )
        except ValueError:
            continue
        condition_start = task5_skip_swift_space(code, closing + 1)
        if task5_swift_keyword_at(code, condition_start, "while"):
            repeat_condition_positions.add(condition_start)
            condition = code[condition_start + len("while") :]
            line_end = condition.find("\n")
            if line_end != -1:
                condition = condition[:line_end]
            if task7_constant_boolean(condition) is not None:
                reject("constant repeat control")

    for keyword in ("if", "guard", "while"):
        for match in re.finditer(rf"\b{keyword}\b", code):
            if keyword == "while" and match.start() in repeat_condition_positions:
                continue
            try:
                opening = task5_control_body_opening(
                    code,
                    match.start(),
                    keyword,
                    name,
                )
                closing = balanced_brace_end(
                    code,
                    opening,
                    f"Task 7 {keyword} statement in {name}",
                )
            except ValueError:
                continue
            condition = code[match.end() : opening]
            if keyword == "guard":
                condition = re.sub(r"\belse[ \t\f\v\r\n]*$", "", condition)
            selected = task7_constant_boolean(condition)
            if keyword in {"if", "guard"} and selected is not None:
                reject(f"constant {keyword} control")
            if keyword == "while" and selected is False:
                reject("constant-unreachable while control")
            if keyword == "while" and selected is True:
                body = code[opening + 1 : closing]
                if not task7_has_reachable_outer_loop_break(body, name):
                    reject("unbounded constant while control")

    for match in re.finditer(r"\bfor\b", code):
        try:
            opening = task5_control_body_opening(
                code,
                match.start(),
                "for",
                name,
            )
        except ValueError:
            continue
        if task7_is_statically_empty_iteration(code[match.end() : opening]):
            reject("constant-unreachable for control")

    for match in re.finditer(r"\bdo\b", code):
        try:
            opening = task5_control_body_opening(
                code,
                match.start(),
                "do",
                name,
            )
            closing = balanced_brace_end(
                code,
                opening,
                f"Task 7 do statement in {name}",
            )
        except ValueError:
            continue
        catch_start = task5_skip_swift_space(code, closing + 1)
        if not task5_swift_keyword_at(code, catch_start, "catch"):
            continue
        do_body = task7_method_owned_code(code[opening + 1 : closing], name)
        can_reach_catch = re.search(r"\bthrow\b", do_body) is not None or re.search(
            r"\btry\b(?![ \t\f\v\r\n]*[?!])",
            do_body,
        ) is not None
        if not can_reach_catch:
            reject("statically unreachable catch control")

    for match in re.finditer(r"\bswitch\b", code):
        try:
            opening = task5_control_body_opening(code, match.start(), "switch", name)
        except ValueError:
            continue
        raw_expression = code[match.end() : opening]
        expression = re.sub(r"[\s()]", "", raw_expression)
        if re.fullmatch(
            r"(?:true|false|-?[0-9]+)", expression
        ) or task7_is_statically_nil_switch_expression(raw_expression):
            reject("constant switch control")


def task7_reachable_direct_method_body(method: str, path: Path, name: str) -> str:
    lexical = task5_code_without_escaped_identifiers(method, name)
    if re.search(
        r"#(?:if|elseif|else|endif)\b",
        lexical,
    ):
        raise ValueError(
            f"Task 7 test {path.name}.{name} must retain reachable direct behavior "
            "without conditional compilation"
        )
    if re.search(r"\bXCTSkip(?:If|Unless)?\s*\(", lexical):
        raise ValueError(
            f"Task 7 test {path.name}.{name} must retain reachable direct behavior "
            "without XCTest skips"
        )
    if re.search(r"\bXCTExpectFailure\s*\(", lexical):
        raise ValueError(
            f"Task 7 test {path.name}.{name} must retain reachable direct behavior "
            "without expected-failure suppression"
        )

    method_owned = task7_method_owned_code(lexical, name)
    task7_reject_method_owned_bypasses(method_owned, path, name)
    reachable = task5_code_with_unreachable_constant_branches_removed(method_owned, name)
    if reachable != method_owned:
        raise ValueError(
            f"Task 7 test {path.name}.{name} must retain reachable direct behavior "
            "without constant-unreachable conditionals"
        )
    return reachable


def verify_task7_test_contracts(
    root: Path,
    enforce_test_asset_digests: bool = True,
) -> None:
    expected_test_sources = set(TASK7_TEST_SUITES)
    if set(TASK7_TEST_ASSET_SHA256) != expected_test_sources:
        raise ValueError("Task 7 operational test digest inventory is incomplete")
    if set(TASK7_TRUSTED_CANONICAL_TEST_SOURCE_SHA256) != expected_test_sources:
        raise ValueError("Task 7 trusted canonical test source inventory is incomplete")
    for relative, (suite, main_actor, expected_methods, production_token) in TASK7_TEST_SUITES.items():
        path = root / relative
        if not path.is_file():
            raise ValueError(f"Task 7 test contract is missing: {relative}")
        source = path.read_text(encoding="utf-8")
        methods = swift_xctest_suite_methods(source, suite, main_actor)
        if set(methods) != expected_methods:
            raise ValueError(f"Task 7 {suite} must retain every exact behavior test")
        reachable_methods: list[str] = []
        for name, body in methods.items():
            reachable = task7_reachable_direct_method_body(body, path, name)
            reachable_methods.append(reachable)
            if not re.search(r"\bXCTAssert[A-Za-z0-9_]*\s*\(", reachable):
                raise ValueError(
                    f"Task 7 test {suite}.{name} must assert real production behavior "
                    "with reachable direct behavior"
                )
        if not any(
            re.search(rf"\b{re.escape(production_token)}\s*\(", body)
            for body in reachable_methods
        ):
            raise ValueError(f"Task 7 {suite} must exercise {production_token}")
    if enforce_test_asset_digests:
        for relative in TASK7_TEST_SUITES:
            actual_digest = hashlib.sha256((root / relative).read_bytes()).hexdigest()
            if TASK7_TEST_ASSET_SHA256.get(relative) != actual_digest:
                raise ValueError(f"Task 7 test asset digest mismatch: {relative}")
            if (
                TASK7_TRUSTED_CANONICAL_TEST_SOURCE_SHA256.get(relative)
                != actual_digest
            ):
                raise ValueError(
                    f"Task 7 trusted canonical test source mismatch: {relative}"
                )


def verify_task7_assets(root: Path) -> None:
    verify_task7_test_contracts(root)
    missing = [relative for relative in TASK7_PRODUCTION_PATHS if not (root / relative).is_file()]
    if missing:
        raise ValueError(f"Task 7 production contracts are missing: {missing}")

    sources = {
        relative: (root / relative).read_text(encoding="utf-8")
        for relative in TASK7_PRODUCTION_PATHS
    }
    forbidden_imports = {"SwiftData", "PersistenceKit", "CoreModels", "ProgressPhotosKit"}
    for relative, source in sources.items():
        forbidden = swift_imported_modules(source) & forbidden_imports
        if forbidden:
            raise ValueError(
                f"Task 7 ReportsKit export must remain persistence and photo-module neutral: "
                f"{relative}: {sorted(forbidden)}"
            )

    required_tokens = {
        TASK7_PRODUCTION_PATHS[0]: (
            "schemaVersion", "selectedModules", "primaryTimestamp", "cells",
            "sortedKeys", "withoutEscapingSlashes", "CanonicalExportScalarV1",
        ),
        TASK7_PRODUCTION_PATHS[1]: ("0xedb88320", "Accumulator", "checksum"),
        TASK7_PRODUCTION_PATHS[2]: (
            "0x0808", "0x0021", "0x08074b50", "Task.checkCancellation",
            "FileHandle", "zip32LimitExceeded", "destinationExists", ".partial",
            "O_NOFOLLOW", "Darwin.fstat", "createAnonymousFile",
            "ReportExportDescriptorIO.clone", "acquireNamespaceLease",
            "applyPublishedFileSecurity",
        ),
        TASK7_PRODUCTION_PATHS[3]: (
            "schemaVersion", "includesPhotos", "sha256", "byteSize", "relativePath",
            "included", "missing", "corrupt",
        ),
        TASK7_PRODUCTION_PATHS[4]: (
            "openat", "mkdirat", "fstatat", "unlinkat", "renameatx_np",
            "fclonefileat", "O_NOFOLLOW", "createAnonymousFile",
            "cleanupDescriptorAllocation", "recoverDescriptorAllocation",
            "F_SETPROTECTIONCLASS", "fsetxattr", "UF_APPEND", "UF_IMMUTABLE",
            "F_GETPROTECTIONCLASS", "ReportExportDarwinProtectionClass.complete.rawValue",
            "st_nlink", "RENAME_EXCL", "ReportExportNamespaceAuthority",
            "ReportExportRootNamespaceRegistry", "originalFlags", "maximumEntries",
            "maximumAttempts",
        ),
        TASK7_PRODUCTION_PATHS[5]: (
            "photosRequireZIP", "fetchExportSnapshot", "json/export.json",
            "csv/", "manifest.json", "photos/", ".allocation-id",
            "applyCompleteFileProtection", "excludeFromBackup", "cleanup",
            "ReportExportArtifactWorker", "ReportExportFileIdentity", "cleanupID",
            "validateCurrentOwnership", "ReportExportLifecycleWorker",
            "maximumRetryAttempts", "terminalRecovery",
            "reserve(cleanupID:", "maximumRecoveryRecords",
        ),
        TASK7_PRODUCTION_PATHS[6]: (
            "@Observable", "400_000_000", "activeGenerationID", "progressTask",
            "shareDidFinish", "viewDidDisappear", "includesPhotos = false",
        ),
        TASK7_PRODUCTION_PATHS[7]: (
            "ForEach(ExportModuleV1.allCases", "reports.export.photos",
            "reports.export.action", "accessibilityIdentifier",
        ),
    }
    for relative, tokens in required_tokens.items():
        code = sources[relative]
        if any(token not in code for token in tokens):
            raise ValueError(f"Task 7 production contract is incomplete: {relative}")

    coordinator_code = swift_code_without_comments_and_literals(sources[TASK7_PRODUCTION_PATHS[5]])
    if any(private in coordinator_code for private in ("imageRef", "image_ref", "progress_photo_note")):
        raise ValueError("Task 7 coordinator must never inspect private photo references or notes")
    if "pendingCleanupTokens" in sources[TASK7_PRODUCTION_PATHS[6]]:
        raise ValueError("Task 7 ViewModel must hand failed cleanup to the bounded registry")

    localization_path = root / "Packages/HealthTrackingModules/Sources/ReportsKit/Resources/Localizable.xcstrings"
    try:
        localization = json.loads(localization_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError("Task 7 localization catalog must remain valid JSON") from error
    strings = localization.get("strings", {})
    missing_keys = sorted(TASK7_LOCALIZATION_KEYS - set(strings))
    if missing_keys:
        raise ValueError(f"Task 7 Turkish localization keys are missing: {missing_keys}")
    for key in TASK7_LOCALIZATION_KEYS:
        value = (
            strings.get(key, {}).get("localizations", {}).get("tr", {})
            .get("stringUnit", {}).get("value")
        )
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"Task 7 localization must provide non-empty Turkish text: {key}")

    if TASK7_PRODUCTION_ASSET_SHA256:
        if set(TASK7_PRODUCTION_ASSET_SHA256) != set(TASK7_PRODUCTION_PATHS):
            raise ValueError("Task 7 production digest inventory must bind every owned source")
        for relative in TASK7_PRODUCTION_PATHS:
            actual_digest = hashlib.sha256((root / relative).read_bytes()).hexdigest()
            if TASK7_PRODUCTION_ASSET_SHA256[relative] != actual_digest:
                raise ValueError(f"Task 7 production asset digest mismatch: {relative}")


def task7_real_asset_self_test(source_root: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="m4-task7-real-assets-") as directory:
        fixture = Path(directory)
        for relative in TASK7_TEST_SUITES:
            destination = fixture / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_root / relative, destination)
        verify_task7_test_contracts(fixture)

        localization_relative = (
            "Packages/HealthTrackingModules/Sources/ReportsKit/Resources/Localizable.xcstrings"
        )
        for relative in (*TASK7_PRODUCTION_PATHS, localization_relative):
            destination = fixture / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_root / relative, destination)
        verify_task7_assets(fixture)

        production_tokens = {
            TASK7_PRODUCTION_PATHS[0]: (".withoutEscapingSlashes",),
            TASK7_PRODUCTION_PATHS[1]: ("0xedb88320",),
            TASK7_PRODUCTION_PATHS[2]: (
                "0x08074b50", "O_NOFOLLOW", "createAnonymousFile",
                "ReportExportDescriptorIO.clone", "acquireNamespaceLease",
            ),
            TASK7_PRODUCTION_PATHS[3]: ("case corrupt",),
            TASK7_PRODUCTION_PATHS[4]: (
                "fclonefileat", "cleanupDescriptorAllocation", "openat",
                "F_SETPROTECTIONCLASS", "F_GETPROTECTIONCLASS",
                "ReportExportDarwinProtectionClass.complete.rawValue",
                "fsetxattr", "UF_APPEND", "UF_IMMUTABLE",
                "st_nlink", "renameatx_np", "RENAME_EXCL",
                "ReportExportRootNamespaceRegistry", "originalFlags", "maximumEntries",
            ),
            TASK7_PRODUCTION_PATHS[5]: (
                '".allocation-id"', "ReportExportArtifactWorker",
                "ReportExportFileIdentity", "cleanupID", "reserve(cleanupID:",
            ),
            TASK7_PRODUCTION_PATHS[6]: ("400_000_000",),
            TASK7_PRODUCTION_PATHS[7]: ("ForEach(ExportModuleV1.allCases",),
        }
        for relative, tokens in production_tokens.items():
            path = fixture / relative
            original = path.read_text(encoding="utf-8")
            for token in tokens:
                if token not in original:
                    raise SystemExit(f"Task 7 production mutation source is missing: {token}")
                path.write_text(original.replace(token, "removedTask7Token"), encoding="utf-8")
                try:
                    verify_task7_assets(fixture)
                except ValueError as error:
                    if "Task 7 production contract is incomplete" not in str(error):
                        raise SystemExit(f"Task 7 production-token mutation failed incorrectly: {error}") from error
                else:
                    raise SystemExit("Task 7 production-token mutation escaped")
                path.write_text(original, encoding="utf-8")

        coordinator = fixture / TASK7_PRODUCTION_PATHS[5]
        original_coordinator = coordinator.read_text(encoding="utf-8")
        coordinator.write_text(original_coordinator + "\nimport ProgressPhotosKit\n", encoding="utf-8")
        try:
            verify_task7_assets(fixture)
        except ValueError as error:
            if "persistence and photo-module neutral" not in str(error):
                raise SystemExit(f"Task 7 import mutation failed incorrectly: {error}") from error
        else:
            raise SystemExit("Task 7 import mutation escaped")
        coordinator.write_text(original_coordinator, encoding="utf-8")

        localization_path = fixture / localization_relative
        original_localization = localization_path.read_text(encoding="utf-8")
        localization = json.loads(original_localization)
        del localization["strings"][sorted(TASK7_LOCALIZATION_KEYS)[0]]
        localization_path.write_text(json.dumps(localization), encoding="utf-8")
        try:
            verify_task7_assets(fixture)
        except ValueError as error:
            if "Turkish localization keys are missing" not in str(error):
                raise SystemExit(f"Task 7 localization mutation failed incorrectly: {error}") from error
        else:
            raise SystemExit("Task 7 localization mutation escaped")
        localization_path.write_text(original_localization, encoding="utf-8")

        for relative in TASK7_PRODUCTION_PATHS:
            path = fixture / relative
            original = path.read_text(encoding="utf-8")
            path.write_text(original + "\nprivate let task7DigestMutation = true\n", encoding="utf-8")
            try:
                verify_task7_assets(fixture)
            except ValueError as error:
                if "Task 7 production asset digest mismatch" not in str(error):
                    raise SystemExit(f"Task 7 production-digest mutation failed incorrectly: {error}") from error
            else:
                raise SystemExit("Task 7 production-digest mutation escaped")
            path.write_text(original, encoding="utf-8")

        verify_task7_assets(fixture)

        for relative in TASK7_TEST_SUITES:
            path = fixture / relative
            original = path.read_text(encoding="utf-8")
            path.unlink()
            try:
                verify_task7_test_contracts(fixture)
            except ValueError as error:
                if "Task 7 test contract is missing" not in str(error):
                    raise SystemExit(f"Task 7 missing-test mutation failed incorrectly: {error}") from error
            else:
                raise SystemExit("Task 7 missing-test mutation escaped")
            path.write_text(original, encoding="utf-8")

        for relative, (_, _, methods, production_token) in TASK7_TEST_SUITES.items():
            path = fixture / relative
            original = path.read_text(encoding="utf-8")
            method = sorted(methods)[0]

            escaped_rebound_wrappers: list[str] = []
            for label, prefix, suffix in (
                (
                    "empty array whole-method wrapper",
                    "\n        for _ in [] {\n",
                    "\n        }\n",
                ),
                (
                    "empty range whole-method wrapper",
                    "\n        for _ in 0..<0 {\n",
                    "\n        }\n",
                ),
                (
                    "empty generic Array whole-method wrapper",
                    "\n        for _ in Array<Int>() {\n",
                    "\n        }\n",
                ),
                (
                    "empty bracket Array whole-method wrapper",
                    "\n        for _ in [Int]() {\n",
                    "\n        }\n",
                ),
                (
                    "empty Swift.Array whole-method wrapper",
                    "\n        for _ in Swift.Array<Int>() {\n",
                    "\n        }\n",
                ),
                (
                    "empty Array.init whole-method wrapper",
                    "\n        for _ in Array<Int>.init() {\n",
                    "\n        }\n",
                ),
                (
                    "empty bracket Array.init whole-method wrapper",
                    "\n        for _ in [Int].init() {\n",
                    "\n        }\n",
                ),
                (
                    "empty ContiguousArray whole-method wrapper",
                    "\n        for _ in ContiguousArray<Int>() {\n",
                    "\n        }\n",
                ),
                (
                    "reachable collection whole-method wrapper",
                    "\n        for _ in Swift.Array<Int>([0]) {\n",
                    "\n        }\n",
                ),
                (
                    "top-level dummy assertion plus dead whole-method wrapper",
                    "\n        XCTAssertTrue(true)\n"
                    "        for _ in Swift.Array<Int>() {\n",
                    "\n        }\n",
                ),
                (
                    "empty literal stride whole-method wrapper",
                    "\n        for _ in stride(from: 0, to: 0, by: 1) {\n",
                    "\n        }\n",
                ),
                (
                    "empty reverse literal stride whole-method wrapper",
                    "\n        for _ in stride(from: 0, to: 1, by: -1) {\n",
                    "\n        }\n",
                ),
                (
                    "empty inclusive literal stride whole-method wrapper",
                    "\n        for _ in stride(from: 0, through: -1, by: 1) {\n",
                    "\n        }\n",
                ),
                (
                    "nonthrowing do-catch whole-method wrapper",
                    "\n        do { XCTAssertTrue(true) } catch {\n",
                    "\n        }\n",
                ),
                (
                    "try-optional do-catch whole-method wrapper",
                    "\n        do { try? Task.checkCancellation() } catch {\n",
                    "\n        }\n",
                ),
                (
                    "try-forced do-catch whole-method wrapper",
                    "\n        do { try! Task.checkCancellation() } catch {\n",
                    "\n        }\n",
                ),
                (
                    "constant optional switch whole-method wrapper",
                    "\n        switch Optional<Int>.none {\n        case .some:\n",
                    "\n        case .none:\n            break\n        }\n",
                ),
                (
                    "cast optional-none switch whole-method wrapper",
                    "\n        switch Optional<Int>.none as Int? {\n        case .some:\n",
                    "\n        case .none:\n            break\n        }\n",
                ),
                (
                    "cast nil switch whole-method wrapper",
                    "\n        switch nil as Int? {\n        case .some:\n",
                    "\n        case .none:\n            break\n        }\n",
                ),
                (
                    "Optional-cast optional-none switch whole-method wrapper",
                    "\n        switch Optional<Int>.none as Optional<Int> {\n        case .some:\n",
                    "\n        case .none:\n            break\n        }\n",
                ),
                (
                    "Optional-cast nil switch whole-method wrapper",
                    "\n        switch nil as Optional<Int> {\n        case .some:\n",
                    "\n        case .none:\n            break\n        }\n",
                ),
                (
                    "Swift.Optional-none switch whole-method wrapper",
                    "\n        switch Swift.Optional<Int>.none as Int? {\n        case .some:\n",
                    "\n        case .none:\n            break\n        }\n",
                ),
                (
                    "inferred optional-none switch whole-method wrapper",
                    "\n        switch .none as Int? {\n        case .some:\n",
                    "\n        case .none:\n            break\n        }\n",
                ),
                (
                    "nil-literal initializer switch whole-method wrapper",
                    "\n        switch Optional<Int>.init(nilLiteral: ()) {\n        case .some:\n",
                    "\n        case .none:\n            break\n        }\n",
                ),
            ):
                mutated = wrap_named_test_body(original, method, prefix, suffix)
                path.write_text(mutated, encoding="utf-8")
                canonical_digest = TASK7_TEST_ASSET_SHA256[relative]
                TASK7_TEST_ASSET_SHA256[relative] = hashlib.sha256(
                    path.read_bytes()
                ).hexdigest()
                try:
                    verify_task7_test_contracts(fixture)
                except ValueError as error:
                    if not any(
                        expected in str(error)
                        for expected in (
                            "reachable direct behavior",
                            "trusted canonical test source mismatch",
                        )
                    ):
                        raise SystemExit(
                            f"Task 7 rebound-digest {label} mutation failed incorrectly: {error}"
                        ) from error
                else:
                    escaped_rebound_wrappers.append(label)
                finally:
                    TASK7_TEST_ASSET_SHA256[relative] = canonical_digest
                    path.write_text(original, encoding="utf-8")
            structural_spoof_method = (
                "testDescriptorDirectoryEnumerationDoesNotAdvanceTheCallersCleanupCursor"
            )
            if structural_spoof_method in methods:
                for label, prefix, suffix in (
                    (
                        "matching dummy assertions plus dead whole-method wrapper",
                        "\n        XCTAssertEqual(1, 1)\n"
                        "        XCTAssertEqual(2, 2)\n"
                        "        for _ in Swift.Array<Int>() {\n",
                        "\n        }\n",
                    ),
                    (
                        "inactive platform compilation whole-method wrapper",
                        "\n        #if os(Windows)\n",
                        "\n        #endif\n",
                    ),
                    (
                        "missing-module compilation whole-method wrapper",
                        "\n        #if canImport(Task7DefinitelyMissingModule)\n",
                        "\n        #endif\n",
                    ),
                ):
                    mutated = wrap_named_test_body(
                        original,
                        structural_spoof_method,
                        prefix,
                        suffix,
                    )
                    path.write_text(mutated, encoding="utf-8")
                    canonical_digest = TASK7_TEST_ASSET_SHA256[relative]
                    TASK7_TEST_ASSET_SHA256[relative] = hashlib.sha256(
                        path.read_bytes()
                    ).hexdigest()
                    try:
                        verify_task7_test_contracts(fixture)
                    except ValueError as error:
                        if not any(
                            expected in str(error)
                            for expected in (
                                "reachable direct behavior",
                                "trusted canonical test source mismatch",
                            )
                        ):
                            raise SystemExit(
                                f"Task 7 rebound-digest {label} mutation failed "
                                f"incorrectly: {error}"
                            ) from error
                    else:
                        escaped_rebound_wrappers.append(label)
                    finally:
                        TASK7_TEST_ASSET_SHA256[relative] = canonical_digest
                        path.write_text(original, encoding="utf-8")
            if escaped_rebound_wrappers:
                raise SystemExit(
                    "Task 7 rebound-digest mutations escaped: "
                    + ", ".join(escaped_rebound_wrappers)
                )

            method_start_for_control = original.index(f"func {method}")
            method_opening_for_control = original.index(
                "{",
                method_start_for_control,
            )
            for label, inserted_control in (
                (
                    "reachable Swift.Array control",
                    "\n        var task7ReachableCount = 0\n"
                    "        for _ in Swift.Array<Int>([0]) {\n"
                    "            task7ReachableCount += 1\n"
                    "        }\n"
                    "        _ = task7ReachableCount\n",
                ),
                (
                    "reachable forward literal stride control",
                    "\n        var task7ReachableCount = 0\n"
                    "        for _ in stride(from: 0, to: 1, by: 1) {\n"
                    "            task7ReachableCount += 1\n"
                    "        }\n"
                    "        _ = task7ReachableCount\n",
                ),
                (
                    "reachable reverse literal stride control",
                    "\n        var task7ReachableCount = 0\n"
                    "        for _ in stride(from: 1, to: 0, by: -1) {\n"
                    "            task7ReachableCount += 1\n"
                    "        }\n"
                    "        _ = task7ReachableCount\n",
                ),
                (
                    "reachable inclusive literal stride control",
                    "\n        var task7ReachableCount = 0\n"
                    "        for _ in stride(from: 0, through: 0, by: 1) {\n"
                    "            task7ReachableCount += 1\n"
                    "        }\n"
                    "        _ = task7ReachableCount\n",
                ),
                (
                    "reachable optional switch control",
                    "\n        var task7ReachableValue = -1\n"
                    "        switch Swift.Optional<Int>.some(0) {\n"
                    "        case let .some(value):\n"
                    "            task7ReachableValue = value\n"
                    "        case .none:\n"
                    "            task7ReachableValue = 1\n"
                    "        }\n"
                    "        _ = task7ReachableValue\n",
                ),
            ):
                mutated = (
                    original[: method_opening_for_control + 1]
                    + inserted_control
                    + original[method_opening_for_control + 1 :]
                )
                path.write_text(mutated, encoding="utf-8")
                try:
                    verify_task7_test_contracts(
                        fixture,
                        enforce_test_asset_digests=False,
                    )
                except ValueError as error:
                    raise SystemExit(
                        f"Task 7 reachable {label} mutation was falsely rejected: {error}"
                    ) from error
                finally:
                    path.write_text(original, encoding="utf-8")

            path.write_text(original.replace(f"func {method}", f"func removed{method}", 1), encoding="utf-8")
            try:
                verify_task7_test_contracts(fixture, enforce_test_asset_digests=False)
            except ValueError as error:
                if "retain every exact behavior test" not in str(error):
                    raise SystemExit(f"Task 7 behavior mutation failed incorrectly: {error}") from error
            else:
                raise SystemExit("Task 7 behavior mutation escaped")
            path.write_text(original, encoding="utf-8")

            method_start = original.index(f"func {method}")
            method_opening = original.index("{", method_start)
            for label, inserted in (
                ("XCTSkip", "\n        throw XCTSkip()\n"),
                ("XCTExpectFailure", "\n        XCTExpectFailure()\n"),
                ("direct return", "\n        return\n"),
                ("direct throw", "\n        throw CancellationError()\n"),
                ("dead conditional", "\n        if false { XCTAssertTrue(true) }\n"),
                ("constant true return", "\n        if true { return }\n"),
                ("unconditional do return", "\n        do { return }\n"),
                ("constant while return", "\n        while true { return }\n"),
                ("constant guard return", "\n        guard false else { return }\n"),
                ("repeat return", "\n        repeat { return } while false\n"),
                (
                    "constant switch return",
                    "\n        switch true { case true: return; case false: break }\n",
                ),
                ("nested if do return", "\n        if true { do { return } }\n"),
                ("nested do if return", "\n        do { if true { return } }\n"),
                ("constant equality return", "\n        if 1 == 1 { return }\n"),
                ("single iteration for return", "\n        for _ in [0] { return }\n"),
                ("constant switch default return", "\n        switch true { default: return }\n"),
                (
                    "nested repeat guard return",
                    "\n        do { repeat { guard false else { return } } while false }\n",
                ),
                (
                    "nested switch break does not exit infinite while",
                    "\n        while true {\n"
                    "            switch Bool.random() { default: break }\n"
                    "        }\n",
                ),
            ):
                mutated = original[: method_opening + 1] + inserted + original[method_opening + 1 :]
                path.write_text(mutated, encoding="utf-8")
                try:
                    verify_task7_test_contracts(fixture, enforce_test_asset_digests=False)
                except ValueError as error:
                    if "reachable direct behavior" not in str(error):
                        raise SystemExit(
                            f"Task 7 {label} mutation failed incorrectly: {error}"
                        ) from error
                else:
                    raise SystemExit(f"Task 7 {label} mutation escaped")

            method_code = swift_code_without_comments_and_literals(original)
            declaration = method_code.index(f"func {method}")
            opening = method_code.index("{", declaration)
            closing = balanced_brace_end(method_code, opening, f"Task 7 self-test {method}")
            for label, replacement in (
                (
                    "unused assertion closure",
                    "\n        let hiddenBehavior = {\n"
                    f"            _ = {production_token}()\n"
                    "            XCTAssertTrue(true)\n"
                    "        }\n",
                ),
                (
                    "unused local assertion function",
                    "\n        func hiddenBehavior() {\n"
                    f"            _ = {production_token}()\n"
                    "            XCTAssertTrue(true)\n"
                    "        }\n",
                ),
                (
                    "unused anonymous assertion closure array",
                    "\n        let hiddenBehaviors = [{\n"
                    f"            _ = {production_token}()\n"
                    "            XCTAssertTrue(true)\n"
                    "        }]\n"
                    "        _ = hiddenBehaviors.count\n",
                ),
                (
                    "discarded anonymous assertion closure array",
                    "\n        _ = [{\n"
                    f"            _ = {production_token}()\n"
                    "            XCTAssertTrue(true)\n"
                    "        }]\n",
                ),
                (
                    "bare unused anonymous assertion closure array",
                    "\n        [{\n"
                    f"            _ = {production_token}()\n"
                    "            XCTAssertTrue(true)\n"
                    "        }]\n",
                ),
            ):
                mutated = original[: opening + 1] + replacement + original[closing:]
                path.write_text(mutated, encoding="utf-8")
                try:
                    verify_task7_test_contracts(fixture, enforce_test_asset_digests=False)
                except ValueError as error:
                    if "reachable direct behavior" not in str(error):
                        raise SystemExit(
                            f"Task 7 {label} mutation failed incorrectly: {error}"
                        ) from error
                else:
                    raise SystemExit(f"Task 7 {label} mutation escaped")
            path.write_text(original, encoding="utf-8")

            reachable_loop = (
                original[: method_opening + 1]
                + "\n        var task7LoopReached = false\n"
                + "        while true {\n"
                + "            task7LoopReached = true\n"
                + "            break\n"
                + "        }\n"
                + "        _ = task7LoopReached\n"
                + original[method_opening + 1 :]
            )
            path.write_text(reachable_loop, encoding="utf-8")
            try:
                verify_task7_test_contracts(fixture, enforce_test_asset_digests=False)
            except ValueError as error:
                raise SystemExit(
                    f"Task 7 reachable while-break mutation was falsely rejected: {error}"
                ) from error
            path.write_text(original, encoding="utf-8")

            path.write_text(
                re.sub(
                    rf"\b{re.escape(production_token)}(?=\s*\()",
                    "RemovedProductionToken",
                    original,
                ),
                encoding="utf-8",
            )
            try:
                verify_task7_test_contracts(fixture, enforce_test_asset_digests=False)
            except ValueError as error:
                if f"must exercise {production_token}" not in str(error):
                    raise SystemExit(f"Task 7 production-token mutation failed incorrectly: {error}") from error
            else:
                raise SystemExit("Task 7 production-token mutation escaped")
            path.write_text(original + "\n// Task 7 copied-real digest mutation.\n", encoding="utf-8")
            try:
                verify_task7_test_contracts(fixture)
            except ValueError as error:
                if "Task 7 test asset digest mismatch" not in str(error):
                    raise SystemExit(f"Task 7 digest mutation failed incorrectly: {error}") from error
            else:
                raise SystemExit("Task 7 digest mutation escaped")
            path.write_text(original, encoding="utf-8")

        trusted_source_escape_mutations: list[
            tuple[str, str, str]
        ] = []

        zip_relative = (
            "Packages/HealthTrackingModules/Tests/ReportsKitTests/"
            "StoredZIPWriterTests.swift"
        )
        zip_path = fixture / zip_relative
        zip_original = zip_path.read_text(encoding="utf-8")
        spoof_method = (
            "testRejectsSourceSymlinkDirectoryDestinationSymlinkAndDestinationAliasingInput"
        )
        zip_code = swift_code_without_comments_and_literals(zip_original)
        spoof_declaration = zip_code.index(f"func {spoof_method}")
        spoof_opening = zip_code.index("{", spoof_declaration)
        spoof_closing = balanced_brace_end(
            zip_code,
            spoof_opening,
            f"Task 7 trusted-source self-test {spoof_method}",
        )
        spoof_method_body = zip_original[spoof_opening + 1 : spoof_closing]
        regular_data_literal = 'Data("regular".utf8)'
        if spoof_method_body.count(regular_data_literal) != 2:
            raise SystemExit(
                "Task 7 trusted-source literal mutation must bind exact source and "
                "expectation occurrences"
            )
        literal_mutation = (
            zip_original[: spoof_opening + 1]
            + spoof_method_body.replace(
                regular_data_literal,
                'Data("different".utf8)',
            )
            + zip_original[spoof_closing:]
        )
        trusted_source_escape_mutations.append((
            "behavior-changing passing string literal contract",
            zip_relative,
            literal_mutation,
        ))

        escaped_spoof_body = (
            spoof_method_body
            .replace("XCTAssertFalse", "`XCTAssertFalse`")
            .replace("XCTAssertEqual", "`XCTAssertEqual`")
        )
        spoof_prefix = (
            '\n        let source = try source("regular.txt", '
            'bytes: Data("regular".utf8))\n'
            "        for _ in [0] {\n"
            '            let output = temporaryDirectory.appendingPathComponent('
            '"never-created.zip")\n'
            "            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))\n"
            "        }\n"
            '        XCTAssertEqual(try Data(contentsOf: source), Data("regular".utf8))\n'
            "        for _ in Swift.Array<Int>() {\n"
        )
        copied_witness_mutation = (
            zip_original[: spoof_opening + 1]
            + spoof_prefix
            + escaped_spoof_body
            + "\n        }\n"
            + zip_original[spoof_closing:]
        )
        trusted_source_escape_mutations.append((
            "copied witnesses plus escaped real assertions",
            zip_relative,
            copied_witness_mutation,
        ))

        json_relative = (
            "Packages/HealthTrackingModules/Tests/ReportsKitTests/"
            "JSONExportEncoderTests.swift"
        )
        json_path = fixture / json_relative
        json_original = json_path.read_text(encoding="utf-8")
        signature_mutation = json_original.replace(
            "    func testEncodesExactVersionedNativeShapeAndCanonicalScalars",
            "    static func testEncodesExactVersionedNativeShapeAndCanonicalScalars",
            1,
        )
        trusted_source_escape_mutations.append((
            "static XCTest discovery signature",
            json_relative,
            signature_mutation,
        ))

        escaped_trusted_source_mutations: list[str] = []
        for label, relative, mutated in trusted_source_escape_mutations:
            path = fixture / relative
            original = path.read_text(encoding="utf-8")
            path.write_text(mutated, encoding="utf-8")
            operational_digest = TASK7_TEST_ASSET_SHA256[relative]
            TASK7_TEST_ASSET_SHA256[relative] = hashlib.sha256(
                path.read_bytes()
            ).hexdigest()
            try:
                verify_task7_test_contracts(fixture)
            except ValueError as error:
                if "trusted canonical test source mismatch" not in str(error):
                    raise SystemExit(
                        f"Task 7 trusted-source {label} mutation failed incorrectly: "
                        f"{error}"
                    ) from error
            else:
                escaped_trusted_source_mutations.append(label)
            finally:
                TASK7_TEST_ASSET_SHA256[relative] = operational_digest
                path.write_text(original, encoding="utf-8")
        if escaped_trusted_source_mutations:
            raise SystemExit(
                "Task 7 trusted canonical source mutations escaped: "
                + ", ".join(escaped_trusted_source_mutations)
            )

        verify_task7_test_contracts(fixture)


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


def replace_nth_once(path: Path, before: str, after: str, occurrence: int) -> str:
    original = path.read_text(encoding="utf-8")
    cursor = 0
    start = -1
    for _ in range(occurrence):
        start = original.find(before, cursor)
        if start == -1:
            raise SystemExit(
                f"M4 focused CI self-test mutation source occurrence "
                f"{occurrence} is missing: {before}"
            )
        cursor = start + len(before)
    mutated = original[:start] + after + original[start + len(before) :]
    path.write_text(mutated, encoding="utf-8")
    return original


def fixture_workflow() -> str:
    run = "\n".join("          " + line for line in ROUTED_RUN.splitlines())
    device_run = "\n".join(
        "          " + line for line in TASK7_DEVICE_BUILD_RUN.splitlines()
    )
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
      - name: Compile Task 7 device filesystem branch
        if: {TASK7_DEVICE_BUILD_GUARD}
        run: |
{device_run}
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
            ("-destination 'generic/platform=iOS'", "-destination 'platform=iOS Simulator'", "exact Task 7 device-only branch"),
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
    reports_architecture_self_test(root)
    task3_real_asset_self_test(root)
    task4_real_asset_self_test(root)
    task5_real_asset_self_test(root)
    task6_real_asset_self_test(root)
    task7_real_asset_self_test(root)
    print("M4 focused CI verifier self-tests passed.")
elif mode == "":
    verify(root)
    verify_reports_architecture(root)
    verify_task5_assets(root)
    verify_task6_assets(root)
    verify_task7_assets(root)
    print("M4 reports verification passed.")
else:
    raise SystemExit("Usage: scripts/verify-m4-reports.sh [--self-test]")
PY
