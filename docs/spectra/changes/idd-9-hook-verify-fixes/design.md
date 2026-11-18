## Context

Change `idd-9-skill-trigger-hooks` added two hooks. Its verify round ran the script against inputs the spec's Examples did not cover and found four defects and several gaps between the documents and the code. This change corrects them before 0.3.0 is released.

## Goals / Non-Goals

**Goals:**

- A session is never refused twice, however long it lives.
- The recognition rules match what the spec states for the path and verb forms a shell command really uses.

**Non-Goals:**

- Parsing shell syntax. Recognition stays a set of regular expressions over the command text.
- Lowering the cost for sessions whose working directory is inside a Dropbox folder (issue #10 covers the `if` field).

## Decisions

### Markers are never deleted by the script

The once-per-session guarantee is the existence of the marker file. Any cleanup by age breaks it for a session resumed later. Markers are empty files, at most two per session, so they are left in place. Alternative considered: delete only markers older than a limit and document the limit as the lifetime of the guarantee. Rejected: it keeps a second refusal possible for no gain a user would notice.

### The marker directory has two sources

`DROPBOX_FIX_HINT_DIR` (used by the tests), else `$CLAUDE_PLUGIN_DATA/hints`. With neither, the script exits silently. The earlier fallback to a fixed name in the temporary directory could land in a shared directory when `TMPDIR` is unset.

### Running the script is a command-position match

A command counts as using the skill when `dropbox-fix.sh` is the program being run: at the start of the command or after `;`, `&`, `|`, `(` or a backquote, optionally after environment assignments and a shell name. Assigning its path to a variable at a command position also counts, because the skill text tells the model to refer to the script by a path it resolves first. A script name that is an argument of another program does not count.

### Verb and path boundaries

A verb counts at the start, after whitespace, a separator, an opening parenthesis, a backquote or a quote, optionally preceded by an absolute path (`/bin/cp`). A relative or `~` path segment named like a verb does not count. A Dropbox path form ends at `/`, whitespace, a quote, a shell separator (`;`, `)`, `|`, `&`, `<`, `>`, backquote) or the end of the command.

### Escaped input skips the prefilter

Raw input containing `\u` goes to stage two, because the words the prefilter looks for can be hidden in escapes. Claude Code does not escape ASCII, so this costs nothing in practice.

### The refusal reason keeps its last clause

The reason ends by saying to load the skill before moving a batch of files. The first wording, a pure statement, was run twice and the model resent the command both times without loading the skill; the current wording was run once and the model loaded the skill. The earlier contract line that both texts are statements no longer holds for the refusal reason; the prompt hint remains a statement. The risk that an instruction-like reason is ignored as injected text was not observed in that run.

## Implementation Contract

- `skill-hint.sh` contains no command that deletes a marker.
- Marker directory: `$DROPBOX_FIX_HINT_DIR`, else `$CLAUDE_PLUGIN_DATA/hints`, else exit 0 with no output.
- Prefilter passes input to `hint.js` when the raw text contains `dropbox` in any letter case (and, in bash mode, a listed verb or `dropbox-fix.sh`), or when it contains `\u`.
- `hint.js` recognition follows the two decisions above; lists stay at the top of the file.
- Acceptance: `/bin/bash tests/test_hooks.sh` passes with the new Example rows; the other four test scripts, `scripts/check-privacy.sh` and `claude plugin validate plugin` pass.
- Out of scope: `dropbox-fix.sh`, `kb.js`, `problems.json`, the CI workflow, the marketplace index, the wording of the two output texts.

## Risks / Trade-offs

- Marker files accumulate, two empty files per session at most. A user can delete the `hints` directory at any time; the only effect is that running sessions can be told once more.
- A command whose working directory is inside a Dropbox folder and that contains a listed verb is refused once even when it names no Dropbox path, for example `git mv`. README says so.
- An absolute path that ends in a segment named like a verb (`ls /x/Dropbox/tar`) still counts as a verb.
