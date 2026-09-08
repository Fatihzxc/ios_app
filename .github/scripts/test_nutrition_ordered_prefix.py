"""Fail-closed fixtures for the temporary five-case predecessor experiment."""
import copy
from pathlib import Path
import shlex
import unittest
import yaml

import nutrition_replay_capture as capture


METHODS = [
    ("NutritionDayUITests", "testContentExposesCalendarNavigationTotalsStableCategoriesAndVoiceOverOrder"),
    ("NutritionDayUITests", "testDarkAX5ReduceMotionAndIncreaseContrastProduceCanonicalEvidence"),
    ("NutritionDayUITests", "testDeleteFailureRollsBackAndRetryPublishesRepositoryTotals"),
    ("NutritionDayUITests", "testEmptyAndRecoverableErrorStatesRemainDistinctAndRetrySameDay"),
    ("NutritionQuickAddUITests", "testCategoryRecipeAndDefaultConfirmAreExactlyThreeTapsAndPersistAfterRelaunch"),
]


def fixture(target="passed"):
    console = "2026-09-08 21:16:59.000+0000 HealthTrackingAppUITests-Runner[123:456] [Default] Running tests...\n"
    records = []
    for index, (suite, method) in enumerate(METHODS):
        case = f"-[HealthTrackingAppUITests.{suite} {method}]"
        outcome = target if index == 4 else "passed"
        console += (f"Test Case '{case}' started.\n"
                    f"    t = 0.00s Start Test at 2026-09-08 21:17:{index * 10:02d}.000\n"
                    f"Test Case '{case}' {outcome} (9.000 seconds).\n")
        records.append({"identifierURL": {"_value": f"test://com.apple.xcode/HealthTrackingApp/HealthTrackingAppUITests/{suite}/{method}"},
                        "testStatus": {"_value": "Success" if outcome == "passed" else "Failure"},
                        "duration": {"_value": "9.0001"},
                        "summaryRef": {"id": {"_value": f"summary-{index}"}}})
    return console, records


class OrderedPrefixTests(unittest.TestCase):
    def test_workflow_selects_one_exact_prefix_without_native_repetition(self):
        workflow = yaml.safe_load(Path(".github/workflows/nutrition-diagnostic.yml").read_text())
        steps = workflow["jobs"]["diagnose"]["steps"]
        run = next(step for step in steps if step.get("name", "").startswith("Run one unchanged predecessor"))
        # YAML block indentation is stripped; isolate the sole native test command.
        self.assertEqual(run["run"].count("xcodebuild test"), 1)
        command = "xcodebuild test" + run["run"].split("xcodebuild test", 1)[1]
        argv = shlex.split(command.replace("\\\n", ""))
        selectors = [item for item in argv if item.startswith("-only-testing:")]
        self.assertEqual(selectors, [f"-only-testing:HealthTrackingAppUITests/{suite}/{method}" for suite, method in METHODS])
        self.assertFalse(any(item.startswith(("-test-iterations", "-run-tests", "-retry-tests", "-parallel-testing")) for item in argv))
        self.assertIn("set -euo pipefail", run["run"])
        self.assertEqual(run["timeout-minutes"], 25)
        self.assertTrue(any(step.get("run") == "python3 .github/scripts/nutrition_replay_capture.py --ordered-prefix"
                            and step.get("if", "").startswith("always()") for step in steps))

    def validate(self, console, records):
        validator = getattr(capture, "validate_ordered_prefix", None)
        self.assertTrue(callable(validator), "Ordered-prefix validation is not implemented")
        return validator(console, records)

    def test_clean_prefix_and_target_failure_are_both_observable(self):
        for outcome in ("passed", "failed"):
            result = self.validate(*fixture(outcome))
            self.assertEqual(result["targetOutcome"], outcome)
            self.assertEqual(result["observedRunnerPID"], 123)

    def test_wrong_order_missing_case_duplicate_or_overlap_are_inconclusive(self):
        console, records = fixture()
        chunks = console.split("Test Case '")
        variants = [
            console.replace(METHODS[0][1], "TEMP").replace(METHODS[1][1], METHODS[0][1]).replace("TEMP", METHODS[1][1]),
            chunks[0] + "Test Case '" + "Test Case '".join(chunks[3:]),
            console + console,
            console.replace("21:17:10.000", "21:17:05.000"),
        ]
        for variant in variants:
            with self.assertRaises(ValueError):
                self.validate(variant, records)

    def test_predecessor_failure_or_skip_is_not_clean_context(self):
        console, records = fixture()
        for outcome in ("failed", "skipped"):
            with self.assertRaisesRegex(ValueError, "predecessor|result"):
                self.validate(console.replace("passed", outcome, 1), records)

    def test_missing_or_multiple_runner_starts_are_inconclusive(self):
        console, records = fixture()
        for variant in (console.split("\n", 1)[1], console + console.split("\n", 1)[0] + "\n"):
            with self.assertRaises(ValueError):
                self.validate(variant, records)

    def test_native_wrong_identity_outcome_duration_or_shared_reference_is_rejected(self):
        console, records = fixture()
        variants = []
        for key, value in (("identifierURL", {"_value": "other"}),
                           ("testStatus", {"_value": "Failure"}),
                           ("duration", {"_value": "19.0"}),
                           ("duration", {"_value": "NaN"}),
                           ("duration", {"_value": "Infinity"}),
                           ("summaryRef", {"id": {"_value": "summary-1"}})):
            variant = copy.deepcopy(records)
            variant[0][key] = value
            variants.append(variant)
        variants.extend([records[:-1], records + records[:1]])
        for variant in variants:
            with self.assertRaises(ValueError):
                self.validate(console, variant)


if __name__ == "__main__":
    unittest.main()
