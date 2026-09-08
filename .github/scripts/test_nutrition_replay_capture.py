"""Temporary diagnostic: reject misleading per-iteration telemetry."""
import unittest
from pathlib import Path
import json
import subprocess
from unittest.mock import patch

from nutrition_replay_capture import correlate, correlate_roots, main, parse_iterations


CASE = "-[HealthTrackingAppUITests.NutritionQuickAddUITests testCategoryRecipeAndDefaultConfirmAreExactlyThreeTapsAndPersistAfterRelaunch]"


def iteration(second, outcome="passed"):
    return (f"Test Case '{CASE}' started.\n"
            f"    t = 0.00s Start Test at 2026-09-08 21:17:{second:02d}.000\n"
            f"Test Case '{CASE}' {outcome} (10.000 seconds).\n")


def trace(second, pid=42, event="begin-entry", flow="persistent", simulator="target"):
    return dict(simulator=simulator, processID=pid,
                timestamp=f"2026-09-08 21:17:{second:02d}.000000+0000",
                eventMessage=f"flow={flow} phase=selecting event={event}")


class ReplayCaptureTests(unittest.TestCase):
    def root_result(self, extra=()):
        parsed = parse_iterations(iteration(0))[0]
        return dict(parsed, processID=42, simulator="target", launches=[0.1, 5.0],
                    terminations=[{"offset": 4.0, "pid": 42}],
                    events=[trace(1, event="root-appear")] + list(extra))

    def test_first_process_root_cannot_mask_missing_relaunch_trace(self):
        with self.assertRaises(ValueError):
            correlate_roots([self.root_result()])

    def test_relaunch_root_correlates_without_requiring_selection_event(self):
        result = self.root_result([trace(6, pid=43, event="root-appear")])
        correlate_roots([result])
        self.assertEqual(result["relaunchedProcessID"], 43)

    def test_old_or_ambiguous_root_and_wrong_failure_pid_are_rejected(self):
        variants = [
            self.root_result([trace(3, pid=43, event="root-appear")]),
            self.root_result([trace(6, pid=43, event="root-appear"), trace(7, pid=44, event="root-appear")]),
            dict(self.root_result([trace(6, pid=43, event="root-appear")]), snapshotProcessID=44),
        ]
        for result in variants:
            with self.assertRaises(ValueError):
                correlate_roots([result])

    def test_failure_before_relaunch_needs_only_first_process_root(self):
        result = self.root_result()
        result.update(terminations=[], launches=[0.1], outcome="failed", snapshotProcessID=42)
        correlate_roots([result])
        self.assertIsNone(result["relaunchedProcessID"])

    def test_console_distinguishes_old_app_cleanup_from_test_relaunch(self):
        events = ("    t = 0.04s Launch com.fatihzxc.HealthTrackingApp\n"
                  "    t = 0.04s Terminate com.fatihzxc.HealthTrackingApp:39\n"
                  "    t = 4.00s Terminate com.fatihzxc.HealthTrackingApp:42\n"
                  "    t = 5.00s Launch com.fatihzxc.HealthTrackingApp\n"
                  "    t = 9.00s Requesting snapshot of accessibility hierarchy for app with pid 43\n")
        log = iteration(0).replace(f"Test Case '{CASE}' passed", events + f"Test Case '{CASE}' passed")
        parsed = parse_iterations(log)[0]
        self.assertEqual(parsed["launches"], [0.04, 5.0])
        self.assertEqual(parsed["terminations"], [{"offset": 0.04, "pid": 39}, {"offset": 4.0, "pid": 42}])
        self.assertEqual(parsed["snapshotProcessID"], 43)

    def test_summary_failure_does_not_discard_raw_app_trace(self):
        root = {"actions": {"_values": [{
            "runDestination": {"targetDeviceRecord": {
                "platformRecord": {"identifier": {"_value": "com.apple.platform.iphonesimulator"}},
                "identifier": {"_value": "target"}}},
            "actionResult": {"testsRef": {"id": {"_value": "summary"}}}}]}}
        devices = {"devices": {"iOS": [{"udid": "target", "state": "Booted"}]}}
        def read(command):
            if "--id" in command:
                raise ValueError("Unfamiliar repetition summary")
            return devices if "simctl" in command else root
        written = {}
        def save(path, value):
            written[path.name] = value
        with patch("nutrition_replay_capture.command_json", side_effect=read), \
             patch("nutrition_replay_capture.subprocess.run", return_value=subprocess.CompletedProcess([], 0, json.dumps([trace(1)]), "")), \
             patch.object(Path, "read_text", return_value="2026-09-08 21:17:00+0000"), \
             patch.object(Path, "write_text", autospec=True, side_effect=save):
            with self.assertRaises(ValueError):
                main()
        self.assertIn("target-trace.json", written)
        self.assertEqual(json.loads(written["target-trace.json"])[0]["processID"], 42)

    def test_keeps_failure_and_separate_iteration_windows(self):
        parsed = parse_iterations(iteration(0) + iteration(20, "failed"))
        self.assertEqual([item["outcome"] for item in parsed], ["passed", "failed"])
        self.assertEqual(parsed[1]["end"].isoformat(), "2026-09-08T21:17:30+00:00")

    def test_native_repetition_headers_keep_each_attempt_and_failure(self):
        log = (iteration(0).replace("started.", "started (Iteration 1 of 10).")
               + iteration(20, "failed").replace("started.", "started (Iteration 2 of 10)."))
        parsed = parse_iterations(log)
        self.assertEqual([item["nativeIteration"] for item in parsed], [1, 2])
        self.assertEqual([item["outcome"] for item in parsed], ["passed", "failed"])

    def test_missing_native_attempt_is_not_silently_ignored(self):
        log = (iteration(0).replace("started.", "started (Iteration 1 of 10).")
               + iteration(20).replace("started.", "started (Iteration 3 of 10)."))
        with self.assertRaises(ValueError):
            parse_iterations(log)

    def test_explicit_console_offset_is_normalized_not_overwritten(self):
        parsed = parse_iterations(iteration(0).replace("21:17:00.000", "21:17:00.000+03:00"))
        self.assertEqual(parsed[0]["start"].isoformat(), "2026-09-08T18:17:00+00:00")

    def test_rejects_missing_start_timestamp_and_incomplete_attempt(self):
        for log in ("", f"Test Case '{CASE}' started.\n", iteration(0).split(" passed")[0]):
            with self.assertRaises(ValueError):
                parse_iterations(log)

    def test_rejects_interleaved_attempts(self):
        with self.assertRaises(ValueError):
            parse_iterations(f"Test Case '{CASE}' started.\n" + iteration(0))

    def test_positive_begin_without_action_is_valid_evidence(self):
        result = correlate(parse_iterations(iteration(0)), [trace(1), trace(2, event="begin-selecting")], {"target"})
        self.assertEqual(result[0]["processID"], 42)
        self.assertEqual(len(result[0]["events"]), 2)

    def test_baseline_or_previous_iteration_cannot_mask_missing_replay(self):
        with self.assertRaises(ValueError):
            correlate(parse_iterations(iteration(0) + iteration(20)),
                      [trace(1), trace(2, event="begin-selecting")], {"target"})

    def test_split_pid_unproven_destination_and_transient_are_rejected(self):
        variants = [
            [trace(1), trace(2, pid=43, event="begin-selecting")],
            [trace(1, simulator="other"), trace(2, simulator="other", event="begin-selecting")],
            [trace(1, flow="transient"), trace(2, flow="transient", event="begin-selecting")],
        ]
        for events in variants:
            with self.assertRaises(ValueError):
                correlate(parse_iterations(iteration(0)), events, {"target"})

    def test_two_positive_pids_are_ambiguous(self):
        events = [trace(1), trace(2, event="begin-selecting"),
                  trace(3, pid=43), trace(4, pid=43, event="begin-selecting")]
        with self.assertRaises(ValueError):
            correlate(parse_iterations(iteration(0)), events, {"target"})


if __name__ == "__main__":
    unittest.main()
