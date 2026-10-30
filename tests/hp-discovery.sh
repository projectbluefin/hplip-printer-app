#!/bin/sh
#
# Regression tests for the "HP" network discovery backend.
#
# The backend announces network printers which "hp-probe" (HPLIP) has found,
# as standard CUPS device records. To be able to test the parsing and the
# emitted records without a real printer, a real container image and a real
# network, the tests here drive the backend with synthetic "hp-probe"
# output. "hp-probe" gets its device data from the announcements of the
# devices on the local network, so the synthetic discovery responses also
# include hostile ones.
#
# Usage: tests/hp-discovery.sh [backend]

set -u

here=$(cd "$(dirname "$0")" && pwd)
backend=${1:-$here/../HP}

if [ ! -x "$backend" ]; then
    echo "ERROR: backend \"$backend\" not found or not executable" 1>&2
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

bin="$tmp/bin"
min="$tmp/min"
mkdir -p "$bin" "$min"

# The backend only needs a POSIX shell and "tr" and "head", and the PATH of
# the tests deliberately does not contain the real system directories, so
# that the presence of "avahi-resolve-address", "host" and "perl" is fully
# under the control of the individual test.
for tool in cat tr head; do
    ln -s "$(command -v $tool)" "$min/$tool"
done

tests=0
failures=0

ok()
{
    tests=$((tests + 1))
    printf 'ok %d - %s\n' "$tests" "$1"
}

not_ok()
{
    tests=$((tests + 1))
    failures=$((failures + 1))
    printf 'not ok %d - %s\n' "$tests" "$1"
    if [ $# -gt 1 ]; then
	printf '#      %s\n' "$2"
    fi
}

# check <test name> <expected value> <actual value>
check()
{
    if [ "$2" = "$3" ]; then
	ok "$1"
    else
	not_ok "$1" "expected: [$2]"
	not_ok "$1 (actual)" "actual:   [$3]"
    fi
}

# Write a stub "hp-probe" which prints the given synthetic discovery output
# for the network bus, and a stub resolver for the given IP addresses.
#
# write_probe <discovery output file> <resolver stub file or ->
write_probe()
{
    {
	printf '#!/bin/sh\n'
	# shellcheck disable=SC2016
	printf 'case "${1:-}" in\n'
	printf '    -h|--help) exit 0 ;;\n'
	printf 'esac\n'
	# The discovery output is embedded as-is, without any expansion, as
	# the backend must not interpret what the devices announce
	printf 'cat <<"HP_PROBE_OUTPUT"\n'
	cat "$1"
	printf 'HP_PROBE_OUTPUT\n'
	printf 'exit 0\n'
    } > "$bin/hp-probe"
    chmod +x "$bin/hp-probe"

    rm -f "$bin/avahi-resolve-address" "$bin/host"

    if [ -n "$2" ] && [ "$2" != "-" ]; then
	cp "$2" "$bin/avahi-resolve-address"
	chmod +x "$bin/avahi-resolve-address"
	cp "$2" "$bin/host"
	chmod +x "$bin/host"
    fi
}

# run <extra PATH directory or ->; then the backend is run with a minimal
# PATH built from the stub directory and the tool directory
run()
{
    if [ -n "$1" ] && [ "$1" != "-" ]; then
	backend_path="$bin:$1:$min"
    else
	backend_path="$bin:$min"
    fi

    PATH="$backend_path" "$backend" > "$tmp/stdout" 2> "$tmp/stderr"
    status=$?
    stdout=$(cat "$tmp/stdout")
    stderr=$(cat "$tmp/stderr")
}

# ---------------------------------------------------------------------------
# Synthetic "hp-probe -bnet -o5" output
# ---------------------------------------------------------------------------

# Header of the device table, as printed by HPLIP's "probe.py"
cat > "$tmp/header" <<'EOF'
DEVICE DISCOVERY

Probing network for printers. Please wait, this will take approx. 5 seconds...

EOF

# Resolver stubs, in the output format of "avahi-resolve-address" and "host"
cat > "$tmp/resolvers" <<'EOF'
#!/bin/sh
case "$1" in
    192.168.1.5) printf '192.168.1.5\tprinter1.local\n' ;;
    192.168.1.6) printf '192.168.1.6\tprinter6.local\n' ;;
    192.168.1.8) printf '192.168.1.8\tprinter8.local\n' ;;
    192.168.1.9) printf '5.1.168.192.in-addr.arpa domain name pointer printer9.example.com.\n' ;;
esac
exit 0
EOF
chmod +x "$tmp/resolvers"

# A printer with the host name in the third column of the table
cat > "$tmp/named" <<'EOF'
Device URI                                  Model                    Name
------------------------------------------  -----------------------  --------------------
hp:/net/OfficeJet_Pro_8600?ip=192.168.1.5   OfficeJet_Pro_8600       printer1

Found 1 printer(s) on the 'net' bus.

Done.
EOF

# A printer whose SLP response has no "x-hp-hn" attribute, so that HPLIP
# reports an empty host name (base/slp.py sets "hn" to "" then) and the
# third column of the table stays empty
cat > "$tmp/unnamed" <<'EOF'
Device URI                                  Model                    Name
------------------------------------------  -----------------------  --------------------
hp:/net/LaserJet_1020?ip=192.168.1.6        LaserJet_1020

Found 1 printer(s) on the 'net' bus.

Done.
EOF

# A printer with several ports, so that the URI has a "port" query
cat > "$tmp/multiport" <<'EOF'
Device URI                                            Model                    Name
----------------------------------------------------  -----------------------  ----------
hp:/net/OfficeJet_Pro_8600?ip=192.168.1.7&port=2      OfficeJet_Pro_8600       printer2

Found 1 printer(s) on the 'net' bus.

Done.
EOF

# A printerless network
cat > "$tmp/printerless" <<'EOF'
WARNING: No devices found on the 'net' bus. If this isn't the result you are expecting,
WARNING: check your network connections and make sure your internet
WARNING: firewall software is disabled.

Done.
EOF

# A hostile device, announcing a model name and a host name which try to
# run commands (the device only has to answer a discovery request with
# these strings, and "${IFS}" avoids the white space which would break the
# table format)
cat > "$tmp/hostile" <<'EOF'
Device URI                                                          Model                              Name
-----------------------------------------------------------------   --------------------------------  ------------------------------
hp:/net/Evil$(touch${IFS}/tmp/hp-canary)?ip=192.168.1.8             Evil$(touch${IFS}/tmp/hp-canary)  x";touch /tmp/hp-canary;"y

Found 1 printer(s) on the 'net' bus.

Done.
EOF

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "# A printerless network only reports the missing helper tools"
rm -f /tmp/hp-canary
cat "$tmp/header" "$tmp/printerless" > "$tmp/out"
write_probe "$tmp/out" "-"
run -
check "printerless network exits without error" "0" "$status"
check "printerless network emits no device record" "" "$stdout"
check "printerless network only warns about the missing tools" \
    "WARNING: \"avahi-resolve-address\" not found, URIs will use IP address instead of ZeroConf name
WARNING: \"host\" utility not found, URIs will use IP address instead of host name" "$stderr"

echo "# A discovered printer is announced as a standard HP device record"
cat "$tmp/header" "$tmp/named" > "$tmp/out"
write_probe "$tmp/out" "$tmp/resolvers"
run -
check "discovered printer exits without error" "0" "$status"
check "discovered printer is announced with its ZeroConf name" \
    'network hp:/net/OfficeJet_Pro_8600?zc=printer1 "OfficeJet Pro 8600" "OfficeJet Pro 8600 Network printer1 HPLIP" "MFG:OfficeJet;MDL:OfficeJet Pro 8600;" ""' \
    "$stdout"
check "discovered printer reports no error" "" "$stderr"

echo "# A printer without host name is announced, too"
cat "$tmp/header" "$tmp/unnamed" > "$tmp/out"
write_probe "$tmp/out" "$tmp/resolvers"
run -
check "printer without host name exits without error" "0" "$status"
check "printer without host name is announced with the resolved name" \
    'network hp:/net/LaserJet_1020?zc=printer6 "LaserJet 1020" "LaserJet 1020 Network printer6 HPLIP" "MFG:LaserJet;MDL:LaserJet 1020;" ""' \
    "$stdout"
check "printer without host name reports no error" "" "$stderr"

echo "# Without ZeroConf resolution the IP address is kept in the device URI"
cat "$tmp/header" "$tmp/named" > "$tmp/out"
write_probe "$tmp/out" "-"
run -
check "device URI keeps the IP address without ZeroConf" \
    'network hp:/net/OfficeJet_Pro_8600?ip=192.168.1.5 "OfficeJet Pro 8600" "OfficeJet Pro 8600 Network printer1 HPLIP" "MFG:OfficeJet;MDL:OfficeJet Pro 8600;" ""' \
    "$stdout"

echo "# Without ZeroConf resolution the host name is used for the device URI"
cat > "$tmp/hostonly" <<'EOF'
#!/bin/sh
case "$1" in
    192.168.1.5) printf '5.1.168.192.in-addr.arpa domain name pointer printer1.example.com.\n' ;;
esac
exit 0
EOF
rm -f "$bin/avahi-resolve-address" "$bin/host"
cp "$tmp/hostonly" "$bin/host"
chmod +x "$bin/host"
run -
check "device URI uses the host name without ZeroConf" \
    'network hp:/net/OfficeJet_Pro_8600?hostname=printer1.example.com "OfficeJet Pro 8600" "OfficeJet Pro 8600 Network printer1 HPLIP" "MFG:OfficeJet;MDL:OfficeJet Pro 8600;" ""' \
    "$stdout"
check "missing ZeroConf resolver is warned about" \
    "WARNING: \"avahi-resolve-address\" not found, URIs will use IP address instead of ZeroConf name" "$stderr"

echo "# A multi-port device keeps its device URI"
cat "$tmp/header" "$tmp/multiport" > "$tmp/out"
write_probe "$tmp/out" "$tmp/resolvers"
run -
check "multi-port device keeps its device URI" \
    'network hp:/net/OfficeJet_Pro_8600?ip=192.168.1.7&port=2 "OfficeJet Pro 8600" "OfficeJet Pro 8600 Network printer2 HPLIP" "MFG:OfficeJet;MDL:OfficeJet Pro 8600;" ""' \
    "$stdout"

echo "# Without a printer name the resolved host name identifies the device"
cat "$tmp/header" "$tmp/unnamed" > "$tmp/out"
write_probe "$tmp/out" "-"
cat > "$bin/host" <<'EOF'
#!/bin/sh
case "$1" in
    192.168.1.6) printf '6.1.168.192.in-addr.arpa domain name pointer printer6.example.com.\n' ;;
esac
exit 0
EOF
chmod +x "$bin/host"
run -
check "unnamed printer is identified by its host name" \
    'network hp:/net/LaserJet_1020?hostname=printer6.example.com "LaserJet 1020" "LaserJet 1020 Network printer6.example.com HPLIP" "MFG:LaserJet;MDL:LaserJet 1020;" ""' \
    "$stdout"

echo "# Without a printer name or resolver the IP address identifies the device"
write_probe "$tmp/out" "-"
run -
check "unnamed printer is identified by its IP address" \
    'network hp:/net/LaserJet_1020?ip=192.168.1.6 "LaserJet 1020" "LaserJet 1020 Network 192.168.1.6 HPLIP" "MFG:LaserJet;MDL:LaserJet 1020;" ""' \
    "$stdout"

echo "# A device without any identifying name is announced by its model only"
cat > "$tmp/anonymous" <<'EOF'
Device URI                                            Model                    Name
----------------------------------------------------  -----------------------  ----------
hp:/net/OfficeJet_Pro_8600?ip=192.168.1.7&port=2      OfficeJet_Pro_8600

Found 1 printer(s) on the 'net' bus.

Done.
EOF
cat "$tmp/header" "$tmp/anonymous" > "$tmp/out"
write_probe "$tmp/out" "$tmp/resolvers"
run -
check "anonymous device is announced by its model only" \
    'network hp:/net/OfficeJet_Pro_8600?ip=192.168.1.7&port=2 "OfficeJet Pro 8600" "OfficeJet Pro 8600 HPLIP" "MFG:OfficeJet;MDL:OfficeJet Pro 8600;" ""' \
    "$stdout"

echo "# A full manufacturer name is kept whole in the device ID"
cat > "$tmp/fullmfg" <<'EOF'
Device URI                                            Model                              Name
----------------------------------------------------  ---------------------------------  ----------
hp:/net/LaserJet_4000?ip=192.168.1.5                  Hewlett-Packard_LaserJet_4000      printer1
hp:/net/DeskJet_990C?ip=192.168.1.6                   Hewlett_Packard_DeskJet_990C       printer6

Found 2 printer(s) on the 'net' bus.

Done.
EOF
cat "$tmp/header" "$tmp/fullmfg" > "$tmp/out"
write_probe "$tmp/out" "$tmp/resolvers"
run -
check "full manufacturer names are kept whole" \
    'network hp:/net/LaserJet_4000?zc=printer1 "Hewlett-Packard LaserJet 4000" "Hewlett-Packard LaserJet 4000 Network printer1 HPLIP" "MFG:Hewlett-Packard;MDL:Hewlett-Packard LaserJet 4000;" ""
network hp:/net/DeskJet_990C?zc=printer6 "Hewlett Packard DeskJet 990C" "Hewlett Packard DeskJet 990C Network printer6 HPLIP" "MFG:Hewlett Packard;MDL:Hewlett Packard DeskJet 990C;" ""' \
    "$stdout"

echo "# A device without a model name is skipped with a warning"
cat > "$tmp/nomodel" <<'EOF'
Device URI                                            Model                    Name
----------------------------------------------------  -----------------------  ----------
hp:/net/Unknown?ip=192.168.1.10
hp:/net/OfficeJet_Pro_8600?ip=192.168.1.5             OfficeJet_Pro_8600       printer1

Found 2 printer(s) on the 'net' bus.

Done.
EOF
cat "$tmp/header" "$tmp/nomodel" > "$tmp/out"
write_probe "$tmp/out" "$tmp/resolvers"
run -
check "device without model name does not fail discovery" "0" "$status"
check "device without model name is not announced" \
    'network hp:/net/OfficeJet_Pro_8600?zc=printer1 "OfficeJet Pro 8600" "OfficeJet Pro 8600 Network printer1 HPLIP" "MFG:OfficeJet;MDL:OfficeJet Pro 8600;" ""' \
    "$stdout"
check "device without model name is warned about" \
    'WARNING: "hp-probe" reported a printer without model name, device URI "hp:/net/Unknown?ip=192.168.1.10" ignored' \
    "$stderr"

echo "# A device answering twice is announced only once"
cat "$tmp/header" "$tmp/named" "$tmp/named" > "$tmp/out"
write_probe "$tmp/out" "$tmp/resolvers"
run -
check "duplicate discovery response is announced once" \
    'network hp:/net/OfficeJet_Pro_8600?zc=printer1 "OfficeJet Pro 8600" "OfficeJet Pro 8600 Network printer1 HPLIP" "MFG:OfficeJet;MDL:OfficeJet Pro 8600;" ""' \
    "$stdout"

echo "# A hostile device cannot run commands and cannot forge device fields"
cat "$tmp/header" "$tmp/hostile" > "$tmp/out"
write_probe "$tmp/out" "$tmp/resolvers"
run -
check "hostile device exits without error" "0" "$status"
if [ -e /tmp/hp-canary ]; then
    not_ok "hostile device cannot run commands" "/tmp/hp-canary was created"
    rm -f /tmp/hp-canary
else
    ok "hostile device cannot run commands"
fi
check "hostile device reports no error" "" "$stderr"
# shellcheck disable=SC2016
check "hostile device cannot forge device record fields" \
    'network hp:/net/Evil$(touch${IFS}/tmp/hp-canary)?zc=printer8 "Evil$(touch${IFS}/tmp/hp-canary)" "Evil$(touch${IFS}/tmp/hp-canary) Network x;touch /tmp/hp-canary;y HPLIP" "Evil$(touch${IFS}/tmp/hp-canary)" ""' \
    "$stdout"
quotes=$(printf '%s' "$stdout" | tr -cd '"' | wc -c)
check "hostile device record keeps its four quoted fields" "8" "$quotes"

echo "# No Perl interpreter is needed"
cat > "$bin/perl" <<'EOF'
#!/bin/sh
echo "PERL-WAS-CALLED" 1>&2
exit 1
EOF
chmod +x "$bin/perl"
cat "$tmp/header" "$tmp/named" > "$tmp/out"
write_probe "$tmp/out" "$tmp/resolvers"
run -
check "discovery works without Perl" \
    'network hp:/net/OfficeJet_Pro_8600?zc=printer1 "OfficeJet Pro 8600" "OfficeJet Pro 8600 Network printer1 HPLIP" "MFG:OfficeJet;MDL:OfficeJet Pro 8600;" ""' \
    "$stdout"
case "$stderr" in
    *PERL-WAS-CALLED*) not_ok "Perl is not called" "$stderr" ;;
    *) ok "Perl is not called" ;;
esac

echo "# A missing or unusable \"hp-probe\" is reported"
rm -f "$bin/hp-probe"
run -
check "missing \"hp-probe\" fails" "1" "$status"
check "missing \"hp-probe\" is reported" \
    'ERROR: "hp-probe" (HPLIP) not found' "$stderr"

cat > "$bin/hp-probe" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$bin/hp-probe"
run -
check "unusable \"hp-probe\" fails" "1" "$status"
check "unusable \"hp-probe\" is reported" \
    'ERROR: "hp-probe" (HPLIP) not executable (Is Python installed?)' "$stderr"

# ---------------------------------------------------------------------------

echo "#"
if [ "$failures" -eq 0 ]; then
    echo "# All $tests checks passed."
    exit 0
fi
echo "# $failures of $tests checks failed."
exit 1
