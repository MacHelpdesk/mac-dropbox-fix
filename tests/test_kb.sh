#!/bin/bash
# Tests for the knowledge base (plugin/data/problems.json) and the commands that read
# it: validate, match, list, show. No process on the Mac is touched: signals are fed
# from files.
#
# Usage: bash tests/test_kb.sh   (from the repo root)

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/plugin/scripts/dropbox-fix.sh"
KB="$REPO_ROOT/plugin/data/problems.json"

pass=0
fail=0

ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n     %s\n' "$1" "$2"; }

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME"

[ -f "$SCRIPT" ] || { echo "FAIL script not found: $SCRIPT"; exit 1; }
[ -f "$KB" ]     || { echo "FAIL knowledge base not found: $KB"; exit 1; }

run() { /bin/bash "$SCRIPT" "$@"; }

# Baseline: a healthy Mac. Each case overrides the lines it needs.
healthy() {
  cat <<'EOF'
dropbox_app=running
dropbox_extension=running
fileproviderd=running
stray_sqlite3=0
dump_result=ok
domain_state=alive
domain_startup_error=none
needs_auth=no
index_dropped=no
sync_anchor_drop=no
pending_indexable=0
total_indexable=1000
EOF
}

signals() { # file, then key=value overrides
  local f="$1" kv k
  shift
  healthy > "$f"
  for kv in "$@"; do
    k="${kv%%=*}"
    grep -v "^$k=" "$f" > "$f.tmp"; mv "$f.tmp" "$f"
    printf '%s\n' "$kv" >> "$f"
  done
}

first_match() { run match "$1" 2>/dev/null | head -1 | cut -f1; }

# --- the shipped knowledge base is valid -------------------------------------------
run validate >/dev/null 2>"$T/err"; rc=$?
assert_eq "validate: shipped knowledge base" 0 "$rc"
[ "$rc" -eq 0 ] || cat "$T/err"

# --- validate rejects what the closed lists do not allow ---------------------------
mutate() { # name, sed expression applied to the shipped knowledge base
  sed -E "$2" "$KB" > "$T/bad.json"
  if cmp -s "$KB" "$T/bad.json"; then bad "$1" "the mutation did not change the file"; return; fi
  DROPBOX_FIX_KB="$T/bad.json" run validate >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ]; then ok "$1"; else bad "$1" "validate accepted it"; fi
}
mutate "validate: unknown action class"  '1,/"class": "ask"/s/"class": "ask"/"class": "sometimes"/'
mutate "validate: unknown evidence"      '1,/"status": "verified"/s/"status": "verified"/"status": "probably"/'
mutate "validate: unknown operator"      '1,/"op": "equals"/s/"op": "equals"/"op": "matches"/'
mutate "validate: unknown signal"        '1,/"signal": "domain_state"/s/"signal": "domain_state"/"signal": "moon_phase"/'
mutate "validate: number operator with text"  '1,/"op": "gte", "value": 1 /s/"op": "gte", "value": 1 /"op": "gte", "value": "1" /'
mutate "validate: id used twice"         's/"id": "sync-anchor-dropped"/"id": "stray-sqlite3-on-nucleus"/'
mutate "validate: schema_version"        's/"schema_version": 1,/"schema_version": 2,/'
mutate "validate: fix without evidence"  '1,/"evidence": "unverified"/s/"evidence": "unverified"/"evidence": ""/'
printf '{ not json' > "$T/bad.json"
DROPBOX_FIX_KB="$T/bad.json" run validate >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then ok "validate: not JSON"; else bad "validate: not JSON" "validate accepted it"; fi

# --- match -------------------------------------------------------------------------
signals "$T/s" domain_state=startup_failed domain_startup_error=sqlite_locked dropbox_extension=not_running pending_indexable=734720
assert_eq "match: domain startup locked" fileprovider-domain-startup-locked "$(first_match "$T/s")"

signals "$T/s" pending_indexable=602720
assert_eq "match: re-indexing after an unclean shutdown" spotlight-reindex-after-unclean-shutdown "$(first_match "$T/s")"

signals "$T/s" sync_anchor_drop=yes index_dropped=yes
assert_eq "match: sync anchor, index dropped now" sync-anchor-dropped "$(first_match "$T/s")"

# The reason text alone is history: it stays in the dump long after the event.
signals "$T/s" sync_anchor_drop=yes index_dropped=no
assert_eq "match: sync anchor text alone matches nothing" "" "$(first_match "$T/s")"

signals "$T/s" stray_sqlite3=2
assert_eq "match: stray sqlite3" stray-sqlite3-on-nucleus "$(first_match "$T/s")"

signals "$T/s" dump_result=timeout domain_state=unknown
assert_eq "match: dump hangs while the extension runs" fileprovider-xpc-deadlock "$(first_match "$T/s")"

signals "$T/s" dropbox_app=not_running dropbox_extension=not_running domain_state=no_process
assert_eq "match: Dropbox is not running" dropbox-app-not-running "$(first_match "$T/s")"

signals "$T/s"
run match "$T/s" >"$T/out" 2>/dev/null; rc=$?
assert_eq "match: healthy Mac matches nothing" "" "$(cat "$T/out")"
assert_eq "match: healthy Mac exit status" 3 "$rc"

signals "$T/s" domain_state=startup_failed domain_startup_error=sqlite_locked
line="$(run match "$T/s" 2>/dev/null | head -1)"
assert_eq "match: second column is the evidence status" verified "$(printf '%s' "$line" | cut -f2)"
assert_eq "match: third column is where the entry comes from" shipped "$(printf '%s' "$line" | cut -f3)"

# --- operators, checked with a small knowledge base of its own ---------------------
cat > "$T/ops.json" <<'EOF2'
{
  "schema_version": 1,
  "signals": {
    "n": { "description": "a number", "values": "number" },
    "s": { "description": "a word", "values": ["a", "b", "unknown"] }
  },
  "never": [],
  "problems": [
    { "id": "n-lte-5", "title": "t", "symptoms": ["x"], "cause": "c",
      "match": { "all": [ { "signal": "n", "op": "lte", "value": 5 } ] },
      "fixes": [ { "id": "f", "action": "a", "class": "user", "evidence": "unverified" } ],
      "evidence": { "status": "unverified" } },
    { "id": "n-gte-5", "title": "t", "symptoms": ["x"], "cause": "c",
      "match": { "all": [ { "signal": "n", "op": "gte", "value": 5 } ] },
      "fixes": [ { "id": "f", "action": "a", "class": "user", "evidence": "unverified" } ],
      "evidence": { "status": "unverified" } },
    { "id": "s-not-a", "title": "t", "symptoms": ["x"], "cause": "c",
      "match": { "all": [ { "signal": "s", "op": "not_equals", "value": "a" } ] },
      "fixes": [ { "id": "f", "action": "a", "class": "user", "evidence": "unverified" } ],
      "evidence": { "status": "unverified" } },
    { "id": "s-is-unknown", "title": "t", "symptoms": ["x"], "cause": "c",
      "match": { "all": [ { "signal": "s", "op": "equals", "value": "unknown" } ] },
      "fixes": [ { "id": "f", "action": "a", "class": "user", "evidence": "unverified" } ],
      "evidence": { "status": "unverified" } }
  ]
}
EOF2
ops() { # signal lines...; prints the matching ids on one line
  printf '%s\n' "$@" > "$T/ops.signals"
  DROPBOX_FIX_KB="$T/ops.json" run match "$T/ops.signals" 2>/dev/null | cut -f1 | tr '\n' ' ' | sed 's/ $//'
}
assert_eq "ops: lte below"                 "n-lte-5 s-not-a"  "$(ops n=3 s=b)"
assert_eq "ops: lte and gte at the value"  "n-lte-5 n-gte-5"  "$(ops n=5 s=a)"
assert_eq "ops: gte above"                 "n-gte-5"          "$(ops n=9 s=a)"
assert_eq "ops: not a number matches neither" ""              "$(ops n=many s=a)"
assert_eq "ops: empty value matches neither"  ""              "$(ops n= s=a)"
assert_eq "ops: not_equals does not match unknown" "s-is-unknown" "$(ops s=unknown)"
assert_eq "ops: a signal that was not reported matches nothing" "" "$(ops other=1)"

# A probe that could not read the domain must not match entries that need its fields.
signals "$T/s" dump_result=timeout domain_state=unknown dropbox_extension=not_running dropbox_app=not_running
got="$(run match "$T/s" 2>/dev/null | cut -f1 | tr '\n' ' ')"
case "$got" in
  *startup-locked*|*sync-anchor*|*spotlight*) bad "match: unreadable domain matches no domain entry" "$got" ;;
  *) ok "match: unreadable domain matches no domain entry" ;;
esac

# --- list and show -----------------------------------------------------------------
n_list="$(run list 2>/dev/null | grep -c .)"
n_ids="$(grep -c '^      "id": ' "$KB")"
assert_eq "list: one line per problem" "$n_ids" "$n_list"

run show fileprovider-domain-startup-locked >"$T/out" 2>/dev/null; rc=$?
assert_eq "show: exit status" 0 "$rc"
if grep -q 'restart-fileproviderd' "$T/out" && grep -q 'ask' "$T/out"; then ok "show: prints fixes with their class"; else bad "show: prints fixes with their class" "$(head -5 "$T/out")"; fi

if grep -q '來源：隨 plugin 發布' "$T/out"; then ok "show: says the entry is shipped"; else bad "show: says the entry is shipped" "$(head -3 "$T/out")"; fi

run show no-such-problem >/dev/null 2>&1; rc=$?
assert_eq "show: unknown id" 1 "$rc"

# --- personal additions in ~/.config/mac-dropbox-fix/problems.local.json ----------
mkdir -p "$HOME/.config/mac-dropbox-fix"
cat > "$HOME/.config/mac-dropbox-fix/problems.local.json" <<'EOF'
{
  "schema_version": 1,
  "problems": [
    {
      "id": "local-example",
      "title": "example added on this Mac",
      "symptoms": ["placeholder"],
      "match": { "all": [ { "signal": "needs_auth", "op": "equals", "value": "yes" } ] },
      "cause": "placeholder",
      "fixes": [ { "id": "sign-in", "action": "placeholder", "class": "user", "evidence": "unverified" } ],
      "evidence": { "status": "unverified" }
    }
  ]
}
EOF
run validate >/dev/null 2>&1; rc=$?
assert_eq "local: validate accepts a well-formed local file" 0 "$rc"
signals "$T/s" needs_auth=yes
assert_eq "local: entries are matched" local-example "$(first_match "$T/s")"
if run list 2>/dev/null | grep -q '^local-example'; then ok "local: entries are listed"; else bad "local: entries are listed" "missing"; fi
assert_eq "local: match marks where the entry comes from" local "$(run match "$T/s" 2>/dev/null | head -1 | cut -f3)"
assert_eq "local: list marks where the entry comes from"  local "$(run list 2>/dev/null | grep '^local-example' | cut -f3)"
run show local-example >"$T/out" 2>/dev/null
if grep -q '來源：個人條目' "$T/out" && grep -q '先給使用者看' "$T/out"; then ok "local: show warns that its commands need asking"; else bad "local: show warns that its commands need asking" "$(head -3 "$T/out")"; fi

sed 's/"class": "user"/"class": "whenever"/' "$HOME/.config/mac-dropbox-fix/problems.local.json" > "$T/l.json"
cp "$T/l.json" "$HOME/.config/mac-dropbox-fix/problems.local.json"
run validate >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then ok "local: validate rejects a bad local file"; else bad "local: validate rejects a bad local file" "accepted"; fi
signals "$T/s" domain_state=startup_failed domain_startup_error=sqlite_locked
assert_eq "local: a bad local file does not hide shipped entries" fileprovider-domain-startup-locked "$(first_match "$T/s")"

sed -e 's/"class": "whenever"/"class": "user"/' -e 's/"id": "local-example"/"id": "sync-anchor-dropped"/' "$T/l.json" > "$HOME/.config/mac-dropbox-fix/problems.local.json"
run validate >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then ok "local: validate rejects an id the shipped file already uses"; else bad "local: validate rejects an id the shipped file already uses" "accepted"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
