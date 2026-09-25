#!/bin/sh
#
# Regression tests for "scripts/hplip-plugin-state.sh", the durable
# transaction which installs, removes, and recovers the HP proprietary
# plugin.
#
# The point of the transaction is what happens when the Printer Application
# is terminated in the middle of an upgrade, so the tests here do exactly
# that: they drive the transaction phase by phase with "begin" and "step",
# stop wherever the phase sequence allows a termination, and then check
# that "recover" reaches a state in which the web interface can report the
# version of a plugin which really is installed. Termination between a
# rename and the journal update which follows it cannot be reached through
# the command line, it is reproduced by performing that one rename by hand
# and leaving the journal where it was.
#
# Usage: tests/hp-plugin-state.sh [helper]

set -u

here=$(cd "$(dirname "$0")" && pwd)
helper=${1:-$here/../scripts/hplip-plugin-state.sh}

if [ ! -f "$helper" ]; then
    echo "ERROR: helper \"$helper\" not found" 1>&2
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

tests=0
failures=0
cases=0

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

# check <test name> <expected> <actual>
check()
{
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        not_ok "$1" "expected [$2], got [$3]"
    fi
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# start_case - a private plugin root and state directory for one test case
start_case()
{
    cases=$((cases + 1))
    work=$tmp/case-$cases
    root=$work/plugin-root
    state=$work/state
    mkdir -p "$root" "$state"
}

# make_plugin <directory> <name> <marker> - a plugin directory which can be
#     recognized by the marker it contains
make_plugin()
{
    rm -rf "${1:?}/${2:?}"
    mkdir -p "${1:?}/${2:?}"
    printf '%s\n' "$3" > "$1/$2/marker"
    printf 'shared library of the %s plugin\n' "$3" > "$1/$2/libhpmud.so"
}

# marker_of <directory> - the marker of a plugin directory, "<none>" if
#     there is no plugin there
marker_of()
{
    if [ -f "$1/marker" ]; then
        cat "$1/marker"
    else
        printf '<none>'
    fi
}

# present <path> - "yes" if the path exists, "no" if it does not
present()
{
    if [ -e "$1" ] || [ -L "$1" ]; then
        printf 'yes'
    else
        printf 'no'
    fi
}

# write_state_file <state-dir> <installed> <eula> <version> - an
#     "hplip.state" as the Printer Application writes it
write_state_file()
{
    {
        printf '[plugin]\n'
        printf 'installed = %s\n' "$2"
        if [ -n "$3" ]; then
            printf 'eula = %s\n' "$3"
        fi
        if [ -n "$4" ]; then
            printf 'version = %s\n' "$4"
        fi
    } > "$1/hplip.state"
}

# c_reader <state-file> <section> <key> - the reading side of the Printer
#     Application's "get_config_value()": a key at the start of a line
#     inside the given section, followed by optional white space and "=".
#     Written with "awk" on purpose, so that it is a check of the file and
#     not a second copy of the writer.
c_reader()
{
    awk -v section="$2" -v key="$3" '
        /^\[/ {
            in_section = (substr($0, 2, length(section)) == section &&
                          substr($0, 2 + length(section), 1) == "]")
            next
        }
        in_section && tolower(substr($0, 1, length(key))) == tolower(key) {
            rest = substr($0, length(key) + 1)
            sub(/^[ \t]*/, "", rest)
            if (substr(rest, 1, 1) == "=") {
                rest = substr(rest, 2)
                sub(/^[ \t]*/, "", rest)
                print rest
                exit
            }
        }
    ' "$1"
}

# snap_grep <state-dir> <hplip-version> - what the Snap's start-up script
#     waits for before it loads firmware:
#       grep -qi 'version *= *<HPLIP version>' <state-dir>/hplip.state
snap_grep()
{
    grep -qi 'version *= *'"$2" "$1/hplip.state"
}

# run <arguments...> - run the helper, capturing its output and its status
run()
{
    out=$("$helper" "$@" 2>"$tmp/stderr")
    status=$?
    err=$(cat "$tmp/stderr")
}

# no_empty_line <test name> - the application logs every line a subprocess
#     prints and assumes it has at least one character
no_empty_line()
{
    empty=$(printf '%s\n' "$out" | grep -c '^$')
    if [ -z "$out" ]; then
        empty=0
    fi
    check "$1" 0 "$empty"
}

# state_after <expected installed> <expected version> <what>
state_after()
{
    check "$3: the installed flag" "$1" "$(c_reader "$state/hplip.state" plugin installed)"
    check "$3: the registered version" "$2" "$(c_reader "$state/hplip.state" plugin version)"
}

# A plugin root in the state in which an upgrade starts: an installed and
# registered plugin of version 3.23.8 and the freshly downloaded and
# verified plugin of version 3.23.12 in the staging directory.
upgrade_ready()
{
    start_case
    make_plugin "$root" plugin old
    make_plugin "$root" plugin_tmp new
    write_state_file "$state" 1 1 3.23.8
}

# ---------------------------------------------------------------------------

echo "# An installation which runs through replaces the plugin and registers it"
upgrade_ready
run install "$root" "$state" 3.23.12
check "install succeeds" 0 "$status"
check "install says nothing went wrong" "" "$err"
check "the new plugin is active" new "$(marker_of "$root/plugin")"
check "the new plugin is complete" yes "$(present "$root/plugin/libhpmud.so")"
check "the previous plugin is removed" no "$(present "$root/plugin_old")"
check "no staging directory is left behind" no "$(present "$root/plugin_tmp")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 1 3.23.12 "after a complete installation"
check "the license acceptance is registered" 1 "$(c_reader "$state/hplip.state" plugin eula)"
check "the Snap start-up script finds the new version" 0 "$(snap_grep "$state" 3.23.12 && echo 0 || echo 1)"
check "the Snap start-up script rejects the old version" 1 "$(snap_grep "$state" 3.23.8 && echo 0 || echo 1)"
no_empty_line "install prints no empty line"

echo "# An installation of a plugin which is not installed yet works"
start_case
make_plugin "$root" plugin_tmp new
write_state_file "$state" 0 "" ""
run install "$root" "$state" 3.23.12
check "install succeeds without a previous plugin" 0 "$status"
check "the new plugin is active" new "$(marker_of "$root/plugin")"
check "the previous plugin is removed" no "$(present "$root/plugin_old")"
state_after 1 3.23.12 "after a first installation"
check "the license acceptance is registered" 1 "$(c_reader "$state/hplip.state" plugin eula)"

echo "# An installation into an empty directory works"
start_case
make_plugin "$root" plugin_tmp new
run install "$root" "$state" 3.23.12
check "install succeeds without a state file" 0 "$status"
check "the new plugin is active" new "$(marker_of "$root/plugin")"
state_after 1 3.23.12 "after an installation without a state file"

# ---------------------------------------------------------------------------

echo "# A termination before anything was moved installs the staged plugin"
upgrade_ready
run begin "$root" "$state" install 3.23.12
check "begin succeeds" 0 "$status"
check "begin writes the journal" yes "$(present "$root/.plugin-txn")"
check "begin records what it replaces" 3.23.8 "$(sed -n 's/^old_version=//p' "$root/.plugin-txn")"
check "begin records that it installs" install "$(sed -n 's/^op=//p' "$root/.plugin-txn")"
check "begin records the new version" 3.23.12 "$(sed -n 's/^new_version=//p' "$root/.plugin-txn")"
check "begin does not move the plugin" old "$(marker_of "$root/plugin")"
check "begin does not move the staging directory" new "$(marker_of "$root/plugin_tmp")"
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the staged plugin is active" new "$(marker_of "$root/plugin")"
check "the previous plugin is removed" no "$(present "$root/plugin_old")"
check "no staging directory is left behind" no "$(present "$root/plugin_tmp")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 1 3.23.12 "after recovering a prepared transaction"
no_empty_line "recover prints no empty line"

echo "# A termination between preserving and swapping does not lose a plugin"
upgrade_ready
run begin "$root" "$state" install 3.23.12
run step "$root" "$state"
check "the first step succeeds" 0 "$status"
check "the plugin is preserved, not deleted" old "$(marker_of "$root/plugin_old")"
check "the plugin directory is not in place" no "$(present "$root/plugin")"
check "the staged plugin waits" new "$(marker_of "$root/plugin_tmp")"
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "a plugin is active again" yes "$(present "$root/plugin")"
check "the staged plugin is the active one" new "$(marker_of "$root/plugin")"
check "no staging directory is left behind" no "$(present "$root/plugin_tmp")"
check "the previous plugin is removed" no "$(present "$root/plugin_old")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 1 3.23.12 "after recovering a preserved transaction"

echo "# A termination between the directory exchange and the registration"
echo "# recovers the version which is really installed"
upgrade_ready
run begin "$root" "$state" install 3.23.12
run step "$root" "$state"
run step "$root" "$state"
check "the second step succeeds" 0 "$status"
check "the new plugin is in place" new "$(marker_of "$root/plugin")"
check "the previous plugin is still there" old "$(marker_of "$root/plugin_old")"
check "the state file still describes the old plugin" \
    3.23.8 "$(c_reader "$state/hplip.state" plugin version)"
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the new plugin is still the active one" new "$(marker_of "$root/plugin")"
check "no staging directory is left behind" no "$(present "$root/plugin_tmp")"
check "the previous plugin is removed" no "$(present "$root/plugin_old")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 1 3.23.12 "after recovering a swapped transaction"
check "the license acceptance is registered" 1 "$(c_reader "$state/hplip.state" plugin eula)"
check "the Snap start-up script finds the recovered version" \
    0 "$(snap_grep "$state" 3.23.12 && echo 0 || echo 1)"

echo "# A termination between the registration and the clean-up only cleans up"
upgrade_ready
run begin "$root" "$state" install 3.23.12
run step "$root" "$state"
run step "$root" "$state"
run step "$root" "$state"
check "the third step succeeds" 0 "$status"
state_after 1 3.23.12 "after a registered transaction"
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the active plugin is unchanged" new "$(marker_of "$root/plugin")"
check "the previous plugin is removed" no "$(present "$root/plugin_old")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 1 3.23.12 "after recovering a registered transaction"

echo "# Recovering twice changes nothing"
run recover "$root" "$state"
check "a second recover succeeds" 0 "$status"
check "the active plugin is unchanged" new "$(marker_of "$root/plugin")"
check "the journal stays removed" no "$(present "$root/.plugin-txn")"
state_after 1 3.23.12 "after recovering twice"

# ---------------------------------------------------------------------------
# A termination between a rename and the journal update which follows it
# cannot be reached through the command line, so the rename is done by hand
# here and the journal is left at the phase it had before.

echo "# A termination right after the plugin was preserved is recovered"
upgrade_ready
run begin "$root" "$state" install 3.23.12
mv "$root/plugin" "$root/plugin_old"
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the staged plugin is active" new "$(marker_of "$root/plugin")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 1 3.23.12 "after recovering a half-done preservation"

echo "# A termination right after the exchange is recovered"
upgrade_ready
run begin "$root" "$state" install 3.23.12
run step "$root" "$state"
mv "$root/plugin_tmp" "$root/plugin"
check "the new plugin is in place before the recovery" new "$(marker_of "$root/plugin")"
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the new plugin is still the active one" new "$(marker_of "$root/plugin")"
check "the previous plugin is removed" no "$(present "$root/plugin_old")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 1 3.23.12 "after recovering a half-done exchange"

echo "# A termination right after the state file was written is recovered"
upgrade_ready
run begin "$root" "$state" install 3.23.12
run step "$root" "$state"
run step "$root" "$state"
write_state_file "$state" 1 1 3.23.12
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the new plugin is still the active one" new "$(marker_of "$root/plugin")"
check "the previous plugin is removed" no "$(present "$root/plugin_old")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 1 3.23.12 "after recovering a half-done registration"

# ---------------------------------------------------------------------------
# Rolling back: a transaction which cannot be finished must leave the
# plugin which was installed before it in place and registered.

echo "# A vanished staging directory rolls the installation back"
upgrade_ready
run begin "$root" "$state" install 3.23.12
rm -rf "$root/plugin_tmp"
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the installed plugin is still the active one" old "$(marker_of "$root/plugin")"
check "the installed plugin is complete" yes "$(present "$root/plugin/libhpmud.so")"
check "no staging directory is left behind" no "$(present "$root/plugin_tmp")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 1 3.23.8 "after rolling a prepared transaction back"
check "the license acceptance is kept" 1 "$(c_reader "$state/hplip.state" plugin eula)"

echo "# A vanished staging directory after the preservation rolls back"
upgrade_ready
run begin "$root" "$state" install 3.23.12
run step "$root" "$state"
rm -rf "$root/plugin_tmp"
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the preserved plugin is put back" old "$(marker_of "$root/plugin")"
check "the preserved plugin is complete" yes "$(present "$root/plugin/libhpmud.so")"
check "no preserved copy is left behind" no "$(present "$root/plugin_old")"
check "no staging directory is left behind" no "$(present "$root/plugin_tmp")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 1 3.23.8 "after rolling a preserved transaction back"

echo "# A rollback restores a state file which the application did not write"
start_case
make_plugin "$root" plugin old
make_plugin "$root" plugin_tmp new
printf '[plugin]\ninstalled=1\nversion=3.23.8\n' > "$state/hplip.state"
run begin "$root" "$state" install 3.23.12
rm -rf "$root/plugin_tmp"
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the installed plugin is active again" old "$(marker_of "$root/plugin")"
check "a version without white space around \"=\" is read" \
    3.23.8 "$(c_reader "$state/hplip.state" plugin version)"
state_after 1 3.23.8 "after rolling back a state file without white space"

# ---------------------------------------------------------------------------

echo "# Removing the plugin unregisters it and leaves nothing behind"
upgrade_ready
make_plugin "$root" plugin_tmp new
run remove "$root" "$state"
check "remove succeeds" 0 "$status"
check "the plugin is removed" no "$(present "$root/plugin")"
check "no preserved copy is left behind" no "$(present "$root/plugin_old")"
check "no staging directory is left behind" no "$(present "$root/plugin_tmp")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 0 "" "after a complete removal"
check "the license acceptance is not registered any more" \
    "" "$(c_reader "$state/hplip.state" plugin eula)"

echo "# A termination during a removal is recovered"
upgrade_ready
run begin "$root" "$state" remove
run step "$root" "$state"
check "the plugin is preserved for the removal" old "$(marker_of "$root/plugin_old")"
check "the state file still describes the installed plugin" \
    3.23.8 "$(c_reader "$state/hplip.state" plugin version)"
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the plugin is removed" no "$(present "$root/plugin")"
check "no preserved copy is left behind" no "$(present "$root/plugin_old")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 0 "" "after recovering a half-done removal"

echo "# A removal which was terminated before anything moved is recovered"
upgrade_ready
run begin "$root" "$state" remove
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the plugin is removed" no "$(present "$root/plugin")"
check "no preserved copy is left behind" no "$(present "$root/plugin_old")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 0 "" "after recovering a prepared removal"

echo "# Removing an installation which is not there is not an error"
start_case
run remove "$root" "$state"
check "remove succeeds without a plugin" 0 "$status"
check "no plugin is left behind" no "$(present "$root/plugin")"
check "the journal is removed" no "$(present "$root/.plugin-txn")"
state_after 0 "" "after removing nothing"

# ---------------------------------------------------------------------------

echo "# Directories of an earlier start are cleaned up"
start_case
make_plugin "$root" plugin old
make_plugin "$root" plugin_tmp new
write_state_file "$state" 1 1 3.23.8
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the never installed staging directory is removed" no "$(present "$root/plugin_tmp")"
check "the installed plugin is untouched" old "$(marker_of "$root/plugin")"
state_after 1 3.23.8 "after cleaning up a staging directory"
no_empty_line "cleaning up prints no empty line"

echo "# A clean-up does not touch a plugin which is only preserved"
start_case
make_plugin "$root" plugin_old old
write_state_file "$state" 1 1 3.23.8
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the only copy of the plugin is kept" old "$(marker_of "$root/plugin_old")"
check "no plugin is invented" no "$(present "$root/plugin")"

echo "# A preserved copy next to an installed plugin is an orphan"
start_case
make_plugin "$root" plugin old
make_plugin "$root" plugin_old older
printf 'unrelated content\n' > "$state/hplip.state"
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the orphaned preserved copy is removed" no "$(present "$root/plugin_old")"
check "the installed plugin is untouched" old "$(marker_of "$root/plugin")"
check "the state file is untouched" "unrelated content" "$(cat "$state/hplip.state")"

echo "# Recovering a directory which does not exist is not an error"
start_case
run recover "$work/never-downloaded" "$state"
check "recover succeeds without a plugin root" 0 "$status"

echo "# Recovering an installation which is not interrupted changes nothing"
start_case
make_plugin "$root" plugin old
write_state_file "$state" 1 1 3.23.8
before=$(cat "$state/hplip.state")
run recover "$root" "$state"
check "recover succeeds" 0 "$status"
check "the installed plugin is untouched" old "$(marker_of "$root/plugin")"
check "the state file is untouched" "$before" "$(cat "$state/hplip.state")"
check "no journal is created" no "$(present "$root/.plugin-txn")"

# ---------------------------------------------------------------------------

echo "# A transaction which cannot start does not change anything"
upgrade_ready
run install "$root" "$state"
check "install without a version fails" 2 "$status"
check "nothing is moved" old "$(marker_of "$root/plugin")"
check "the staging directory is kept" new "$(marker_of "$root/plugin_tmp")"
check "no journal is created" no "$(present "$root/.plugin-txn")"

echo "# A version is not allowed to smuggle a command"
upgrade_ready
canary=$work/canary
mkdir -p "$canary"
# The single quotes are the point: these are the characters a shell would
# run if they ever reached a command line, and they must stay text
# shellcheck disable=SC2016
for version in '3.23.12; rm -rf '"$canary" '3.23.12 && rm -rf '"$canary" \
               '$(rm -rf '"$canary"')' '`rm -rf '"$canary"'`' '3.23.12 3.24.0' \
               '../3.23.12'; do
    run install "$root" "$state" "$version"
    check "install rejects the version \"$version\"" 1 "$status"
done
check "no command was executed" yes "$(present "$canary")"
check "nothing is moved" old "$(marker_of "$root/plugin")"
check "the staging directory is kept" new "$(marker_of "$root/plugin_tmp")"
check "no journal is created" no "$(present "$root/.plugin-txn")"

echo "# Only one transaction can be in progress"
upgrade_ready
run begin "$root" "$state" install 3.23.12
check "the first begin succeeds" 0 "$status"
run begin "$root" "$state" install 3.23.12
check "a second begin fails" 1 "$status"
run install "$root" "$state" 3.23.12
check "an install next to a transaction fails" 1 "$status"
check "the running transaction is still intact" \
    3.23.8 "$(sed -n 's/^old_version=//p' "$root/.plugin-txn")"
run recover "$root" "$state"
check "the running transaction is recovered" 0 "$status"
check "the staged plugin is active" new "$(marker_of "$root/plugin")"

echo "# An install without a staging directory does not touch the plugin"
upgrade_ready
rm -rf "$root/plugin_tmp"
run install "$root" "$state" 3.23.12
check "install fails without a staged plugin" 1 "$status"
check "the installed plugin is untouched" old "$(marker_of "$root/plugin")"
check "no journal is left behind" no "$(present "$root/.plugin-txn")"
state_after 1 3.23.8 "after an install without a staging directory"

echo "# An unknown command and missing arguments are rejected"
run
check "no arguments is a usage error" 2 "$status"
run frobnicate "$root" "$state"
check "an unknown command is a usage error" 2 "$status"
run install "$root"
check "a missing argument is a usage error" 2 "$status"
run begin "$root" "$state" install
check "an install transaction without a version is rejected" 1 "$status"
upgrade_ready
run begin "$root" "$state" frobnicate
check "an unknown transaction name is rejected" 1 "$status"
check "no journal is created" no "$(present "$root/.plugin-txn")"
run install "$work/never-downloaded" "$state" 3.23.12
check "an install into a directory which does not exist fails" 1 "$status"
run step "$root" "$state"
check "a step without a transaction fails" 1 "$status"

# ---------------------------------------------------------------------------

echo "#"
if [ "$failures" -eq 0 ]; then
    echo "# All $tests checks passed."
    exit 0
fi
echo "# $failures of $tests checks failed."
exit 1
