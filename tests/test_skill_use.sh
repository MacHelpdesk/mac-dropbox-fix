#!/bin/bash
# Tests for plugin/skills/dropbox-use/SKILL.md: the four closed action lists and what
# they hold, and the evidence labels in the copying section. The skill is prose that
# Claude follows; these tests check the text it is given, not a run.
# Every test is tagged with the spec Example it checks: `spec-example: <capability> / <title>`.
#
# Usage: bash tests/test_skill_use.sh   (from the repo root)

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO_ROOT/plugin/skills/dropbox-use/SKILL.md"

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
    *)      bad "$1" "[$2] not found" ;;
  esac
}

assert_lacks() { # name needle haystack
  case "$3" in
    *"$2"*) bad "$1" "[$2] found where it must not be" ;;
    *)      ok "$1" ;;
  esac
}

# The lines under the first heading that starts with the given text, up to the next
# heading of level 2 or 3.
section() { # heading prefix
  awk -v h="$1" '
    index($0, h) == 1 { on = 1; next }
    on && /^##+ / { exit }
    on { print }
  ' "$SKILL"
}

# The data rows of the markdown tables in a block of text: table lines without the
# header row and the separator row.
rows() { # text
  printf '%s\n' "$1" | awk '/^\|/ { n++; if (n > 2) print } !/^\|/ { n = 0 }'
}

line_of() { # heading prefix: its line number, or 0
  awk -v h="$1" 'index($0, h) == 1 { print NR; found = 1; exit } END { if (!found) print 0 }' "$SKILL"
}

DIRECT="### 直接做"
ASK="### 先問"
USER_ONLY="### 只說明步驟，由使用者自己做"
NEVER="### 不做"

if [ ! -f "$SKILL" ]; then
  bad "skill file exists" "$SKILL not found"
  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  exit 1
fi

# --- spec-example: dropbox-use-skill / list membership -------------------------------
d="$(line_of "$DIRECT")"; a="$(line_of "$ASK")"; u="$(line_of "$USER_ONLY")"; n="$(line_of "$NEVER")"
if [ "$d" -gt 0 ] && [ "$a" -gt "$d" ] && [ "$u" -gt "$a" ] && [ "$n" -gt "$u" ]; then
  ok "lists: four lists in order direct, ask first, user only, never"
else
  bad "lists: four lists in order direct, ask first, user only, never" "lines $d $a $u $n"
fi
for h in "$DIRECT" "$ASK" "$USER_ONLY" "$NEVER"; do
  assert_has "lists: '$h' says it is closed" "只有這" "$(grep -m1 "^$h" "$SKILL")"
done
assert_has "lists: closed lists are not extended by analogy" "不得依性質相似類推" "$(section "## 行為界線")"
assert_has   "lists: local-status done directly"     "dropbox-fix.sh local-status" "$(section "$DIRECT")"
assert_lacks "lists: download not done directly"     "dropbox-fix.sh download"     "$(section "$DIRECT")"
assert_has   "lists: download asked first"           "dropbox-fix.sh download"     "$(section "$ASK")"
assert_lacks "lists: local-status not asked first"   "dropbox-fix.sh local-status" "$(section "$ASK")"
assert_has   "lists: Make Available Offline by the user" "可離線使用"              "$(section "$USER_ONLY")"
assert_lacks "lists: no subcommand in the user list" "dropbox-fix.sh"              "$(section "$USER_ONLY")"
assert_has   "lists: nucleus.sqlite3 never touched"  "nucleus.sqlite3"             "$(section "$NEVER")"
assert_lacks "lists: no subcommand in the never list" "dropbox-fix.sh"             "$(section "$NEVER")"

# --- spec-example: dropbox-use-skill / required mentions in the download entry --------
entry="$(rows "$(section "$ASK")" | grep 'dropbox-fix.sh download')"
for k in online_only online_only_bytes free_bytes; do
  assert_has "download entry: names $k" "\`$k\`" "$entry"
done
assert_has "download entry: says files can be evicted again" "回收" "$entry"

# --- spec-example: dropbox-use-skill / four never items --------------------------------
never="$(rows "$(section "$NEVER")")"
assert_eq  "never: exactly four entries" 4 "$(printf '%s\n' "$never" | grep -c .)"
assert_has "never: making files online-only" "僅線上"          "$never"
assert_has "never: Dropbox settings"         "設定"            "$never"
assert_has "never: nucleus.sqlite3"          "nucleus.sqlite3" "$never"
assert_has "never: paths outside the Dropbox folder" "CloudStorage" "$never"

# --- spec-example: dropbox-use-skill / copying section labels --------------------------
copying="$(rows "$(section "## 複製或備份")")"
n_methods="$(printf '%s\n' "$copying" | grep -c .)"
if [ "$n_methods" -ge 2 ]; then ok "copying: at least two methods described"
else bad "copying: at least two methods described" "found $n_methods"; fi
unlabelled="$(printf '%s\n' "$copying" | grep . | grep -vE 'verified|reported')"
assert_eq "copying: every method carries an evidence label" "" "$unlabelled"
internal="$(printf '%s\n' "$copying" | grep 'com.dropbox.internal')"
assert_has "copying: a method mentions com.dropbox.internal" "com.dropbox.internal" "$internal"
assert_eq  "copying: com.dropbox.internal lines are unverified" "" \
  "$(printf '%s\n' "$internal" | grep . | grep -v 'unverified')"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
