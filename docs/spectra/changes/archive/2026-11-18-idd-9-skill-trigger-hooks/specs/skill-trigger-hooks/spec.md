## Purpose

The plugin's hooks tell the model about the `dropbox-fix` and `dropbox-use` skills at the moment they apply, because the skill listing can omit their descriptions. This capability fixes when a hook speaks, how often, and that a failing hook never blocks a prompt or a command.

## ADDED Requirements

### Requirement: a stuck-Dropbox prompt gets one hint naming dropbox-fix

`skill-hint.sh prompt` SHALL print a `UserPromptSubmit` JSON object whose `additionalContext` contains `mac-dropbox-fix:dropbox-fix` when the decoded `prompt` field contains `dropbox` in any letter case and at least one term from the closed stuck-term list in `hint.js`. For every other prompt it SHALL print nothing. It SHALL exit 0 in both cases.

#### Scenario: prompt reports Dropbox not syncing

- **WHEN** the prompt names Dropbox and a stuck term
- **THEN** stdout is one JSON object with `hookSpecificOutput.hookEventName` equal to `UserPromptSubmit` and an `additionalContext` naming `mac-dropbox-fix:dropbox-fix`

##### Example: prompts and hints

| Prompt | Output |
| --- | --- |
| 但現在dropbox沒同步欸 | hint |
| Dropbox 卡住了 | hint |
| My Dropbox is not syncing | hint |
| Dropbox 很吃 CPU | hint |
| 把報告放到 Dropbox | nothing |
| build 卡住了 | nothing |

---
### Requirement: the first batch file command in a Dropbox folder is refused once

`skill-hint.sh bash` SHALL print a `PreToolUse` JSON object with `permissionDecision` equal to `deny` and a `permissionDecisionReason` containing `mac-dropbox-fix:dropbox-use` when the decoded `tool_input.command` contains a verb from the closed list (`cp`, `mv`, `rsync`, `ditto`, `tar`, `zip`) at a command position and either the command or the `cwd` field points into a Dropbox folder. Dropbox folder forms are a closed list: a path containing `Library/CloudStorage/Dropbox`, and `Dropbox` directly under the home directory written as `~/Dropbox`, `$HOME/Dropbox`, `${HOME}/Dropbox` or the expanded home path. For every other command it SHALL print nothing and exit 0.

#### Scenario: copy out of a Dropbox folder

- **WHEN** the command is a `cp` whose source lies under `Library/CloudStorage/Dropbox`
- **THEN** stdout is one JSON object refusing the call and naming `mac-dropbox-fix:dropbox-use`

##### Example: commands and decisions

| Command | cwd | Output |
| --- | --- | --- |
| cp -R ~/Library/CloudStorage/Dropbox/a /tmp/b | home | deny |
| mv ~/Dropbox/x ~/Dropbox/y | home | deny |
| tar czf /tmp/a.tgz notes | inside the Dropbox folder | deny |
| rsync -a "$HOME/Dropbox/a/" /tmp/a/ | home | deny |
| ls ~/Library/CloudStorage/Dropbox | home | nothing |
| cp a.txt b.txt | home | nothing |
| scp ~/Dropbox/x host: | home | nothing |

---
### Requirement: each skill is announced at most once per session

The script SHALL create a marker file for the session and skill before printing a hint or a refusal, and SHALL print only when that creation succeeded in this run. A second matching input with the same `session_id` SHALL produce no output. A different `session_id` SHALL be treated independently.

#### Scenario: the refused command is sent again

- **WHEN** the same matching Bash input arrives twice with one session id
- **THEN** the first run prints a refusal and the second run prints nothing

##### Example: same session twice, then another session

- **GIVEN** an empty marker directory
- **WHEN** a matching Bash input with session id `s1` is given twice, then once with session id `s2`
- **THEN** the outputs are deny, nothing, deny

##### Example: prompt hint repeats in no session

- **GIVEN** an empty marker directory
- **WHEN** the prompt `Dropbox 卡住了` is given twice with session id `s1`
- **THEN** the outputs are hint, nothing

---
### Requirement: any failure lets the prompt or command through

The script SHALL exit 0 with empty stdout when the input is not JSON, when a needed field is absent, when `osascript` fails or is absent, when the mode argument is unknown, when the session id is absent or contains a character outside `[A-Za-z0-9_-]`, and when the marker file cannot be created.

#### Scenario: the marker directory is not writable

- **WHEN** a matching Bash input arrives and the marker directory cannot be written
- **THEN** stdout is empty and the exit status is 0

##### Example: failure inputs

| Condition | Output | Exit |
| --- | --- | --- |
| stdin is `not json but dropbox cp` | nothing | 0 |
| matching Bash input, `osascript` replaced by a command that exits 1 | nothing | 0 |
| matching Bash input, marker directory is a regular file | nothing | 0 |
| matching Bash input without `session_id` | nothing | 0 |
| matching Bash input with `session_id` equal to `../x` | nothing | 0 |
| matching Bash input, mode argument `other` | nothing | 0 |

---
### Requirement: a session already using a skill is left alone

A Bash command that runs `dropbox-fix.sh` SHALL never be refused. It SHALL record the marker of the skill it belongs to: `local-status` and `download` belong to `dropbox-use`, every other subcommand to `dropbox-fix`. A prompt that starts with `/mac-dropbox-fix:dropbox-fix`, `/dropbox-fix`, `/mac-dropbox-fix:dropbox-use` or `/dropbox-use` SHALL record the matching marker and produce no output.

#### Scenario: the skill's own download then a copy

- **WHEN** a session runs `dropbox-fix.sh download` on a Dropbox path and then a `cp` from the same path
- **THEN** neither command is refused

##### Example: local-status before a copy

- **GIVEN** an empty marker directory and session id `s1`
- **WHEN** the Bash input `bash /p/scripts/dropbox-fix.sh local-status ~/Dropbox/a` is given, then `cp -R ~/Dropbox/a /tmp/a`
- **THEN** both outputs are nothing

##### Example: slash command before a stuck prompt

- **GIVEN** an empty marker directory and session id `s1`
- **WHEN** the prompt `/mac-dropbox-fix:dropbox-fix` is given, then `Dropbox 卡住了`
- **THEN** both outputs are nothing

---
### Requirement: only decoded prompt, command and cwd fields are matched

Matching SHALL use the decoded `prompt` field in prompt mode, and the decoded `tool_input.command` and `cwd` fields in bash mode. Text in `transcript_path`, `tool_input.description` or any other field SHALL NOT cause output. In prompt mode the `cwd` field SHALL NOT cause output.

#### Scenario: Dropbox appears only in the description

- **WHEN** a Bash input has command `cp a.txt b.txt`, a home-directory cwd and a description that mentions copying from Dropbox
- **THEN** stdout is empty

##### Example: fields that do not count

| Mode | Field carrying the Dropbox text | Other fields | Output |
| --- | --- | --- | --- |
| bash | `tool_input.description` is `cp files from ~/Dropbox` | command `cp a.txt b.txt`, cwd home | nothing |
| bash | `transcript_path` contains `Library-CloudStorage-Dropbox` | command `cp a.txt b.txt`, cwd home | nothing |
| prompt | `cwd` is inside the Dropbox folder | prompt `build 卡住了` | nothing |
| prompt | prompt written with `\u` escapes for `Dropbox 沒同步` | cwd home | hint |

---
### Requirement: input without the word dropbox starts no second process

When the raw input does not contain `dropbox` in any letter case, the script SHALL exit 0 without running `osascript`. In bash mode it SHALL also exit without running `osascript` when the raw input contains none of the listed verbs and does not contain `dropbox-fix.sh`.

#### Scenario: an ordinary command

- **WHEN** the Bash input is `git status` in a home-directory cwd
- **THEN** `osascript` is not run and stdout is empty

##### Example: osascript invocations counted by a stub

| Mode | Input | osascript runs |
| --- | --- | --- |
| bash | command `git status`, cwd home | 0 |
| bash | command `ls`, cwd inside the Dropbox folder | 0 |
| prompt | prompt `hello` , cwd home | 0 |
| bash | command `cp ~/Dropbox/a /tmp/a`, cwd home | 1 |

---
### Requirement: the hook configuration is bounded and points at the plugin's script

`plugin/hooks/hooks.json` SHALL be valid JSON declaring exactly the events `UserPromptSubmit` and `PreToolUse`. The `PreToolUse` entry SHALL have the matcher `Bash`. Every hook entry SHALL be of type `command`, SHALL reference `${CLAUDE_PLUGIN_ROOT}/scripts/skill-hint.sh`, and SHALL set `timeout` to 10.

#### Scenario: the configuration file is read

- **WHEN** `plugin/hooks/hooks.json` is parsed
- **THEN** it holds two events, one hook each, each with a timeout of 10 seconds

##### Example: hooks.json contents

| Event | Matcher | Command ends with | timeout |
| --- | --- | --- | --- |
| UserPromptSubmit | (none) | `skill-hint.sh" prompt` | 10 |
| PreToolUse | Bash | `skill-hint.sh" bash` | 10 |

---
### Requirement: the plugin states that it runs hooks

`README.md` SHALL contain a section that names both hook events, says the script runs on every prompt and every Bash command, and says a Bash command is refused at most once per session. The `description` in `plugin/.claude-plugin/plugin.json` SHALL mention the hooks. The verification tables in `README.md` and in both skill files SHALL each contain a row for the hooks that states whether a real Claude Code run was done.

#### Scenario: a reader looks for what the plugin does on its own

- **WHEN** `README.md` is searched for `UserPromptSubmit` and `PreToolUse`
- **THEN** both are found in one section that also states the once-per-session limit

##### Example: disclosure strings

| File | Required text |
| --- | --- |
| README.md | `UserPromptSubmit`, `PreToolUse`, and the wording for once per session |
| plugin/.claude-plugin/plugin.json description | `hook` |
| plugin/skills/dropbox-fix/SKILL.md verification table | a row containing `hook` |
| plugin/skills/dropbox-use/SKILL.md verification table | a row containing `hook` |
