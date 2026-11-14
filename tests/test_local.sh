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
  [ -n "$3" ] && printf '%s\t%s\n' "${1##*/}" "$3" >> "$STUB_STATE/flags"
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
SCOPED_SUBCOMMANDS="local-status"
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
