#!/bin/bash
# Tests for plugin/scripts/dropbox-fix.sh: probe, match (through probe), restart-fileproviderd.
#
# pgrep, fileproviderctl and kill are replaced by stubs on PATH, so the tests never
# touch the real File Provider daemon or Dropbox. The dumps under tests/fixtures/ are
# synthetic: every identifier in them is a placeholder.
#
# Usage: bash tests/test_probe.sh   (from the repo root)

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/plugin/scripts/dropbox-fix.sh"
FIX="$REPO_ROOT/tests/fixtures"

pass=0
fail=0

ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n     %s\n' "$1" "$2"; }

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}

sig() { # signal name, read from $OUT
  printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | head -1
}

has_sig() { # signal name: is there such a line in $OUT at all
  if printf '%s\n' "$OUT" | grep -q "^$1="; then echo yes; else echo no; fi
}

setup() {
  T="$(mktemp -d)"
  export STUB_STATE="$T/state"
  export HOME="$T/home"
  export TMPDIR="$T/tmp"
  export DROPBOX_FIX_DUMP_WAIT=3
  export DROPBOX_FIX_RESTART_WAIT=3
  export DROPBOX_FIX_DOMAINS_PLIST="$T/Domains.plist"
  mkdir -p "$STUB_STATE" "$HOME" "$TMPDIR" "$T/bin"
  : > "$STUB_STATE/procs"
  : > "$STUB_STATE/calls"

  # procs: one process per line, "PID NAME FULL COMMAND LINE". The script must always
  # limit pgrep to the current user; a call without -u is recorded as a fault.
  cat > "$T/bin/pgrep" <<'EOF'
#!/bin/bash
mode=""; pat=""; user=""
while [ $# -gt 0 ]; do
  case "$1" in
    -u) user="$2"; shift ;;
    -x) mode=x ;;
    -f) mode=f ;;
    *)  pat="$1" ;;
  esac
  shift
done
[ -n "$user" ] || echo "pgrep without -u: $mode $pat" >> "$STUB_STATE/calls"
found=1
while read -r pid name rest; do
  [ -n "$pid" ] || continue
  if [ "$mode" = x ]; then
    [ "$name" = "$pat" ] || continue
  else
    printf '%s %s\n' "$name" "$rest" | grep -Eq -- "$pat" || continue
  fi
  echo "$pid"; found=0
done < "$STUB_STATE/procs"
exit "$found"
EOF

  # dump: text to print. dump_hang: keep running afterwards, as the real dump of a
  # healthy domain does. dump_exit: exit status when it does not hang.
  cat > "$T/bin/fileproviderctl" <<'EOF'
#!/bin/bash
echo "fileproviderctl $*" >> "$STUB_STATE/calls"
[ -f "$STUB_STATE/dump" ] && cat "$STUB_STATE/dump"
if [ -e "$STUB_STATE/dump_hang" ]; then
  echo $$ > "$STUB_STATE/dump_pid"
  exec sleep 30
fi
[ -f "$STUB_STATE/dump_exit" ] && exit "$(cat "$STUB_STATE/dump_exit")"
exit 0
EOF

  # `env kill -TERM PID` in the script resolves to this stub.
  cat > "$T/bin/kill" <<'EOF'
#!/bin/bash
echo "kill $*" >> "$STUB_STATE/calls"
[ -e "$STUB_STATE/kill_fails" ] && exit 1
if [ -f "$STUB_STATE/procs_after_kill" ]; then cp "$STUB_STATE/procs_after_kill" "$STUB_STATE/procs"; fi
exit 0
EOF
  chmod +x "$T/bin/pgrep" "$T/bin/fileproviderctl" "$T/bin/kill"
  OLD_PATH="$PATH"
  PATH="$T/bin:$PATH"
  export PATH
}

teardown() { PATH="$OLD_PATH"; export PATH; rm -rf "$T"; }

procs() { printf '%s\n' "$@" > "$STUB_STATE/procs"; }

# Nothing may be left in the temporary directory, the hanging dump must be gone, and
# pgrep must never have been called for every user.
assert_clean() { # name
  assert_eq "$1: temporary files removed" "" "$(ls -A "$TMPDIR")"
  assert_eq "$1: pgrep limited to this user" "" "$(grep '^pgrep without' "$STUB_STATE/calls")"
  if [ -f "$STUB_STATE/dump_pid" ]; then
    # the stub is ended asynchronously; give it a moment before judging
    sleep 1
    if kill -0 "$(cat "$STUB_STATE/dump_pid")" 2>/dev/null; then
      bad "$1: dump process ended" "pid $(cat "$STUB_STATE/dump_pid") is still running"
      kill "$(cat "$STUB_STATE/dump_pid")" 2>/dev/null
    else
      ok "$1: dump process ended"
    fi
  fi
}

APP='100 Dropbox /Applications/Dropbox.app/Contents/MacOS/Dropbox'
EXT='200 DropboxFileProvider /Applications/Dropbox.app/Contents/PlugIns/DropboxFileProvider.appex/Contents/MacOS/DropboxFileProvider -x'
FPD='300 fileproviderd /System/Library/PrivateFrameworks/FileProvider.framework/Support/fileproviderd'

[ -f "$SCRIPT" ] || { echo "FAIL script not found: $SCRIPT"; exit 1; }

# --- probe: domain failed to start because its database was locked -----------------
setup
procs "$APP" "$FPD"
cp "$FIX/dump_startup_locked.txt" "$STUB_STATE/dump"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "locked: dropbox_app"            running        "$(sig dropbox_app)"
assert_eq "locked: dropbox_extension"      not_running    "$(sig dropbox_extension)"
assert_eq "locked: fileproviderd"          running        "$(sig fileproviderd)"
assert_eq "locked: dump_result"            ok             "$(sig dump_result)"
assert_eq "locked: domain_state"           startup_failed "$(sig domain_state)"
assert_eq "locked: domain_startup_error"   sqlite_locked  "$(sig domain_startup_error)"
assert_eq "locked: needs_auth"             no             "$(sig needs_auth)"
assert_eq "locked: pending_indexable"      734720         "$(sig pending_indexable)"
assert_eq "locked: stray_sqlite3"          0              "$(sig stray_sqlite3)"
assert_eq "locked: no domain_count without the plist" no  "$(has_sig domain_count)"
assert_clean "locked"
MATCH="$(/bin/bash "$SCRIPT" match 2>/dev/null | head -1 | cut -f1)"
assert_eq "locked: match runs the probe"   fileprovider-domain-startup-locked "$MATCH"
assert_clean "locked, match"
teardown

# --- probe: domain failed to start for another reason ------------------------------
setup
procs "$APP" "$FPD"
cp "$FIX/dump_startup_other.txt" "$STUB_STATE/dump"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "other error: domain_state"         startup_failed "$(sig domain_state)"
assert_eq "other error: domain_startup_error" other          "$(sig domain_startup_error)"
teardown

# --- probe: healthy domain that is still re-indexing; colour codes are removed ------
setup
procs "$APP" "$EXT" "$FPD"
cp "$FIX/dump_alive_reindexing.txt" "$STUB_STATE/dump"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "alive: dropbox_extension"     running "$(sig dropbox_extension)"
assert_eq "alive: domain_state"          alive   "$(sig domain_state)"
assert_eq "alive: domain_startup_error"  none    "$(sig domain_startup_error)"
assert_eq "alive: index_dropped"         no      "$(sig index_dropped)"
assert_eq "alive: sync_anchor_drop"      no      "$(sig sync_anchor_drop)"
assert_eq "alive: last_drop_reason"      "Error while indexing a batch" "$(sig last_drop_reason)"
assert_eq "alive: last_drop_date"        "2026-01-01 00:00:00 +0000"    "$(sig last_drop_date)"
assert_eq "alive: pending_indexable"     602720  "$(sig pending_indexable)"
assert_eq "alive: total_indexable"       1282895 "$(sig total_indexable)"
teardown

# --- probe: the index is dropped and the reason names the sync anchor ---------------
setup
procs "$APP" "$EXT" "$FPD"
cp "$FIX/dump_sync_anchor_dropped.txt" "$STUB_STATE/dump"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "anchor: sync_anchor_drop" yes "$(sig sync_anchor_drop)"
assert_eq "anchor: index_dropped"    yes "$(sig index_dropped)"
teardown

# --- probe: fields that are not printed are reported as unknown or left out ---------
setup
procs "$APP" "$EXT" "$FPD"
cp "$FIX/dump_alive_no_indexer.txt" "$STUB_STATE/dump"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "no indexer: domain_state"      alive   "$(sig domain_state)"
assert_eq "no indexer: needs_auth"        unknown "$(sig needs_auth)"
assert_eq "no indexer: index_dropped"     unknown "$(sig index_dropped)"
assert_eq "no indexer: sync_anchor_drop"  unknown "$(sig sync_anchor_drop)"
assert_eq "no indexer: no pending_indexable line" no "$(has_sig pending_indexable)"
assert_eq "no indexer: no last_drop_reason line"  no "$(has_sig last_drop_reason)"
teardown

# --- probe: a state line this tool does not know ------------------------------------
setup
procs "$APP" "$EXT" "$FPD"
cp "$FIX/dump_unknown_state.txt" "$STUB_STATE/dump"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "unknown state: domain_state" unknown "$(sig domain_state)"
assert_eq "unknown state: no domain_startup_error line" no "$(has_sig domain_startup_error)"
teardown

# --- probe: domain registered but nothing is serving it ----------------------------
setup
procs "$FPD"
cp "$FIX/dump_no_process.txt" "$STUB_STATE/dump"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "no process: dropbox_app"   not_running "$(sig dropbox_app)"
assert_eq "no process: domain_state"  no_process  "$(sig domain_state)"
teardown

# --- probe: Dropbox has no File Provider domain on this Mac ------------------------
setup
procs "$FPD"
cp "$FIX/dump_no_provider.txt" "$STUB_STATE/dump"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "no provider: dump_result"  no_provider "$(sig dump_result)"
assert_eq "no provider: domain_state" absent      "$(sig domain_state)"
teardown

# --- probe: the dump command fails ---------------------------------------------------
setup
procs "$APP" "$EXT" "$FPD"
echo 1 > "$STUB_STATE/dump_exit"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "dump fails: dump_result"  failed  "$(sig dump_result)"
assert_eq "dump fails: domain_state" unknown "$(sig domain_state)"
teardown

# --- probe: the dump never prints anything; the probe gives up, nothing is left -----
setup
procs "$APP" "$EXT" "$FPD"
: > "$STUB_STATE/dump_hang"
start=$(date +%s)
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
elapsed=$(( $(date +%s) - start ))
assert_eq "hang: dump_result"  timeout "$(sig dump_result)"
assert_eq "hang: domain_state" unknown "$(sig domain_state)"
if [ "$elapsed" -le 10 ]; then ok "hang: probe returns within the wait"; else bad "hang: probe returns within the wait" "took ${elapsed}s"; fi
assert_clean "hang"
teardown

# --- probe: the dump prints the provider header, then stalls -----------------------
# This is not "Dropbox has no domain": the domain was never reached.
setup
procs "$APP" "$EXT" "$FPD"
cp "$FIX/dump_header_only.txt" "$STUB_STATE/dump"
: > "$STUB_STATE/dump_hang"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "stall after header: dump_result"  timeout "$(sig dump_result)"
assert_eq "stall after header: domain_state" unknown "$(sig domain_state)"
MATCH="$(/bin/bash "$SCRIPT" match 2>/dev/null | head -1 | cut -f1)"
assert_eq "stall after header: fits the deadlock entry" fileprovider-xpc-deadlock "$MATCH"
assert_clean "stall after header"
teardown

# --- probe: the dump stalls in the middle of a number -------------------------------
setup
procs "$APP" "$EXT" "$FPD"
cp "$FIX/dump_cut_mid_number.txt" "$STUB_STATE/dump"
: > "$STUB_STATE/dump_hang"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "cut mid-number: dump_result" timeout "$(sig dump_result)"
assert_eq "cut mid-number: no pending_indexable line" no "$(has_sig pending_indexable)"
teardown

# --- probe: a full dump that keeps printing after the fields we need ---------------
setup
procs "$APP" "$EXT" "$FPD"
cp "$FIX/dump_alive_idle.txt" "$STUB_STATE/dump"
: > "$STUB_STATE/dump_hang"
start=$(date +%s)
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
elapsed=$(( $(date +%s) - start ))
assert_eq "long dump: dump_result"  ok    "$(sig dump_result)"
assert_eq "long dump: domain_state" alive "$(sig domain_state)"
if [ "$elapsed" -le 10 ]; then ok "long dump: probe stops reading early"; else bad "long dump: probe stops reading early" "took ${elapsed}s"; fi
assert_clean "long dump"
teardown

# --- probe: interrupted while the dump hangs ----------------------------------------
setup
procs "$APP" "$EXT" "$FPD"
: > "$STUB_STATE/dump_hang"
export DROPBOX_FIX_DUMP_WAIT=20
start=$(date +%s)
/bin/bash "$SCRIPT" probe >/dev/null 2>&1 &
probe_pid=$!
sleep 2
kill -TERM "$probe_pid"
wait "$probe_pid" 2>/dev/null
elapsed=$(( $(date +%s) - start ))
if [ "$elapsed" -le 8 ]; then ok "interrupted: probe stops promptly"; else bad "interrupted: probe stops promptly" "took ${elapsed}s"; fi
assert_clean "interrupted"
teardown

# --- probe: more than one Dropbox domain --------------------------------------------
setup
procs "$APP" "$EXT" "$FPD"
cp "$FIX/dump_alive_idle.txt" "$STUB_STATE/dump"
cp "$FIX/domains_1.plist" "$DROPBOX_FIX_DOMAINS_PLIST"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "one domain: domain_count" 1     "$(sig domain_count)"
assert_eq "one domain: domain_state" alive "$(sig domain_state)"
cp "$FIX/domains_2.plist" "$DROPBOX_FIX_DOMAINS_PLIST"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "two domains: domain_count" 2       "$(sig domain_count)"
assert_eq "two domains: domain_state" unknown "$(sig domain_state)"
assert_eq "two domains: no pending_indexable line" no "$(has_sig pending_indexable)"
teardown

# --- probe: sqlite3 processes left on Dropbox's own database -----------------------
setup
procs "$APP" "$EXT" "$FPD" \
  '401 sqlite3 sqlite3 /tmp/d/.dropbox/instance1/sync_fp/nucleus.sqlite3 .tables' \
  '402 sqlite3 sqlite3 /tmp/d/.dropbox/instance1/sync_fp/nucleus.sqlite3 VACUUM' \
  '403 sqlite3 sqlite3 /tmp/other.db'
cp "$FIX/dump_alive_idle.txt" "$STUB_STATE/dump"
OUT="$(/bin/bash "$SCRIPT" probe 2>/dev/null)"
assert_eq "stray: stray_sqlite3 counts only nucleus" 2 "$(sig stray_sqlite3)"
teardown

# --- restart-fileproviderd ---------------------------------------------------------
setup
procs "$APP" "$FPD"
printf '%s\n' "$APP" '301 fileproviderd /System/Library/PrivateFrameworks/FileProvider.framework/Support/fileproviderd' > "$STUB_STATE/procs_after_kill"
OUT="$(/bin/bash "$SCRIPT" restart-fileproviderd 2>&1)"; rc=$?
assert_eq "restart: exit status"       0 "$rc"
assert_eq "restart: sends TERM to the old pid" "kill -TERM 300" "$(grep '^kill' "$STUB_STATE/calls")"
case "$OUT" in *301*) ok "restart: reports the new pid" ;; *) bad "restart: reports the new pid" "$OUT" ;; esac
assert_clean "restart"
teardown

setup
procs "$APP"
OUT="$(/bin/bash "$SCRIPT" restart-fileproviderd 2>&1)"; rc=$?
assert_eq "restart, not running: exit status" 1 "$rc"
assert_eq "restart, not running: nothing is killed" "" "$(grep '^kill' "$STUB_STATE/calls")"
teardown

setup
procs "$APP" "$FPD"
printf '%s\n' "$APP" > "$STUB_STATE/procs_after_kill"
OUT="$(/bin/bash "$SCRIPT" restart-fileproviderd 2>&1)"; rc=$?
assert_eq "restart, never comes back: exit status" 2 "$rc"
teardown

# The signal was accepted but the same process is still there: that is not a restart.
setup
procs "$APP" "$FPD"
OUT="$(/bin/bash "$SCRIPT" restart-fileproviderd 2>&1)"; rc=$?
assert_eq "restart, same pid stays: exit status" 2 "$rc"
teardown

setup
procs "$APP" "$FPD"
: > "$STUB_STATE/kill_fails"
OUT="$(/bin/bash "$SCRIPT" restart-fileproviderd 2>&1)"; rc=$?
assert_eq "restart, kill refused: exit status" 1 "$rc"
teardown

# --- usage -------------------------------------------------------------------------
setup
/bin/bash "$SCRIPT" no-such-command >/dev/null 2>&1; rc=$?
assert_eq "unknown subcommand: exit status" 64 "$rc"
/bin/bash "$SCRIPT" show >/dev/null 2>&1; rc=$?
assert_eq "show without an id: exit status" 64 "$rc"
teardown

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
