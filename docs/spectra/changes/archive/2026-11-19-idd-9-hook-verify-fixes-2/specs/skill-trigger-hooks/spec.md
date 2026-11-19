## MODIFIED Requirements

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
| Dropbox 裡的不動產估價表幫我整理一下 | nothing |
| Dropbox 的同步數字一直不動 | hint |
| build 卡住了 | nothing |

### Requirement: the first batch file command in a Dropbox folder is refused once

`skill-hint.sh bash` SHALL print a `PreToolUse` JSON object with `permissionDecision` equal to `deny` and a `permissionDecisionReason` containing `mac-dropbox-fix:dropbox-use` when the decoded `tool_input.command` contains a verb from the closed list (`cp`, `mv`, `rsync`, `ditto`, `tar`, `zip`) at a command position and either the command or the `cwd` field points into a Dropbox folder. A command position is the start of the command, or directly after whitespace, `;`, `&`, `|`, `(`, a backquote or a quote; a verb directly preceded there by an absolute path also counts; the verb SHALL be followed by whitespace or the end of the command. Dropbox folder forms are a closed list: a path containing `Library/CloudStorage/Dropbox`, and `Dropbox` directly under the home directory written as `~/Dropbox`, `$HOME/Dropbox`, `${HOME}/Dropbox` or the expanded home path, each followed by `/`, whitespace, a quote, one of `;`, `)`, `|`, `&`, `<`, `>`, a backquote, or the end of the command. The `cwd` field points into a Dropbox folder when it contains `Library/CloudStorage/Dropbox` anywhere, or is `Dropbox` directly under the home directory or a path below it. For every other command it SHALL print nothing and exit 0.

#### Scenario: copy out of a Dropbox folder

- **WHEN** the command is a `cp` whose source lies under `Library/CloudStorage/Dropbox`
- **THEN** stdout is one JSON object refusing the call and naming `mac-dropbox-fix:dropbox-use`

##### Example: commands and decisions

| Command | cwd | Output |
| --- | --- | --- |
| cp -R ~/Library/CloudStorage/Dropbox/a /tmp/b | home | deny |
| mv ~/Dropbox/x ~/Dropbox/y | home | deny |
| tar czf /tmp/a.tgz notes | inside the Dropbox folder | deny |
| tar czf /tmp/a.tgz notes | `/Volumes/x/Library/CloudStorage/Dropbox/w` | deny |
| rsync -a "$HOME/Dropbox/a/" /tmp/a/ | home | deny |
| cd ~/Dropbox; tar czf /tmp/a.tgz notes | home | deny |
| (cd ~/Dropbox; zip -r /tmp/a.zip x) | home | deny |
| SRC=$HOME/Dropbox; cp -R $SRC /tmp/a | home | deny |
| bash -c "cp -R ~/Dropbox/a /tmp/a" | home | deny |
| /bin/cp -R ~/Dropbox/a /tmp/a | home | deny |
| ls ~/Library/CloudStorage/Dropbox | home | nothing |
| ls ~/Dropbox/tar | home | nothing |
| cp a.txt b.txt | home | nothing |
| scp ~/Dropbox/x host: | home | nothing |

### Requirement: each skill is announced at most once per session

The script SHALL create a marker file for the session and skill before printing a hint or a refusal, and SHALL print only when that creation succeeded in this run. A second matching input with the same `session_id` SHALL produce no output, however much time has passed. A different `session_id` SHALL be treated independently. The script SHALL NOT delete marker files. A marker path that already exists in any form, including a symbolic link, SHALL count as an existing marker.

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

##### Example: an old marker survives another session

- **GIVEN** a marker directory where session `s1` was refused once and its marker file is dated 2025-01-01
- **WHEN** a matching Bash input with session id `s2` is given, then one with session id `s1`
- **THEN** the outputs are deny, nothing, and the marker file of `s1` still exists

##### Example: marker path is a symbolic link

- **GIVEN** a marker directory in which `s1.use` is a symbolic link to `/dev/null`
- **WHEN** a matching Bash input with session id `s1` is given
- **THEN** the output is nothing

### Requirement: a session already using a skill is left alone

A Bash command that runs `dropbox-fix.sh` SHALL never be refused. Running means the script path is the program at the start of the command or directly after `;`, `&`, `|`, `(`, a backquote or a line break, optionally after environment assignments and one of `sh`, `bash`, `zsh`, `/bin/sh`, `/bin/bash`, `/bin/zsh`. The script path is written unquoted, or inside double or single quotes, where it MUST be allowed to contain spaces. Such a command SHALL record the marker of the skill it belongs to: `local-status` and `download` belong to `dropbox-use`, every other subcommand to `dropbox-fix`. A command that assigns a path ending in `dropbox-fix.sh` to a variable at the same positions SHALL NOT be refused. When the same command runs that variable (`$NAME`, `${NAME}`, or either inside double quotes) at one of those positions, the subcommand after it SHALL decide the marker as above; with no such run the command SHALL record the `dropbox-fix` marker. A command in which `dropbox-fix.sh` appears only as an argument of another program SHALL be treated like any other command. A prompt that starts with `/mac-dropbox-fix:dropbox-fix`, `/dropbox-fix`, `/mac-dropbox-fix:dropbox-use` or `/dropbox-use` SHALL record the matching marker and produce no output.

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

##### Example: script name as an argument

| First Bash input (session `s1`) | Its output | Then prompt `Dropbox 卡住了` |
| --- | --- | --- |
| tar -czf /tmp/b.tgz ~/Dropbox/dropbox-fix.sh ~/Dropbox/data | deny | hint |
| S=/p/scripts/dropbox-fix.sh; bash "$S" probe | nothing | nothing |
| cd /p && DROPBOX_FIX_READ_WAIT=5 /bin/bash scripts/dropbox-fix.sh probe | nothing | nothing |
| S=/p/scripts/dropbox-fix.sh; "$S" local-status ~/Dropbox/a | nothing | hint |

##### Example: variable run before a copy

| First Bash input (session `s1`) | Its output | Then `cp -R ~/Dropbox/a /tmp/a` |
| --- | --- | --- |
| S=/p/scripts/dropbox-fix.sh; "$S" local-status ~/Dropbox/a | nothing | nothing |
| S="${CLAUDE_PLUGIN_ROOT}/scripts/dropbox-fix.sh"; bash "$S" download ~/Dropbox/a | nothing | nothing |
| bash "/p/with space/scripts/dropbox-fix.sh" local-status ~/Dropbox/a | nothing | nothing |
| a comment line, a line break, then bash /p/scripts/dropbox-fix.sh local-status ~/Dropbox/a | nothing | nothing |
| S=/p/scripts/dropbox-fix.sh; "$S" probe | nothing | deny |

### Requirement: input without the word dropbox starts no second process

When the raw input contains neither `dropbox` in any letter case nor `\u00` followed by two hexadecimal digits, the script SHALL exit 0 without running `osascript` or any other program. In bash mode it SHALL also exit without running `osascript` when the raw input contains none of the listed verbs, does not contain `dropbox-fix.sh`, and does not contain `\u00` followed by two hexadecimal digits. The verbs are looked for in the whole raw input, not only in the command. The raw input includes the `cwd` and `transcript_path` fields, so a session whose working directory is inside a Dropbox folder reaches `osascript` on every prompt.

#### Scenario: an ordinary command

- **WHEN** the Bash input is `git status` in a home-directory cwd
- **THEN** `osascript` is not run and stdout is empty

##### Example: osascript invocations counted by a stub

| Mode | Input | osascript runs |
| --- | --- | --- |
| bash | command `git status`, cwd home | 0 |
| bash | command `ls`, cwd inside the Dropbox folder, description `list` | 0 |
| prompt | prompt `hello` , cwd home | 0 |
| prompt | prompt `fix the \usepackage line`, cwd home | 0 |
| prompt | prompt `hello`, cwd inside the Dropbox folder | 1 |
| bash | command `cp ~/Dropbox/a /tmp/a`, cwd home | 1 |

### Requirement: the plugin states that it runs hooks

`README.md` SHALL contain a section that names both hook events, says the script runs on every prompt and every Bash command, and says a Bash command is refused at most once per session. The `description` in `plugin/.claude-plugin/plugin.json` SHALL mention the hooks and say that a script starts on every prompt and every Bash command. `CLAUDE.md` and both skill files SHALL say that a script starts on every prompt and every Bash command. The verification tables in `README.md` and in both skill files SHALL each contain a row for the hooks that states whether a real Claude Code run was done.

#### Scenario: a reader looks for what the plugin does on its own

- **WHEN** `README.md` is searched for `UserPromptSubmit` and `PreToolUse`
- **THEN** both are found in one section that also states the once-per-session limit

##### Example: disclosure strings

| File | Required text |
| --- | --- |
| README.md | `UserPromptSubmit`, `PreToolUse`, and the wording for once per session |
| plugin/.claude-plugin/plugin.json description | `hook` and `每則訊息與每個 Bash 指令` |
| plugin/skills/dropbox-fix/SKILL.md verification table | a row containing `hook` |
| CLAUDE.md, plugin/skills/dropbox-fix/SKILL.md, plugin/skills/dropbox-use/SKILL.md | `每則訊息與每個 Bash 指令` |
| plugin/skills/dropbox-use/SKILL.md verification table | a row containing `hook` |
