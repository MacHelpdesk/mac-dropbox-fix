## Context

Second round of fixes for the hooks added in `idd-9-skill-trigger-hooks`. Five reviewers reproduced the same defect: the `dropbox-use` skill tells the model to resolve the script path first, the model stores it in a variable, and the hook then records the `dropbox-fix` marker whatever subcommand runs.

## Goals / Non-Goals

**Goals:**

- A session that ran `local-status` or `download`, in any of the forms the skill text leads to, is not refused at its copy step.

**Non-Goals:**

- Recognising every shell spelling. Quoted program names, a backslash before a verb, a glob after the Dropbox path, letter case of the path and `bash -c` around the script stay unrecognised and are listed in README.

## Decisions

### A variable run is matched within one command

When a command assigns a path ending in `dropbox-fix.sh` to a variable at a command position and later runs `$NAME`, `${NAME}` or either in double quotes at a command position, the subcommand after it decides the marker. An assignment with no such run records the `dropbox-fix` marker as before. Shell state does not carry between Bash tool calls, so one command is the whole scope.

### Three token forms for the script path

Double-quoted, single-quoted (both may contain spaces) or unquoted. `=` is not part of an unquoted token, so an assignment is no longer read as the program.

### Marker creation refuses any existing path

noclobber only refuses an existing regular file. The script checks for an existing path or symbolic link first and treats it as an existing marker.

### The escape exception is narrowed

Only `\u00` followed by two hexadecimal digits can hide an ASCII letter of the words the prefilter looks for. A literal backslash-u in a prompt or command (LaTeX, printf) is encoded as `\\u` and is followed by other characters, so it no longer starts `osascript`. The statement in the previous design that this exception costs nothing was wrong for such input.

### No program before the prefilter

The script directory comes from `$0` by parameter expansion and stdin is read with the `read` builtin, so an input that fails the prefilter starts nothing besides bash itself.

### Run counts

The refusal reason in its current wording has been run three times in real Claude Code sessions, and the model loaded `dropbox-use` each time. The previous design said once; the user-facing tables carry the current count.

## Implementation Contract

- `ownScript(command)` in `hint.js` returns `using-use`, `using-fix` or an empty string, following the two decisions above.
- `insideDropbox(cwd, home)` is true when `cwd` contains `Library/CloudStorage/Dropbox`, or is `home/Dropbox` or below it.
- `mark()` returns failure when the marker path exists in any form.
- Prefilter: `\u00` plus two hexadecimal digits passes; otherwise the rules of the previous change.
- Acceptance: `/bin/bash tests/test_hooks.sh` passes with the new Example rows; the other four test scripts, `scripts/check-privacy.sh` and `claude plugin validate plugin` pass; one real `claude -p --plugin-dir plugin` run of each scenario at the final code.
- Out of scope: `dropbox-fix.sh`, `kb.js`, `problems.json`, the CI workflow, the marketplace index, the wording of the two output texts.

## Risks / Trade-offs

- A command that runs the script and also copies from Dropbox on the same line is let through whole, as the spec states.
- Input written with `\u` escapes outside `\u00XX` for the words concerned cannot occur: those words are ASCII.
