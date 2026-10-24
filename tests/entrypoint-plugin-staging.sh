#!/usr/bin/env bash
# Exercise the plugin staging-directory helpers from hplip-printer-app.c
# without building the OCI image or requiring PAPPL/CUPS.
#
# hplip_download_plugin() clears "<uncompress dir>/plugin_tmp" with
# hplip_remove_uncompress_dir() before it extracts a new plugin there, and
# again after any failure. In the OCI and Snap builds the uncompress dir is
# HPLIP_PLUGIN_ALT_DIR, which is also the persistent state volume holding the
# installed plugin, so the cleanup must:
# - remove only the named staging directory's regular files and symlinks,
#   never what a symlink points at, and never the state directory itself;
# - report failure (so the download refuses to extract over it) when the
#   staging path holds a sub-directory or is not a directory;
# - treat an absent staging directory as already clean.
# The classic build stages under $HOME/.hplip instead; that variant is
# compiled and checked too.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/hplip-printer-app.c"

work="$(mktemp -d)"
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT

# Slice from hplip_get_uncompress_dir() through the end of
# hplip_remove_uncompress_dir(). A grep miss must reach the error below
# rather than end the script silently under "set -e".
start_line="$(grep -n -E '^hplip_get_uncompress_dir\(' "$src" | head -n 1 | cut -d: -f1 || true)"
next_line="$(grep -n -E '^hplip_download_plugin\(' "$src" | head -n 1 | cut -d: -f1 || true)"
if [ -z "$start_line" ] || [ -z "$next_line" ] ||
   ! grep -q -E '^hplip_remove_uncompress_dir\(' "$src"; then
    printf 'tests/entrypoint-plugin-staging.sh: could not locate the staging helpers in %s\n' "$src" >&2
    exit 1
fi
# Include the return-type line above the function name.
start_line=$((start_line - 1))
end_line=$((next_line - 1))
while [ "$end_line" -gt "$start_line" ]; do
    [ "$(sed -n "${end_line}p" "$src")" = "}" ] && break
    end_line=$((end_line - 1))
done
if [ "$end_line" -le "$start_line" ]; then
    printf 'tests/entrypoint-plugin-staging.sh: could not locate the end of hplip_remove_uncompress_dir in %s\n' "$src" >&2
    exit 1
fi

harness_c="$work/harness.c"
cat << 'C_EOF' > "$harness_c"
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>

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

// Sliced hplip_get_uncompress_dir() and hplip_remove_uncompress_dir()
// from hplip-printer-app.c:
C_EOF

sed -n "${start_line},${end_line}p" "$src" >> "$harness_c"

cat << 'C_EOF' >> "$harness_c"

int
main(int argc, char **argv)
{
  char *dir;

  if (argc == 3 && !strcmp(argv[1], "get"))
  {
    if ((dir = hplip_get_uncompress_dir(NULL, atoi(argv[2]))) == NULL)
      return (1);
    puts(dir);
    free(dir);
    return (0);
  }
  if (argc == 3 && !strcmp(argv[1], "remove"))
    return (hplip_remove_uncompress_dir(NULL, argv[2]) ? 0 : 1);
  return (2);
}
C_EOF

cc_bin="${CC:-gcc}"
if ! command -v "$cc_bin" >/dev/null 2>&1; then
    cc_bin="cc"
fi

# The sliced code assigns inside its readdir() loop condition on purpose and
# declares one variable it never uses; neither is what these checks are for.
cflags=(-std=c99 -Wall -Wextra -Werror -Wno-parentheses -Wno-unused-variable)

alt_dir="$work/state"
alt_bin="$work/harness-alt"
home_bin="$work/harness-home"
"$cc_bin" "${cflags[@]}" -DHPLIP_PLUGIN_ALT_DIR="\"$alt_dir\"" -o "$alt_bin" "$harness_c"
"$cc_bin" "${cflags[@]}" -o "$home_bin" "$harness_c"

failures=0
checks=0
check() {
    # check <description> <expected> <actual>
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then
        printf 'ok: %s\n' "$1"
    else
        printf 'FAIL: %s: expected %s, got %s\n' "$1" "$2" "$3" >&2
        failures=$((failures + 1))
    fi
}

status_of() {
    local status=0
    "$@" >/dev/null 2>&1 || status=$?
    printf '%s' "$status"
}

present() {
    if [ -e "$1" ] || [ -L "$1" ]; then printf yes; else printf no; fi
}

reset_alt() {
    chmod -R u+w "$alt_dir" "$work/outside" 2>/dev/null || true
    rm -rf "$alt_dir" "$work/outside"
    mkdir -p "$alt_dir/plugin" "$work/outside/dir"
    printf installed > "$alt_dir/plugin/marker"
    printf keep > "$work/outside/file"
    printf keep > "$work/outside/dir/file"
}

# --- OCI/Snap variant: staging lives in the persistent state directory ----

reset_alt
check "alt dir: the uncompress dir is HPLIP_PLUGIN_ALT_DIR" \
    "$alt_dir" "$("$alt_bin" get 1 2>/dev/null)"
rm -rf "$alt_dir"
"$alt_bin" get 1 >/dev/null 2>&1 || true
check "alt dir: create=1 never creates the state directory itself" \
    no "$(present "$alt_dir")"

reset_alt
check "absent staging directory counts as already clean" \
    0 "$(status_of "$alt_bin" remove plugin_tmp)"
check "absent staging directory: state directory is kept" \
    yes "$(present "$alt_dir")"

reset_alt
mkdir "$alt_dir/plugin_tmp"
printf a > "$alt_dir/plugin_tmp/hp_laserjet.so"
printf b > "$alt_dir/plugin_tmp/plugin.spec"
ln -s "$work/outside/file" "$alt_dir/plugin_tmp/link-to-file"
ln -s "$work/outside/dir" "$alt_dir/plugin_tmp/link-to-dir"
ln -s "$work/does-not-exist" "$alt_dir/plugin_tmp/dangling"
check "staging directory with files and symlinks is removed" \
    0 "$(status_of "$alt_bin" remove plugin_tmp)"
check "staging directory is gone" no "$(present "$alt_dir/plugin_tmp")"
check "state directory survives, even with the staging gone" \
    yes "$(present "$alt_dir")"
check "installed plugin next to the staging directory is untouched" \
    installed "$(cat "$alt_dir/plugin/marker" 2>/dev/null || true)"
check "file a staged symlink pointed at is not deleted" \
    keep "$(cat "$work/outside/file" 2>/dev/null || true)"
check "directory a staged symlink pointed at is not emptied" \
    keep "$(cat "$work/outside/dir/file" 2>/dev/null || true)"

reset_alt
rm -rf "$alt_dir/plugin"
mkdir "$alt_dir/plugin_tmp"
check "emptied state directory is not removed in the alt-dir build" \
    0 "$(status_of "$alt_bin" remove plugin_tmp)"
check "emptied state directory still exists" yes "$(present "$alt_dir")"

reset_alt
mkdir -p "$alt_dir/plugin_tmp/sub"
printf a > "$alt_dir/plugin_tmp/top"
printf b > "$alt_dir/plugin_tmp/sub/nested"
check "staging directory holding a sub-directory reports failure" \
    1 "$(status_of "$alt_bin" remove plugin_tmp)"
check "sub-directory staging is left in place for the download to refuse" \
    yes "$(present "$alt_dir/plugin_tmp/sub/nested")"

reset_alt
printf x > "$alt_dir/plugin_tmp"
check "staging path that is a regular file reports failure" \
    1 "$(status_of "$alt_bin" remove plugin_tmp)"
check "regular-file staging path is not deleted" \
    yes "$(present "$alt_dir/plugin_tmp")"

# --- Classic variant: staging lives under $HOME/.hplip ---------------------

home="$work/home"
mkdir -p "$home"

check "classic: no HOME means no uncompress dir" \
    1 "$(status_of env -u HOME "$home_bin" get 1)"
check "classic: no HOME makes the cleanup report failure" \
    1 "$(status_of env -u HOME "$home_bin" remove plugin_tmp)"

check "classic: uncompress dir is \$HOME/.hplip" \
    "$home/.hplip" "$(HOME="$home" "$home_bin" get 0 2>/dev/null)"
check "classic: create=0 does not create \$HOME/.hplip" \
    no "$(present "$home/.hplip")"
check "classic: create=1 creates \$HOME/.hplip" \
    0 "$(status_of env HOME="$home" "$home_bin" get 1)"
check "classic: \$HOME/.hplip is private to its owner" \
    700 "$(stat -c %a "$home/.hplip" 2>/dev/null || true)"
check "classic: create=1 accepts an existing \$HOME/.hplip" \
    0 "$(status_of env HOME="$home" "$home_bin" get 1)"

mkdir "$home/.hplip/plugin_tmp"
printf a > "$home/.hplip/plugin_tmp/file"
check "classic: staging cleanup succeeds" \
    0 "$(status_of env HOME="$home" "$home_bin" remove plugin_tmp)"
check "classic: emptied \$HOME/.hplip is removed with the staging" \
    no "$(present "$home/.hplip")"

mkdir -p "$home/.hplip/plugin_tmp"
printf mine > "$home/.hplip/user-file"
check "classic: staging cleanup succeeds next to other content" \
    0 "$(status_of env HOME="$home" "$home_bin" remove plugin_tmp)"
check "classic: \$HOME/.hplip holding other content is kept" \
    mine "$(cat "$home/.hplip/user-file" 2>/dev/null || true)"

if [ "$failures" -ne 0 ]; then
    printf '%s of %s plugin staging check(s) failed\n' "$failures" "$checks" >&2
    exit 1
fi
printf 'All %s plugin staging checks passed\n' "$checks"
