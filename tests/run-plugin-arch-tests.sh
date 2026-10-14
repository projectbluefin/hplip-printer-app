#!/bin/sh
#
# Verify the HP plugin architecture matching on both release architectures.
#
# Builds the real hplip-plugin-arch.c against a directory of fake vendor
# libraries and checks that:
#
#   * the amd64 release (arch tag "x86_64") stages exactly its x86_64
#     libraries and rejects the arm64/arm32/x86_32 ones;
#   * the arm64 release (arch tag "arm64") stages exactly its arm64
#     libraries and rejects the x86_64 one;
#   * a vendor bundle which lacks the architecture reports zero matches
#     instead of silently staging a broken plugin.
#   * a plugin directory too long for the staging path is refused with
#     ENAMETOOLONG instead of overflowing the path buffer.
#
# Needs only a C compiler. A stage whose tools are missing is skipped.
#
# Usage: tests/run-plugin-arch-tests.sh

set -u

# shellcheck disable=SC2317,SC2329  # invoked by the trap below
cleanup() {
    rm -rf "$tmpdir"
    # The test program stages its symlinks under /tmp/hplip-arch-*.
    rm -rf /tmp/hplip-arch-x86_64-* /tmp/hplip-arch-arm64-* /tmp/hplip-arch-none-* \
        /tmp/hplip-arch-long-*
}
trap cleanup EXIT INT TERM

check() {
    # check <description> <expected> <actual>
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then
        echo "ok: $1"
    else
        failures=$((failures + 1))
        echo "FAIL: $1: expected $2, got $3"
    fi
}

skip() {
    skipped="${skipped}${skipped:+, }$1"
    echo "SKIP: $1"
}

find_cc() {
    for candidate in ${CC:-} cc gcc clang; do
        [ -n "$candidate" ] || continue
        if command -v "$candidate" >/dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done

    # No system compiler, but a Python-hosted one is enough to build this.
    if command -v python3 >/dev/null 2>&1 &&
       python3 -c "import ziglang" >/dev/null 2>&1; then
        echo "python3 -m ziglang cc"
        return 0
    fi

    return 1
}

topdir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmpdir=$(mktemp -d)

checks=0
failures=0
skipped=""

cc_cmd=$(find_cc) || cc_cmd=""

if [ -n "$cc_cmd" ]; then
    # shellcheck disable=SC2086
    if $cc_cmd -std=c99 -Wall -Wextra -Werror -D_GNU_SOURCE \
        -I"$topdir" \
        -o "$tmpdir/test-plugin-arch" \
        "$topdir/tests/test-plugin-arch.c" \
        "$topdir/hplip-plugin-arch.c" \
        > "$tmpdir/build.log" 2>&1; then
        check "the arch-matching unit tests build" "yes" "yes"
        if "$tmpdir/test-plugin-arch" > "$tmpdir/test.log" 2>&1; then
            check "the arch-matching unit tests pass" "yes" "yes"
        else
            check "the arch-matching unit tests pass" "yes" "no"
            sed 's/^/  /' "$tmpdir/test.log"
        fi
    else
        check "the arch-matching unit tests build" "yes" "no"
        sed 's/^/  /' "$tmpdir/build.log"
    fi
else
    skip "the unit tests (no C compiler found; set CC or install one)"
fi

echo
if [ -n "$skipped" ]; then
    echo "skipped: $skipped"
fi

if [ "$failures" -eq 0 ]; then
    echo "$checks checks, 0 failures"
    exit 0
fi

echo "$checks checks, $failures failures"
exit 1
