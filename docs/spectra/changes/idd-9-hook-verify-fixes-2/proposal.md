## Why

The second verify round of issue #9 found that running the plugin's script through a variable records the wrong marker, so a session that is following `dropbox-use` is still refused at its copy step. It also found smaller gaps: a quoted script path with a space, a script run on a later line, an existing marker path that is not a regular file, a working directory check narrower than the spec, a stuck term that matches an unrelated word, and a prefilter exception wider than it needs to be.

## What Changes

- A script run through a variable assigned in the same command records the marker of the subcommand it runs.
- A quoted script path may contain spaces. A line break is a command position for the script.
- An existing marker path of any kind counts as an existing marker.
- A working directory whose path contains `Library/CloudStorage/Dropbox` counts, wherever it lies.
- The stuck term for "not moving" no longer matches the word for real estate.
- Only input containing `\u00` followed by two hexadecimal digits skips the prefilter. The script starts no other program before the prefilter.
- CLAUDE.md and both skill files say that a script starts on every prompt and every Bash command.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `skill-trigger-hooks`: what counts as running the script, marker creation, the working directory form, one stuck term, and the prefilter exception.

## Impact

- Changed files: plugin/scripts/skill-hint.sh, plugin/scripts/hint.js, tests/test_hooks.sh, README.md, CLAUDE.md, CHANGELOG.md, both SKILL.md files.
- Version stays 0.3.0, which has not been released.
