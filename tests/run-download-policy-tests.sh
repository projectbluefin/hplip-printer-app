#!/bin/sh
#
# Verify the bounds on the HTTP transfers which fetch HP's proprietary
# plugin.
#
# Two stages:
#
#   1. the unit tests for hplip-download-policy.c, built against
#      tests/stub-curl/curl/curl.h so that neither libcurl nor PAPPL has to
#      be installed.  When libcurl's own header is present the module is
#      additionally compile-checked against it, which is what catches a
#      bound named wrongly in the module;
#
#   2. a live check that the libcurl options those bounds consist of really
#      do end a transfer against a local endpoint which accepts the
#      connection and then stops answering - the case issue #13 describes.
#      The endpoint is started by tests/stall-server.py, and one healthy
#      request is made as well so that a check which can only ever fail
#      would be caught here instead of passing silently.
#
# Usage: tests/run-download-policy-tests.sh
#
# Needs a C compiler, python3, curl, date and timeout.  A stage whose tools
# are missing is skipped with a message naming what was missing.

set -u

topdir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmpdir=$(mktemp -d)

checks=0
failures=0
skipped=""

server_pid=""
server_port=""

# shellcheck disable=SC2317,SC2329  # invoked by the trap below
cleanup() {
    if [ -n "$server_pid" ]; then
	kill "$server_pid" 2>/dev/null
    fi
    rm -rf "$tmpdir"
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


# --- Stage 1: the bounds themselves -----------------------------------

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

cc_cmd=$(find_cc) || cc_cmd=""

if [ -n "$cc_cmd" ]; then
    curl_includes=""
    # CURL_INCLUDE_DIR lets a caller point at libcurl's headers when they
    # are unpacked somewhere other than the system include directory.
    for dir in ${CURL_INCLUDE_DIR:-} /usr/include /usr/local/include; do
	[ -n "$dir" ] || continue
	if [ -f "$dir/curl/curl.h" ]; then
	    curl_includes="-I$dir"
	    break
	fi
    done

    build_failed=0

    if [ -n "$curl_includes" ]; then
	# shellcheck disable=SC2086
	if $cc_cmd -std=c99 -Wall -Wextra -Werror $curl_includes \
		-c "$topdir/hplip-download-policy.c" \
		-o "$tmpdir/policy-against-libcurl.o" \
		> "$tmpdir/real-build.log" 2>&1; then
	    check "hplip-download-policy.c compiles against libcurl's own header" \
		  "yes" "yes"
	else
	    check "hplip-download-policy.c compiles against libcurl's own header" \
		  "yes" "no"
	    sed 's/^/  /' "$tmpdir/real-build.log"
	    build_failed=1
	fi
    fi

    # The test binary is always built against the stub, because the stub is
    # what provides the recording curl_easy_setopt().
    if [ "$build_failed" -eq 0 ]; then
	# shellcheck disable=SC2086
	if $cc_cmd -std=c99 -Wall -Wextra -Werror -D_GNU_SOURCE \
		-I"$topdir" -I"$topdir/tests/stub-curl" \
		-o "$tmpdir/test-download-policy" \
		"$topdir/tests/test-download-policy.c" \
		"$topdir/hplip-download-policy.c" \
		> "$tmpdir/stub-build.log" 2>&1; then
	    if "$tmpdir/test-download-policy" > "$tmpdir/unit.log" 2>&1; then
		check "the unit tests pass ($(cat "$tmpdir/unit.log"))" \
		      "yes" "yes"
	    else
		check "the unit tests pass" "yes" "no"
		sed 's/^/  /' "$tmpdir/unit.log"
	    fi
	else
	    check "the unit tests build" "yes" "no"
	    sed 's/^/  /' "$tmpdir/stub-build.log"
	fi
    fi
else
    skip "the unit tests (no C compiler found; set CC or install one)"
fi


# --- Stage 2: a local endpoint which accepts but never answers ---------

if ! command -v python3 >/dev/null 2>&1; then
    skip "the stalled-endpoint check (no python3 found)"
elif ! command -v curl >/dev/null 2>&1; then
    skip "the stalled-endpoint check (no curl found)"
elif ! command -v timeout >/dev/null 2>&1; then
    skip "the stalled-endpoint check (no timeout found)"
else
    start_server() {
	# start_server <mode>: sets server_port on success
	server_port=""
	rm -f "$tmpdir/port" "$tmpdir/server.err"

	python3 "$topdir/tests/stall-server.py" --mode "$1" \
	    > "$tmpdir/port" 2> "$tmpdir/server.err" &
	server_pid=$!

	waited=0
	while [ ! -s "$tmpdir/port" ]; do
	    if [ "$waited" -ge 50 ]; then
		return 1
	    fi
	    sleep 0.1
	    waited=$((waited + 1))
	done

	server_port=$(head -n 1 "$tmpdir/port")
	[ -n "$server_port" ]
    }

    stop_server() {
	if [ -n "$server_pid" ]; then
	    kill "$server_pid" 2>/dev/null
	    wait "$server_pid" 2>/dev/null
	    server_pid=""
	fi
    }

    # The bounds the application applies to every plugin download, as curl
    # command line options: connect, total, and stall.  The stall bound is
    # deliberately tighter here than the connect and total ones so that the
    # elapsed time below says which of them did the work.
    bounded() {
	# bounded <url>: echoes curl's exit status
	curl --connect-timeout 1 --max-time 6 \
	     --speed-limit 1024 --speed-time 2 \
	     --silent --show-error --output /dev/null "$1" >/dev/null 2>&1
	echo $?
    }

    # A healthy endpoint has to succeed, otherwise "it failed" below would
    # prove nothing at all about the bounds.
    if start_server healthy; then
	check "a healthy endpoint is downloaded" "0" \
	      "$(bounded "http://127.0.0.1:$server_port/plugin.conf")"
    else
	check "the healthy test server starts" "yes" "no"
	sed 's/^/  /' "$tmpdir/server.err"
    fi
    stop_server

    for mode in accept-only stall-body; do
	if ! start_server "$mode"; then
	    check "the $mode test server starts" "yes" "no"
	    sed 's/^/  /' "$tmpdir/server.err"
	    stop_server
	    continue
	fi
	url="http://127.0.0.1:$server_port/plugin.conf"

	# What this endpoint does to a client with no bounds at all: it is
	# still waiting when the test gives up on it.  That is the
	# behaviour issue #13 describes, and it is what the options above
	# are there to remove.
	start=$(date +%s)
	timeout 5 curl --silent --output /dev/null "$url" >/dev/null 2>&1
	unbounded_status=$?
	unbounded_elapsed=$(( $(date +%s) - start ))
	check "$mode keeps an unbounded client waiting" "124" "$unbounded_status"
	check "$mode really is still holding the connection after 5 s" "yes" \
	      "$([ "$unbounded_elapsed" -ge 5 ] && echo yes || echo no)"

	# The same endpoint with the bounds the application applies: a
	# bounded failure, and libcurl's "timeout was reached" at that.
	start=$(date +%s)
	status=$(bounded "$url")
	elapsed=$(( $(date +%s) - start ))
	stop_server

	check "$mode yields a bounded failure (curl exit 28)" "28" "$status"
	check "$mode fails well inside the total bound" "yes" \
	      "$([ "$elapsed" -lt 5 ] && echo yes || echo no)"
	echo "  ($mode took ${elapsed}s, the total bound is 6s)"
    done
fi


# --- Result ------------------------------------------------------------

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
