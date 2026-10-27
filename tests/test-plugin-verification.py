#!/usr/bin/env python3
"""Exercise the production verifier with real GPG, without network downloads.

Optionally supply HP_PLUGIN, HP_PLUGIN_SIGNATURE and HP_SIGNING_KEY to also
verify an official archive offline. Proprietary bytes are never executed.
"""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PIN = "4ABA2F66DBD5A95894910E0673D770CDA59047B9"
# Frozen ("!") so every key is stamped with exactly this time. A ticking fake
# clock restarts in each gpg call, so a slow key generation would otherwise
# leave the key newer than the next signature ("Time conflict").
FAKED_TIME = "1577836800!"


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


class Verification(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="hp-verifier-")
        cls.base = Path(cls.temp.name)
        cls.binary = cls.base / "verify"
        subprocess.run(shlex.split(os.environ.get("CC", "cc")) + [
            "-std=c99", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT),
            str(ROOT / "tests/plugin-verifier.c"),
            str(ROOT / "hplip-plugin-verify.c"), "-o", str(cls.binary),
        ], check=True)
        cls.signer = cls.base / "signer"
        cls.signer.mkdir(mode=0o700)
        cls.gpg = ["gpg", "--no-options", "--homedir", str(cls.signer),
                   "--batch", "--pinentry-mode", "loopback", "--passphrase", ""]
        cls.payload = cls.base / "plugin ' ; touch SHOULD_NOT_EXIST.run"
        cls.payload.write_text("untrusted payload must never be executed\n")
        cls.keys = []
        for name, expiry in [("valid", "0"), ("other", "0"), ("expired", "1d")]:
            run(*cls.gpg, "--faked-system-time", FAKED_TIME,
                "--quick-generate-key", name, "ed25519", "sign", expiry)
            listing = run(*cls.gpg, "--with-colons", "--list-keys", name)
            fingerprint = next(line.split(":")[9] for line in listing.splitlines()
                               if line.startswith("fpr:"))
            key = cls.base / (name + ".asc")
            key.write_text(run(*cls.gpg, "--armor", "--export", fingerprint))
            sig = cls.base / (name + ".sig")
            run(*cls.gpg, "--faked-system-time", FAKED_TIME,
                "--local-user", fingerprint, "--output", str(sig),
                "--detach-sign", str(cls.payload))
            cls.keys.append((fingerprint, key, sig))
        cls.expired_sig = cls.base / "expired-signature.sig"
        run(*cls.gpg, "--faked-system-time", FAKED_TIME,
            "--default-sig-expire", "1d", "--local-user", cls.keys[0][0],
            "--output", str(cls.expired_sig), "--detach-sign", str(cls.payload))

    @classmethod
    def tearDownClass(cls):
        subprocess.run(["gpgconf", "--homedir", str(cls.signer), "--kill", "all"],
                       check=True)
        cls.temp.cleanup()

    def setUp(self):
        self.home = self.base / self._testMethodName

    def verify(self, expected, *, key=None, pin=None, sig=None, payload=None):
        fingerprint, public_key, signature = self.keys[0]
        result = subprocess.run([
            str(self.binary), str(self.home), str(key or public_key),
            pin or fingerprint, str(sig or signature), str(payload or self.payload),
        ], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if expected else 1, result.stderr)

    def test_valid_and_restart(self):
        self.verify(True)
        self.assertEqual(self.home.stat().st_mode & 0o777, 0o700)
        self.verify(True)

    def test_tampered_payload(self):
        altered = self.base / "altered.run"
        altered.write_bytes(self.payload.read_bytes().replace(b"untrusted", b"UNTRUSTED"))
        self.verify(False, payload=altered)

    def test_tampered_signature(self):
        altered = self.base / "altered.sig"
        data = bytearray(self.keys[0][2].read_bytes())
        data[-1] ^= 1
        altered.write_bytes(data)
        self.verify(False, sig=altered)

    def test_wrong_key_in_persistent_keyring(self):
        other_pin, other_key, other_sig = self.keys[1]
        self.verify(True, key=other_key, pin=other_pin, sig=other_sig)
        self.verify(False, sig=other_sig)

    def test_expired_signature_ignores_user_config(self):
        self.home.mkdir(mode=0o700)
        (self.home / "gpg.conf").write_text("faked-system-time 1577836800\n")
        self.verify(False, sig=self.expired_sig)

    def test_expired_key(self):
        pin, key, sig = self.keys[2]
        self.verify(False, key=key, pin=pin, sig=sig)

    def test_missing_key_and_files(self):
        self.verify(False, key=self.base / "missing-key")
        self.verify(False, sig=self.base / "missing-signature")
        self.verify(False, payload=self.base / "missing-payload")

    def test_unsafe_home(self):
        self.home.mkdir(mode=0o755)
        self.verify(False)

    def test_symlink_home(self):
        self.home.symlink_to(self.signer, target_is_directory=True)
        self.verify(False)

    @unittest.skipUnless(os.environ.get("HP_PLUGIN"), "official HP fixture not supplied")
    def test_official_hp_plugin(self):
        args = dict(key=Path(os.environ["HP_SIGNING_KEY"]), pin=PIN,
                    sig=Path(os.environ["HP_PLUGIN_SIGNATURE"]),
                    payload=Path(os.environ["HP_PLUGIN"]))
        self.verify(True, **args)
        self.verify(True, **args)  # persistent keyring / restart
        altered = self.base / "hp-altered.run"
        data = bytearray(args["payload"].read_bytes())
        data[-1] ^= 1
        altered.write_bytes(data)
        self.verify(False, **dict(args, payload=altered))
        altered_sig = self.base / "hp-altered.asc"
        altered_sig.write_text("invalid signature\n")
        self.verify(False, **dict(args, sig=altered_sig))


if __name__ == "__main__":
    unittest.main(verbosity=2)
