#!/usr/bin/env bash
# Exercise the state directory setup and the daemon readiness waits in
# files/container-entrypoint.sh without building or running the OCI image.
#
# The state directory is the appliance's persistent volume: the entrypoint
# creates its layout, locks it to 0700, seeds snmp.conf and the USB quirks
# from the image only when the volume has none, and points every CUPS/HPLIP
# path at it. tests/oci-appliance.sh checks part of that after a full image
# build. The readiness waits for dbus-daemon and avahi-daemon are only ever
# seen succeeding there; nothing checks that the container gives up, and
# never starts the next daemon, when one of them does not come up.
#
# Absolute paths in the sliced blocks are rewritten under a scratch root so
# the checks run unprivileged. Fail loudly if the entrypoint is restructured
# so that a marker no longer exists.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
entrypoint="$root/files/container-entrypoint.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

line_of() {
    local pattern="$1" line
    line="$(grep -n -E "$pattern" "$entrypoint" | head -n 1 | cut -d: -f1)"
    if [ -z "${line:-}" ]; then
        printf 'tests/entrypoint-state.sh: no line matching %s in %s\n' \
            "$pattern" "$entrypoint" >&2
        exit 1
    fi
    printf '%s\n' "$line"
}

# slice <start-pattern> <end-pattern> <output>: copy the inclusive block,
# with every absolute /var, /run, /etc and /usr path moved under $SANDBOX.
slice() {
    local start end
    start="$(line_of "$1")"
    end="$(line_of "$2")"
    if [ "$end" -le "$start" ]; then
        printf 'tests/entrypoint-state.sh: %s precedes %s in %s\n' \
            "$2" "$1" "$entrypoint" >&2
        exit 1
    fi
    # ${SANDBOX} is meant literally: it expands when the slice runs.
    # shellcheck disable=SC2016
    sed -n "${start},${end}p" "$entrypoint" |
        sed -E 's#(^|[ "=:])/(var|run|etc|usr)/#\1${SANDBOX}/\2/#g' >"$3"
}

setup="$work/setup.sh"
slice '^state=/var/lib/hplip-printer-app$' '^export USB_QUIRK_DIR=' "$setup"
readiness="$work/readiness.sh"
slice '^dbus-daemon ' '^\[\[ -f /run/avahi-daemon/pid \]\]$' "$readiness"

failures=0
report() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

mode_of() {
    stat -c '%a' "$1"
}

# new_sandbox <name>: a scratch root holding the image-provided seed files.
new_sandbox() {
    local sandbox="$work/$1"
    mkdir -p "$sandbox/etc/cups" "$sandbox/usr/share/cups/usb"
    printf '# image snmp.conf\n' >"$sandbox/etc/cups/snmp.conf"
    printf '# image usb quirks\n' >"$sandbox/usr/share/cups/usb/org.cups.usb-quirks"
    printf '%s\n' "$sandbox"
}

# run_setup <sandbox>: run the setup block and print the exported settings.
run_setup() {
    SANDBOX="$1" bash -c '
        set -euo pipefail
        source "$1"
        for name in HOME CUPS_SERVERROOT PPD_PATHS SPOOL_DIR STATE_DIR \
                    STATE_FILE USB_QUIRK_DIR; do
            printf "%s=%s\n" "$name" "${!name}"
        done
    ' setup "$setup"
}

# --- Fresh volume: layout, 0700 and seeding --------------------------------
sandbox="$(new_sandbox fresh)"
state="$sandbox/var/lib/hplip-printer-app"
if ! env_out="$(run_setup "$sandbox")"; then
    report "fresh volume: setup block failed"
else
    for dir in ppd spool usb cups/ssl snmp run; do
        [ -d "$state/$dir" ] || report "fresh volume: $dir was not created"
    done
    for dir in run/dbus run/avahi-daemon run/hplip-printer-app; do
        [ -d "$sandbox/$dir" ] || report "fresh volume: /$dir was not created"
    done
    [ "$(mode_of "$state")" = 700 ] ||
        report "fresh volume: state directory mode is $(mode_of "$state"), want 700"
    [ "$(cat "$state/cups/snmp.conf" 2>/dev/null)" = '# image snmp.conf' ] ||
        report "fresh volume: snmp.conf was not seeded from the image"
    [ "$(cat "$state/usb/org.cups.usb-quirks" 2>/dev/null)" = '# image usb quirks' ] ||
        report "fresh volume: USB quirks were not seeded from the image"

    expected="HOME=$state
CUPS_SERVERROOT=$state/cups
PPD_PATHS=$sandbox/usr/share/ppd/:$state/ppd/
SPOOL_DIR=$state/spool
STATE_DIR=$state
STATE_FILE=$state/hplip-printer-app.state
USB_QUIRK_DIR=$state"
    [ "$env_out" = "$expected" ] ||
        report "fresh volume: exported paths differ
--- want
$expected
--- got
$env_out"
fi

# --- Existing volume: user edits survive a restart, mode is re-locked -------
sandbox="$(new_sandbox existing)"
state="$sandbox/var/lib/hplip-printer-app"
mkdir -p "$state/cups" "$state/usb"
chmod 0755 "$state"
printf '# saved by user\n' >"$state/cups/snmp.conf"
printf '# user quirks\n' >"$state/usb/org.cups.usb-quirks"
if ! run_setup "$sandbox" >/dev/null; then
    report "existing volume: setup block failed"
else
    [ "$(cat "$state/cups/snmp.conf")" = '# saved by user' ] ||
        report "existing volume: user snmp.conf was overwritten"
    [ "$(cat "$state/usb/org.cups.usb-quirks")" = '# user quirks' ] ||
        report "existing volume: user USB quirks were overwritten"
    [ "$(mode_of "$state")" = 700 ] ||
        report "existing volume: 0755 state directory was not re-locked to 700"
fi

# --- Image without seed files: nothing to copy is not an error -------------
sandbox="$work/bare"
mkdir -p "$sandbox"
state="$sandbox/var/lib/hplip-printer-app"
if ! run_setup "$sandbox" >/dev/null; then
    report "image without seed files: setup block failed"
else
    [ ! -e "$state/cups/snmp.conf" ] ||
        report "image without seed files: snmp.conf appeared from nowhere"
    [ ! -e "$state/usb/org.cups.usb-quirks" ] ||
        report "image without seed files: USB quirks appeared from nowhere"
fi

# --- Daemon readiness waits -------------------------------------------------
# Stand-in daemons are shell functions: each records that it started and, if
# told to, creates its readiness signal after an optional delay. dbus-daemon
# signals with a listening socket (the wait tests -S), avahi-daemon with a
# pid file.
make_socket() {
    python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$1"
}
export -f make_socket

# run_readiness <name> <dbus: ready|never> <avahi: ready|never> [dbus delay]
# Prints the started daemons, one per line, and returns the block's status.
run_readiness() {
    local sandbox="$work/ready-$1"
    mkdir -p "$sandbox/run/dbus" "$sandbox/run/avahi-daemon"
    SANDBOX="$sandbox" DBUS_MODE="$2" AVAHI_MODE="$3" DBUS_DELAY="${4:-0}" \
        bash -c '
        set -euo pipefail
        started="$SANDBOX/started"
        : >"$started"
        dbus-daemon() {
            printf "dbus-daemon\n" >>"$started"
            sleep "$DBUS_DELAY"
            if [ "$DBUS_MODE" = ready ]; then
                make_socket "$SANDBOX/run/dbus/system_bus_socket"
            fi
        }
        avahi-daemon() {
            printf "avahi-daemon\n" >>"$started"
            if [ "$AVAHI_MODE" = ready ]; then
                printf "%s\n" "$$" >"$SANDBOX/run/avahi-daemon/pid"
            fi
        }
        children=()
        finish() {
            local status=$?
            wait "${children[@]}" 2>/dev/null || true
            cat "$started"
            exit "$status"
        }
        trap finish EXIT
        source "$1"
        [ "${#children[@]}" -eq 2 ] || { echo "children=${#children[@]}" >&2; exit 99; }
    ' readiness "$readiness"
}

if ! out="$(run_readiness both-ready ready ready)"; then
    report "both daemons ready: block failed"
elif [ "$out" != $'dbus-daemon\navahi-daemon' ]; then
    report "both daemons ready: started '$out', want dbus-daemon then avahi-daemon"
fi

# A socket that appears after several polls must still be waited for.
if ! out="$(run_readiness dbus-late ready ready 0.5)"; then
    report "dbus-daemon late: block gave up before the socket appeared"
elif [ "$out" != $'dbus-daemon\navahi-daemon' ]; then
    report "dbus-daemon late: started '$out', want dbus-daemon then avahi-daemon"
fi

status=0
out="$(run_readiness dbus-never never ready)" || status=$?
if [ "$status" -eq 0 ]; then
    report "dbus-daemon never ready: block succeeded without a system bus"
elif [ "$out" != 'dbus-daemon' ]; then
    report "dbus-daemon never ready: started '$out', want only dbus-daemon"
fi

status=0
out="$(run_readiness avahi-never ready never)" || status=$?
if [ "$status" -eq 0 ]; then
    report "avahi-daemon never ready: block succeeded without avahi"
elif [ "$out" != $'dbus-daemon\navahi-daemon' ]; then
    report "avahi-daemon never ready: started '$out', want dbus-daemon then avahi-daemon"
fi

if [ "$failures" -ne 0 ]; then
    printf 'tests/entrypoint-state.sh: %d failure(s)\n' "$failures" >&2
    exit 1
fi
printf 'tests/entrypoint-state.sh: all checks passed\n'
