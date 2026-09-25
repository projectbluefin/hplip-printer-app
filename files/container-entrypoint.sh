#!/usr/bin/env bash
set -euo pipefail

port="${PORT:-18030}"
if [[ ! "$port" =~ ^[0-9]+$ ]] || (( ${#port} > 5 )); then
  printf 'PORT must be a numeric unprivileged TCP port\n' >&2
  exit 64
fi
port=$((10#$port))
if (( port < 1024 || port > 65535 )); then
  printf 'PORT must be between 1024 and 65535\n' >&2
  exit 64
fi

state=/var/lib/hplip-printer-app
# $state/run is HPLIP-specific persistent state (see hplip.conf's
# run=/var/lib/hplip-printer-app/run). Clear any stale PID/socket files left
# behind by a previous instance before recreating it, so a restarted
# stateful container never inherits incompatible runtime state.
rm -rf "$state/run"
mkdir -p "$state/ppd" "$state/spool" "$state/usb" "$state/cups/ssl" "$state/snmp" "$state/run" /run/dbus /run/avahi-daemon /run/hplip-printer-app
if [[ -O "$state" ]]; then chmod 0700 "$state"; fi
if [[ ! -e "$state/cups/snmp.conf" && -f /etc/cups/snmp.conf ]]; then
  cp /etc/cups/snmp.conf "$state/cups/snmp.conf"
fi
if [[ ! -e "$state/usb/org.cups.usb-quirks" && -f /usr/share/cups/usb/org.cups.usb-quirks ]]; then
  cp /usr/share/cups/usb/org.cups.usb-quirks "$state/usb/"
fi

export HOME="$state"
export BACKEND_DIR=/usr/lib/cups/backend
export CUPS_SERVERBIN=/usr/lib/cups
export CUPS_SERVERROOT="$state/cups"
export FILTER_DIR=/usr/lib/cups/filter
export PATH="$FILTER_DIR:/usr/bin:/usr/sbin"
export PPD_PATHS="/usr/share/ppd/:$state/ppd/"
export PPDC_DATADIR=/usr/share/ppdc
export PYTHONPATH=/usr/share/hplip
export SPOOL_DIR="$state/spool"
export STATE_DIR="$state"
export STATE_FILE="$state/hplip-printer-app.state"
export TESTPAGE_DIR=/usr/share/hplip-printer-app
export TMPDIR=/tmp
export USB_QUIRK_DIR="$state"

# Only HP's public signing key is in the image; downloaded proprietary files
# and the keyring live in the user-owned persistent volume.
gpg --batch --no-permission-warning --homedir "$state" --import /usr/share/hplip/signing-key.asc >/dev/null

children=()
stop_children() {
  local index pid
  for ((index = ${#children[@]} - 1; index >= 0; index--)); do
    pid="${children[index]}"
    kill -TERM "$pid" 2>/dev/null || true
  done
  if ((${#children[@]})); then
    wait "${children[@]}" 2>/dev/null || true
  fi
}
handle_signal() {
  trap - TERM INT EXIT
  stop_children
  exit 143
}
trap handle_signal TERM INT
trap stop_children EXIT

dbus-daemon --system --nofork --nopidfile &
children+=("$!")
for _ in $(seq 1 30); do
  [[ -S /run/dbus/system_bus_socket ]] && break
  sleep 0.1
done
[[ -S /run/dbus/system_bus_socket ]]

avahi-daemon --no-drop-root --no-chroot &
children+=("$!")
for _ in $(seq 1 30); do
  [[ -f /run/avahi-daemon/pid ]] && break
  sleep 0.1
done
[[ -f /run/avahi-daemon/pid ]]

hplip-printer-app -o "server-port=$port" -o "log-file=$state/hplip-printer-app.log" server &
children+=("$!")

if wait -n "${children[@]}"; then
  status=1
else
  status=$?
fi
stop_children
trap - TERM INT EXIT
exit "$status"
