#!/usr/bin/env bash
# Exercise the PORT validation at the top of files/container-entrypoint.sh
# without building or running the OCI image.
#
# The entrypoint rejects a PORT that is not a decimal number, that is longer
# than five digits, or that falls outside the unprivileged range, and it
# normalises a value with leading zeros as decimal rather than octal. Only
# "PORT=invalid" is exercised by tests/oci-appliance.sh, and that test needs a
# full image build; every numeric bound below is otherwise unexecuted.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
entrypoint="$root/files/container-entrypoint.sh"
marker='^state=/var/lib/hplip-printer-app$'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Everything before the state directory setup is the port validation, and it is
# free of side effects, so it can run on its own. Fail loudly if the entrypoint
# is restructured so that the marker no longer exists.
marker_line="$(grep -n -E "$marker" "$entrypoint" | head -n 1 | cut -d: -f1)"
if [ -z "${marker_line:-}" ]; then
    printf 'tests/entrypoint-port.sh: no line matching %s in %s\n' \
        "$marker" "$entrypoint" >&2
    exit 1
fi

prologue="$work/port-prologue.sh"
head -n "$((marker_line - 1))" "$entrypoint" >"$prologue"
printf 'printf "%%s\\n" "$port"\n' >>"$prologue"

numeric_message='PORT must be a numeric unprivileged TCP port'
range_message='PORT must be between 1024 and 65535'

failures=0

report() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

# run <label> <expected-status> <expected-output> [PORT value]
# Omitting the PORT value leaves PORT unset.
run() {
    local label="$1" want_status="$2" want_output="$3"
    local status=0 output
    if [ "$#" -ge 4 ]; then
        output="$(PORT="$4" bash "$prologue" 2>&1)" || status=$?
    else
        output="$(env -u PORT bash "$prologue" 2>&1)" || status=$?
    fi
    if [ "$status" != "$want_status" ]; then
        report "$label: exit status $status, expected $want_status"
        return
    fi
    if [ "$output" != "$want_output" ]; then
        report "$label: output '$output', expected '$want_output'"
        return
    fi
    printf 'ok: %s\n' "$label"
}

# A rejected PORT must be reported on stderr, not stdout: the entrypoint runs
# as PID 1 and its stdout is the application log.
run_stream_check() {
    local label="$1" value="$2"
    local out
    out="$(PORT="$value" bash "$prologue" 2>/dev/null)" || true
    if [ -n "$out" ]; then
        report "$label: rejection wrote '$out' to stdout"
        return
    fi
    printf 'ok: %s\n' "$label"
}

run 'unset PORT defaults to 18030'        0 18030
run 'empty PORT defaults to 18030'        0 18030 ''
run 'explicit default port'               0 18030 18030
run 'lowest allowed port'                 0 1024  1024
run 'highest allowed port'                0 65535 65535
run 'leading zero is decimal, not octal'   0 9100  09100
run 'padded boundary port'                0 1024  01024

run 'non-numeric PORT'            64 "$numeric_message" invalid
run 'trailing text after digits'  64 "$numeric_message" 18030abc
run 'leading space'               64 "$numeric_message" ' 18030'
run 'negative number'             64 "$numeric_message" -1
run 'explicit plus sign'          64 "$numeric_message" +18030
run 'hexadecimal port'            64 "$numeric_message" 0x4696
run 'embedded newline'            64 "$numeric_message" "$(printf '18030\n80')"
run 'six digits are refused before arithmetic' 64 "$numeric_message" 123456
run 'padding past five digits is refused'      64 "$numeric_message" 018030

run 'port zero'                      64 "$range_message" 0
run 'privileged port'                64 "$range_message" 80
run 'last privileged port'           64 "$range_message" 1023
run 'privileged port with padding'   64 "$range_message" 0080
run 'one past the top of the range'  64 "$range_message" 65536
run 'five digits above the range'    64 "$range_message" 99999

run_stream_check 'non-numeric rejection keeps stdout clean' invalid
run_stream_check 'out-of-range rejection keeps stdout clean' 80

if [ "$failures" -ne 0 ]; then
    printf '%s check(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'All PORT validation checks passed\n'
