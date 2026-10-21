"""Keep the CI BuildStream cache inputs in step with the element sources.

bst-cache.yml seeds the BuildStream cache under a key hashed from the
repository files the build reads; fsdk-ci.yml and registry-actions.yml restore
it with the same hash and restore-keys narrowed to that exact prefix. The file
list is written out by hand in each workflow, so a new local source added to an
element but missed in one workflow either leaves the key unchanged when that
file changes or splits producer and consumer keys so the seeded cache is never
hit.
"""

import fnmatch
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"
CACHE_WORKFLOWS = ("bst-cache.yml", "fsdk-ci.yml", "registry-actions.yml")
# Inputs that change the seed run but are not build sources.
SEED_ONLY_PATHS = {"ci/buildstream.conf", ".github/workflows/bst-cache.yml"}


def hash_inputs(workflow):
    text = (WORKFLOWS / workflow).read_text()
    match = re.search(r"INPUTS_HASH:\s*\$\{\{\s*hashFiles\((.*?)\)\s*\}\}", text)
    if match is None:
        raise AssertionError(f"{workflow}: no INPUTS_HASH hashFiles(...) found")
    return re.findall(r"'([^']+)'", match[1])


def seed_push_paths():
    text = (WORKFLOWS / "bst-cache.yml").read_text()
    block = re.search(r"^  push:\n(?:    .*\n)*?    paths:\n((?:      - .*\n)+)", text, re.M)
    if block is None:
        raise AssertionError("bst-cache.yml: no on.push.paths filter found")
    return [line.split("- ", 1)[1].strip() for line in block[1].splitlines()]


def local_sources():
    paths = set()
    for element in (ROOT / "elements").rglob("*.bst"):
        for path in re.findall(r"^\s+path:\s*(\S+)\s*$", element.read_text(), re.M):
            if (ROOT / path).exists():
                paths.add(path)
    return paths


def covered(path, patterns):
    for pattern in patterns:
        if pattern.endswith("/**"):
            if path == pattern[:-3] or path.startswith(pattern[:-2]):
                return True
        elif fnmatch.fnmatchcase(path, pattern):
            return True
    return False


class BuildInputsTests(unittest.TestCase):
    def test_cache_workflows_hash_the_same_inputs(self):
        lists = {workflow: hash_inputs(workflow) for workflow in CACHE_WORKFLOWS}
        reference = lists[CACHE_WORKFLOWS[0]]
        for workflow, inputs in lists.items():
            self.assertEqual(inputs, reference, f"{workflow} hashFiles differs from {CACHE_WORKFLOWS[0]}")

    def test_every_local_source_is_hashed(self):
        sources = local_sources()
        self.assertIn("Makefile", sources)
        inputs = hash_inputs(CACHE_WORKFLOWS[0])
        missing = sorted(path for path in sources if not covered(path, inputs))
        self.assertEqual(missing, [], "element local sources missing from INPUTS_HASH hashFiles")

    def test_seed_runs_when_a_hashed_input_changes(self):
        self.assertEqual(
            set(seed_push_paths()) - SEED_ONLY_PATHS,
            set(hash_inputs("bst-cache.yml")),
            "bst-cache.yml on.push.paths must list exactly the hashFiles inputs plus seed-only files",
        )

    def test_covered_matches_globs_and_exact_paths(self):
        self.assertTrue(covered("files/container-entrypoint.sh", ["files/**"]))
        self.assertTrue(covered("files", ["files/**"]))
        self.assertTrue(covered("VERSION", ["VERSION"]))
        self.assertFalse(covered("filesystem.c", ["files/**"]))
        self.assertFalse(covered("hplip-new.c", ["hplip-printer-app.c"]))


if __name__ == "__main__":
    unittest.main()
