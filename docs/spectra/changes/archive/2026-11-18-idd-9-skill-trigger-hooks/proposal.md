## Why

The plugin's two skills load only when the model reads their descriptions in the skill listing. On a machine with many skills installed, Claude Code drops descriptions from that listing and keeps only names, so the trigger conditions written in the descriptions never reach the model (issue #9). `dropbox-use` is hit hardest: its main trigger is Claude itself about to copy or move files in a Dropbox folder, a moment when nobody says the word Dropbox.

## What Changes

- The plugin ships hooks (`plugin/hooks/hooks.json`) and a hook script (`plugin/scripts/skill-hint.sh` with `plugin/scripts/hint.js`).
- A submitted prompt that mentions Dropbox together with a stuck or not-syncing term gets one piece of added context per session naming the skill `mac-dropbox-fix:dropbox-fix`.
- The first Bash command of a session that copies, moves or archives in a Dropbox folder is refused once, with a reason naming the skill `mac-dropbox-fix:dropbox-use`. The same session is never refused again.
- Every failure of the hook script lets the prompt or command through unchanged.
- README, CLAUDE.md, the plugin manifest description and CHANGELOG state that the plugin now runs a script on every prompt and every Bash command. Version becomes 0.3.0.

## Capabilities

### New Capabilities

- `skill-trigger-hooks`: when the plugin's hooks add context or refuse a command, how often, and what they do when anything goes wrong.

### Modified Capabilities

(none)

## Impact

- New files: plugin/hooks/hooks.json, plugin/scripts/skill-hint.sh, plugin/scripts/hint.js, tests/test_hooks.sh.
- Changed files: plugin/.claude-plugin/plugin.json, CHANGELOG.md, README.md, CLAUDE.md, the verification tables in plugin/skills/dropbox-fix/SKILL.md and plugin/skills/dropbox-use/SKILL.md.
- Every installer: one short script start per prompt and per Bash command; at most one refused Bash command per session.
- The marketplace index in MacHelpdesk/mac-helpdesk copies the manifest description and is updated separately (MacHelpdesk/mac-helpdesk#5).
