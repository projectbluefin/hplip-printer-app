#!/usr/bin/env bash
# Exercise the config and command-output line stripping from hplip-printer-app.c
# without building the OCI image or requiring PAPPL/CUPS.
#
# Regression test for #76:
# - get_config_value() must not index line[-1] on blank LF or CRLF lines.
#
# Also pins how get_config_value() scopes a lookup, since the plugin download
# picks its url/size/checksum from the [<hplip version>] section of HP's
# plugin.conf and the plugin status reads [plugin] from hplip.state:
# - only the requested section is searched, and a section whose name merely
#   starts with the requested one ([3.26.40] for 3.26.4) does not match;
# - a key whose name merely starts with the requested one does not match;
# - a line without "=", an empty value, or an empty key yields NULL.
# - hplip_run_command_line() must not strip the final character from output
#   lacking a trailing newline, and must tolerate empty lines.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/hplip-printer-app.c"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Slice get_config_value from hplip-printer-app.c. A grep miss must reach the
# error below rather than end the script silently under "set -e".
start_line="$(grep -n -E '^get_config_value\(' "$src" | head -n 1 | cut -d: -f1 || true)"
end_line="$(grep -n -E '^hplip_version\(' "$src" | head -n 1 | cut -d: -f1 || true)"
if [ -z "$start_line" ] || [ -z "$end_line" ]; then
    printf 'tests/entrypoint-line-strip.sh: could not locate get_config_value in %s\n' "$src" >&2
    exit 1
fi
start_line=$((start_line - 1))
end_line=$((end_line - 1))
while [ "$end_line" -gt "$start_line" ]; do
    line_content="$(sed -n "${end_line}p" "$src")"
    [ "$line_content" = "}" ] && break
    end_line=$((end_line - 1))
done

if [ "$end_line" -le "$start_line" ]; then
    printf 'tests/entrypoint-line-strip.sh: could not locate get_config_value in %s\n' "$src" >&2
    exit 1
fi

# Slice command line output stripper from hplip_run_command_line
cmd_start="$(grep -n -E '^hplip_run_command_line\(' "$src" | head -n 1 | cut -d: -f1 || true)"
cmd_strip=''
if [ -n "$cmd_start" ]; then
    cmd_strip="$(sed -n "${cmd_start},+30p" "$src" | grep -n "Remove newline" | head -n 1 | cut -d: -f1 || true)"
fi

if [ -z "$cmd_strip" ]; then
    printf 'tests/entrypoint-line-strip.sh: could not locate command output line stripper in %s\n' "$src" >&2
    exit 1
fi
cmd_strip_line=$((cmd_start + cmd_strip - 1))
strip_code="$(sed -n "${cmd_strip_line}p" "$src")"

harness_c="$work/harness.c"
cat << 'C_EOF' > "$harness_c"
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <assert.h>

// Sliced get_config_value() from hplip-printer-app.c:
C_EOF

sed -n "${start_line},${end_line}p" "$src" >> "$harness_c"

cat << C_EOF >> "$harness_c"

// Sliced command-output line stripper from hplip_run_command_line():
static void strip_cmd_output(char *buf) {
  $strip_code
}

static char *lookup(const char *text, const char *section, const char *key) {
  FILE *fp = fmemopen((void *)text, strlen(text), "r");
  if (!fp) exit(2);
  char *v = get_config_value(fp, section, key);
  fclose(fp);
  return v;
}

static int expect(const char *text, const char *section, const char *key,
                  const char *want) {
  char *v = lookup(text, section, key);
  int ok = want ? (v && !strcmp(v, want)) : (v == NULL);
  if (!ok)
    fprintf(stderr, "[%s] %s: expected %s, got %s\n", section ? section : "(null)",
            key ? key : "(null)", want ? want : "NULL", v ? v : "NULL");
  free(v);
  return ok;
}

static const char plugin_conf[] =
  "[3.26.3]\n"
  "url = https://example.invalid/old.run\n"
  "checksum = old\n"
  "\n"
  "[3.26.40]\n"
  "url = https://example.invalid/prefix.run\n"
  "\n"
  "[3.26.4]\n"
  "url_mirror = https://example.invalid/mirror.run\n"
  "url = https://example.invalid/new.run\n"
  "checksum = new\n";

int main(int argc, char **argv) {
  if (argc < 2) return 1;
  const char *test = argv[1];

  if (!strcmp(test, "config-blank-lf")) {
    FILE *fp = fmemopen("[hplip]\n\nversion = 3.26.4\n", 26, "r");
    if (!fp) return 2;
    char *v = get_config_value(fp, "hplip", "version");
    assert(v && !strcmp(v, "3.26.4"));
    free(v);
    fclose(fp);
    return 0;
  }
  if (!strcmp(test, "config-blank-crlf")) {
    FILE *fp = fmemopen("[hplip]\r\n\r\nversion = 3.26.4\r\n", 29, "r");
    if (!fp) return 2;
    char *v = get_config_value(fp, "hplip", "version");
    assert(v && !strcmp(v, "3.26.4"));
    free(v);
    fclose(fp);
    return 0;
  }
  if (!strcmp(test, "cmd-no-trailing-newline")) {
    char buf[1024] = "final-line";
    strip_cmd_output(buf);
    assert(!strcmp(buf, "final-line"));
    return 0;
  }
  if (!strcmp(test, "cmd-trailing-newline")) {
    char buf[1024] = "regular-line\n";
    strip_cmd_output(buf);
    assert(!strcmp(buf, "regular-line"));
    return 0;
  }
  if (!strcmp(test, "cmd-empty-line")) {
    char buf[1024] = "";
    strip_cmd_output(buf);
    assert(!strcmp(buf, ""));
    return 0;
  }
  if (!strcmp(test, "config-section-scope")) {
    int ok = 1;
    ok &= expect(plugin_conf, "3.26.4", "url", "https://example.invalid/new.run");
    ok &= expect(plugin_conf, "3.26.4", "checksum", "new");
    ok &= expect(plugin_conf, "3.26.3", "url", "https://example.invalid/old.run");
    ok &= expect(plugin_conf, "3.26.40", "url", "https://example.invalid/prefix.run");
    ok &= expect(plugin_conf, "3.26", "url", NULL);
    ok &= expect(plugin_conf, "3.26.5", "url", NULL);
    ok &= expect(plugin_conf, "3.26.40", "checksum", NULL);
    ok &= expect("[hplip]\nversion = 3.26.4\n[plugin]\ninstalled = 1\n",
                 "plugin", "version", NULL);
    ok &= expect("[plugin]\ninstalled = 1\n[hplip]\n", "hplip", "installed", NULL);
    return ok ? 0 : 1;
  }
  if (!strcmp(test, "config-key-match")) {
    int ok = 1;
    ok &= expect("[plugin]\nversionx = 9\nversion = 3.26.4\n",
                 "plugin", "version", "3.26.4");
    ok &= expect("[plugin]\ninstalled_by = x\n", "plugin", "installed", NULL);
    ok &= expect("[plugin]\nversion=3.26.4\n", "plugin", "version", "3.26.4");
    ok &= expect("[plugin]\nversion \t=\t 3.26.4\n", "plugin", "version", "3.26.4");
    ok &= expect("[HPLIP]\nVERSION = 3.26.4\n", "hplip", "version", "3.26.4");
    return ok ? 0 : 1;
  }
  if (!strcmp(test, "config-no-value")) {
    int ok = 1;
    ok &= expect("[plugin]\nversion 3.26.4\n", "plugin", "version", NULL);
    ok &= expect("[plugin]\nversion =\n", "plugin", "version", NULL);
    ok &= expect("[plugin]\nversion =   \n", "plugin", "version", NULL);
    ok &= expect("[plugin]\nversion = 1\n", "plugin", "", NULL);
    ok &= expect("[plugin]\nversion = 1\n", "plugin", NULL, NULL);
    return ok ? 0 : 1;
  }
  return 3;
}
C_EOF

cc_bin="${CC:-gcc}"
if ! command -v "$cc_bin" >/dev/null 2>&1; then
    cc_bin="cc"
fi

bin="$work/harness"
"$cc_bin" -std=c99 -Wall -Wextra -Werror -fsanitize=bounds -fsanitize-trap=bounds \
    -o "$bin" "$harness_c"

failures=0
report() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

run_check() {
    local name="$1" desc="$2"
    local status=0
    "$bin" "$name" >/dev/null 2>&1 || status=$?
    if [ "$status" -eq 0 ]; then
        printf 'ok: %s\n' "$desc"
    else
        report "$desc (exit code $status)"
    fi
}

run_check config-blank-lf "get_config_value parses sections with blank LF lines"
run_check config-blank-crlf "get_config_value parses sections with blank CRLF lines"
run_check config-section-scope "get_config_value only reads the requested section, never a prefix-named one"
run_check config-key-match "get_config_value matches whole keys, ignoring spacing and case"
run_check config-no-value "get_config_value returns NULL for a missing '=', an empty value or an empty key"
run_check cmd-no-trailing-newline "command-output line stripper preserves lines without trailing newline"
run_check cmd-trailing-newline "command-output line stripper removes trailing newline"
run_check cmd-empty-line "command-output line stripper handles empty line"

if [ "$failures" -ne 0 ]; then
    printf '%s check(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'All config and line-strip checks passed\n'
