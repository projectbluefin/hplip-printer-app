#!/usr/bin/env python3
"""Execute promote-stable.yml's fast-forward gate against fixture repos.

The promote job moves `stable`, the only branch whose version tags publish
immutable OCI releases. Its "Fast-forward stable only from verified testing
HEAD" step must push only the exact commit the verify job rebuilt, only while
that commit is still the tip of `testing`, and only as a fast-forward of
`stable`. The step runs only on a manual dispatch, so this test lifts its run
block out of the workflow verbatim and runs it in throwaway git repositories:
a change to the gate is tested as written, with no copy to drift from it.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/promote-stable.yml"
STEP_NAME = "Fast-forward stable only from verified testing HEAD"
TOKEN = "fixture-token-0123456789"


def step_script(workflow, step_name):
    """Return the dedented `run: |` body of the named step."""
    lines = workflow.read_text().splitlines()
    starts = [i for i, line in enumerate(lines)
              if re.fullmatch(rf"\s*- name: {re.escape(step_name)}", line)]
    if len(starts) != 1:
        raise ValueError(f"expected one step named {step_name!r} in {workflow}")
    step_indent = len(lines[starts[0]]) - len(lines[starts[0]].lstrip())
    run_at = None
    for i in range(starts[0] + 1, len(lines)):
        line = lines[i]
        indent = len(line) - len(line.lstrip())
        if line.strip() and indent <= step_indent:
            break
        if re.fullmatch(r"\s*run: \|", line):
            run_at = i
            break
    if run_at is None:
        raise ValueError(f"step {step_name!r} has no `run: |` block")
    run_indent = len(lines[run_at]) - len(lines[run_at].lstrip())
    body = []
    for line in lines[run_at + 1:]:
        if line.strip() and len(line) - len(line.lstrip()) <= run_indent:
            break
        body.append(line)
    while body and not body[-1].strip():
        body.pop()
    block_indent = min(len(l) - len(l.lstrip()) for l in body if l.strip())
    return "\n".join(l[block_indent:] for l in body) + "\n"


def git(cwd, *args):
    return subprocess.run(
        ["git", "-c", "user.name=test", "-c", "user.email=test@example.invalid",
         "-c", "init.defaultBranch=testing", "-c", "commit.gpgsign=false",
         "-c", "init.templateDir=", *args],
        cwd=cwd, check=True, capture_output=True, text=True,
        env={**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"},
    ).stdout.strip()


class PromoteStableGate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = step_script(WORKFLOW, STEP_NAME)

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="promote-stable-gate."))
        self.addCleanup(shutil.rmtree, self.tmp)
        self.origin = self.tmp / "origin.git"
        self.seed = self.tmp / "seed"
        git(self.tmp, "init", "--quiet", "--bare", str(self.origin))
        git(self.tmp, "init", "--quiet", str(self.seed))
        git(self.seed, "remote", "add", "origin", str(self.origin))
        self.released = self.commit("released")
        git(self.seed, "push", "--quiet", "origin",
            "HEAD:refs/heads/stable", "HEAD:refs/heads/testing")
        self.candidate = self.commit("verified on testing")
        self.push_testing()

    def commit(self, message):
        git(self.seed, "commit", "--quiet", "--allow-empty", "-m", message)
        return git(self.seed, "rev-parse", "HEAD")

    def push_testing(self):
        git(self.seed, "push", "--quiet", "--force", "origin", "HEAD:refs/heads/testing")

    def origin_ref(self, branch):
        return git(self.tmp, "--git-dir", str(self.origin), "rev-parse", f"refs/heads/{branch}")

    def checkout(self, sha):
        """Mirror actions/checkout with `ref: <sha>` and `fetch-depth: 0`."""
        work = self.tmp / "work"
        if work.exists():
            shutil.rmtree(work)
        git(self.tmp, "clone", "--quiet", "--no-checkout", str(self.origin), str(work))
        git(work, "checkout", "--quiet", "--detach", sha)
        return work

    def run_gate(self, work, candidate):
        env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.tmp),
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
            "CANDIDATE": candidate,
            "GH_TOKEN": TOKEN,
        }
        return subprocess.run(["bash", "-c", self.script], cwd=work, env=env,
                              capture_output=True, text=True)

    def assert_promoted(self, result, sha):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.origin_ref("stable"), sha)

    def assert_refused(self, result, stable_before):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.origin_ref("stable"), stable_before,
                         "a refused promotion must leave stable where it was")

    def test_testing_head_fast_forwards_stable(self):
        work = self.checkout(self.candidate)
        self.assert_promoted(self.run_gate(work, self.candidate), self.candidate)
        self.assertEqual(self.origin_ref("testing"), self.candidate)

    def test_several_commits_ahead_fast_forward_in_one_push(self):
        self.commit("second")
        head = self.commit("third")
        self.push_testing()
        work = self.checkout(head)
        self.assert_promoted(self.run_gate(work, head), head)

    def test_candidate_already_on_stable_is_a_no_op(self):
        git(self.seed, "push", "--quiet", "origin", f"{self.candidate}:refs/heads/stable")
        work = self.checkout(self.candidate)
        self.assert_promoted(self.run_gate(work, self.candidate), self.candidate)

    def test_candidate_must_be_a_full_lowercase_sha(self):
        work = self.checkout(self.candidate)
        for candidate in ("", self.candidate[:7], self.candidate[:39],
                          self.candidate + "0", self.candidate.upper(),
                          "testing", "HEAD", f" {self.candidate}"):
            with self.subTest(candidate=candidate):
                self.assert_refused(self.run_gate(work, candidate), self.released)

    def test_checked_out_commit_must_be_the_candidate(self):
        work = self.checkout(self.released)
        self.assert_refused(self.run_gate(work, self.candidate), self.released)

    def test_candidate_no_longer_testing_tip_is_refused(self):
        # testing moved after the verify job checked the candidate out; the
        # gate must re-fetch rather than trust the clone's tracking ref.
        work = self.checkout(self.candidate)
        self.commit("landed on testing during verification")
        self.push_testing()
        self.assertEqual(git(work, "rev-parse", "origin/testing"), self.candidate)
        self.assert_refused(self.run_gate(work, self.candidate), self.released)

    def test_older_testing_commit_is_refused(self):
        work = self.checkout(self.released)
        git(self.seed, "push", "--quiet", "origin", f"{self.released}:refs/heads/stable")
        self.assert_refused(self.run_gate(work, self.released), self.released)

    def test_rewound_testing_is_refused(self):
        # testing force-pushed back past the candidate after checkout.
        work = self.checkout(self.candidate)
        git(self.seed, "push", "--quiet", "--force", "origin",
            f"{self.released}:refs/heads/testing")
        self.assert_refused(self.run_gate(work, self.candidate), self.released)

    def test_commit_not_on_testing_is_refused(self):
        git(self.seed, "checkout", "--quiet", "--detach", self.released)
        stray = self.commit("never reached testing")
        git(self.seed, "push", "--quiet", "origin", f"{stray}:refs/heads/scratch")
        work = self.checkout(stray)
        self.assert_refused(self.run_gate(work, stray), self.released)

    def test_diverged_stable_is_never_rewritten(self):
        git(self.seed, "checkout", "--quiet", "--detach", self.released)
        hotfix = self.commit("hotfix pushed straight to stable")
        git(self.seed, "push", "--quiet", "origin", f"{hotfix}:refs/heads/stable")
        work = self.checkout(self.candidate)
        self.assert_refused(self.run_gate(work, self.candidate), hotfix)

    def test_token_is_never_persisted_or_printed(self):
        work = self.checkout(self.candidate)
        result = self.run_gate(work, self.candidate)
        self.assert_promoted(result, self.candidate)
        self.assertNotIn(TOKEN, result.stdout + result.stderr)
        config = (work / ".git/config").read_text()
        self.assertNotIn("extraheader", config)
        self.assertNotIn("AUTHORIZATION", config)


if __name__ == "__main__":
    unittest.main()
