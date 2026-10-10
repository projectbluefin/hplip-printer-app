"""Keep updater changes compatible with native CI."""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class RenovateTests(unittest.TestCase):
    def test_ubuntu_runner_compatibility_limit(self):
        rules = json.loads((ROOT / "renovate.json").read_text())["packageRules"]
        runner_rule = next(r for r in rules if r.get("matchDatasources") == ["github-runners"])
        self.assertEqual(runner_rule["matchPackageNames"], ["ubuntu"])
        self.assertEqual(runner_rule["allowedVersions"], r"/^24\.04(?:-arm)?$/")

    def test_fsdk_containers_bump_is_automatic(self):
        config = json.loads((ROOT / "renovate.json").read_text())
        self.assertIn("custom.regex", config["enabledManagers"])
        url = "https://github.com/projectbluefin/fsdk-containers"
        manager = next(m for m in config["customManagers"] if m.get("depNameTemplate") == url)
        self.assertEqual(manager["datasourceTemplate"], "git-refs")
        pattern = manager["matchStrings"][0].replace("(?<", "(?P<")
        match = re.search(pattern, (ROOT / "elements/fsdk-containers.bst").read_text())
        self.assertEqual(match["currentValue"], "main")
        self.assertRegex(match["currentDigest"], r"^[0-9a-f]{40}$")
        rule = next(r for r in config["packageRules"] if r.get("matchDepNames") == [url])
        self.assertTrue(rule["automerge"])
        # A bare ref bump must be complete: no committed FSDK labels to resync.
        oci = (ROOT / "elements/oci/hplip-printer-app.bst").read_text()
        self.assertNotIn("io.projectbluefin.fsdk", oci)


if __name__ == "__main__":
    unittest.main()
