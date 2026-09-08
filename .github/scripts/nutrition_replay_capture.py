"""Temporary, fail-closed correlation of unchanged XCTest repetitions and app logs."""
from collections import Counter
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
import subprocess


CASE = "-[HealthTrackingAppUITests.NutritionQuickAddUITests testCategoryRecipeAndDefaultConfirmAreExactlyThreeTapsAndPersistAfterRelaunch]"


def parse_iterations(console):
    iterations = []
    active = None
    for line in console.splitlines():
        if line.strip() == f"Test Case '{CASE}' started.":
            if active is not None:
                raise ValueError("Overlapping or duplicate case start")
            active = {}
        elif active is not None and "Start Test at " in line:
            if "start" in active:
                raise ValueError("Duplicate case timestamp")
            # Workflow explicitly runs in UTC; retain that provenance with the artifact.
            start = datetime.fromisoformat(line.split("Start Test at ", 1)[1].strip())
            active["start"] = start.replace(tzinfo=timezone.utc) if start.tzinfo is None else start.astimezone(timezone.utc)
        elif line.startswith(f"Test Case '{CASE}' "):
            match = re.fullmatch(re.escape(f"Test Case '{CASE}' ") + r"(passed|failed) \(([0-9.]+) seconds\)\.", line)
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


def main():
    output = Path(".build/nutrition-replay")
    result_path = ".build/NutritionWarm.xcresult"
    base = ["xcrun", "xcresulttool", "get", "object", "--legacy", "--format", "json", "--path", result_path]
    root = command_json(base)
    (output / "result-root.json").write_text(json.dumps(root, indent=2))
    destinations = set()
    statuses = []

    def metadata(node):
        if isinstance(node, dict):
            if node.get("_type", {}).get("_name") == "ActionTestMetadata":
                statuses.append(node["testStatus"]["_value"].lower())
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
            (output / f"test-summary-{index}.json").write_text(json.dumps(summary, indent=2))
            metadata(summary)
    iterations = parse_iterations((output / "xcodebuild.log").read_text())
    results = correlate(iterations, traces, destinations)
    (output / "iterations.json").write_text(json.dumps(results, indent=2, default=str))
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
    main()
