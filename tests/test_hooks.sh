#!/bin/bash
# Tests for the plugin's hooks: plugin/scripts/skill-hint.sh with plugin/scripts/hint.js,
# and plugin/hooks/hooks.json. Hook input is synthetic JSON built here; the home directory
# is a temporary one, so no real path appears in this file. Markers go to a temporary
# directory per case.
# Every test is tagged with the spec Example it checks: `spec-example: <capability> / <title>`.
#
# Usage: bash tests/test_hooks.sh   (from the repo root)

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/plugin/scripts/skill-hint.sh"
HOOKS="$REPO_ROOT/plugin/hooks/hooks.json"

# The directory name must not contain the word the prefilter looks for: these paths end
# up in the cwd and transcript_path fields of the synthetic input.
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/hooks-test.XXXXXX")" || exit 2
trap 'rm -rf "$TMPD"' EXIT
THOME="$TMPD/home"
DBX="$THOME/Library/CloudStorage/Dropbox"
mkdir -p "$DBX"
TRANSCRIPT="$THOME/.claude/projects/-tmp-x/t.jsonl"

pass=0
fail=0
n=0

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

# A new, empty marker directory.
fresh() { n=$((n + 1)); MARK="$TMPD/mark.$n"; mkdir -p "$MARK"; }

jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

prompt_json() { # session prompt cwd [transcript]
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"%s"}' \
    "$(jesc "$1")" "$(jesc "${4:-$TRANSCRIPT}")" "$(jesc "$3")" "$(jesc "$2")"
}

bash_json() { # session command cwd [description] [transcript]
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"%s"}}' \
    "$(jesc "$1")" "$(jesc "${5:-$TRANSCRIPT}")" "$(jesc "$3")" "$(jesc "$2")" "$(jesc "${4:-run a command}")"
}

# Runs the hook script. Sets OUT (stdout) and RC.
run() { # mode json
  OUT="$(printf '%s' "$2" | HOME="$THOME" DROPBOX_FIX_HINT_DIR="$MARK" /bin/bash "$SCRIPT" "$1" 2>/dev/null)"
  RC=$?
}

# What the output is: hint, deny, nothing, or other.
kind() {
  if [ -z "$OUT" ]; then echo nothing; return; fi
  case "$OUT" in
    *'"hookEventName":"UserPromptSubmit"'*'mac-dropbox-fix:dropbox-fix'*) echo hint ;;
    *'"permissionDecision":"deny"'*'mac-dropbox-fix:dropbox-use'*)        echo deny ;;
    *) echo other ;;
  esac
}

# One JSON object, readable by the engine that ships with macOS.
is_json_object() {
  printf '%s' "$OUT" | osascript -l JavaScript -e '
    ObjC.import("Foundation");
    var d = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
    var s = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(d, $.NSUTF8StringEncoding));
    var o = JSON.parse(s);
    (o !== null && typeof o === "object" && !(o instanceof Array)) ? "yes" : "no";' 2>/dev/null
}

prompt_case() { # expected prompt
  fresh
  run prompt "$(prompt_json s1 "$2" "$THOME")"
  assert_eq "prompt [$2] -> $1" "$1/0" "$(kind)/$RC"
}

bash_case() { # expected command cwd
  fresh
  run bash "$(bash_json s1 "$2" "$3")"
  assert_eq "bash [$2] -> $1" "$1/0" "$(kind)/$RC"
}

# --- spec-example: skill-trigger-hooks / prompts and hints
prompt_case hint    '但現在dropbox沒同步欸'
prompt_case hint    'Dropbox 卡住了'
prompt_case hint    'My Dropbox is not syncing'
prompt_case hint    'Dropbox 很吃 CPU'
prompt_case nothing '把報告放到 Dropbox'
prompt_case nothing 'build 卡住了'

fresh
run prompt "$(prompt_json s1 'Dropbox 卡住了' "$THOME")"
assert_eq "prompt hint is one JSON object" "yes" "$(is_json_object)"

# --- spec-example: skill-trigger-hooks / commands and decisions
bash_case deny    'cp -R ~/Library/CloudStorage/Dropbox/a /tmp/b' "$THOME"
bash_case deny    'mv ~/Dropbox/x ~/Dropbox/y'                    "$THOME"
bash_case deny    'tar czf /tmp/a.tgz notes'                      "$DBX/work"
bash_case deny    'rsync -a "$HOME/Dropbox/a/" /tmp/a/'           "$THOME"
bash_case deny    "ditto $THOME/Dropbox/a /tmp/a"                 "$THOME"
bash_case nothing 'ls ~/Library/CloudStorage/Dropbox'             "$THOME"
bash_case nothing 'cp a.txt b.txt'                                "$THOME"
bash_case nothing 'scp ~/Dropbox/x host:'                         "$THOME"

fresh
run bash "$(bash_json s1 'cp -R ~/Dropbox/a /tmp/a' "$THOME")"
assert_eq "bash refusal is one JSON object" "yes" "$(is_json_object)"
assert_has "bash refusal says it happens once per session" "session" "$OUT"

# --- spec-example: skill-trigger-hooks / same session twice, then another session
fresh
seq_out=""
run bash "$(bash_json s1 'cp -R ~/Dropbox/a /tmp/a' "$THOME")"; seq_out="$(kind)"
run bash "$(bash_json s1 'cp -R ~/Dropbox/a /tmp/a' "$THOME")"; seq_out="$seq_out $(kind)"
run bash "$(bash_json s2 'cp -R ~/Dropbox/a /tmp/a' "$THOME")"; seq_out="$seq_out $(kind)"
assert_eq "bash: s1, s1, s2" "deny nothing deny" "$seq_out"

# --- spec-example: skill-trigger-hooks / prompt hint repeats in no session
fresh
run prompt "$(prompt_json s1 'Dropbox 卡住了' "$THOME")"; seq_out="$(kind)"
run prompt "$(prompt_json s1 'Dropbox 卡住了' "$THOME")"; seq_out="$seq_out $(kind)"
assert_eq "prompt: s1, s1" "hint nothing" "$seq_out"

# --- spec-example: skill-trigger-hooks / failure inputs
MATCH="$(bash_json s1 'cp -R ~/Dropbox/a /tmp/a' "$THOME")"

fresh
run bash 'not json but dropbox cp'
assert_eq "failure: stdin is not JSON" "nothing/0" "$(kind)/$RC"

fresh
STUB_FAIL="$TMPD/stub-fail"; mkdir -p "$STUB_FAIL"
printf '#!/bin/bash\nexit 1\n' > "$STUB_FAIL/osascript"; chmod +x "$STUB_FAIL/osascript"
OUT="$(printf '%s' "$MATCH" | HOME="$THOME" DROPBOX_FIX_HINT_DIR="$MARK" PATH="$STUB_FAIL:$PATH" /bin/bash "$SCRIPT" bash 2>/dev/null)"; RC=$?
assert_eq "failure: osascript exits 1" "nothing/0" "$(kind)/$RC"

fresh
rmdir "$MARK"; : > "$MARK"
run bash "$MATCH"
assert_eq "failure: marker directory is a regular file" "nothing/0" "$(kind)/$RC"
rm -f "$MARK"

fresh
run bash "{\"cwd\":\"$THOME\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cp -R ~/Dropbox/a /tmp/a\"}}"
assert_eq "failure: no session_id" "nothing/0" "$(kind)/$RC"

fresh
run bash "$(bash_json '../x' 'cp -R ~/Dropbox/a /tmp/a' "$THOME")"
assert_eq "failure: session_id is ../x" "nothing/0" "$(kind)/$RC"
assert_eq "failure: session_id ../x wrote nothing outside the marker directory" "" "$(ls "$TMPD" | grep -x 'x.use')"

fresh
run other "$MATCH"
assert_eq "failure: unknown mode" "nothing/0" "$(kind)/$RC"

# --- spec-example: skill-trigger-hooks / local-status before a copy
fresh
run bash "$(bash_json s1 'bash /p/scripts/dropbox-fix.sh local-status ~/Dropbox/a' "$THOME")"; seq_out="$(kind)"
run bash "$(bash_json s1 'cp -R ~/Dropbox/a /tmp/a' "$THOME")"; seq_out="$seq_out $(kind)"
assert_eq "in use: local-status, then cp" "nothing nothing" "$seq_out"

fresh
run bash "$(bash_json s1 'bash /p/scripts/dropbox-fix.sh download ~/Dropbox/a' "$THOME")"
assert_eq "in use: the skill's own download is never refused" "nothing/0" "$(kind)/$RC"

fresh
run bash "$(bash_json s1 '/bin/bash /p/scripts/dropbox-fix.sh probe' "$THOME")"; seq_out="$(kind)"
run prompt "$(prompt_json s1 'Dropbox 卡住了' "$THOME")"; seq_out="$seq_out $(kind)"
assert_eq "in use: probe, then a stuck prompt" "nothing nothing" "$seq_out"

# --- spec-example: skill-trigger-hooks / slash command before a stuck prompt
fresh
run prompt "$(prompt_json s1 '/mac-dropbox-fix:dropbox-fix' "$THOME")"; seq_out="$(kind)"
run prompt "$(prompt_json s1 'Dropbox 卡住了' "$THOME")"; seq_out="$seq_out $(kind)"
assert_eq "in use: slash command, then a stuck prompt" "nothing nothing" "$seq_out"

fresh
run prompt "$(prompt_json s1 '/dropbox-use ~/Dropbox/a' "$THOME")"; seq_out="$(kind)"
run bash "$(bash_json s1 'cp -R ~/Dropbox/a /tmp/a' "$THOME")"; seq_out="$seq_out $(kind)"
assert_eq "in use: /dropbox-use, then cp" "nothing nothing" "$seq_out"

# --- spec-example: skill-trigger-hooks / fields that do not count
fresh
run bash "$(bash_json s1 'cp a.txt b.txt' "$THOME" 'cp files from ~/Dropbox')"
assert_eq "fields: Dropbox only in the description" "nothing/0" "$(kind)/$RC"

fresh
run bash "$(bash_json s1 'cp a.txt b.txt' "$THOME" 'copy' "$THOME/.claude/projects/-x-Library-CloudStorage-Dropbox-w/t.jsonl")"
assert_eq "fields: Dropbox only in transcript_path" "nothing/0" "$(kind)/$RC"

fresh
run prompt "$(prompt_json s1 'build 卡住了' "$DBX/work")"
assert_eq "fields: prompt mode ignores a Dropbox cwd" "nothing/0" "$(kind)/$RC"

fresh
run prompt "{\"session_id\":\"s1\",\"cwd\":\"$THOME\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"Dropbox \\u6c92\\u540c\\u6b65\"}"
assert_eq "fields: prompt written with \\u escapes" "hint/0" "$(kind)/$RC"

# --- spec-example: skill-trigger-hooks / osascript invocations counted by a stub
STUB_COUNT="$TMPD/stub-count"; mkdir -p "$STUB_COUNT"
REAL_OSA="$(command -v osascript)"
printf '#!/bin/bash\necho x >> "%s/count"\nexec "%s" "$@"\n' "$STUB_COUNT" "$REAL_OSA" > "$STUB_COUNT/osascript"
chmod +x "$STUB_COUNT/osascript"

count_case() { # expected mode json name
  fresh
  rm -f "$STUB_COUNT/count"
  printf '%s' "$3" | HOME="$THOME" DROPBOX_FIX_HINT_DIR="$MARK" PATH="$STUB_COUNT:$PATH" /bin/bash "$SCRIPT" "$2" >/dev/null 2>&1
  local c=0
  [ -f "$STUB_COUNT/count" ] && c="$(wc -l < "$STUB_COUNT/count" | tr -d ' ')"
  assert_eq "cost: $4 -> osascript runs $1" "$1" "$c"
}

count_case 0 bash   "$(bash_json s1 'git status' "$THOME")"            "git status at home"
count_case 0 bash   "$(bash_json s1 'ls' "$DBX/work")"                 "ls inside the Dropbox folder"
count_case 0 prompt "$(prompt_json s1 'hello' "$THOME")"               "prompt hello"
count_case 1 bash   "$(bash_json s1 'cp ~/Dropbox/a /tmp/a' "$THOME")" "cp from Dropbox"

# --- spec-example: skill-trigger-hooks / hooks.json contents
hooks_lines="$(osascript -l JavaScript -e '
  ObjC.import("Foundation");
  function run(argv) {
    var s = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null));
    var o = JSON.parse(s), lines = [], ev, i, j, g, h;
    var names = Object.keys(o.hooks).sort();
    lines.push("events=" + names.join(","));
    for (ev = 0; ev < names.length; ev++) {
      for (i = 0; i < o.hooks[names[ev]].length; i++) {
        g = o.hooks[names[ev]][i];
        for (j = 0; j < g.hooks.length; j++) {
          h = g.hooks[j];
          lines.push([names[ev], g.matcher === undefined ? "-" : g.matcher, h.type, h.timeout, h.command].join("|"));
        }
      }
    }
    return lines.join("\n");
  }' "$HOOKS" 2>/dev/null)"
assert_eq "hooks.json: exactly two events" "events=PreToolUse,UserPromptSubmit" "$(printf '%s\n' "$hooks_lines" | sed -n '1p')"
assert_eq "hooks.json: two hook entries" "2" "$(printf '%s\n' "$hooks_lines" | sed '1d' | grep -c .)"
assert_eq "hooks.json: PreToolUse entry" \
  'PreToolUse|Bash|command|10|/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/skill-hint.sh" bash' \
  "$(printf '%s\n' "$hooks_lines" | grep '^PreToolUse|')"
assert_eq "hooks.json: UserPromptSubmit entry" \
  'UserPromptSubmit|-|command|10|/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/skill-hint.sh" prompt' \
  "$(printf '%s\n' "$hooks_lines" | grep '^UserPromptSubmit|')"

# --- spec-example: skill-trigger-hooks / disclosure strings
readme_section="$(awk '
  /^## / { if (found) exit; buf = "" }
  { buf = buf $0 "\n" }
  /UserPromptSubmit/ { found = 1 }
  END { if (found) printf "%s", buf }
' "$REPO_ROOT/README.md")"
assert_has "disclosure: README section names UserPromptSubmit" "UserPromptSubmit" "$readme_section"
assert_has "disclosure: the same README section names PreToolUse" "PreToolUse" "$readme_section"
assert_has "disclosure: the same README section states the once-per-session limit" "每個 session 最多" "$readme_section"
manifest_desc="$(grep '"description"' "$REPO_ROOT/plugin/.claude-plugin/plugin.json")"
assert_has "disclosure: manifest description mentions the hooks" "hook" "$manifest_desc"
for s in dropbox-fix dropbox-use; do
  table="$(awk '/^## 驗證到哪裡/ { on = 1; next } on && /^## / { exit } on' "$REPO_ROOT/plugin/skills/$s/SKILL.md" | grep '^|')"
  assert_has "disclosure: $s verification table has a hook row" "hook" "$table"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
