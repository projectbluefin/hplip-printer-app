#!/usr/bin/env bash
# Exercise hplip_plugin_status() from hplip-printer-app.c without PAPPL, CUPS
# or an image build.
#
# At every start hplip_plugin_support() asks hplip_plugin_status() whether the
# proprietary plugin is not installed, installed and current, or outdated, and
# an "outdated" answer makes the appliance download and reinstall the plugin
# from HP before the web interface comes up. The plugin page uses the same
# answer to pick its buttons. So the decision must be exact:
#   * no hplip.state, "installed = 0", a missing or empty plugin version, or an
#     unreadable hplip.conf means "not installed" -- never an update attempt;
#   * a plugin version equal to the [hplip] version in hplip.conf (ignoring
#     case) means "installed", so a current plugin is not re-downloaded;
#   * any other version means "outdated";
#   * only the [plugin] section of hplip.state counts.
# The function and its helpers get_config_value() and hplip_version() are
# compiled straight out of hplip-printer-app.c; only papplLog() and the two
# directory macros are replaced.
#
# It is named entrypoint-*.sh so that `just check-entrypoint` (run by the
# FSDK OCI CI validate step) picks it up.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/hplip-printer-app.c"

# CC may carry arguments, e.g. CC="python3 -m ziglang cc".
read -r -a cc <<< "${CC:-cc}"
if ! command -v "${cc[0]}" >/dev/null 2>&1; then
    printf 'tests/entrypoint-plugin-status.sh: no C compiler (%s)\n' "${CC:-cc}" >&2
    exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/plugin-status-XXXXXX")"
trap 'chmod -R u+rwx "$work" 2>/dev/null; rm -rf "$work"' EXIT

# Slice the status enum, then get_config_value() through the closing brace of
# hplip_plugin_status(). A grep miss must reach the error below rather than
# end the script silently under "set -e".
enum_start="$(grep -n -E '^typedef enum hplip_plugin_status_e' "$src" | head -n 1 | cut -d: -f1 || true)"
enum_end="$(grep -n -E '^\} hplip_plugin_status_t;' "$src" | head -n 1 | cut -d: -f1 || true)"
start="$(grep -n -E '^get_config_value\(' "$src" | head -n 1 | cut -d: -f1 || true)"
fn="$(grep -n -E '^hplip_plugin_status\(' "$src" | head -n 1 | cut -d: -f1 || true)"
if [ -z "$enum_start" ] || [ -z "$enum_end" ] || [ -z "$start" ] || [ -z "$fn" ] ||
   [ "$fn" -le "$start" ]; then
    printf 'tests/entrypoint-plugin-status.sh: could not locate hplip_plugin_status() and its helpers in %s\n' "$src" >&2
    exit 1
fi
start=$((start - 1))
end="$(awk -v from="$fn" 'NR > from && /^}/ { print NR; exit }' "$src")"
if [ -z "$end" ]; then
    printf 'tests/entrypoint-plugin-status.sh: no end of hplip_plugin_status() in %s\n' "$src" >&2
    exit 1
fi
if ! sed -n "${start},${end}p" "$src" | grep -q -E '^hplip_version\('; then
    printf 'tests/entrypoint-plugin-status.sh: hplip_version() is no longer between the sliced lines\n' >&2
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
#include <errno.h>
#include <stdarg.h>

typedef struct pappl_system_s pappl_system_t;
enum { PAPPL_LOGLEVEL_DEBUG, PAPPL_LOGLEVEL_ERROR };

static void
papplLog(pappl_system_t *system, int level, const char *fmt, ...)
{
  va_list ap;

  (void)system;
  fputs(level == PAPPL_LOGLEVEL_ERROR ? "E " : "D ", stderr);
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  fputc('\n', stderr);
}

static const char *conf_dir, *state_dir;
#define HPLIP_CONF_DIR conf_dir
#define HPLIP_PLUGIN_STATE_DIR state_dir

// Sliced from hplip-printer-app.c:
C_EOF

sed -n "${enum_start},${enum_end}p" "$src" >> "$harness_c"
sed -n "${start},${end}p" "$src" >> "$harness_c"

cat << 'C_EOF' >> "$harness_c"

int
main(int argc, char **argv)
{
  hplip_plugin_status_t status;

  if (argc != 3)
    return (2);
  conf_dir = argv[1];
  state_dir = argv[2];
  status = hplip_plugin_status(NULL);
  puts(status == HPLIP_PLUGIN_NOT_INSTALLED ? "not-installed" :
       status == HPLIP_PLUGIN_INSTALLED ? "installed" :
       status == HPLIP_PLUGIN_OUTDATED ? "outdated" : "unknown");
  return (0);
}
C_EOF

bin="$work/harness"
"${cc[@]}" -std=c99 -Wall -Wextra -Werror -o "$bin" "$harness_c"

failures=0
case_no=0

# check <description> <expected> <hplip.conf text or "-" for none>
#       <hplip.state text or "-" for none>
check() {
    local desc="$1" want="$2" conf="$3" state="$4" got status=0
    case_no=$((case_no + 1))
    local dir="$work/case$case_no"
    mkdir -p "$dir/conf" "$dir/state"
    [ "$conf" = - ] || printf '%b' "$conf" > "$dir/conf/hplip.conf"
    [ "$state" = - ] || printf '%b' "$state" > "$dir/state/hplip.state"
    got="$("$bin" "$dir/conf" "$dir/state" 2>"$dir/log")" || status=$?
    if [ "$status" -eq 0 ] && [ "$got" = "$want" ]; then
        printf 'ok: %s\n' "$desc"
    else
        printf 'FAIL: %s: expected %s, got %s (exit %s)\n' "$desc" "$want" "${got:-nothing}" "$status" >&2
        sed 's/^/    /' "$dir/log" >&2
        failures=$((failures + 1))
    fi
}

conf='[hplip]\nversion = 3.26.4\n'

check "no hplip.state means not installed" \
    not-installed "$conf" -
check "an installed plugin of the HPLIP version is current" \
    installed "$conf" '[plugin]\ninstalled = 1\neula = 1\nversion = 3.26.4\n'
check "the version comparison ignores case" \
    installed '[hplip]\nversion = 3.26.4A\n' '[plugin]\ninstalled = 1\nversion = 3.26.4a\n'
check "an older plugin version is outdated" \
    outdated "$conf" '[plugin]\ninstalled = 1\nversion = 3.26.3\n'
check "a newer plugin version is outdated too" \
    outdated "$conf" '[plugin]\ninstalled = 1\nversion = 3.26.5\n'
check "a version that only shares a prefix is outdated" \
    outdated "$conf" '[plugin]\ninstalled = 1\nversion = 3.26.40\n'
check "installed = 0 means not installed, whatever the version" \
    not-installed "$conf" '[plugin]\ninstalled = 0\nversion = 3.26.3\n'
check "a non-numeric installed flag means not installed" \
    not-installed "$conf" '[plugin]\ninstalled = yes\nversion = 3.26.3\n'
check "a missing installed flag means not installed" \
    not-installed "$conf" '[plugin]\nversion = 3.26.3\n'
check "a missing plugin version means not installed" \
    not-installed "$conf" '[plugin]\ninstalled = 1\n'
check "an empty plugin version means not installed" \
    not-installed "$conf" '[plugin]\ninstalled = 1\nversion =\n'
check "a version outside [plugin] is ignored" \
    not-installed "$conf" '[hplip]\nversion = 3.26.3\n[plugin]\ninstalled = 1\n'
check "an installed flag outside [plugin] is ignored" \
    not-installed "$conf" '[other]\ninstalled = 1\n[plugin]\nversion = 3.26.3\n'
check "an unreadable hplip.conf means not installed, not outdated" \
    not-installed - '[plugin]\ninstalled = 1\nversion = 3.26.3\n'
check "an hplip.conf without [hplip] version means not installed" \
    not-installed '[other]\nversion = 3.26.4\n' '[plugin]\ninstalled = 1\nversion = 3.26.3\n'

# hplip.state that exists but cannot be opened (not ENOENT) is logged as an
# error and still reported as not installed. Root can open any file, so only
# check this as an unprivileged user.
if [ "$(id -u)" -ne 0 ]; then
    case_no=$((case_no + 1))
    dir="$work/case$case_no"
    mkdir -p "$dir/conf" "$dir/state"
    printf '%b' "$conf" > "$dir/conf/hplip.conf"
    printf '[plugin]\ninstalled = 1\nversion = 3.26.3\n' > "$dir/state/hplip.state"
    chmod 000 "$dir/state/hplip.state"
    got="$("$bin" "$dir/conf" "$dir/state" 2>"$dir/log")" || true
    if [ "$got" = not-installed ] && grep -q '^E Unable to open HPLIP plugin status file' "$dir/log"; then
        printf 'ok: an unreadable hplip.state is logged and means not installed\n'
    else
        printf 'FAIL: unreadable hplip.state: expected not-installed and an error log, got %s\n' "${got:-nothing}" >&2
        sed 's/^/    /' "$dir/log" >&2
        failures=$((failures + 1))
    fi
fi

if [ "$failures" -ne 0 ]; then
    printf '%s check(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'All plugin status checks passed\n'
