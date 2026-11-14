## Purpose

The `dropbox-use` skill guides Claude when it works with files in a Dropbox folder on macOS: check whether they are local, ask before downloading, and say what is and is not verified about copying. Its action boundaries are closed lists, in the same form as the `dropbox-fix` skill.

## ADDED Requirements

### Requirement: the skill's action lists are closed and place each subcommand

`plugin/skills/dropbox-use/SKILL.md` SHALL contain four lists of actions in this order: done directly, asked first, done only by the user, never done. Each list SHALL state that it is closed. `dropbox-fix.sh local-status` SHALL appear only in the done-directly list and `dropbox-fix.sh download` SHALL appear only in the asked-first list.

#### Scenario: subcommands sit in their lists

- **WHEN** the skill file is read
- **THEN** `local-status` is listed under done directly, `download` under asked first, and neither appears in another list

##### Example: list membership

| Item | Expected list |
| --- | --- |
| `dropbox-fix.sh local-status` | done directly |
| `dropbox-fix.sh download` | asked first |
| Finder "Make Available Offline" | done only by the user |
| touching `nucleus.sqlite3` | never done |

### Requirement: asking before download states size, space and eviction

The asked-first entry for `download` SHALL tell Claude to state, before asking, the `online_only` and `online_only_bytes` values and the `free_bytes` value from `local-status`, and that downloaded files can later be made online-only again by the system.

#### Scenario: what is said before a download

- **WHEN** the skill's asked-first entry for `download` is read
- **THEN** it names `online_only`, `online_only_bytes` and `free_bytes` and mentions that downloaded files can be evicted again

##### Example: required mentions in the download entry

- **GIVEN** the asked-first entry for `download` in `plugin/skills/dropbox-use/SKILL.md`
- **WHEN** a test reads that entry
- **THEN** it finds the strings `online_only`, `online_only_bytes`, `free_bytes` and the skill's wording for eviction

### Requirement: the never list covers settings, database, eviction and scope

The never-done list SHALL contain exactly these four items: making files online-only, changing Dropbox settings, touching Dropbox's `nucleus.sqlite3`, and acting on paths outside a Dropbox folder under the user's CloudStorage directory.

#### Scenario: never list content

- **WHEN** the skill's never-done list is read
- **THEN** it has the four items and no other

##### Example: four never items

- **GIVEN** the never-done list in `plugin/skills/dropbox-use/SKILL.md`
- **WHEN** a test counts its entries and searches them
- **THEN** there are four entries and they mention online-only eviction, Dropbox settings, `nucleus.sqlite3`, and paths outside the Dropbox folder

### Requirement: copying guidance states its verification status

Every copying method the skill describes SHALL be followed by one of `verified`, `reported` or `unverified`, with the macOS and Dropbox versions for `verified`. The effect of copying Dropbox's internal extended attributes SHALL be marked `unverified` until the test-folder experiment is recorded.

#### Scenario: no unlabelled copying advice

- **WHEN** the skill's copying section is read
- **THEN** each method carries an evidence label

##### Example: copying section labels

- **GIVEN** the copying section of `plugin/skills/dropbox-use/SKILL.md` before the test-folder experiment
- **WHEN** a test reads each method line
- **THEN** every method line contains `verified`, `reported` or `unverified`, and the line about copying `com.dropbox.internal` contains `unverified`
