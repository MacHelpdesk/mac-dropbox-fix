#!/bin/bash
# dropbox-fix — measure why Dropbox is not syncing on this Mac, and look the result up
# in a knowledge base of known problems; also check and download online-only files.
#
#   dropbox-fix.sh probe                   print what can be measured, one signal=value per line
#   dropbox-fix.sh match [SIGNALS_FILE]    known problems these signals fit, best first
#                                          (id, evidence status, title; tab separated).
#                                          Without a file it runs the probe. Exit 3: no match.
#   dropbox-fix.sh list                    every known problem
#   dropbox-fix.sh show ID                 one problem: symptoms, cause, fixes, what does not work
#   dropbox-fix.sh validate                check problems.json and the personal additions
#   dropbox-fix.sh restart-fileproviderd   restart this user's fileproviderd, see below
#   dropbox-fix.sh local-status PATH       files under PATH, how many are online-only, their
#                                          size and the free space, one key=value per line
#   dropbox-fix.sh download PATH           read every online-only file under PATH so that
#                                          File Provider downloads it, see below
#
# probe, match, list, show, validate and local-status read; they change nothing. probe starts
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
# local-status and download accept only a path inside a Dropbox folder under
# ~/Library/CloudStorage. A file is online-only when stat lists the dataless flag; its
# size is never used for that, because online-only files report their full size.
# download reads each online-only file, one at a time, so that File Provider downloads
# it; it modifies, moves and deletes nothing. It refuses to start when the free space is
# smaller than the online-only total (exit 4), gives each read DROPBOX_FIX_READ_WAIT
# seconds (default 300), retries only after a pass that made a file local (at most three
# passes), and stops at once after three reads in a row time out. Files still online-only
# at the end are listed (exit 2). Whether to run it is decided in the dropbox-use skill.
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
READ_WAIT="${DROPBOX_FIX_READ_WAIT:-300}"
KILL_WAIT="${DROPBOX_FIX_KILL_WAIT:-5}"

ME="$(id -u)"
TMPD=""
DUMP_PID=""
DUMP_RESULT=""
READ_PID=""

# DUMP_PID, READ_PID and TMPD are set in this shell, never in a subshell, so this sees them.
cleanup() {
  if [ -n "$DUMP_PID" ]; then kill "$DUMP_PID" 2>/dev/null; fi
  if [ -n "$READ_PID" ]; then kill -9 "$READ_PID" 2>/dev/null; fi
  if [ -n "$TMPD" ]; then rm -rf "$TMPD"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

need_tmpd() {
  [ -n "$TMPD" ] && return 0
  TMPD="$(mktemp -d)" || exit 1
}

# The header up to the end of the subcommand list: everything before its second
# comment line that holds only "#", so adding a subcommand needs no line numbers here.
usage() {
  awk 'NR == 1 { next } $0 == "#" { if (++n == 2) exit } { print }' "$0" \
    | sed 's/^# \{0,1\}//' >&2
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

# stat prints "SIZE FLAGS" for '%z %Sf'; FLAGS is "-" when a file has none. File
# Provider marks a file that is not on this Mac with the dataless flag, and such a file
# still reports its full size, so the size never decides whether a file is local.
dataless_in() { # stat line
  case ",${1#* }," in *,dataless,*) return 0 ;; esac
  return 1
}

is_online() { # file
  local line
  line="$(stat -f '%z %Sf' "$1" 2>/dev/null)" || return 1
  dataless_in "$line"
}

# Counts the regular files under a path, sorted, and finds the online-only ones. Writes
# them NUL-separated to $TMPD/online and sets FILES, ONLINE and ONLINE_BYTES. find runs
# without -L, so a symlink inside the folder is not followed out of it.
# Must be called directly, not in $(...).
scan() { # path
  local f line size
  FILES=0
  ONLINE=0
  ONLINE_BYTES=0
  : > "$TMPD/online"
  find "$1" -type f -print0 2>/dev/null | LC_ALL=C sort -z > "$TMPD/files"
  while IFS= read -r -d '' f; do
    FILES=$((FILES + 1))
    line="$(stat -f '%z %Sf' "$f" 2>/dev/null)" || continue
    dataless_in "$line" || continue
    size="${line%% *}"
    case "$size" in ''|*[!0-9]*) size=0 ;; esac
    ONLINE=$((ONLINE + 1))
    ONLINE_BYTES=$((ONLINE_BYTES + size))
    printf '%s\0' "$f" >> "$TMPD/online"
  done < "$TMPD/files"
}

# Free space on the volume holding a path, in bytes: the Available column of df's
# single data line, in 1024-byte units. Prints nothing when it cannot be read.
free_bytes() { # path
  local kb
  kb="$(df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print $4 }')"
  case "$kb" in ''|*[!0-9]*) return 0 ;; esac
  echo $((kb * 1024))
}

# Prints the physical path (symlinks resolved) of a file or folder that lies inside a
# Dropbox folder under ~/Library/CloudStorage. Anything else is refused with one reason
# line on stderr and status 1, before anything under it is read. A file given directly
# must not be a symlink: reading it would read whatever it points to.
dropbox_path() { # path
  local p="$1" phys root rest
  if [ -d "$p" ]; then
    phys="$(cd "$p" 2>/dev/null && pwd -P)" || { echo "cannot enter $p" >&2; return 1; }
  elif [ -f "$p" ] && [ ! -L "$p" ]; then
    phys="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)/$(basename "$p")" \
      || { echo "cannot enter the folder of $p" >&2; return 1; }
  elif [ -L "$p" ]; then
    echo "refusing a symlink to a file: $p" >&2; return 1
  else
    echo "no such file or folder: $p" >&2; return 1
  fi
  root="$(cd "$HOME/Library/CloudStorage" 2>/dev/null && pwd -P)" \
    || { echo "there is no ~/Library/CloudStorage on this Mac" >&2; return 1; }
  case "$phys" in
    "$root"/*) ;;
    *) echo "not inside a Dropbox folder under ~/Library/CloudStorage: $p" >&2; return 1 ;;
  esac
  rest="${phys#"$root"/}"
  case "${rest%%/*}" in
    Dropbox*) ;;
    *) echo "not inside a Dropbox folder under ~/Library/CloudStorage: $p" >&2; return 1 ;;
  esac
  printf '%s\n' "$phys"
}

local_status() { # path
  local free phys
  [ -n "${1:-}" ] || usage
  phys="$(dropbox_path "$1")" || exit 1
  need_tmpd
  scan "$phys"
  free="$(free_bytes "$phys")"
  echo "files=$FILES"
  echo "online_only=$ONLINE"
  echo "online_only_bytes=$ONLINE_BYTES"
  [ -n "$free" ] && echo "free_bytes=$free"
  return 0
}

# A file's path as printed in online_only_file= lines: relative to the PATH given, or
# its own name when PATH was that file.
relative() { # file, physical path
  if [ "$1" = "$2" ]; then basename "$1"; else printf '%s\n' "${1#"$2"/}"; fi
}

# Ends the read in READ_PID: TERM, a bounded wait, then KILL. A read blocked on an
# online-only file may not end at once, so this never waits without a limit; when even
# KILL does not end it, it says so and leaves it.
stop_read() {
  local n=0
  kill "$READ_PID" 2>/dev/null
  while kill -0 "$READ_PID" 2>/dev/null && [ "$n" -lt "$KILL_WAIT" ]; do
    sleep 1
    n=$((n + 1))
  done
  if kill -0 "$READ_PID" 2>/dev/null; then
    kill -9 "$READ_PID" 2>/dev/null
    sleep 1
  fi
  if kill -0 "$READ_PID" 2>/dev/null; then
    echo "a read could not be stopped (pid $READ_PID); going on without it" >&2
  else
    wait "$READ_PID" 2>/dev/null
  fi
  READ_PID=""
}

# Reads one file in the background so that File Provider downloads it, and stops the
# read after READ_WAIT seconds. Returns 0 when the read finished, 1 when it failed, and
# 2 when it was stopped. Must be called directly, not in $(...): it sets READ_PID.
read_one() { # file
  local waited=0 status
  dd if="$1" of=/dev/null bs=1048576 </dev/null 2>/dev/null &
  READ_PID=$!
  while kill -0 "$READ_PID" 2>/dev/null; do
    if [ "$waited" -ge "$READ_WAIT" ]; then
      stop_read
      return 2
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$READ_PID" 2>/dev/null
  status=$?
  READ_PID=""
  [ "$status" -eq 0 ] || return 1
  return 0
}

download() { # path
  local phys f remaining pass made free timeouts stopped
  [ -n "${1:-}" ] || usage
  phys="$(dropbox_path "$1")" || exit 1
  need_tmpd
  scan "$phys"
  if [ "$ONLINE" -eq 0 ]; then
    echo "online_only=0"
    return 0
  fi
  free="$(free_bytes "$phys")"
  if [ -z "$free" ]; then
    echo "could not read the free space on this volume; downloading anyway" >&2
  elif [ "$free" -lt "$ONLINE_BYTES" ]; then
    echo "not enough free space: free_bytes=$free, online_only_bytes=$ONLINE_BYTES; nothing was read" >&2
    exit 4
  fi
  # Another pass runs only while fewer than three have run and the last one made a
  # file local; otherwise it would repeat the same reads. Three timed-out reads in a
  # row look like an offline Mac: the run stops at once and the rest stays unread.
  cp "$TMPD/online" "$TMPD/todo"
  pass=0
  timeouts=0
  stopped=""
  while [ "$pass" -lt 3 ]; do
    pass=$((pass + 1))
    made=0
    : > "$TMPD/next"
    while IFS= read -r -d '' f; do
      if [ -n "$stopped" ]; then
        printf '%s\0' "$f" >> "$TMPD/next"
        continue
      fi
      read_one "$f"
      if [ $? -eq 2 ]; then timeouts=$((timeouts + 1)); else timeouts=0; fi
      if is_online "$f"; then
        printf '%s\0' "$f" >> "$TMPD/next"
      else
        made=$((made + 1))
      fi
      [ "$timeouts" -ge 3 ] && stopped=timeouts
    done < "$TMPD/todo"
    mv "$TMPD/next" "$TMPD/todo"
    [ -z "$stopped" ] || break
    [ -s "$TMPD/todo" ] || break
    [ "$made" -gt 0 ] || break
  done
  remaining="$(tr -cd '\000' < "$TMPD/todo" | wc -c | tr -d ' ')"
  [ -n "$stopped" ] && echo "stopped=$stopped"
  echo "downloaded=$((ONLINE - remaining))"
  echo "still_online_only=$remaining"
  while IFS= read -r -d '' f; do
    echo "online_only_file=$(relative "$f" "$phys")"
  done < "$TMPD/todo"
  [ "$remaining" -eq 0 ] || exit 2
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
  local-status)          local_status "${2:-}" ;;
  download)              download "${2:-}" ;;
  *)                     usage ;;
esac
