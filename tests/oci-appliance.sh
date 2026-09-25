#!/usr/bin/env bash
set -euo pipefail

image=ghcr.io/projectbluefin/hplip-printer-app:build
name=hplip-printer-app-smoke
failure_name=hplip-printer-app-child-failure
invalid_name=hplip-printer-app-invalid-port
port="${PORT:-18030}"
sink_port="$((port + 1000))"
state="$(mktemp -d)"
output="$(mktemp)"
cookies="$(mktemp)"
sink_pid=

cleanup() {
  podman rm -f "$name" "$failure_name" "$invalid_name" >/dev/null 2>&1 || true
  if [[ -n "$sink_pid" ]]; then
    kill "$sink_pid" >/dev/null 2>&1 || true
    wait "$sink_pid" 2>/dev/null || true
  fi
  podman unshare rm -rf "$state"
  rm -f "$output" "$cookies"
}
trap cleanup EXIT

wait_for_http() {
  local expected_port="$1" response
  for _ in $(seq 1 90); do
    if response="$(curl --fail --silent "http://127.0.0.1:${expected_port}/" 2>/dev/null)" &&
       [[ "$response" == *'<title>HPLIP Printer Application</title>'* ]]; then
      return 0
    fi
    sleep 1
  done
  podman logs "$name" >&2 || true
  return 1
}

podman run --rm --entrypoint /usr/bin/bash "$image" -c '
  set -euo pipefail
  for bin in /usr/bin/hplip-printer-app /usr/bin/gs /usr/bin/gpg \
    /usr/bin/hp-probe /usr/lib/cups/backend/hp /usr/lib/cups/backend/HP \
    /usr/lib/cups/backend/socket /usr/lib/cups/filter/hpcups \
    /usr/lib/cups/filter/hpps; do
    test -x "$bin"
  done
  for bin in /usr/bin/hplip-printer-app /usr/lib/cups/backend/hp \
    /usr/lib/cups/filter/hpcups /usr/lib/cups/filter/hpps; do
    [[ "$(ldd "$bin")" != *"not found"* ]]
  done
  test -s /usr/share/ppd/hplip/HP/hp-deskjet_990c.ppd.gz
  test -s /usr/share/ppd/hplip/HP/hp-color_laserjet-ps.ppd.gz
  test -s /usr/share/hplip-printer-app/testpage.pdf
  test -s /usr/share/hplip/signing-key.asc
  test ! -e /var/lib/hplip-printer-app/plugin
  test ! -x /usr/bin/cupsd
  test ! -x /usr/bin/gcc
  test ! -x /usr/bin/apt-get
'

podman unshare chown 65532:65532 "$state"
python3 tests/socket-sink.py "$sink_port" "$output" &
sink_pid=$!
podman run -d --name "$name" --network host -e PORT="$port" \
  -v "$state:/var/lib/hplip-printer-app:Z" "$image" >/dev/null
wait_for_http "$port"
curl --insecure --fail --silent "https://127.0.0.1:${port}/" | grep -q '<title>HPLIP Printer Application</title>'
podman exec "$name" /usr/bin/bash -c '
  set -euo pipefail
  test "$(id -u):$(id -g)" = 65532:65532
  test -d /var/lib/hplip-printer-app/ppd
  test -d /var/lib/hplip-printer-app/cups/ssl
  test -s /var/lib/hplip-printer-app/pubring.kbx
  test -s /var/lib/hplip-printer-app/usb/org.cups.usb-quirks
'

system_uri="ipp://127.0.0.1:${port}/ipp/system"
printer_uri="ipp://127.0.0.1:${port}/ipp/print/deskjet-test"
drivers="$(podman exec "$name" hplip-printer-app -u "$system_uri" drivers)"
model="$(printf '%s\n' "$drivers" | grep -i 'deskjet 990c' | sed -n '1s/[[:space:]].*//p')"
[[ -n "$model" ]]
podman exec "$name" hplip-printer-app -u "$system_uri" \
  -d deskjet-test -m "$model" -v "cups:socket://127.0.0.1:${sink_port}" add

page="$(curl --fail --silent --cookie-jar "$cookies" "http://127.0.0.1:${port}/deskjet-test/")"
session="${page#*name=\"session\" value=\"}"
session="${session%%\"*}"
[[ -n "$session" && "$session" != "$page" ]]
curl --fail --silent --cookie "$cookies" \
  --data-urlencode "session=$session" --data 'action=print-test-page' \
  "http://127.0.0.1:${port}/deskjet-test/" >/dev/null
for _ in $(seq 1 180); do
  [[ -s "$output" ]] && break
  sleep 0.5
done
if [[ ! -s "$output" ]]; then
  podman exec "$name" cat /var/lib/hplip-printer-app/hplip-printer-app.log >&2 || true
  printf 'FAIL: hpcups produced no socket bytes\n' >&2
  exit 1
fi
wait "$sink_pid"
sink_pid=
python3 - "$output" <<'PY'
from pathlib import Path
import sys

output = Path(sys.argv[1]).read_bytes()
assert b"\x1b*r" in output, "expected HPLIP PCL raster commands, not input PostScript"
assert not output.startswith(b"%!PS")
PY
jobs=
for _ in $(seq 1 120); do
  jobs="$(podman exec "$name" hplip-printer-app -u "$printer_uri" jobs)"
  [[ "$jobs" == *completed* ]] && break
  sleep 0.5
done
[[ "$jobs" == *completed* ]]
podman exec "$name" /usr/bin/bash -c 'printf "# saved by user\n" > /var/lib/hplip-printer-app/cups/snmp.conf'
podman stop --time 15 "$name" >/dev/null
[[ "$(podman inspect "$name" --format '{{.State.ExitCode}}')" == 143 ]]
podman rm "$name" >/dev/null
podman run -d --name "$name" --network host -e PORT="$port" \
  -v "$state:/var/lib/hplip-printer-app:Z" "$image" >/dev/null
wait_for_http "$port"
podman exec "$name" /usr/bin/bash -c '[[ "$(< /var/lib/hplip-printer-app/cups/snmp.conf)" == "# saved by user" ]]'
printers="$(podman exec "$name" hplip-printer-app -u "$system_uri" printers)"
[[ "$printers" == *deskjet-test* ]]
podman stop --time 15 "$name" >/dev/null
podman rm "$name" >/dev/null

podman run -d --name "$failure_name" --network host -e PORT="$port" \
  -v "$state:/var/lib/hplip-printer-app:Z" "$image" >/dev/null
wait_for_http "$port"
podman exec "$failure_name" /usr/bin/bash -c '
  for proc in /proc/[0-9]*; do
    read -r comm < "$proc/comm" || continue
    if [[ "$comm" == avahi-daemon ]]; then
      kill -TERM "${proc##*/}"
      exit 0
    fi
  done
  exit 1
'
for _ in $(seq 1 150); do
  [[ "$(podman inspect "$failure_name" --format '{{.State.Running}}')" == false ]] && break
  sleep 0.1
done
[[ "$(podman inspect "$failure_name" --format '{{.State.Running}}')" == false ]]
[[ "$(podman inspect "$failure_name" --format '{{.State.ExitCode}}')" != 0 ]]

status=0
podman run --name "$invalid_name" -e PORT=invalid "$image" >/dev/null 2>&1 || status=$?
[[ "$status" == 64 ]]
printf 'OK: HPLIP image printed PCL raster over IPP/socket and preserved state\n'
