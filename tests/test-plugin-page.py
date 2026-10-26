#!/usr/bin/env python3
"""Render the production plugin status panel without PAPPL or a printer."""
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PluginPage(unittest.TestCase):
    def test_install_controls(self):
        source = (ROOT / "hplip-printer-app.c").read_text()
        policy = re.search(r"^#define HPLIP_CAN_INSTALL_PLUGIN .*", source,
                           re.MULTILINE).group()
        # Compile the actual status panel with output-only PAPPL substitutes.
        panel = source.split("// Show plugin status and buttons", 1)[1]
        panel = panel[panel.index("papplClientHTMLPuts"):]
        panel = panel.split("if (plugin_status != HPLIP_PLUGIN_NOT_INSTALLED && licensetext)", 1)[0]
        harness = r'''
#include <stdio.h>
#include <stdlib.h>
static unsigned int test_uid;
#define getuid() test_uid
#define HPLIP_PLUGIN_NOT_INSTALLED 0
#define HPLIP_PLUGIN_INSTALLED 1
#define HPLIP_PLUGIN_OUTDATED 2
#define papplClientHTMLPuts(client, text) fputs(text, stdout)
#define papplClientHTMLPrintf(client, ...) printf(__VA_ARGS__)
#define papplClientGetURI(client) "/plugin"
#define papplClientHTMLStartForm(client, uri, secure) puts("<form>")
'''
        harness += policy + r'''
int main(int argc, char **argv) {
  (void)argc;
  test_uid = (unsigned int)atoi(argv[1]);
  int plugin_status = atoi(argv[2]);
  const char *uri;
'''
        harness += panel + '\n(void)uri;\nreturn 0;\n}\n'
        with tempfile.TemporaryDirectory(prefix="hp-plugin-page-") as temp:
            path = Path(temp)
            (path / "page.c").write_text(harness)
            for oci in (0, 1):
                subprocess.run(shlex.split(os.environ.get("CC", "cc")) + [
                    "-std=c99", "-Wall", "-Wextra", "-Werror",
                    f"-DHPLIP_OCI={oci}", str(path / "page.c"),
                    "-o", str(path / "page"),
                ], check=True)
                for uid in (0, 65532):
                    for status, label in enumerate(("Install Plugin",
                                                    "Re-install Plugin",
                                                    "Update Plugin",
                                                    "Install/Update Plugin")):
                        with self.subTest(oci=oci, uid=uid, status=status):
                            html = subprocess.check_output([
                                str(path / "page"), str(uid), str(status),
                            ], text=True)
                            allowed = bool(oci or uid == 0)
                            self.assertEqual('value="install-plugin"' in html, allowed)
                            self.assertEqual("which can be installed here." in html, allowed)
                            self.assertEqual("hp-plugin</font>" in html,
                                             not allowed and status != 1)
                            if allowed:
                                self.assertIn(f">{label}</button>", html)
                                self.assertEqual('value="remove-plugin"' in html,
                                                 bool(oci and status != 0))


if __name__ == "__main__":
    unittest.main(verbosity=2)
