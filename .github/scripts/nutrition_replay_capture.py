"""Temporary, fail-closed correlation of unchanged XCTest repetitions and app logs."""
from collections import Counter
from datetime import datetime, timedelta, timezone
import json
import math
from pathlib import Path
import re
import subprocess
import sys


CASE = "-[HealthTrackingAppUITests.NutritionQuickAddUITests testCategoryRecipeAndDefaultConfirmAreExactlyThreeTapsAndPersistAfterRelaunch]"
PREFIX_CASES = [
    "-[HealthTrackingAppUITests.NutritionDayUITests testContentExposesCalendarNavigationTotalsStableCategoriesAndVoiceOverOrder]",
    "-[HealthTrackingAppUITests.NutritionDayUITests testDarkAX5ReduceMotionAndIncreaseContrastProduceCanonicalEvidence]",
    "-[HealthTrackingAppUITests.NutritionDayUITests testDeleteFailureRollsBackAndRetryPublishesRepositoryTotals]",
    "-[HealthTrackingAppUITests.NutritionDayUITests testEmptyAndRecoverableErrorStatesRemainDistinctAndRetrySameDay]",
    CASE,
]


def parse_iterations(console, case=CASE):
    iterations = []
    active = None
    for line in console.splitlines():
        started = re.fullmatch(re.escape(f"Test Case '{case}' started")
                               + r"(?: \(Iteration ([1-9][0-9]*) of ([1-9][0-9]*)\))?\.", line.strip())
        if started:
            if active is not None:
                raise ValueError("Overlapping or duplicate case start")
            active = {"launches": [], "terminations": []}
            if started[1]:
                ordinal, limit = int(started[1]), int(started[2])
                if ordinal != len(iterations) + 1 or ordinal > limit:
                    raise ValueError("Missing or out-of-order native iteration")
                if iterations and iterations[0].get("nativeLimit") != limit:
                    raise ValueError("Mixed repetition limits or header formats")
                active.update(nativeIteration=ordinal, nativeLimit=limit)
            elif iterations and "nativeIteration" in iterations[0]:
                raise ValueError("Missing native repetition ordinal")
        elif active is not None and "Start Test at " in line:
            if "start" in active:
                raise ValueError("Duplicate case timestamp")
            # Workflow explicitly runs in UTC; retain that provenance with the artifact.
            start = datetime.fromisoformat(line.split("Start Test at ", 1)[1].strip())
            active["start"] = start.replace(tzinfo=timezone.utc) if start.tzinfo is None else start.astimezone(timezone.utc)
        elif active is not None and re.search(r"t =\s*[0-9.]+s\s+Launch com\.fatihzxc\.HealthTrackingApp$", line):
            active["launches"].append(float(re.search(r"t =\s*([0-9.]+)s", line)[1]))
        elif active is not None and "Terminate com.fatihzxc.HealthTrackingApp:" in line:
            match = re.search(r"t =\s*([0-9.]+)s\s+Terminate com\.fatihzxc\.HealthTrackingApp:(\d+)$", line)
            if not match:
                raise ValueError("Unrecognized application termination marker")
            active["terminations"].append({"offset": float(match[1]), "pid": int(match[2])})
        elif active is not None and "Requesting snapshot of accessibility hierarchy for app with pid " in line:
            active["snapshotProcessID"] = int(line.rsplit(" ", 1)[1])
        elif line.startswith(f"Test Case '{case}' "):
            match = re.fullmatch(re.escape(f"Test Case '{case}' ") + r"(passed|failed) \(([0-9.]+) seconds\)\.", line)
            if not match or active is None or "start" not in active:
                raise ValueError("Unmatched result or missing case timestamp")
            active["outcome"] = match[1]
            active["duration"] = float(match[2])
            active["end"] = active["start"] + timedelta(seconds=active["duration"])
            if iterations and active["start"] < iterations[-1]["end"]:
                raise ValueError("Overlapping iteration windows")
            iterations.append(active)
            active = None
    if active is not None or not iterations:
        raise ValueError("Missing or incomplete repetition evidence")
    return iterations


def validate_ordered_prefix(console, records):
    """Validate this one observed invocation, not an arbitrary XCTest schema."""
    markers = re.findall(r"^Test Case '([^']+)' (.*)$", console, re.MULTILINE)
    if len(markers) != 10:
        raise ValueError("Missing, duplicated, or extra ordered-prefix case markers")
    parsed = []
    for index, case in enumerate(PREFIX_CASES):
        start, result = markers[index * 2:index * 2 + 2]
        if start != (case, "started.") or result[0] != case:
            raise ValueError("Unexpected ordered-prefix execution order or overlap")
        attempts = parse_iterations(console, case)
        if len(attempts) != 1:
            raise ValueError("Expected one attempt per ordered-prefix case")
        attempt = attempts[0]
        if parsed and attempt["start"] < parsed[-1]["end"]:
            raise ValueError("Overlapping predecessor/target time windows")
        if index < 4 and attempt["outcome"] != "passed":
            raise ValueError("Failed predecessor: target context is inconclusive")
        parsed.append(attempt)
    runners = list(re.finditer(r"^.*HealthTrackingAppUITests-Runner\[(\d+):\d+\].*Running tests\.\.\.$",
                               console, re.MULTILINE))
    if len(runners) != 1 or runners[0].start() >= console.index("Test Case '"):
        raise ValueError("Missing or multiple observed test-runner starts")
    if len(records) != 5:
        raise ValueError("Expected exactly five native test metadata records")
    references = set()
    for case, attempt in zip(PREFIX_CASES, parsed):
        suite, method = case.removeprefix("-[HealthTrackingAppUITests.").removesuffix("]").split(" ")
        identity = f"test://com.apple.xcode/HealthTrackingApp/HealthTrackingAppUITests/{suite}/{method}"
        matches = [record for record in records if record["identifierURL"]["_value"] == identity]
        if len(matches) != 1:
            raise ValueError("Missing or duplicate native case identity")
        record = matches[0]
        expected = "Success" if attempt["outcome"] == "passed" else "Failure"
        if record["testStatus"]["_value"] != expected:
            raise ValueError("Native/console outcome mismatch")
        duration = float(record["duration"]["_value"])
        if not math.isfinite(duration) or abs(duration - attempt["duration"]) > 0.001:
            raise ValueError("Native/console duration mismatch")
        references.add(record["summaryRef"]["id"]["_value"])
    if len(references) != 5:
        raise ValueError("Native case summary references are not distinct")
    return {"orderedPrefix": "four passing predecessors then target",
            "observedRunnerPID": int(runners[0][1]),
            "targetOutcome": parsed[-1]["outcome"],
            "limitation": "Fresh runner invocation; original full-suite worker history is not reproduced"}


def correlate(iterations, traces, destinations):
    results = []
    for number, iteration in enumerate(iterations, 1):
        grouped = {}
        for event in traces:
            if event["simulator"] not in destinations or "flow=persistent " not in event.get("eventMessage", ""):
                continue
            timestamp = datetime.fromisoformat(re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", event["timestamp"]))
            if timestamp.tzinfo is None:
                raise ValueError("Trace timestamp lacks timezone")
            if iteration["start"] <= timestamp < iteration["end"]:
                key = (event["simulator"], event.get("processID"))
                grouped.setdefault(key, []).append(event)
        proven = [key for key, events in grouped.items() if key[1] is not None and
                  {"begin-entry", "begin-selecting"} <= {
                      event["eventMessage"].split("event=", 1)[-1] for event in events}]
        if len(proven) != 1:
            raise ValueError(f"Iteration {number}: missing or ambiguous positive begin trace")
        simulator, pid = proven[0]
        results.append(dict(iteration=number, **iteration, simulator=simulator, processID=pid,
                            # Retain all matching processes/lifecycles, including any reset evidence.
                            events=[event for events in grouped.values() for event in events]))
    return results


def command_json(command):
    return json.loads(subprocess.check_output(command, text=True))


def correlate_roots(results):
    for result in results:
        pid = result["processID"]
        roots = [event for event in result["events"]
                 if event["simulator"] == result["simulator"]
                 and event["eventMessage"].split("event=", 1)[-1] == "root-appear"]
        if not any(event.get("processID") == pid for event in roots):
            raise ValueError("Missing positive first-process root trace")
        stops = [item["offset"] for item in result["terminations"] if item["pid"] == pid]
        result["relaunchedProcessID"] = None
        if not stops:
            if result["outcome"] == "passed" or len(result["launches"]) != 1:
                raise ValueError("Missing expected relaunch markers")
        else:
            launches = [offset for offset in result["launches"] if offset > stops[0]]
            if len(stops) != 1 or len(launches) != 1:
                raise ValueError("Missing or ambiguous relaunch marker")
            relaunched_at = result["start"] + timedelta(seconds=launches[0])
            candidates = set()
            for event in roots:
                timestamp = datetime.fromisoformat(re.sub(r"([+-]\d{2})(\d{2})$", r"\1:\2", event["timestamp"]))
                if timestamp >= relaunched_at and event.get("processID") not in (None, pid):
                    candidates.add(event["processID"])
            if len(candidates) != 1:
                raise ValueError("Missing or ambiguous relaunched-process root trace")
            result["relaunchedProcessID"] = candidates.pop()
            result["relaunchedAt"] = relaunched_at
        expected_pid = result["relaunchedProcessID"] or pid
        if result.get("snapshotProcessID", expected_pid) != expected_pid:
            raise ValueError("Failure snapshot PID does not match correlated app process")


def main(ordered_prefix=False):
    output = Path(".build/nutrition-replay")
    result_path = ".build/NutritionWarm.xcresult"
    base = ["xcrun", "xcresulttool", "get", "object", "--legacy", "--format", "json", "--path", result_path]
    root = command_json(base)
    (output / "result-root.json").write_text(json.dumps(root, indent=2))
    destinations = set()
    statuses = []
    records = []
    summaries = []

    def metadata(node):
        if isinstance(node, dict):
            if node.get("_type", {}).get("_name") == "ActionTestMetadata":
                statuses.append(node["testStatus"]["_value"].lower())
                records.append(node)
            for value in node.values():
                metadata(value)
        elif isinstance(node, list):
            for value in node:
                metadata(value)

    for action in root["actions"]["_values"]:
        target = action["runDestination"]["targetDeviceRecord"]
        if target["platformRecord"]["identifier"]["_value"] == "com.apple.platform.iphonesimulator":
            destinations.add(target["identifier"]["_value"])
    (output / "test-destinations.json").write_text(json.dumps(sorted(destinations)))
    devices = command_json(["xcrun", "simctl", "list", "devices", "--json"])
    (output / "simulators.json").write_text(json.dumps(devices, indent=2))
    traces = []
    for runtime, candidates in devices["devices"].items():
        for device in candidates:
            simulator = device["udid"]
            if simulator not in destinations:
                continue
            if device.get("state") != "Booted":
                subprocess.run(["xcrun", "simctl", "boot", simulator], check=True)
                subprocess.run(["xcrun", "simctl", "bootstatus", simulator, "-b"], check=True)
            result = subprocess.run([
                "xcrun", "simctl", "spawn", simulator, "log", "show", "--start",
                (output / "start-utc.txt").read_text().strip(), "--style", "json", "--predicate",
                'subsystem == "com.fatihzxc.HealthTrackingApp.NutritionDiagnostic"',
            ], text=True, capture_output=True)
            (output / f"{simulator}-trace.json").write_text(result.stdout)
            (output / f"{simulator}-capture.txt").write_text(
                f"runtime={runtime} simulator={simulator} exit={result.returncode}\n" + result.stderr)
            if not result.returncode:
                traces.extend(dict(event, simulator=simulator) for event in json.loads(result.stdout))
    # Preserve ephemeral app events before interpreting unfamiliar repetition metadata.
    for index, action in enumerate(root["actions"]["_values"]):
        reference = action["actionResult"].get("testsRef")
        if reference:
            summary = command_json(base + ["--id", reference["id"]["_value"]])
            summaries.append(summary)
            (output / f"test-summary-{index}.json").write_text(json.dumps(summary, indent=2))
            metadata(summary)
    iterations = parse_iterations((output / "xcodebuild.log").read_text())
    results = correlate(iterations, traces, destinations)
    (output / "iterations.json").write_text(json.dumps(results, indent=2, default=str))
    correlate_roots(results)
    (output / "iterations.json").write_text(json.dumps(results, indent=2, default=str))
    if ordered_prefix:
        # Raw events, console, bundle and target correlation are already retained.
        # Multiple action/testable destinations cannot establish this ordered context.
        if len(destinations) != 1 or len(root["actions"]["_values"]) != 1 or len(summaries) != 1:
            raise ValueError("Ordered prefix requires one native action/destination/summary")
        plan_runs = summaries[0]["summaries"]["_values"]
        if len(plan_runs) != 1 or len(plan_runs[0]["testableSummaries"]["_values"]) != 1:
            raise ValueError("Ordered prefix requires one native testable run")
        validation = validate_ordered_prefix((output / "xcodebuild.log").read_text(), records)
        validation["simulator"] = next(iter(destinations))
        (output / "validation.json").write_text(json.dumps(validation, indent=2))
        print("One ordered-prefix experiment correlated:", validation, "Not acceptance.")
        return
    expected = Counter("success" if item["outcome"] == "passed" else "failure" for item in iterations)
    (output / "validation.json").write_text(json.dumps({
        "consoleAppCorrelation": "positive for each parsed iteration",
        "bundleIterationCorrelation": "INCONCLUSIVE: controller must verify native repetition schema and test identities",
        "legacyMetadataStatuses": dict(Counter(statuses)),
        "consoleOutcomes": dict(expected),
    }, indent=2))
    # This only detects a mismatch. Equal counters do not prove native per-attempt
    # identity/cardinality; inspect the first repeated bundle before interpreting it.
    if Counter(statuses) != expected:
        raise ValueError(f"xcresult/console iteration mismatch: {dict(Counter(statuses))} != {dict(expected)}")
    outcomes = [item["outcome"] for item in iterations]
    if len(outcomes) > 10 or (len(outcomes) < 10 and outcomes[-1] != "failed") or "failed" in outcomes[:-1]:
        raise ValueError("Repetition count/outcomes do not match bounded stop-on-failure")
    print(f"Console/app correlation for {len(results)} iterations; outcomes={outcomes}. "
          "Native bundle iteration correlation requires controller schema/identity review. Not acceptance.")


if __name__ == "__main__":
    if sys.argv[1:] not in ([], ["--ordered-prefix"]):
        raise SystemExit("Only optional --ordered-prefix is supported")
    main(ordered_prefix=sys.argv[1:] == ["--ordered-prefix"])
