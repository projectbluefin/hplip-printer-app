"""Keep the publish job's provenance attestation retried, and still gated.

A transient transparency-log error during attestation failed a publish
(#246). The first attempt may fail; the retry must not, and the image is
tagged only after the verify step has checked the attestation exists.
"""

import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/registry-actions.yml"


def publish_steps():
    return yaml.safe_load(WORKFLOW.read_text())["jobs"]["publish"]["steps"]


def index(steps, predicate, what):
    matches = [i for i, s in enumerate(steps) if predicate(s)]
    if len(matches) != 1:
        raise AssertionError(f"expected exactly one {what} step, found {len(matches)}")
    return matches[0]


class PublishAttestationTests(unittest.TestCase):
    def test_attestation_is_retried_once_on_failure(self):
        steps = publish_steps()
        attests = [i for i, s in enumerate(steps) if s.get("uses", "").startswith("actions/attest@")]
        self.assertEqual(len(attests), 2, "attest once, then retry once")
        first, retry = (steps[i] for i in attests)
        self.assertEqual(first["uses"], retry["uses"])
        self.assertEqual(first["with"], retry["with"])
        self.assertTrue(first.get("continue-on-error"))
        self.assertFalse(retry.get("continue-on-error", False), "the retry must fail the job")
        condition = f"steps.{first['id']}.outcome == 'failure'"
        self.assertEqual(retry.get("if"), condition)
        waits = [s for s in steps[attests[0] + 1:attests[1]] if s.get("if") == condition]
        self.assertEqual(len(waits), 1, "pause between the two attempts")
        self.assertRegex(waits[0]["run"], r"^sleep [1-9][0-9]*$")

    def test_tags_move_only_after_provenance_is_verified(self):
        steps = publish_steps()
        last_attest = max(i for i, s in enumerate(steps) if s.get("uses", "").startswith("actions/attest@"))
        verify = index(steps, lambda s: "gh attestation verify" in s.get("run", ""), "attestation verify")
        tag = index(steps, lambda s: "oras tag" in s.get("run", ""), "tag")
        self.assertLess(last_attest, verify)
        self.assertLess(verify, tag)
        self.assertFalse(steps[verify].get("continue-on-error", False))


if __name__ == "__main__":
    unittest.main()
