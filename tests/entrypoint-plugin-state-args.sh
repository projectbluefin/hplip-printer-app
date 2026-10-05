#!/usr/bin/env bash
# Exercise the arguments hplip-printer-app.c hands to the plugin state helper
# (scripts/hplip-plugin-state.sh) without PAPPL, CUPS or an image build.
#
# hplip_run_plugin_state() builds a shell command line from the plugin
# directory, the state directory and the plugin version (which comes from
# HP's plugin.conf), and hplip_quote_argument() / hplip_is_safe_argument_char()
# are all that keep those values to exactly one helper argument each. This
# test compiles those three functions straight out of hplip-printer-app.c,
# replaces only papplLog() and hplip_run_command_line() (the latter still runs
# the command line through /bin/sh, as popen() does), and checks that:
#
#   * exactly [0-9A-Za-z/._+-] is accepted, every other byte is refused;
#   * accepted values are single-quoted, refused, empty, NULL and oversized
#     values are reported and not passed on;
#   * install/remove/recover reach the helper with the expected argv, and a
#     refused value never starts the helper at all;
#   * a failing helper is reported as a failure.
#
# It is named entrypoint-*.sh so that `just check-entrypoint` (run by the
# FSDK OCI CI validate step) picks it up.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/hplip-printer-app.c"

# CC may carry arguments, e.g. CC="python3 -m ziglang cc".
read -r -a cc <<< "${CC:-cc}"
if ! command -v "${cc[0]}" >/dev/null 2>&1; then
    printf 'tests/entrypoint-plugin-state-args.sh: no C compiler (%s)\n' "${CC:-cc}" >&2
    exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/plugin-state-args-XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Slice from the return type of hplip_is_safe_argument_char() to the closing
# brace of hplip_run_plugin_state(); the quoting helper sits between them.
start="$(grep -n -E '^hplip_is_safe_argument_char\(' "$src" | head -n 1 | cut -d: -f1)"
fn="$(grep -n -E '^hplip_run_plugin_state\(' "$src" | head -n 1 | cut -d: -f1)"
if [ -z "$start" ] || [ -z "$fn" ] || [ "$fn" -le "$start" ]; then
    printf 'tests/entrypoint-plugin-state-args.sh: could not locate the plugin state helpers in %s\n' "$src" >&2
    exit 1
fi
start=$((start - 1))
end="$(awk -v from="$fn" 'NR > from && /^}/ { print NR; exit }' "$src")"
if [ -z "$end" ]; then
    printf 'tests/entrypoint-plugin-state-args.sh: no end of hplip_run_plugin_state() in %s\n' "$src" >&2
    exit 1
fi
if ! sed -n "${start},${end}p" "$src" | grep -q -E '^hplip_quote_argument\('; then
    printf 'tests/entrypoint-plugin-state-args.sh: hplip_quote_argument() is no longer between the sliced lines\n' >&2
    exit 1
fi

# Fake helper: one argument per line, exit status from FAKE_HELPER_STATUS.
helper="$work/hplip-plugin-state.sh"
cat > "$helper" << 'SH_EOF'
#!/bin/sh
: > "$FAKE_HELPER_ARGV"
for a in "$@"; do
    printf '%s\n' "$a" >> "$FAKE_HELPER_ARGV"
done
exit "${FAKE_HELPER_STATUS:-0}"
SH_EOF
chmod +x "$helper"
mkdir "$work/state"

harness="$work/harness.c"
cat > "$harness" << 'C_EOF'
#define _GNU_SOURCE
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct pappl_system_s pappl_system_t;
enum { PAPPL_LOGLEVEL_DEBUG, PAPPL_LOGLEVEL_ERROR };

static char last_log[8192];
static int  commands_run;
static char last_command[8192];

static void
papplLog(pappl_system_t *system, int level, const char *fmt, ...)
{
  va_list ap;

  (void)system;
  (void)level;
  va_start(ap, fmt);
  vsnprintf(last_log, sizeof(last_log), fmt, ap);
  va_end(ap);
}

int
hplip_run_command_line(pappl_system_t *sys, const char *command)
{
  (void)sys;
  commands_run ++;
  snprintf(last_command, sizeof(last_command), "%s", command);
  return (system(command));
}

int hplip_is_safe_argument_char(int c);
int hplip_quote_argument(char *buf, size_t bufsize, const char *arg,
			 pappl_system_t *system);
int hplip_run_plugin_state(pappl_system_t *system, const char *command,
			   const char *plugin_dir, const char *version);

// Sliced from hplip-printer-app.c:
C_EOF
sed -n "${start},${end}p" "$src" >> "$harness"
cat >> "$harness" << 'C_EOF'

static int checks, failures;

static void
check(int ok, const char *what)
{
  checks ++;
  if (ok)
    printf("ok: %s\n", what);
  else
  {
    failures ++;
    printf("FAIL: %s\n", what);
  }
}

static char *
read_argv(void)
{
  static char buf[8192];
  FILE *fp;
  size_t n;

  buf[0] = '\0';
  if ((fp = fopen(getenv("FAKE_HELPER_ARGV"), "r")) == NULL)
    return (buf);
  n = fread(buf, 1, sizeof(buf) - 1, fp);
  buf[n] = '\0';
  fclose(fp);
  return (buf);
}

static void
reset(void)
{
  commands_run = 0;
  last_log[0] = '\0';
  last_command[0] = '\0';
  unlink(getenv("FAKE_HELPER_ARGV"));
  unsetenv("FAKE_HELPER_STATUS");
}

static void
refused_run(const char *what, const char *dir, const char *version)
{
  char msg[256], marker[4096];

  reset();
  snprintf(marker, sizeof(marker), "%s/pwned", getenv("WORK"));
  unlink(marker);
  snprintf(msg, sizeof(msg), "%s: refused", what);
  check(hplip_run_plugin_state(NULL, "install", dir, version) == 0, msg);
  snprintf(msg, sizeof(msg), "%s: helper never started", what);
  check(commands_run == 0 && access(getenv("FAKE_HELPER_ARGV"), F_OK) != 0, msg);
  snprintf(msg, sizeof(msg), "%s: nothing injected ran", what);
  check(access(marker, F_OK) != 0, msg);
  snprintf(msg, sizeof(msg), "%s: refusal is logged", what);
  check(strstr(last_log, "Refusing to pass") != NULL, msg);
}

int
main(void)
{
  const char *work = getenv("WORK");
  char buf[64], expect[8192], dir[4096], inj[4096];
  int c, accepted = 0, wrong = 0;


  // Character class: exactly [0-9A-Za-z/._+-], for every byte value.
  for (c = 0; c < 256; c ++)
  {
    int want = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') ||
	       (c >= 'a' && c <= 'z') || c == '/' || c == '.' || c == '_' ||
	       c == '-' || c == '+';
    int got = hplip_is_safe_argument_char(c) != 0;

    accepted += got;
    if (got != want)
    {
      wrong ++;
      printf("  byte 0x%02x: expected %d, got %d\n", c, want, got);
    }
  }
  check(wrong == 0 && accepted == 67,
	"safe characters are exactly [0-9A-Za-z/._+-]");

  // Quoting.
  check(hplip_quote_argument(buf, sizeof(buf), "/var/lib/hp", NULL) == 1 &&
	!strcmp(buf, "'/var/lib/hp'"), "plain path is single-quoted");
  check(hplip_quote_argument(buf, sizeof(buf), "3.22.10", NULL) == 1 &&
	!strcmp(buf, "'3.22.10'"), "version is single-quoted");

  last_log[0] = '\0';
  check(hplip_quote_argument(buf, sizeof(buf), NULL, NULL) == 0 &&
	strstr(last_log, "Empty argument") != NULL, "NULL argument is refused");
  last_log[0] = '\0';
  check(hplip_quote_argument(buf, sizeof(buf), "", NULL) == 0 &&
	strstr(last_log, "Empty argument") != NULL, "empty argument is refused");

  {
    static const char *bad[] =
    {
      "a'b", "a\"b", "a`id`", "$(id)", "${HOME}", "a;b", "a&b", "a|b",
      "a b", "a\tb", "a\nb", "a\rb", "a\\b", "a*", "a?", "a<b", "a>b",
      "~/x", "a#b", "a=b", "a,b", "a:b", "caf\xc3\xa9", "\xff"
    };
    size_t i;
    int all = 1;

    for (i = 0; i < sizeof(bad) / sizeof(bad[0]); i ++)
    {
      last_log[0] = '\0';
      if (hplip_quote_argument(buf, sizeof(buf), bad[i], NULL) != 0 ||
	  !strstr(last_log, "Refusing to pass"))
      {
	all = 0;
	printf("  accepted unsafe argument #%zu\n", i);
      }
    }
    check(all, "quotes, shell metacharacters, whitespace and non-ASCII bytes are refused");
  }

  // Size bound: two quotes and the terminating NUL must fit.
  check(hplip_quote_argument(buf, 8, "abcde", NULL) == 1 &&
	!strcmp(buf, "'abcde'"), "argument that exactly fits is accepted");
  last_log[0] = '\0';
  check(hplip_quote_argument(buf, 7, "abcde", NULL) == 0 &&
	strstr(last_log, "too long") != NULL,
	"argument one byte too long is refused, not truncated");

  // The helper call itself.
  snprintf(dir, sizeof(dir), "%s/plugin", work);

  reset();
  check(hplip_run_plugin_state(NULL, "install", dir, "3.22.10") == 1,
	"install succeeds when the helper does");
  snprintf(expect, sizeof(expect), "%s install '%s' '%s' '3.22.10'",
	   HPLIP_PLUGIN_STATE_SCRIPT, dir, HPLIP_PLUGIN_STATE_DIR);
  check(commands_run == 1 && !strcmp(last_command, expect),
	"install command line quotes every value");
  snprintf(expect, sizeof(expect), "install\n%s\n%s\n3.22.10\n", dir,
	   HPLIP_PLUGIN_STATE_DIR);
  check(!strcmp(read_argv(), expect),
	"install reaches the helper as command, plugin dir, state dir, version");

  reset();
  check(hplip_run_plugin_state(NULL, "remove", dir, NULL) == 1,
	"remove succeeds when the helper does");
  snprintf(expect, sizeof(expect), "remove\n%s\n%s\n", dir,
	   HPLIP_PLUGIN_STATE_DIR);
  check(!strcmp(read_argv(), expect),
	"remove without a version passes exactly three arguments");

  reset();
  check(hplip_run_plugin_state(NULL, "recover", dir, NULL) == 1,
	"recover succeeds when the helper does");
  snprintf(expect, sizeof(expect), "recover\n%s\n%s\n", dir,
	   HPLIP_PLUGIN_STATE_DIR);
  check(!strcmp(read_argv(), expect),
	"recover passes exactly three arguments");

  reset();
  setenv("FAKE_HELPER_STATUS", "3", 1);
  check(hplip_run_plugin_state(NULL, "install", dir, "3.22.10") == 0,
	"helper failure makes the transaction fail");
  check(commands_run == 1 && strstr(last_log, "failed (status") != NULL &&
	strstr(last_log, "\"install\"") != NULL,
	"helper failure is logged with its command");

  snprintf(inj, sizeof(inj), "3.22.10'; touch %s/pwned; '", work);
  refused_run("quote break-out in the version", dir, inj);
  snprintf(inj, sizeof(inj), "3.22.10$(touch %s/pwned)", work);
  refused_run("command substitution in the version", dir, inj);
  snprintf(inj, sizeof(inj), "%s/plugin'; touch %s/pwned; '", work, work);
  refused_run("quote break-out in the plugin directory", inj, "3.22.10");
  snprintf(inj, sizeof(inj), "%s/plug in", work);
  refused_run("space in the plugin directory", inj, NULL);

  reset();
  check(hplip_run_plugin_state(NULL, "install", "", "3.22.10") == 0 &&
	commands_run == 0, "empty plugin directory never starts the helper");

  printf("%d checks, %d failures\n", checks, failures);
  return (failures != 0);
}
C_EOF

"${cc[@]}" -std=gnu99 -Wall -Wextra -Werror \
    -DHPLIP_PLUGIN_STATE_SCRIPT="\"$helper\"" \
    -DHPLIP_PLUGIN_STATE_DIR="\"$work/state\"" \
    -o "$work/harness" "$harness"

WORK="$work" FAKE_HELPER_ARGV="$work/argv" "$work/harness"
