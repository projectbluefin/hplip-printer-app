#!/usr/bin/env bash
# Exercise the child supervision at the bottom of files/container-entrypoint.sh
# without building or running the OCI image.
#
# The entrypoint is PID 1 of the appliance container: it starts dbus-daemon,
# avahi-daemon and hplip-printer-app, and its traps are the only thing that
# stops them when the container is asked to stop. tests/oci-appliance.sh needs a
# full image build and never signals the container, so stop_children() and
# handle_signal() are otherwise unexecuted. A regression here is a container
# that leaves daemons behind, hangs on shutdown, or reports "stopped on
# request" after a daemon crashed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
entrypoint="$root/files/container-entrypoint.sh"
start_marker='^children=\(\)$'
end_marker='^trap stop_children EXIT$'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

line_of() {
    local pattern="$1" line
    line="$(grep -n -E "$pattern" "$entrypoint" | head -n 1 | cut -d: -f1)"
    if [ -z "${line:-}" ]; then
        printf 'tests/entrypoint-supervisor.sh: no line matching %s in %s\n' \
            "$pattern" "$entrypoint" >&2
        exit 1
    fi
    printf '%s\n' "$line"
}

# The supervision block is self-contained: an empty child list, the two
# handlers, and the traps that arm them. Slice it out so it can run against
# stand-in children instead of real daemons. Fail loudly if the entrypoint is
# restructured so that either marker no longer exists.
start_line="$(line_of "$start_marker")"
end_line="$(line_of "$end_marker")"
if [ "$end_line" -le "$start_line" ]; then
    printf 'tests/entrypoint-supervisor.sh: %s precedes %s in %s\n' \
        "$end_marker" "$start_marker" "$entrypoint" >&2
    exit 1
fi

supervisor="$work/supervisor.sh"
sed -n "${start_line},${end_line}p" "$entrypoint" >"$supervisor"

# A stand-in daemon: it records its own name when it is asked to stop, so a
# check can see both that it was signalled and in which order. It announces
# itself only once its TERM trap is installed, so no check ever signals a child
# that would die from the default disposition instead.
child="$work/child.sh"
cat >"$child" <<'CHILD'
#!/usr/bin/env bash
name="$1"
log="$2"
ready="$3"
trap 'printf "%s\n" "$name" >>"$log"; exit 0' TERM
: >"$ready.$name"
while :; do
    sleep 0.05
done
CHILD
chmod +x "$child"

failures=0

report() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

# Shared by every harness: records the order in which stop_children() signals
# the children. The children themselves wake from sleep in an arbitrary order,
# so only the caller's own iteration can be asserted. Installed after the
# supervision block is sourced, so stop_children() resolves this definition.
record_kill='
kill() {
    if [ "${1:-}" = "-TERM" ]; then
        local index
        for index in "${!children[@]}"; do
            if [ "${children[index]}" = "${2:-}" ]; then
                printf "child%s\\n" "$((index + 1))" >>"$order"
            fi
        done
    fi
    builtin kill "$@"
}
'

# Shared by every harness: block until all stand-in daemons are trapping TERM.
await_ready='
await_ready() {
    local want="$1" waited=0 seen
    while :; do
        seen=0
        for f in "$ready".*; do
            [ -e "$f" ] && seen=$((seen + 1))
        done
        [ "$seen" -ge "$want" ] && return 0
        waited=$((waited + 1))
        [ "$waited" -gt 400 ] && return 1
        sleep 0.05
    done
}
'

# write_harness <name> <child-count> <action>
# Builds a script that sources the sliced supervision block, starts <count>
# stand-in daemons under it, publishes its own pid, and then runs <action>.
write_harness() {
    local name="$1" count="$2" action="$3" n
    local path="$work/$name.sh"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'set -euo pipefail\n'
        printf 'log="$1"\nready="$2"\npidfile="$3"\norder="$4"\n'
        printf '%s\n' "$await_ready"
        printf '. %q\n' "$supervisor"
        for ((n = 1; n <= count; n++)); do
            printf '%q "child%s" "$log" "$ready" &\n' "$child" "$n"
            printf 'children+=("$!")\n'
        done
        printf 'printf "%%s\\n" "$$" >"$pidfile"\n'
        printf 'await_ready %s\n' "$count"
        printf '%s\n' "$record_kill"
        printf '%s\n' "$action"
    } >"$path"
    chmod +x "$path"
    printf '%s\n' "$path"
}

# Paths for the harness currently under test.
new_run() {
    run_name="$1"
    run_log="$work/$run_name.log"
    run_ready="$work/$run_name.ready"
    run_pidfile="$work/$run_name.pid"
    run_order="$work/$run_name.order"
    : >"$run_log"
    : >"$run_order"
    rm -f "$run_pidfile"
}

# The children append to the log as each one wakes up, so compare them as a
# set; the signalling order is asserted separately from $run_order.
stopped_children() {
    sort <"$run_log" | tr '\n' ' ' | sed 's/ *$//'
}

signal_order() {
    tr '\n' ' ' <"$run_order" | sed 's/ *$//'
}

# run_sync <name> <count> <action> — runs the harness to completion.
# Leaves its status in $run_status. Exit 124 means the 30s timeout fired.
run_sync() {
    local path
    new_run "$1"
    path="$(write_harness "$1" "$2" "$3")"
    run_status=0
    timeout 30 "$path" "$run_log" "$run_ready" "$run_pidfile" "$run_order" || run_status=$?
}

# run_signalled <name> <count> <signal> — starts a harness that parks in
# "wait -n" like the real entrypoint does, signals it, and waits for it.
run_signalled() {
    local path pid='' waited=0 runner
    new_run "$1"
    path="$(write_harness "$1" "$2" '
sleep 30 &
children+=("$!")
wait -n "${children[@]}" || true
sleep 30
')"
    # Without job control bash starts "&" jobs with SIGINT ignored, and a
    # timeout(1) that keeps that disposition (uutils) hands it to the harness,
    # whose INT trap then never fires. Monitor mode spawns the job normally.
    set -m
    timeout 30 "$path" "$run_log" "$run_ready" "$run_pidfile" "$run_order" &
    runner=$!
    set +m
    while [ "$waited" -le 400 ]; do
        pid="$(cat "$run_pidfile" 2>/dev/null || true)"
        [ -n "$pid" ] && break
        waited=$((waited + 1))
        sleep 0.05
    done
    run_pid="$pid"
    if [ -z "$pid" ]; then
        run_status=''
        kill -KILL "$runner" 2>/dev/null || true
        wait "$runner" 2>/dev/null || true
        return 0
    fi
    # The children are ready by construction; give the harness a moment to
    # reach "wait -n" so the signal is delivered to a parked shell.
    sleep 0.5
    kill -"$3" "$pid" 2>/dev/null || true
    run_status=0
    wait "$runner" || run_status=$?
}

# --- stop_children() terminates every recorded child, newest first -----------
#
# Reverse order matters: hplip-printer-app is started last and must be asked to
# stop before the D-Bus bus it is still talking to goes away.

run_sync stop-all 3 '
stop_children
trap - EXIT
'
if [ "$run_status" != 0 ]; then
    report "stop_children exits $run_status, expected 0 (124 means it hung)"
elif [ "$(stopped_children)" != 'child1 child2 child3' ]; then
    report "stop_children stopped '$(stopped_children)', expected every child"
elif [ "$(signal_order)" != 'child3 child2 child1' ]; then
    report "stop_children signalled '$(signal_order)', expected 'child3 child2 child1'"
else
    printf 'ok: stop_children terminates every child, newest first\n'
fi

# --- stop_children() returns when nothing was started ------------------------
#
# A bare "wait" with no recorded children blocks on the shell's whole job table
# instead of returning, so the guard on ${#children[@]} is load-bearing: an
# entrypoint that failed before dbus-daemon started would hang on exit instead
# of reporting the failure.

run_sync stop-none 0 '
stop_children
trap - EXIT
'
if [ "$run_status" != 0 ]; then
    report "stop_children with no children exits $run_status, expected 0 (124 means it hung)"
else
    printf 'ok: stop_children returns when no child was started\n'
fi

# --- stop_children() tolerates a child that already exited -------------------
#
# The entrypoint reaches stop_children precisely because one child died, so a
# dead pid must not abort the handler under "set -e" before the survivors have
# been signalled.

run_sync stop-dead 2 '
kill -KILL "${children[0]}" 2>/dev/null || true
wait "${children[0]}" 2>/dev/null || true
stop_children
trap - EXIT
'
if [ "$run_status" != 0 ]; then
    report "stop_children with a dead child exits $run_status, expected 0"
elif [ "$(stopped_children)" != 'child2' ]; then
    report "stop_children after a death stopped '$(stopped_children)', expected 'child2'"
else
    printf 'ok: stop_children signals the survivors when a child already exited\n'
fi

# --- the EXIT trap stops the children and keeps the status -------------------
#
# The entrypoint's last line is "exit $status", where $status is the failed
# daemon's exit code; the EXIT trap must clean up without overwriting it.

run_sync exit-trap 2 '
exit 7
'
if [ "$run_status" != 7 ]; then
    report "the EXIT trap left exit status $run_status, expected 7"
elif [ "$(stopped_children)" != 'child1 child2' ]; then
    report "the EXIT trap stopped '$(stopped_children)', expected every child"
else
    printf 'ok: the EXIT trap stops the children and preserves the exit status\n'
fi

# --- SIGTERM and SIGINT exit 143 with the children stopped exactly once ------
#
# 143 is 128+SIGTERM, which podman stop and Kubernetes read as "stopped on
# request" rather than a crash. handle_signal() disarms the EXIT trap first, so
# each child must be signalled once, not once per trap.

check_signal() {
    local signal="$1" label="$2"
    run_signalled "signal-$signal" 2 "$signal"
    if [ -z "${run_pid:-}" ]; then
        report "$label: the harness never reported its pid"
        return
    fi
    if [ "$run_status" != 143 ]; then
        report "$label: exit status $run_status, expected 143 (124 means shutdown hung)"
        return
    fi
    if [ "$(stopped_children)" != 'child1 child2' ]; then
        report "$label: stopped '$(stopped_children)', expected every child"
        return
    fi
    if [ "$(signal_order)" != 'child3 child2 child1' ]; then
        report "$label: signalled '$(signal_order)', expected 'child3 child2 child1' exactly once"
        return
    fi
    printf 'ok: %s\n' "$label"
}

check_signal TERM 'SIGTERM stops the children once and exits 143'
check_signal INT  'SIGINT stops the children once and exits 143'

if [ "$failures" -ne 0 ]; then
    printf '%s check(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'All entrypoint supervision checks passed\n'
