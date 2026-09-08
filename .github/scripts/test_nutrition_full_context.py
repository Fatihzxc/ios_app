"""One full-context diagnostic must not masquerade as a passing short prefix."""
import copy
import json
from pathlib import Path
import shlex
import unittest
import yaml

import nutrition_replay_capture as capture
from test_nutrition_ordered_prefix import fixture, METHODS


def full_fixture(target="passed"):
    console, records = fixture(target)
    console = console.replace("passed", "skipped", 1)
    records[0]["testStatus"]["_value"] = "Skipped"
    reference = {"sourceSHA": "f69c305961330e40bc4fc0325e0263435dd1503c", "cases": [
        {"case": f"-[HealthTrackingAppUITests.{suite} {method}]",
         "outcome": "skipped" if index == 0 else "failed" if index == 4 else "passed"}
        for index, (suite, method) in enumerate(METHODS)
    ]}
    return console, records, reference


class FullContextTests(unittest.TestCase):
    def validate(self, *args):
        validator = getattr(capture, "validate_full_context", None)
        self.assertTrue(callable(validator), "Full-context validation is not implemented")
        return validator(*args)

    def test_pass_or_relevant_failure_retains_expected_background_skips(self):
        for outcome in ("passed", "failed"):
            result = self.validate(*full_fixture(outcome))
            self.assertEqual(result["targetOutcome"], outcome)
            self.assertEqual(result["backgroundOutcomeChanges"], [])
            self.assertEqual(result["matchedNativeUICaseCount"], 5)

    def test_different_failure_is_reported_separately(self):
        console, records, reference = full_fixture()
        console = console.replace("passed", "failed", 1)
        records[1]["testStatus"]["_value"] = "Failure"
        result = self.validate(console, records, reference)
        self.assertEqual(len(result["backgroundOutcomeChanges"]), 1)
        self.assertEqual(result["targetOutcome"], "passed")

    def test_missing_extra_reordered_or_multiple_worker_context_is_rejected(self):
        console, records, reference = full_fixture()
        variants = [console.replace(METHODS[0][1], "unknown"),
                    console + console,
                    console.replace("started.", "started (Iteration 1 of 10).", 1),
                    console + console.split("\n", 1)[0] + "\n"]
        for variant in variants:
            with self.assertRaises(ValueError):
                self.validate(variant, records, reference)

    def test_other_test_bundle_metadata_does_not_count_as_ui_context(self):
        console, records, reference = full_fixture()
        other = copy.deepcopy(records[0])
        other["identifierURL"]["_value"] = "test://com.apple.xcode/HealthTrackingApp/CoreModelsTests/Other/testOther"
        self.assertEqual(self.validate(console, records + [other], reference)["matchedNativeUICaseCount"], 5)

    def test_serial_markers_report_estimated_duration_overlap_without_inventing_parallelism(self):
        console, records, reference = full_fixture()
        console = console.replace("(9.000 seconds)", "(10.014 seconds)", 1)
        records[0]["duration"]["_value"] = "10.0141"
        result = self.validate(console, records, reference)
        self.assertEqual(result["estimatedWindowOverlaps"][0]["seconds"], 0.014)
        self.assertEqual(result["targetOutcome"], "passed")

    def test_nonmonotonic_start_times_and_interleaved_markers_are_rejected(self):
        console, records, reference = full_fixture()
        first_result = console.splitlines()[3]
        second_start = console.splitlines()[4]
        interleaved = console.replace(first_result + "\n" + second_start,
                                     second_start + "\n" + first_result)
        for variant in (console.replace("21:17:10.000", "21:17:00.000"), interleaved):
            with self.assertRaises(ValueError):
                self.validate(variant, records, reference)

    def test_reference_is_original_82_case_order_with_target_at_54(self):
        reference = json.loads(Path(".github/scripts/nutrition_full_context_reference.json").read_text())
        self.assertEqual(reference["sourceSHA"], "f69c305961330e40bc4fc0325e0263435dd1503c")
        self.assertEqual(reference["sourceRun"], 34241435577)
        self.assertEqual(len(reference["cases"]), 82)
        self.assertEqual([item["case"] for item in reference["cases"][49:54]], capture.PREFIX_CASES)
        self.assertEqual(sum(item["outcome"] == "skipped" for item in reference["cases"]), 3)

    def test_workflow_preserves_original_full_selection_reset_and_budget(self):
        workflow = yaml.safe_load(Path(".github/workflows/nutrition-diagnostic.yml").read_text())
        steps = workflow["jobs"]["diagnose"]["steps"]
        candidates = [step for step in steps if step.get("name") == "Run one instrumented complete functional suite"]
        self.assertEqual(len(candidates), 1, "Full-context native invocation is not configured")
        run = candidates[0]
        command = "xcodebuild test" + run["run"].split("xcodebuild test", 1)[1]
        argv = shlex.split(command.replace("\\\n", ""))
        self.assertEqual(run["run"].count("xcodebuild test"), 1)
        self.assertFalse(any(item.startswith(("-only-testing", "-test-iterations", "-run-tests", "-retry-tests", "-parallel-testing")) for item in argv))
        self.assertEqual([item for item in argv if item.startswith("-skip-testing")], [
            "-skip-testing:HealthTrackingAppUITests/TodayGuidanceUITests/testColdLaunchPublishesFirstMeaningfulDirectiveWithinOneSecondMedian"])
        self.assertEqual(run["timeout-minutes"], 150)
        self.assertIn("set -euo pipefail", run["run"])
        self.assertIn("scripts/bootstrap.sh", run["run"])
        reset = steps[steps.index(run) - 1]
        production = yaml.safe_load(Path(".github/workflows/ios.yml").read_text())
        original_reset = next(step for step in production["jobs"]["test"]["steps"]
                              if step.get("name") == "Reset selected simulator before complete functional suite")
        self.assertEqual(reset["run"], original_reset["run"])
        self.assertTrue(any(step.get("run") == "python3 .github/scripts/nutrition_replay_capture.py --full-context"
                            and step.get("if", "").startswith("always()") for step in steps))


if __name__ == "__main__":
    unittest.main()
