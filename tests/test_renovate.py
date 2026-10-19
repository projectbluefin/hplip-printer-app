"""Keep updater changes compatible with native CI."""

import json
import re
import subprocess
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
        pattern = re.compile(manager["matchStrings"][0].replace("(?<", "(?P<"))
        # bst source track writes git-describe refs (project.conf ref-format);
        # Renovate must match both forms and always write a plain sha.
        plain = re.sub(r"ref: \S+-g", "ref: ", (ROOT / "elements/fsdk-containers.bst").read_text())
        new = "0" * 40
        for junction in (plain, plain.replace("ref: ", "ref: v26.08.2-3-g")):
            match = pattern.search(junction)
            self.assertIsNotNone(match, junction)
            self.assertEqual(match["currentValue"], "main")
            self.assertRegex(match["currentDigest"], r"^[0-9a-f]{40}$")
            replaced = manager["autoReplaceStringTemplate"].replace("{{{newValue}}}", "main").replace("{{{newDigest}}}", new)
            self.assertEqual(pattern.search(junction.replace(match[0], replaced))[0], f"track: main\n    ref: {new}")
        rule = next(r for r in config["packageRules"] if r.get("matchDepNames") == [url])
        self.assertLessEqual(
            {"automerge": True, "automergeType": "pr", "platformAutomerge": True, "ignoreTests": False, "minimumReleaseAge": None}.items(),
            rule.items(),
        )
        # A bare ref bump must be complete: no committed FSDK labels to resync.
        oci = (ROOT / "elements/oci/hplip-printer-app.bst").read_text()
        self.assertNotIn("io.projectbluefin.fsdk", oci)

    def test_every_custom_manager_matches_its_files(self):
        # A regex manager that matches nothing is skipped by Renovate without
        # any error, so its dependency silently stops updating.
        config = json.loads((ROOT / "renovate.json").read_text())
        tracked = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.splitlines()
        for manager in config["customManagers"]:
            for file_pattern in manager["managerFilePatterns"]:
                files = [f for f in tracked if re.search(file_pattern.strip("/"), f)]
                self.assertTrue(files, f"{file_pattern} names no file")
                for path in files:
                    text = (ROOT / path).read_text()
                    for match_string in manager["matchStrings"]:
                        self.assertIsNotNone(_compile(match_string).search(text), f"{match_string} matches nothing in {path}")

    def test_version_follows_hplip_source(self):
        config = json.loads((ROOT / "renovate.json").read_text())
        hplip_manager, version_manager = (
            next(m for m in config["customManagers"] if m["managerFilePatterns"] == [pattern])
            for pattern in (r"/^elements\/printer-app\/hplip\.bst$/", "/^VERSION$/")
        )
        self.assertEqual(hplip_manager["depNameTemplate"], version_manager["depNameTemplate"])
        source_tag = _compile(hplip_manager["matchStrings"][0]).search((ROOT / "elements/printer-app/hplip.bst").read_text())["currentValue"]
        upstream = re.fullmatch(version_manager["extractVersionTemplate"].replace("(?<", "(?P<"), source_tag)["version"]
        version = (ROOT / "VERSION").read_text()
        self.assertEqual(_compile(version_manager["matchStrings"][0]).search(version)["currentValue"], upstream)

        # An upstream bump rewrites the whole line, dropping any -N packaging revision.
        pattern = _compile(version_manager["matchStrings"][0])
        for current in ("3.26.4\n", "3.26.4-2\n"):
            bumped = pattern.sub(version_manager["autoReplaceStringTemplate"].replace("{{{newValue}}}", "3.27.0"), current, count=1)
            self.assertEqual(bumped, "3.27.0\n")


def _compile(match_string):
    return re.compile(match_string.replace("(?<", "(?P<"))


if __name__ == "__main__":
    unittest.main()
