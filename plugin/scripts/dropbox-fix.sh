#!/bin/bash
# dropbox-fix — measure why Dropbox is not syncing on this Mac, and look the result up
# in a knowledge base of known problems.
#
#   dropbox-fix.sh probe                   print what can be measured, one signal=value per line
#   dropbox-fix.sh match [SIGNALS_FILE]    known problems these signals fit, best first
#                                          (id, evidence status, title; tab separated).
#                                          Without a file it runs the probe. Exit 3: no match.
#   dropbox-fix.sh list                    every known problem
#   dropbox-fix.sh show ID                 one problem: symptoms, cause, fixes, what does not work
#   dropbox-fix.sh validate                check problems.json and the personal additions
#   dropbox-fix.sh restart-fileproviderd   the only subcommand that changes anything, see below
#
# probe, match, list, show and validate read; they change nothing. probe starts
# `fileproviderctl dump` for the Dropbox provider and stops it as soon as the fields it
# needs have been printed, because a healthy domain's dump runs to millions of lines.
# It reads one domain. With more than one Dropbox domain (two linked accounts) it says
# so and reports the domain's state as unknown.
#
# restart-fileproviderd sends TERM to this user's fileproviderd and waits for launchd
# to start a new one. Every cloud folder that daemon serves (iCloud Drive, Google
# Drive, OneDrive, Dropbox) reconnects. It touches no database file and no account.
# Whether to run it is decided in the dropbox-fix skill, not here.
#
# The knowledge base is ../data/problems.json. A person's own additions go in
# ~/.config/mac-dropbox-fix/problems.local.json; see README.md.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
KB="${DROPBOX_FIX_KB:-$HERE/../data/problems.json}"
LOCAL_KB="${DROPBOX_FIX_LOCAL_KB:-$HOME/.config/mac-dropbox-fix/problems.local.json}"
KBJS="$HERE/kb.js"

PROVIDER="com.getdropbox.dropbox.fileprovider"
EXTENSION_PATTERN='DropboxFileProvider\.appex/Contents/MacOS/DropboxFileProvider'
DOMAINS_PLIST="${DROPBOX_FIX_DOMAINS_PLIST:-$HOME/Library/Application Support/FileProvider/$PROVIDER/Domains.plist}"
DUMP_WAIT="${DROPBOX_FIX_DUMP_WAIT:-20}"
RESTART_WAIT="${DROPBOX_FIX_RESTART_WAIT:-30}"
DUMP_LINES=400

ME="$(id -u)"
TMPD=""
DUMP_PID=""
DUMP_RESULT=""

# DUMP_PID and TMPD are set in this shell, never in a subshell, so this sees them.
cleanup() {
  if [ -n "$DUMP_PID" ]; then kill "$DUMP_PID" 2>/dev/null; fi
  if [ -n "$TMPD" ]; then rm -rf "$TMPD"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

need_tmpd() {
  [ -n "$TMPD" ] && return 0
  TMPD="$(mktemp -d)" || exit 1
}

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 64
}

kb() { # command [arg]
  osascript -l JavaScript "$KBJS" "$1" "$KB" "$LOCAL_KB" ${2+"$2"}
}

state_of() { # prints running or not_running for the pgrep arguments given
  if pgrep -u "$ME" "$@" >/dev/null 2>&1; then echo running; else echo not_running; fi
}

# True once the dump holds the fields the probe reads, in complete lines. A dump cut in
# the middle of a line (no newline at the end) is not complete yet.
dump_has_fields() {
  [ -s "$TMPD/dump.raw" ] || return 1
  [ -z "$(tail -c 1 "$TMPD/dump.raw")" ] || return 1
  LC_ALL=C grep -q -e 'total-indexable-count' -e '== CloudStorage xattrs ==' "$TMPD/dump.raw"
}

# Runs the dump in the background and ends it once the Dropbox domain has been
# printed. Piping the dump into a reader that exits early does not stop
# fileproviderctl, so it is ended explicitly. Leaves the text, without colour codes,
# in $TMPD/dump.txt and sets DUMP_RESULT:
#   ok           the dump got as far as the fields, and lists the Dropbox provider
#   no_provider  the dump got that far, and does not list the Dropbox provider
#   failed       the dump command exited with an error
#   timeout      the fields were not printed within DUMP_WAIT seconds, whatever else was
# Must be called directly, not in $(...): it sets DUMP_PID for cleanup.
read_dump() {
  local waited=0 ended="" status=0 esc
  fileproviderctl dump "$PROVIDER" > "$TMPD/dump.raw" 2>/dev/null &
  DUMP_PID=$!
  while :; do
    if dump_has_fields; then
      ended=fields
      break
    fi
    if ! kill -0 "$DUMP_PID" 2>/dev/null; then
      ended=exit
      break
    fi
    [ "$waited" -ge "$DUMP_WAIT" ] && break
    sleep 1
    waited=$((waited + 1))
  done
  if [ "$ended" = exit ]; then
    wait "$DUMP_PID" 2>/dev/null
    status=$?
  else
    kill "$DUMP_PID" 2>/dev/null
    wait "$DUMP_PID" 2>/dev/null
  fi
  DUMP_PID=""

  esc="$(printf '\033')"
  head -n "$DUMP_LINES" "$TMPD/dump.raw" 2>/dev/null | LC_ALL=C sed "s/${esc}\[[0-9;]*m//g" > "$TMPD/dump.txt"

  if [ -z "$ended" ]; then
    DUMP_RESULT=timeout
  elif [ "$ended" = exit ] && [ "$status" -ne 0 ]; then
    DUMP_RESULT=failed
  elif LC_ALL=C grep -q "^${PROVIDER}\$" "$TMPD/dump.txt"; then
    DUMP_RESULT=ok
  else
    DUMP_RESULT=no_provider
  fi
}

# How many domains Dropbox has registered: the top-level keys of its Domains.plist,
# leaving out the hidden default domain that every provider has. Prints nothing when
# the file cannot be read.
domain_count() {
  local tab n
  [ -r "$DOMAINS_PLIST" ] || return 0
  tab="$(printf '\t')"
  n="$(plutil -convert xml1 -o - "$DOMAINS_PLIST" 2>/dev/null | LC_ALL=C grep "^${tab}<key>" \
        | LC_ALL=C grep -vc '<key>NSFileProviderDomainDefaultIdentifier</key>')"
  case "$n" in
    ''|*[!0-9]*) ;;
    *) echo "$n" ;;
  esac
}

# The first domain that is not the hidden default one, up to the end of its indexer
# fields. Structural words in this dump (alive, unable to startup, needs-auth, ...)
# and the value of last-drop-reason are not translated. The descriptions inside
# NSError lines are, and are never parsed.
domain_section() {
  LC_ALL=C awk '
    /^== CloudStorage xattrs ==/ { exit }
    !inside && /^domain: / && !/\(default\)/ { inside = 1 }
    inside { print }
    inside && /total-indexable-count/ { exit }
  ' "$TMPD/dump.txt"
}

field() { # label, read from $TMPD/domain.txt
  LC_ALL=C sed -n "s/^ *$1: *//p" "$TMPD/domain.txt" | head -1
}

yes_no() {
  case "$1" in
    yes|no) echo "$1" ;;
    *)      echo unknown ;;
  esac
}

probe() {
  local state startup reason dropped pending total stray count

  need_tmpd

  echo "dropbox_app=$(state_of -x Dropbox)"
  echo "dropbox_extension=$(state_of -f "$EXTENSION_PATTERN")"
  echo "fileproviderd=$(state_of -x fileproviderd)"
  stray="$(pgrep -u "$ME" -f 'sqlite3.*nucleus\.sqlite3' 2>/dev/null | grep -c .)"
  echo "stray_sqlite3=${stray:-0}"

  count="$(domain_count)"
  [ -n "$count" ] && echo "domain_count=$count"

  read_dump
  echo "dump_result=$DUMP_RESULT"

  # From here on, a value that was not read is reported as unknown or left out.
  case "$DUMP_RESULT" in
    timeout|failed)
      echo "domain_state=unknown"
      return 0 ;;
  esac
  if [ -n "$count" ] && [ "$count" -gt 1 ]; then
    echo "domain_state=unknown"
    return 0
  fi

  domain_section > "$TMPD/domain.txt"
  if [ ! -s "$TMPD/domain.txt" ]; then
    echo "domain_state=absent"
    return 0
  fi

  if LC_ALL=C grep -q 'unable to startup' "$TMPD/domain.txt"; then
    state=startup_failed
  elif LC_ALL=C grep -q '^ *alive (' "$TMPD/domain.txt"; then
    state=alive
  elif LC_ALL=C grep -q 'no process observed' "$TMPD/domain.txt"; then
    state=no_process
  else
    state=unknown
  fi
  echo "domain_state=$state"

  case "$state" in
    startup_failed)
      if LC_ALL=C grep -q 'SqliteErrorDomain 5[^0-9]' "$TMPD/domain.txt"; then
        startup=sqlite_locked
      else
        startup=other
      fi
      echo "domain_startup_error=$startup" ;;
    alive|no_process)
      echo "domain_startup_error=none" ;;
  esac

  echo "needs_auth=$(yes_no "$(field needs-auth)")"
  echo "index_dropped=$(yes_no "$(field index-is-dropped)")"

  reason="$(field last-drop-reason)"
  if [ -z "$reason" ]; then
    echo "sync_anchor_drop=unknown"
  elif printf '%s' "$reason" | LC_ALL=C grep -qi 'sync anchor'; then
    echo "sync_anchor_drop=yes"
  else
    echo "sync_anchor_drop=no"
  fi
  [ -n "$reason" ] && echo "last_drop_reason=$reason"
  dropped="$(field last-drop-date)"
  [ -n "$dropped" ] && echo "last_drop_date=$dropped"

  pending="$(field pending-indexable-count | LC_ALL=C sed 's/^\([0-9][0-9]*\) .*/\1/')"
  total="$(field total-indexable-count | LC_ALL=C sed 's/^\([0-9][0-9]*\) .*/\1/')"
  case "$pending" in ''|*[!0-9]*) ;; *) echo "pending_indexable=$pending" ;; esac
  case "$total"   in ''|*[!0-9]*) ;; *) echo "total_indexable=$total" ;; esac
  return 0
}

match() { # [signals file]
  local file="${1:-}" found
  if [ -z "$file" ]; then
    need_tmpd
    file="$TMPD/signals"
    probe > "$file"
  elif [ ! -r "$file" ]; then
    echo "cannot read $file" >&2
    exit 1
  fi
  found="$(kb match "$file")" || exit 1
  if [ -z "$found" ]; then
    echo "no known problem fits these signals" >&2
    exit 3
  fi
  printf '%s\n' "$found"
}

restart_fileproviderd() {
  local old new waited=0
  old="$(pgrep -u "$ME" -x fileproviderd 2>/dev/null | head -1)"
  if [ -z "$old" ]; then
    echo "fileproviderd is not running for this user; nothing to restart" >&2
    exit 1
  fi
  # `env kill`, not the shell builtin: /bin/kill is what a person would type, and the
  # tests replace it on PATH.
  if ! env kill -TERM "$old"; then
    echo "could not signal fileproviderd (pid $old)" >&2
    exit 1
  fi
  while [ "$waited" -lt "$RESTART_WAIT" ]; do
    new="$(pgrep -u "$ME" -x fileproviderd 2>/dev/null | head -1)"
    if [ -n "$new" ] && [ "$new" != "$old" ]; then
      echo "fileproviderd restarted: pid $old -> $new after ${waited}s"
      echo "the Dropbox domain needs a minute or two to start; then run: dropbox-fix.sh probe"
      exit 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  echo "fileproviderd (pid $old) was signalled but no new one appeared within ${RESTART_WAIT}s" >&2
  echo "open the Dropbox folder in Finder, which asks launchd for it, then run: dropbox-fix.sh probe" >&2
  exit 2
}

case "${1:-}" in
  probe)                 probe ;;
  match)                 match "${2:-}" ;;
  list)                  kb list ;;
  show)                  [ -n "${2:-}" ] || usage; kb show "$2" ;;
  validate)              kb validate ;;
  restart-fileproviderd) restart_fileproviderd ;;
  *)                     usage ;;
esac
