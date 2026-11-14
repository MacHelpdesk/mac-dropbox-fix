#!/bin/bash
# Tests for the local-status and download subcommands of plugin/scripts/dropbox-fix.sh.
#
# stat, df and dd are replaced by stubs on PATH, so the tests need no Dropbox:
#   - a file's File Provider flags come from $STUB_STATE/flags, one "name<TAB>flags" line
#     per file name (no line means no flags, printed as "-" like the real stat);
#   - the free space comes from $STUB_STATE/free_kb, the Available column of `df -Pk`;
#   - dd is the read that makes File Provider download a file: it records the read and
#     clears the file's dataless flag, unless the file name is listed in
#     $STUB_STATE/stubborn (stays dataless) or $STUB_STATE/hang (the read never returns).
# Every test is tagged with the spec Example it checks: `spec-example: <capability> / <title>`.
#
# Usage: bash tests/test_local.sh   (from the repo root)

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/plugin/scripts/dropbox-fix.sh"

pass=0
fail=0

ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n     %s\n' "$1" "$2"; }

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}

assert_has() { # name needle haystack
  case "$3" in
    *"$2"*) ok "$1" ;;
    *)      bad "$1" "[$2] not found in [$3]" ;;
  esac
}

sig() { # key, read from $OUT
  printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | head -1
}

reads() { # how many reads the dd stub recorded, optionally of one file name
  if [ -n "${1:-}" ]; then
    grep -cxF "read $1" "$STUB_STATE/calls"
  else
    grep -c '^read ' "$STUB_STATE/calls"
  fi
}

setup() {
  T="$(mktemp -d)"
  export STUB_STATE="$T/state"
  export HOME="$T/home"
  export TMPDIR="$T/tmp"
  export DROPBOX_FIX_READ_WAIT=5
  export DROPBOX_FIX_KILL_WAIT=2
  mkdir -p "$STUB_STATE" "$HOME" "$TMPDIR" "$T/bin"
  : > "$STUB_STATE/flags"
  : > "$STUB_STATE/calls"
  : > "$STUB_STATE/stubborn"
  : > "$STUB_STATE/hang"
  : > "$STUB_STATE/hang_pids"
  echo 5000 > "$STUB_STATE/free_kb"
  DBX="$HOME/Library/CloudStorage/Dropbox"
  mkdir -p "$DBX"

  cat > "$T/bin/stat" <<'EOF'
#!/bin/bash
fmt=""
while [ $# -gt 0 ]; do
  case "$1" in
    -f) fmt="$2"; shift 2 ;;
    *)  break ;;
  esac
done
for p in "$@"; do
  name="${p##*/}"
  name="${name//$'\n'/|}"
  size="$(/usr/bin/stat -f %z "$p")" || exit 1
  flags="$(awk -F'\t' -v n="$name" '$1 == n { print $2; exit }' "$STUB_STATE/flags")"
  [ -n "$flags" ] || flags="-"
  out="${fmt//"%z"/$size}"
  out="${out//"%Sf"/$flags}"
  printf '%s\n' "$out"
done
EOF

  cat > "$T/bin/df" <<'EOF'
#!/bin/bash
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/stub 10000000 5000000 $(cat "$STUB_STATE/free_kb") 50% /"
EOF

  cat > "$T/bin/dd" <<'EOF'
#!/bin/bash
src=""
for a in "$@"; do
  case "$a" in if=*) src="${a#if=}" ;; esac
done
name="${src##*/}"
name="${name//$'\n'/|}"
echo "read $name" >> "$STUB_STATE/calls"
if grep -qxF "$name" "$STUB_STATE/hang"; then
  echo $$ >> "$STUB_STATE/hang_pids"
  exec sleep 30
fi
grep -qxF "$name" "$STUB_STATE/stubborn" && exit 0
awk -F'\t' -v OFS='\t' -v n="$name" '
  $1 == n {
    k = split($2, a, ","); out = ""
    for (i = 1; i <= k; i++) if (a[i] != "dataless") out = out (out == "" ? "" : ",") a[i]
    if (out == "") out = "-"
    $2 = out
  }
  { print }
' "$STUB_STATE/flags" > "$STUB_STATE/flags.new" && mv "$STUB_STATE/flags.new" "$STUB_STATE/flags"
exit 0
EOF
  chmod +x "$T/bin/stat" "$T/bin/df" "$T/bin/dd"
  OLD_PATH="$PATH"
  PATH="$T/bin:$PATH"
  export PATH
}

teardown() { PATH="$OLD_PATH"; export PATH; rm -rf "$T"; }

mkfile() { # path under the Dropbox folder, size in bytes, flags ("" for none)
  mkdir -p "$(dirname "$DBX/$1")"
  head -c "$2" /dev/zero > "$DBX/$1"
  local key="${1##*/}"
  key="${key//$'\n'/|}"   # the stubs look files up by name, with a newline written as |
  [ -n "$3" ] && printf '%s\t%s\n' "$key" "$3" >> "$STUB_STATE/flags"
  return 0
}

# No read may be left running and the temporary directory must be empty afterwards.
assert_no_reads_left() { # name
  local pid alive=""
  sleep 1
  while read -r pid; do
    [ -n "$pid" ] || continue
    if kill -0 "$pid" 2>/dev/null; then alive="$alive $pid"; kill -9 "$pid" 2>/dev/null; fi
  done < "$STUB_STATE/hang_pids"
  assert_eq "$1: no read process left running" "" "$alive"
  assert_eq "$1: temporary files removed" "" "$(ls -A "$TMPDIR")"
}

[ -f "$SCRIPT" ] || { echo "FAIL script not found: $SCRIPT"; exit 1; }

# --- spec-example: dropbox-local-files / two of three files online-only ---------------
setup
mkfile a.pdf 1000 compressed,dataless
mkfile sub/b.docx 500 dataless
mkfile c.txt 20 ""
OUT="$(/bin/bash "$SCRIPT" local-status "$DBX" 2>/dev/null)"; rc=$?
assert_eq "local-status: exit status"       0       "$rc"
assert_eq "local-status: files"             3       "$(sig files)"
assert_eq "local-status: online_only"       2       "$(sig online_only)"
assert_eq "local-status: online_only_bytes" 1500    "$(sig online_only_bytes)"
assert_eq "local-status: free_bytes"        5120000 "$(sig free_bytes)"
assert_eq "local-status: key order" "files online_only online_only_bytes free_bytes" \
  "$(printf '%s\n' "$OUT" | sed 's/=.*//' | tr '\n' ' ' | sed 's/ $//')"
assert_eq "local-status: no file read"      0       "$(reads)"
assert_no_reads_left "local-status"
teardown

# --- spec-example: dropbox-local-files / path scope cases ------------------------------
# Every subcommand that takes a PATH runs through the same physical-path check.
SCOPED_SUBCOMMANDS="local-status download"
setup
CS="$HOME/Library/CloudStorage"
mkdir -p "$DBX/work" "$CS/Dropbox-Personal/work" "$HOME/Documents/work" "$CS/GoogleDrive-x/work"
ln -s "$HOME/Documents" "$DBX/link-out"
for sub in $SCOPED_SUBCOMMANDS; do
  while IFS='|' read -r path want label; do
    ERR="$(/bin/bash "$SCRIPT" "$sub" "$path" 2>&1 >/dev/null)"; rc=$?
    assert_eq "$sub scope: $label" "$want" "$rc"
    if [ "$want" = 1 ]; then
      [ -n "$ERR" ] && ok "$sub scope: $label states a reason" \
                    || bad "$sub scope: $label states a reason" "stderr was empty"
    fi
  done <<ROWS
$DBX/work|0|inside the Dropbox folder
$CS/Dropbox-Personal/work|0|folder name starts with Dropbox
$HOME/Documents/work|1|not under CloudStorage
$CS/GoogleDrive-x/work|1|another provider
$DBX/link-out|1|symlink resolved physically lands outside
$DBX/missing|1|does not exist
ROWS
done
assert_eq "scope: no file read" 0 "$(reads)"
teardown

# --- spec-example: dropbox-local-files / two files downloaded in the first pass ---------
setup
mkfile a.pdf 1000 compressed,dataless
mkfile sub/b.docx 500 dataless
mkfile c.txt 20 ""
OUT="$(/bin/bash "$SCRIPT" download "$DBX" 2>/dev/null)"; rc=$?
assert_eq "download all: exit status"       0 "$rc"
assert_eq "download all: downloaded"        2 "$(sig downloaded)"
assert_eq "download all: still_online_only" 0 "$(sig still_online_only)"
assert_eq "download all: a.pdf read once"   1 "$(reads a.pdf)"
assert_eq "download all: b.docx read once"  1 "$(reads b.docx)"
assert_eq "download all: c.txt not read"    0 "$(reads c.txt)"
assert_eq "download all: nothing listed"    "" "$(printf '%s\n' "$OUT" | grep '^online_only_file=')"
assert_no_reads_left "download all"
teardown

# --- spec-example: dropbox-local-files / nothing to download ---------------------------
setup
mkfile a.pdf 1000 ""
mkfile sub/b.docx 500 compressed
OUT="$(/bin/bash "$SCRIPT" download "$DBX" 2>/dev/null)"; rc=$?
assert_eq "nothing to download: exit status" 0 "$rc"
assert_eq "nothing to download: output" "online_only=0" "$OUT"
assert_eq "nothing to download: no file read" 0 "$(reads)"
assert_no_reads_left "nothing to download"
teardown

# --- spec-example: dropbox-local-files / one stubborn file among two -------------------
setup
mkfile a.pdf 1000 dataless
mkfile sub/big.pptx 3000 compressed,dataless
echo big.pptx >> "$STUB_STATE/stubborn"
OUT="$(/bin/bash "$SCRIPT" download "$DBX" 2>/dev/null)"; rc=$?
assert_eq "stubborn: exit status"            2 "$rc"
assert_eq "stubborn: big.pptx read twice"    2 "$(reads big.pptx)"
assert_eq "stubborn: a.pdf read once"        1 "$(reads a.pdf)"
assert_eq "stubborn: downloaded"             1 "$(sig downloaded)"
assert_eq "stubborn: still_online_only"      1 "$(sig still_online_only)"
assert_eq "stubborn: listed" "sub/big.pptx" "$(sig online_only_file)"
assert_eq "stubborn: not stopped on timeouts" "" "$(sig stopped)"
assert_no_reads_left "stubborn"
teardown

# --- spec-example: dropbox-local-files / 1024 bytes free for 1500 bytes needed ---------
setup
mkfile a.pdf 1000 dataless
mkfile b.docx 500 dataless
echo 1 > "$STUB_STATE/free_kb"
ERR="$(/bin/bash "$SCRIPT" download "$DBX" 2>&1 >/dev/null)"; rc=$?
assert_eq  "no space: exit status" 4 "$rc"
assert_has "no space: names the free bytes"   1024 "$ERR"
assert_has "no space: names the bytes needed" 1500 "$ERR"
assert_eq  "no space: no file read" 0 "$(reads)"
assert_no_reads_left "no space"
teardown

# --- spec-example: dropbox-local-files / hanging read stopped after two seconds ---------
setup
export DROPBOX_FIX_READ_WAIT=2
mkfile a.pdf 1000 dataless
mkfile hang.pdf 2000 dataless
echo hang.pdf >> "$STUB_STATE/hang"
started=$SECONDS
OUT="$(/bin/bash "$SCRIPT" download "$DBX" 2>/dev/null)"; rc=$?
took=$((SECONDS - started))
assert_eq "hang: exit status"        2 "$rc"
assert_eq "hang: a.pdf downloaded"   1 "$(sig downloaded)"
assert_eq "hang: listed" "hang.pdf" "$(sig online_only_file)"
assert_eq "hang: hang.pdf read twice" 2 "$(reads hang.pdf)"
if [ "$took" -le 15 ]; then ok "hang: reads stopped (took ${took}s)"
else bad "hang: reads stopped" "took ${took}s; each read should end after about 2s"; fi
assert_no_reads_left "hang"
teardown

# --- spec-example: dropbox-local-files / offline run stops after three timeouts ---------
setup
export DROPBOX_FIX_READ_WAIT=1
for i in 1 2 3 4 5; do
  mkfile "c$i.pdf" 100 dataless
  echo "c$i.pdf" >> "$STUB_STATE/hang"
done
OUT="$(/bin/bash "$SCRIPT" download "$DBX" 2>/dev/null)"; rc=$?
assert_eq "offline: exit status"        2 "$rc"
assert_eq "offline: reads started"      3 "$(reads)"
assert_eq "offline: stopped"            timeouts "$(sig stopped)"
assert_eq "offline: downloaded"         0 "$(sig downloaded)"
assert_eq "offline: still_online_only"  5 "$(sig still_online_only)"
assert_eq "offline: every file listed"  5 "$(printf '%s\n' "$OUT" | grep -c '^online_only_file=')"
assert_eq "offline: stopped comes first" "stopped downloaded still_online_only" \
  "$(printf '%s\n' "$OUT" | sed 's/=.*//' | grep -v online_only_file | tr '\n' ' ' | sed 's/ $//')"
assert_no_reads_left "offline"
teardown

# --- spec-example: dropbox-local-files / a file name with a newline stays on one line ---
setup
NL='
'
mkfile "evil${NL}stopped=timeouts.pdf" 100 dataless
mkfile "報告.pdf" 100 dataless
printf '%s\n' "evil|stopped=timeouts.pdf" "報告.pdf" >> "$STUB_STATE/stubborn"
OUT="$(/bin/bash "$SCRIPT" download "$DBX" 2>/dev/null)"; rc=$?
assert_eq  "newline name: exit status" 2 "$rc"
assert_has "newline name: printed on one line" "online_only_file=evil?stopped=timeouts.pdf" "$OUT"
assert_has "newline name: non-ASCII name unchanged" "online_only_file=報告.pdf" "$OUT"
assert_eq  "newline name: no injected line" "" "$(printf '%s\n' "$OUT" | grep -x 'stopped=timeouts')"
assert_no_reads_left "newline name"
teardown

# --- spec-example: dropbox-local-files / download with no argument ---------------------
setup
ERR="$(/bin/bash "$SCRIPT" download 2>&1 >/dev/null)"; rc=$?
assert_eq "download without PATH: exit status" 64 "$rc"
assert_has "usage names local-status PATH" "dropbox-fix.sh local-status PATH" "$ERR"
assert_has "usage names download PATH" "dropbox-fix.sh download PATH" "$ERR"
/bin/bash "$SCRIPT" local-status >/dev/null 2>&1; rc=$?
assert_eq "local-status without PATH: exit status" 64 "$rc"
teardown

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
