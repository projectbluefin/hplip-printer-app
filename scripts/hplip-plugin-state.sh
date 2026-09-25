#!/bin/sh
#
# "hplip-plugin-state.sh" - Install, remove, and recover the HP proprietary
#                           plugin with a durable transaction.
#
# The Printer Application installs the proprietary plugin of HPLIP by
# replacing the directory <plugin-root>/plugin with a newly downloaded and
# verified one. Doing this by removing "plugin" and then renaming
# "plugin_tmp" to "plugin" loses the previously installed plugin when the
# service is terminated in between (crash, "podman kill", power loss,
# container restart, automatic image update), and it leaves the
# registration of the plugin in "<state-dir>/hplip.state" behind, so that a
# restart can present a plugin directory and a registered version which do
# not belong together:
#
#  1. "plugin" is removed and the new directory is not yet in place: a
#     working installation is lost although the new plugin was never
#     activated.
#  2. "plugin" contains the new plugin but "hplip.state" still describes
#     the old (or no) plugin: the web interface reports a version which is
#     not the version which is actually loaded.
#  3. A "plugin_tmp" directory is left behind, without anything which would
#     explain it.
#
# This script replaces that sequence with a small journaled transaction.
# Every step is a single atomic directory rename, the journal
# "<plugin-root>/.plugin-txn" is always written and flushed *before* the
# rename it describes, and "recover" carries an interrupted transaction to
# its end. The old plugin is preserved as "<plugin-root>/plugin_old" until
# the new plugin is in place and registered, so the transaction never
# removes the only usable copy of a plugin.
#
# Directories and files:
#
#  <plugin-root>/plugin        Active plugin, as loaded by HPLIP
#  <plugin-root>/plugin_tmp    Staging, the downloaded and verified plugin
#  <plugin-root>/plugin_old    The previous plugin, kept during a swap
#  <plugin-root>/.plugin-txn   The transaction journal
#  <state-dir>/hplip.state     Registered plugin version, read by the
#                              Printer Application
#
# A transaction is a strict sequence of phases, therefore "recover" only
# has to complete the phase which was interrupted:
#
#  prepared    Journal written, nothing moved yet
#  preserved   "plugin" renamed to "plugin_old" (a no-op if not installed)
#  swapped     "plugin_tmp" renamed to "plugin"   (install only)
#  registered  "hplip.state" written for the new plugin
#
# Afterwards the journal is removed and "plugin_old" deleted ("commit").
# Because the phases are only ever left behind in a state which the next
# run can recognize from the directories alone, no step needs to read back
# what it did last time and every step is idempotent.
#
# Usage:
#   hplip-plugin-state.sh install  <plugin-root> <state-dir> <version>
#   hplip-plugin-state.sh remove   <plugin-root> <state-dir>
#   hplip-plugin-state.sh recover  <plugin-root> <state-dir>
#   hplip-plugin-state.sh begin    <plugin-root> <state-dir> install|remove [<version>]
#   hplip-plugin-state.sh step     <plugin-root> <state-dir>
#
# "install", "remove", and "recover" are the commands which the Printer
# Application uses, "begin" and "step" are the primitives these are built
# from. The test suite uses "begin" and "step" to stop the transaction at a
# defined phase, exactly like a termination of the service would, and then
# checks that "recover" reaches a consistent state again.
#
# Only a POSIX shell and the utilities "cat", "mv", "rm", and "sync" are
# needed, no "eval" is used, and every value is passed as an argument
# instead of being interpolated into a command line, so that neither a
# configuration file nor anything downloaded can become a command.

set -u

prog=${0##*/}

# White space which "read" and parameter expansion cannot express directly
tab=$(printf '\t')
cr=$(printf '\r')

# "sync <file>" is what makes a rename survive a restart. Where "sync"
# cannot flush a single path, flush everything instead, and if there is no
# "sync" at all, continue without it, as an installation which is not
# crash-safe is still better than an installation which does not work.
have_sync=1
command -v sync >/dev/null 2>&1 || have_sync=0

# Diagnostics go to stdout, which the Printer Application logs. No empty
# line is ever printed, as the logging of the application assumes that
# every line it reads from a subprocess has at least one character.
log()
{
    printf '%s: %s\n' "$prog" "$*"
}

die()
{
    log "$*"
    exit 1
}

usage()
{
    cat 1>&2 <<EOF
Usage: $prog install <plugin-root> <state-dir> <version>
       $prog remove  <plugin-root> <state-dir>
       $prog recover <plugin-root> <state-dir>
       $prog begin   <plugin-root> <state-dir> install|remove [<version>]
       $prog step    <plugin-root> <state-dir>
EOF
    exit 2
}

# fsync_path <path> - flush a file or directory, so that the rename which
#                     was performed before it is not lost by a restart
fsync_path()
{
    [ "$have_sync" = 1 ] || return 0
    sync "$1" 2>/dev/null && return 0
    sync 2>/dev/null || :
    return 0
}

# write_durable <directory> <file> - replace <file> with the contents read
#                                    from stdin, atomically and durably
write_durable()
{
    _wd_tmp=$2.tmp.$$
    rm -f "$_wd_tmp" 2>/dev/null || :
    if ! cat > "$_wd_tmp"; then
        rm -f "$_wd_tmp" 2>/dev/null || :
        return 1
    fi
    chmod 644 "$_wd_tmp" 2>/dev/null || :
    fsync_path "$_wd_tmp"
    if ! mv -f "$_wd_tmp" "$2"; then
        rm -f "$_wd_tmp" 2>/dev/null || :
        return 1
    fi
    fsync_path "$1"
    return 0
}

# strip_cr <line> - remove a trailing carriage return, result in "stripped"
strip_cr()
{
    stripped=${1%"$cr"}
}

# strip_leading_ws <string> - remove leading white space, result in
#                             "stripped"
strip_leading_ws()
{
    stripped=$1
    while :; do
        case "$stripped" in
            " "*) stripped=${stripped# } ;;
            "$tab"*) stripped=${stripped#"$tab"} ;;
            *) break ;;
        esac
    done
}

#
# The transaction journal
#

# journal_get <plugin-root> <key> - print the value of <key>, empty if the
#                                   key or the journal is not present
journal_get()
{
    _jg_value=
    if [ -f "$1/.plugin-txn" ]; then
        while IFS= read -r _jg_line; do
            case "$_jg_line" in
                "$2"=*)
                    _jg_value=${_jg_line#*=}
                    break
                    ;;
            esac
        done < "$1/.plugin-txn"
    fi
    printf '%s' "$_jg_value"
}

# journal_set <plugin-root> <phase> - move the journal to the next phase,
#                                     keeping the rest of the record
journal_set()
{
    _js_phase=$2
    {
        printf 'op=%s\n' "$(journal_get "$1" op)"
        printf 'phase=%s\n' "$_js_phase"
        printf 'new_version=%s\n' "$(journal_get "$1" new_version)"
        printf 'old_installed=%s\n' "$(journal_get "$1" old_installed)"
        printf 'old_eula=%s\n' "$(journal_get "$1" old_eula)"
        printf 'old_version=%s\n' "$(journal_get "$1" old_version)"
    } | write_durable "$1" "$1/.plugin-txn"
}

# journal_write <plugin-root> <op> <phase> <new version> <old installed>
#               <old eula> <old version>
journal_write()
{
    {
        printf 'op=%s\n' "$2"
        printf 'phase=%s\n' "$3"
        printf 'new_version=%s\n' "$4"
        printf 'old_installed=%s\n' "$5"
        printf 'old_eula=%s\n' "$6"
        printf 'old_version=%s\n' "$7"
    } | write_durable "$1" "$1/.plugin-txn"
}

#
# The plugin state file <state-dir>/hplip.state, a plain ".ini" file with
# a "[plugin]" section and the keys "installed", "eula", and "version".
# The Printer Application reads it with its "get_config_value()" function,
# which matches a key at the start of a line in the current section and
# accepts white space around the "=", and the Snap's start-up script greps
# it for "version *= *<HPLIP version>". Both are what the writer below
# produces. Keys of the section which this script does not know are
# dropped, which is safe because the file belongs to the Printer
# Application, "hp-plugin" is not used in the image, and nothing else reads
# it.
#

# state_get <state-dir> <key> - print the value of <key> in the "[plugin]"
#                               section, empty if it is not set
state_get()
{
    _sg_value=
    _sg_in_section=0
    if [ -f "$1/hplip.state" ]; then
        while IFS= read -r _sg_line; do
            strip_cr "$_sg_line"
            _sg_line=$stripped
            case "$_sg_line" in
                \[*\])
                    case "$_sg_line" in
                        "[plugin]") _sg_in_section=1 ;;
                        *) _sg_in_section=0 ;;
                    esac
                    continue
                    ;;
            esac
            [ "$_sg_in_section" = 1 ] || continue
            strip_leading_ws "$_sg_line"
            _sg_line=$stripped
            case "$_sg_line" in
                "$2"*) ;;
                *) continue ;;
            esac
            _sg_rest=${_sg_line#"$2"}
            strip_leading_ws "$_sg_rest"
            _sg_rest=$stripped
            case "$_sg_rest" in
                "="*) _sg_rest=${_sg_rest#=} ;;
                *) continue ;;
            esac
            strip_leading_ws "$_sg_rest"
            _sg_value=$stripped
            break
        done < "$1/hplip.state"
    fi
    printf '%s' "$_sg_value"
}

# state_write <state-dir> <installed> <eula> <version> - atomically replace
#                    the plugin state file. An empty <eula> or <version>
#                    omits the key, which is what an uninstalled plugin
#                    looks like.
state_write()
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
    } | write_durable "$1" "$1/hplip.state"
}

#
# The steps of the transaction
#

# step_preserve <plugin-root> <state-dir> - keep the currently installed
#                                          plugin as "plugin_old"
step_preserve()
{
    if [ "$(journal_get "$1" op)" = "install" ] &&
       [ ! -d "$1/plugin_tmp" ]; then
        # There is nothing to install any more (the staging directory was
        # removed while we were not looking), so do not touch the plugin
        # which is installed at the moment
        log "The plugin to install ($1/plugin_tmp) is gone, leaving the installed plugin untouched."
        rollback "$1" "$2"
        return 2
    fi

    if [ -e "$1/plugin" ]; then
        # A leftover "plugin_old" can only be older than the installed
        # plugin, as the previous transaction would have removed it
        rm -rf "$1/plugin_old" || return 1
        # Single atomic rename, the only copy of the plugin which exists in
        # this moment is "plugin_old"
        mv "$1/plugin" "$1/plugin_old" || return 1
        fsync_path "$1"
    fi

    journal_set "$1" preserved
}

# step_swap <plugin-root> <state-dir> - make the staged plugin the active one
step_swap()
{
    if [ -e "$1/plugin" ]; then
        # The rename below is already done and only the journal update got
        # lost, which can be told from the staging directory being gone
        if [ -e "$1/plugin_tmp" ]; then
            log "Both $1/plugin and $1/plugin_tmp exist, cannot decide which plugin is the new one."
            return 1
        fi
        journal_set "$1" swapped
        return $?
    fi

    if [ ! -d "$1/plugin_tmp" ]; then
        # Neither the installed nor the staged plugin exist, put back what
        # was installed before the transaction
        log "Neither the plugin to install ($1/plugin_tmp) nor an installed plugin exist."
        rollback "$1" "$2"
        return 2
    fi

    # Single atomic rename
    mv "$1/plugin_tmp" "$1/plugin" || return 1
    fsync_path "$1"

    journal_set "$1" swapped
}

# step_register <plugin-root> <state-dir> - write the plugin state file
step_register()
{
    if [ "$(journal_get "$1" op)" = "remove" ]; then
        state_write "$2" 0 "" "" || return 1
    else
        state_write "$2" 1 1 "$(journal_get "$1" new_version)" || return 1
    fi

    journal_set "$1" registered
}

# step_commit <plugin-root> <state-dir> - finish the transaction, leaving
#     nothing but the active plugin behind
step_commit()
{
    # The previous plugin is not needed any more, and a staging directory
    # which is still there belongs to a plugin which was never installed
    # (only possible when a removal was committed while a download was
    # waiting for its license to be accepted)
    rm -rf "$1/plugin_old" || return 1
    rm -rf "$1/plugin_tmp" || return 1
    fsync_path "$1"

    rm -f "$1/.plugin-txn" || return 1
    fsync_path "$1"
    return 0
}

# rollback <plugin-root> <state-dir> - undo everything the transaction did
#                                      so far, so that the plugin which was
#                                      installed before it is active again
rollback()
{
    log "Rolling the interrupted plugin transaction back."

    if [ ! -e "$1/plugin" ] && [ -e "$1/plugin_old" ]; then
        # The one and only copy of the previously installed plugin
        mv "$1/plugin_old" "$1/plugin" || return 1
        fsync_path "$1"
    fi

    # Staging belongs to a transaction which is not going to happen any
    # more, and leaving it behind is what the recovery is supposed to
    # prevent
    rm -rf "$1/plugin_tmp" || return 1

    _rb_installed=$(journal_get "$1" old_installed)
    case "$_rb_installed" in
        ''|*[!0-9]*) _rb_installed=0 ;;
    esac
    if [ "$_rb_installed" -ne 0 ]; then
        state_write "$2" "$_rb_installed" "$(journal_get "$1" old_eula)" \
                    "$(journal_get "$1" old_version)" || return 1
    else
        state_write "$2" 0 "" "" || return 1
    fi

    rm -f "$1/.plugin-txn" || return 1
    fsync_path "$1"

    log "The plugin which was installed before the transaction is active again."
    return 0
}

# do_step <plugin-root> <state-dir> - perform the next step of the
#     transaction in <plugin-root>.
#     Returns 0 if the transaction advanced, 2 if it was rolled back and is
#     therefore finished, and 1 on an error.
do_step()
{
    _ds_op=$(journal_get "$1" op)
    _ds_phase=$(journal_get "$1" phase)

    if [ -z "$_ds_op" ] || [ -z "$_ds_phase" ]; then
        log "No plugin transaction in progress in $1."
        return 1
    fi

    case "$_ds_op:$_ds_phase" in
        install:prepared)  step_preserve "$1" "$2" ;;
        install:preserved) step_swap "$1" "$2" ;;
        install:swapped)   step_register "$1" "$2" ;;
        remove:prepared)   step_preserve "$1" "$2" ;;
        remove:preserved)  step_register "$1" "$2" ;;
        *:registered)      step_commit "$1" "$2" ;;
        *)
            log "Unknown plugin transaction state \"$_ds_op:$_ds_phase\" in $1."
            return 1
            ;;
    esac
}

# transaction_loop <plugin-root> <state-dir> - carry the transaction in
#     <plugin-root> through to its end.
#     Returns 0 if it was committed, 2 if it was rolled back, 1 on error.
transaction_loop()
{
    _tl_rollback=0
    _tl_steps=0

    while [ -f "$1/.plugin-txn" ]; do
        do_step "$1" "$2"
        _tl_status=$?
        case "$_tl_status" in
            0) ;;
            2)
                _tl_rollback=1
                break
                ;;
            *) return 1 ;;
        esac

        _tl_steps=$((_tl_steps + 1))
        if [ "$_tl_steps" -gt 16 ]; then
            log "The plugin transaction in $1 does not terminate."
            return 1
        fi
    done

    if [ "$_tl_rollback" = 1 ]; then
        return 2
    fi
    return 0
}

#
# The commands
#

# do_begin <plugin-root> <state-dir> <op> [<version>] - record what the
#     transaction in <plugin-root> is going to do and what it is going to
#     replace, before anything is moved
do_begin()
{
    _db_op=$3
    _db_version=${4:-}

    [ -d "$1" ] || die "The plugin directory $1 does not exist."

    if [ -f "$1/.plugin-txn" ]; then
        die "A plugin transaction is already in progress in $1."
    fi

    case "$_db_op" in
        install)
            [ -n "$_db_version" ] || die "An install transaction needs a plugin version."
            case "$_db_version" in
                *[!0-9A-Za-z._+-]*)
                    die "The plugin version \"$_db_version\" contains characters which are not allowed in a version."
                    ;;
            esac
            [ -d "$1/plugin_tmp" ] ||
                die "There is no plugin to install in $1/plugin_tmp."
            ;;
        remove) ;;
        *) die "Unknown transaction \"$_db_op\"." ;;
    esac

    journal_write "$1" "$_db_op" prepared "$_db_version" \
                  "$(state_get "$2" installed)" \
                  "$(state_get "$2" eula)" \
                  "$(state_get "$2" version)" ||
        die "Unable to write the plugin transaction journal in $1."

    return 0
}

# do_install <plugin-root> <state-dir> <version> - install the plugin which
#     was downloaded into <plugin-root>/plugin_tmp
do_install()
{
    do_begin "$1" "$2" install "$3" || return 1

    transaction_loop "$1" "$2"
    _di_status=$?
    case "$_di_status" in
        0) return 0 ;;
        2)
            log "The plugin was not installed, the previously installed plugin stays active."
            return 1
            ;;
        *) return 1 ;;
    esac
}

# do_remove <plugin-root> <state-dir> - uninstall the active plugin
do_remove()
{
    do_begin "$1" "$2" remove || return 1

    transaction_loop "$1" "$2"
    _dr_status=$?
    case "$_dr_status" in
        0) return 0 ;;
        2)
            log "The plugin was not removed, it stays active."
            return 1
            ;;
        *) return 1 ;;
    esac
}

# do_recover <plugin-root> <state-dir> - finish or undo a transaction which
#     was interrupted during an earlier start, and remove directories which
#     a finished transaction left behind
do_recover()
{
    if [ ! -d "$1" ]; then
        # Nothing was ever downloaded into this directory
        return 0
    fi

    if [ -f "$1/.plugin-txn" ]; then
        log "Found an interrupted plugin transaction ($(journal_get "$1" op), phase \"$(journal_get "$1" phase)\"), completing it."

        transaction_loop "$1" "$2"
        case "$?" in
            0)
                log "Recovered the plugin state after an interrupted installation."
                return 0
                ;;
            2)
                log "Recovered the plugin state after an interrupted installation by undoing it."
                return 0
                ;;
            *) return 1 ;;
        esac
    fi

    # No transaction is in progress. The directories which only exist
    # inside a transaction are then left over from an earlier start:
    # "plugin_tmp" is a plugin which was downloaded and verified but never
    # installed (its license was not accepted any more, or the start which
    # was downloading it was terminated), "plugin_old" is a plugin swap
    # whose clean-up was not finished. A running installation uses neither,
    # and leaving them behind would keep unexplained state around for ever
    # and make the volume grow with every interrupted download.
    _drc_cleaned=0

    if [ -d "$1/plugin_tmp" ]; then
        log "Removing the left-over plugin directory $1/plugin_tmp, the plugin in it was never installed."
        rm -rf "$1/plugin_tmp" || return 1
        _drc_cleaned=1
    fi

    # A "plugin_old" whose "plugin" is gone is not an orphan but the last
    # copy of the installed plugin, and is left alone
    if [ -e "$1/plugin_old" ] && [ -e "$1/plugin" ]; then
        log "Removing the left-over plugin directory $1/plugin_old, the swap it belongs to is finished."
        rm -rf "$1/plugin_old" || return 1
        _drc_cleaned=1
    fi

    if [ "$_drc_cleaned" = 1 ]; then
        fsync_path "$1"
    fi

    return 0
}

case "${1:-}" in
    install)
        [ $# -eq 4 ] || usage
        do_install "$2" "$3" "$4"
        ;;
    remove)
        [ $# -eq 3 ] || usage
        do_remove "$2" "$3"
        ;;
    recover)
        [ $# -eq 3 ] || usage
        do_recover "$2" "$3"
        ;;
    begin)
        [ $# -ge 4 ] || usage
        do_begin "$2" "$3" "$4" "${5:-}"
        ;;
    step)
        [ $# -eq 3 ] || usage
        do_step "$2" "$3"
        _status=$?
        if [ "$_status" = 1 ]; then
            exit 1
        fi
        exit 0
        ;;
    *)
        usage
        ;;
esac

exit $?
