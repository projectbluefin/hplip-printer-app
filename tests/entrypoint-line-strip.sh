#!/usr/bin/env bash
# Exercise the config and command-output line stripping from hplip-printer-app.c
# without building the OCI image or requiring PAPPL/CUPS.
#
# Regression test for #76:
# - get_config_value() must not index line[-1] on blank LF or CRLF lines.
# - hplip_run_command_line() must not strip the final character from output
#   lacking a trailing newline, and must tolerate empty lines.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/hplip-printer-app.c"

tmp_base="${TMPDIR:-$root}"
work="$(mktemp -d "${tmp_base%/}/line-strip-test-XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Slice get_config_value from hplip-printer-app.c
start_line="$(grep -n -E '^get_config_value\(' "$src" | head -n 1 | cut -d: -f1)"
start_line=$((start_line - 1))
end_line="$(grep -n -E '^hplip_version\(' "$src" | head -n 1 | cut -d: -f1)"
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
cmd_start="$(grep -n -E '^hplip_run_command_line\(' "$src" | head -n 1 | cut -d: -f1)"
cmd_strip="$(sed -n "${cmd_start},+30p" "$src" | grep -n "Remove newline" | head -n 1 | cut -d: -f1)"
cmd_strip_line=$((cmd_start + cmd_strip - 1))
strip_code="$(sed -n "${cmd_strip_line}p" "$src")"

if [ -z "${strip_code:-}" ]; then
    printf 'tests/entrypoint-line-strip.sh: could not locate command output line stripper in %s\n' "$src" >&2
    exit 1
fi

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
run_check cmd-no-trailing-newline "command-output line stripper preserves lines without trailing newline"
run_check cmd-trailing-newline "command-output line stripper removes trailing newline"
run_check cmd-empty-line "command-output line stripper handles empty line"

if [ "$failures" -ne 0 ]; then
    printf '%s check(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'All config and line-strip checks passed\n'
