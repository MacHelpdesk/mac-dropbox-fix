## Why

Claude Code sessions that work inside a Dropbox folder on macOS keep running into File Provider details that nothing in this plugin covers: online-only files report their full size, this macOS's `fileproviderctl` has no download command, and a plain copy carries Dropbox's internal extended attributes. Issue #2 records one such session (117 online-only files, about 18 minutes to download) and asks for a reusable way to check whether files are local and to download them before acting on them.

## What Changes

- New read-only subcommand `dropbox-fix.sh local-status PATH`: prints how many files under PATH exist, how many are online-only, their total size, and the free disk space, one `key=value` per line like `probe`.
- New subcommand `dropbox-fix.sh download PATH`: reads every online-only file under PATH so that File Provider downloads it, refuses to start when free space is smaller than the online-only total, bounds each read with a timeout, and lists the files that are still online-only when it gives up.
- Both subcommands accept only paths inside a Dropbox folder under the user's CloudStorage directory.
- New skill `dropbox-use`: when Claude is about to work with files in a Dropbox folder, it checks with `local-status`, asks before every `download`, explains that downloaded files can be evicted again and how the user marks them available offline in Finder, and gives copying guidance whose verification status is stated.
- README and CLAUDE.md: the plugin's stated scope widens from "Dropbox is not syncing" to also cover using files in a Dropbox folder; CHANGELOG gains a 0.2.0 section; the plugin manifest moves to 0.2.0 with an updated description and keywords.
- The marketplace entry in the MacHelpdesk/mac-helpdesk repository carries the same description as the plugin manifest and is updated in that repository.

## Capabilities

### New Capabilities

- `dropbox-local-files`: the `local-status` and `download` subcommands of `dropbox-fix.sh`: output, exit codes, path scope, free-space check and per-file timeout.
- `dropbox-use-skill`: the `dropbox-use` skill's closed lists of what it does directly, what it asks first, what only the user does, and what it never does.

### Modified Capabilities

(none)

## Impact

- Affected code: plugin/scripts/dropbox-fix.sh (two new subcommands, usage text in the header).
- New files: plugin/skills/dropbox-use/SKILL.md, tests/test_local.sh.
- Affected docs and manifest: README.md, CLAUDE.md, CHANGELOG.md, plugin/.claude-plugin/plugin.json.
- Other repository: MacHelpdesk/mac-helpdesk, .claude-plugin/marketplace.json and README.md (description sync).
- No change to the existing `probe`, `match`, `list`, `show`, `validate` and `restart-fileproviderd` behavior, and no change to the knowledge base.
