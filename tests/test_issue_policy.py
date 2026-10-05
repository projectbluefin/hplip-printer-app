"""Keep updater changes compatible with the released lifecycle and native CI."""

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class IssuePolicyTests(unittest.TestCase):
    def test_canonical_caller_and_narrow_pinning_exception(self):
        content = (ROOT / ".github/workflows/issue-lifecycle.yml").read_text()
        self.assertIn(
            "projectbluefin/actions/.github/workflows/reusable-issue-lifecycle.yml@v1",
            content,
        )
        rules = json.loads((ROOT / "renovate.json").read_text())["packageRules"]
        rule = rules[-1]
        self.assertEqual(rule["matchManagers"], ["github-actions"])
        self.assertEqual(rule["matchFileNames"], [".github/workflows/issue-lifecycle.yml"])
        self.assertEqual(rule["matchPackageNames"], ["projectbluefin/actions"])
        self.assertIs(rule["pinDigests"], False)
        runner_rule = next(r for r in rules if r.get("matchDatasources") == ["github-runners"])
        self.assertEqual(runner_rule["matchPackageNames"], ["ubuntu"])
        self.assertEqual(runner_rule["allowedVersions"], r"/^24\.04(?:-arm)?$/")


if __name__ == "__main__":
    unittest.main()
