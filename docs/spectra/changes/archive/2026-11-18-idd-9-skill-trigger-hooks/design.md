## Context

Skill listings on machines with many skills carry names only. Measured on one such machine (issue #9): the listing budget was already doubled and both skills of this plugin still appeared without descriptions; `dropbox-use` loaded in 1 of 12 sessions that ran inside a Dropbox folder. Claude Code's documentation says rules that must hold every time belong in hooks, and that `additionalContext` from a `PreToolUse` hook is placed next to the tool result, after the command has run.

The maintainer chose the direction on 2026-11-18: hooks for both skills, and for the Bash side a single refusal per session instead of a hint that arrives after the command.

Constraints from this repository: scripts run under the system bash 3.2; no `jq`, `python3` or `timeout` at run time; JSON is read with `osascript -l JavaScript` in ES5 (as `kb.js` does); tracked files carry no home paths.

## Goals / Non-Goals

**Goals:**

- The model learns of `mac-dropbox-fix:dropbox-fix` when a prompt reports Dropbox stuck, and of `mac-dropbox-fix:dropbox-use` before a batch file operation in a Dropbox folder runs.
- A session is interrupted at most once per skill.
- A broken hook never blocks a prompt or a command.
- The common case (no Dropbox involved) costs one bash start and nothing else.

**Non-Goals:**

- No prompt-side hint for `dropbox-use`.
- No use of the hook `if` field; whether it narrows without losing commands is tracked in issue #10.
- No renaming of skills, no change to `dropbox-fix.sh` or `kb.js`.
- No change to `.github/workflows/ci.yml`.
- No guarantee that the model loads the skill after reading the hint; that is observed, not enforced.

## Decisions

### Refuse the first matching Bash command once instead of adding context

`PreToolUse` `additionalContext` reaches the model with the tool result, so it cannot protect the first command. A `deny` decision reaches the model before anything runs. The refusal is limited to once per session so that a wrong match costs one extra round trip and nothing more. Alternative considered: context only (keeps commands untouched, but the first batch copy runs on placeholders unseen). Alternative considered: `ask` (puts the question to the person, who cannot judge placeholders either).

### Create the session marker before printing a refusal

The script creates the marker file with noclobber and prints the refusal only when that creation succeeded. If the marker exists, cannot be created, or the session id is missing or malformed, the command is allowed. A second refusal in one session is therefore impossible by construction, including when the data directory is unwritable.

### Two stages: a bash prefilter, then JXA on decoded fields

Stage one is pure bash on the raw input: no `dropbox` (any case) means exit 0; in bash mode it also requires one of the verb strings or `dropbox-fix.sh`. Measured on macOS 27.3, mean of 10 runs: 6 ms for stage one, 52 ms for an `osascript` JSON parse. Stage two parses the JSON and matches only decoded fields: `prompt` in prompt mode; `tool_input.command` and `cwd` in bash mode. The raw input also holds `transcript_path` and `tool_input.description`, which can contain the word Dropbox, so matching the raw text would misfire. Alternative considered: extracting fields with bash regular expressions (no second process, but wrong for `\u` escapes and escaped quotes).

### Closed lists for terms, verbs and paths

Stuck terms, command verbs (`cp`, `mv`, `rsync`, `ditto`, `tar`, `zip`) and Dropbox path forms are closed lists in `hint.js`. Path forms: any path containing `Library/CloudStorage/Dropbox`; and `Dropbox` directly under the home directory written as `~/Dropbox`, `$HOME/Dropbox`, `${HOME}/Dropbox` or the expanded home path. The home directory is passed to `hint.js` as an argument so tests can use a temporary one.

### A session where the skill is already in use is left alone

A Bash command that runs the plugin's own `dropbox-fix.sh` is always allowed and records the marker of the skill it belongs to (`local-status` and `download` belong to `dropbox-use`, every other subcommand to `dropbox-fix`). A prompt that starts with `/mac-dropbox-fix:dropbox-fix` or `/mac-dropbox-fix:dropbox-use` (with or without the plugin prefix) records the marker and adds nothing.

### Markers live in the plugin data directory

Marker directory, first that applies: `DROPBOX_FIX_HINT_DIR` (tests), `CLAUDE_PLUGIN_DATA/hints`, `TMPDIR/mac-dropbox-fix-hints`. File name: session id plus `.fix` or `.use`. When a marker is created, markers older than 14 days in that directory are deleted.

### Every hook entry sets a timeout of 10 seconds

The default for a `PreToolUse` command hook is 600 seconds. A timed-out hook renders no decision, so 10 seconds bounds the worst case and still fails open.

## Implementation Contract

- Behavior: `skill-hint.sh prompt` and `skill-hint.sh bash` read one hook input JSON object on stdin. They print either nothing or exactly one JSON object, and always exit 0.
- Prompt hint shape: `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"<text>"}}`; the text contains `mac-dropbox-fix:dropbox-fix`.
- Refusal shape: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<text>"}}`; the text contains `mac-dropbox-fix:dropbox-use` and says the refusal happens once per session.
- Both texts are fixed strings in the script, written as statements. Nothing from the input is copied into the output.
- `hint.js MODE HOME` reads stdin and prints one line `VERDICT SESSION`, where VERDICT is one of `none`, `hint-fix`, `hint-use`, `using-fix`, `using-use`, and SESSION is the session id when it matches `[A-Za-z0-9_-]{1,128}`, otherwise `-`.
- Failure modes, all silent with exit 0 and empty stdout: input that is not JSON, missing fields, `osascript` missing or failing, unknown mode, marker directory that cannot be created or written.
- `plugin/hooks/hooks.json` declares exactly two events: `UserPromptSubmit`, and `PreToolUse` with matcher `Bash`. Each command starts with `/bin/bash`, references the script through `${CLAUDE_PLUGIN_ROOT}`, and sets `timeout` 10.
- Acceptance: `bash tests/test_hooks.sh` passes under `/bin/bash`; the other four test scripts still pass; `scripts/check-privacy.sh` passes; `claude plugin validate plugin` passes; a real `claude -p --plugin-dir plugin` run of each scenario is recorded in the verification tables with its Claude Code version, or the row says unverified.
- In scope: the files named in the proposal. Out of scope: `dropbox-fix.sh`, `kb.js`, `problems.json`, the CI workflow, the marketplace index.

## Risks / Trade-offs

- A command that merely names a Dropbox path next to a listed verb is refused once. Accepted by the maintainer; the reason text says the same command runs when sent again.
- A stuck report phrased outside the term list gets no hint; behaviour is then the same as before this change.
- Hook input fields and the rendering of a refusal belong to Claude Code and can change; the verification tables record the version tested.
- The hook runs for every installer on every prompt and Bash command. Stage one keeps that to one bash start (6 ms measured).
