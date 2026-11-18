## Why

The first verify round of issue #9 found behaviour of the new hooks that breaks or is missing from the `skill-trigger-hooks` spec: a marker cleanup that lets a resumed session be refused a second time, Dropbox paths followed by a shell separator that are not recognised, a script name used as an ordinary argument that counts as running the skill, and input written with JSON escapes that never reaches the decoding stage.

## What Changes

- Marker files are never deleted by the hook script. The 14-day cleanup is removed.
- The marker directory is a closed list of two sources. Without either, the script prints nothing.
- A Dropbox path is recognised when it is followed by a shell separator. A verb is recognised after a quote, and after a path only when that path is absolute.
- Only a command that runs `dropbox-fix.sh`, or assigns its path to a variable, counts as a session using the skill.
- Raw input that contains a JSON `\u` escape always goes to the decoding stage.
- README states the cost inside a Dropbox working directory, the wider misjudgement cases, and that disabling the plugin also removes both skills. The manifest description says a script starts on every prompt and Bash command.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `skill-trigger-hooks`: path and verb recognition, what counts as using the skill, the prefilter for escaped input, marker lifetime and location, and the manifest disclosure.

## Impact

- Changed files: plugin/scripts/skill-hint.sh, plugin/scripts/hint.js, tests/test_hooks.sh, README.md, CLAUDE.md, CHANGELOG.md, plugin/.claude-plugin/plugin.json.
- No new files in the plugin. Version stays 0.3.0, which has not been released.
