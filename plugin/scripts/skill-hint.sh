#!/bin/bash
# skill-hint — the plugin's hook script. Tells the model about the dropbox-fix and
# dropbox-use skills at the moment they apply, because the skill listing can omit their
# descriptions.
#
# Usage (hook input JSON on stdin):
#   skill-hint.sh prompt    UserPromptSubmit: a prompt that reports Dropbox stuck or not
#                           syncing gets added context naming mac-dropbox-fix:dropbox-fix
#   skill-hint.sh bash      PreToolUse on Bash: the first command of a session that copies,
#                           moves or archives in a Dropbox folder is refused once, with a
#                           reason naming mac-dropbox-fix:dropbox-use
#
# Prints nothing or exactly one JSON object, and always exits 0: a prompt or a command is
# never blocked because this script failed. Each skill is announced at most once per
# session; a marker file is created before anything is printed, and nothing is printed
# unless that creation succeeded.
#
# Stage one is this file: when the raw input does not mention dropbox (or, in bash mode,
# none of the listed verbs), it exits without starting another process. Input that carries
# \u00 and two hexadecimal digits always goes on, because such an escape can hide a letter
# of those words. Stage two is
# hint.js, which parses the JSON and matches decoded fields only.
#
# Markers: $DROPBOX_FIX_HINT_DIR (the tests set it), else $CLAUDE_PLUGIN_DATA/hints. With
# neither, nothing is printed. One empty file per session and skill. This script never
# deletes a marker: the marker is what keeps a session from being told twice, however
# long the session lives.

set -u

MODE="${1:-}"
case "$MODE" in
  prompt|bash) ;;
  *) exit 0 ;;
esac

# Builtins only up to the prefilter: an input that fails it starts no other program.
HERE="${0%/*}"
[ "$HERE" = "$0" ] && HERE=.
INPUT=""
IFS= read -r -d '' INPUT

case "$INPUT" in
  *'\u00'[0-9A-Fa-f][0-9A-Fa-f]*) ;;
  *[Dd][Rr][Oo][Pp][Bb][Oo][Xx]*)
    if [ "$MODE" = bash ]; then
      case "$INPUT" in
        *cp*|*mv*|*rsync*|*ditto*|*tar*|*zip*|*dropbox-fix.sh*) ;;
        *) exit 0 ;;
      esac
    fi
    ;;
  *) exit 0 ;;
esac

if [ -n "${DROPBOX_FIX_HINT_DIR:-}" ]; then
  MARK_DIR="$DROPBOX_FIX_HINT_DIR"
elif [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
  MARK_DIR="$CLAUDE_PLUGIN_DATA/hints"
else
  exit 0
fi

# A quick look at the session id, only to skip stage two when there is nothing left to
# say in this session. hint.js reads the real value.
SID_RE='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
if [[ $INPUT =~ $SID_RE ]]; then
  QUICK="${BASH_REMATCH[1]}"
  if [ -e "$MARK_DIR/$QUICK.fix" ] && [ -e "$MARK_DIR/$QUICK.use" ]; then
    exit 0
  fi
fi

VERDICT_LINE="$(printf '%s' "$INPUT" | osascript -l JavaScript "$HERE/hint.js" "$MODE" "${HOME:-}" 2>/dev/null)" || exit 0
VERDICT="${VERDICT_LINE%% *}"
SESSION="${VERDICT_LINE#* }"

case "$SESSION" in
  ''|-|*[!A-Za-z0-9_-]*) exit 0 ;;
esac

# Creates the marker for one skill. Succeeds only when this call created it.
mark() { # fix|use
  mkdir -p "$MARK_DIR" 2>/dev/null || return 1
  [ -d "$MARK_DIR" ] || return 1
  # noclobber refuses only an existing regular file; a symbolic link or a pipe at the
  # marker path would otherwise count as newly created.
  if [ -e "$MARK_DIR/$SESSION.$1" ] || [ -L "$MARK_DIR/$SESSION.$1" ]; then return 1; fi
  ( set -C; : > "$MARK_DIR/$SESSION.$1" ) 2>/dev/null || return 1
  return 0
}

case "$VERDICT" in
  using-fix) mark fix ;;
  using-use) mark use ;;
  hint-fix)
    [ "$MODE" = prompt ] || exit 0
    mark fix || exit 0
    cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"mac-dropbox-fix：這則訊息提到 Dropbox 卡住或不同步。這個 plugin 的 skill `mac-dropbox-fix:dropbox-fix` 會先量測 Dropbox 與 macOS File Provider 的狀態，再對照已知問題的知識庫找出原因；skill 清單裡它的描述可能沒有列出。這則說明每個 session 只出現一次。"}}
JSON
    ;;
  hint-use)
    [ "$MODE" = bash ] || exit 0
    mark use || exit 0
    cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"mac-dropbox-fix：這個指令要在 Dropbox 資料夾裡複製、搬移或打包檔案，這一次沒有執行。Dropbox 資料夾裡的檔案可能是僅線上的佔位檔：ls 顯示完整大小，內容還在雲端；拿一批佔位檔去複製或打包，會邊下載邊做，中途斷線就只做了一半。這個 plugin 的 skill `mac-dropbox-fix:dropbox-use`（用 Skill 工具載入）第一步是唯讀的 local-status，量出哪些檔案已經在這台 Mac 上；動一批檔案之前先載入它。這個擋下每個 session 只發生一次，之後的指令不會再被擋。"}}
JSON
    ;;
esac
exit 0
