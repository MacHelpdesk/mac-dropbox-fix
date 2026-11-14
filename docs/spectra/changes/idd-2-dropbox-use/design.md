## Context

`dropbox-fix.sh` today has five read-only subcommands (`probe`, `match`, `list`, `show`, `validate`) and one that changes state (`restart-fileproviderd`). Output is one `key=value` per line for `probe`; exit codes follow a small convention: 0 success, 1 error, 2 "acted but did not reach the goal" (`restart-fileproviderd`), 3 "no match" (`match`), 64 usage. Whether a state-changing subcommand runs is decided by the skill, not by the script.

Issue #2 asks for a second skill for using files in a Dropbox folder. Evidence gathered on macOS 27.3 with Dropbox 280.3.5020 (recorded on the issue): online-only files carry the `dataless` file flag and still report their full `st_size`; `fileproviderctl` on this macOS has no download subcommand; reading a file's content makes File Provider download it (117 files, about 117 MB, about 18 minutes, one run); every file carries `com.dropbox.attrs` and `com.dropbox.internal`.

Decisions already made by the maintainer on the issue: put the skill in this plugin as `dropbox-use`; scope is Dropbox on macOS through File Provider only; implement checks and downloads as `dropbox-fix.sh` subcommands (approach B) named `local-status` and `download`; the skill always asks before `download`; the skill explains eviction and the Finder "Make Available Offline" step; extended-attribute behaviour is to be tested in a dedicated folder in the maintainer's own Dropbox.

## Goals / Non-Goals

**Goals:**

- A read-only way to tell how many files under a path are online-only and how large they are, without trusting `st_size`.
- A way to download every online-only file under a path that cannot hang forever, refuses when the disk is too small, and says which files are still online-only.
- A skill that tells Claude when to use these and what to say before downloading.

**Non-Goals:**

- Renaming the plugin or `dropbox-fix.sh`.
- Making files online-only again (eviction) or pinning them offline from the command line.
- Dropbox web or API operations, other cloud providers, iCloud.
- Changing the `dropbox-fix` skill, its tables, or the knowledge base.
- Performing copies or moves for the user: the skill gives guidance; the user's own task does the copying.

## Decisions

### Implement local-status and download as dropbox-fix.sh subcommands

The maintainer chose subcommands over shell lines embedded in the skill (decision comment on #2). Output format and exit codes then live in one place, and the existing stub-based tests can cover them. Alternative considered: one or two shell lines in SKILL.md — simpler, but the format would drift with each run and could not be tested.

### Name the subcommands local-status and download

Chosen by the maintainer in spectra-discuss. Plain verbs match `probe` and `show`; `materialize` (Apple's term) was rejected as unfamiliar; plain `status` was rejected because `probe` already reports sync status.

### Detect online-only files by the dataless file flag

`local-status` and `download` enumerate regular files with `find PATH -type f` and treat a file as online-only when `stat -f %Sf` lists `dataless`. `st_size` is never used to decide whether a file is local, because online-only files report their full size. Alternative considered: compare `st_size` with allocated blocks — rejected, compressed and sparse files break it.

### Download by reading each online-only file sequentially with a per-file timeout

Reading the content is the only download method found on macOS 27.3. Each file is read in the background and polled once a second, and after `DROPBOX_FIX_READ_WAIT` seconds it is sent TERM, the same pattern `read_dump` uses for `fileproviderctl dump`. Because a read blocked in the kernel on an online-only file may not end at once, the script then waits a bounded time for it, sends KILL if it is still running, and reports and moves on if even that does not end it; it never waits without a limit. A file whose read was stopped or failed is counted as still online-only. Files are read one at a time, in a stable sorted order.

Retries end on whichever comes first (confirmed by the maintainer on 2026-11-14, after the offline worst case of the first draft was worked out: 117 files × 300 seconds × 3 passes ≈ 29 hours):

- three passes have run;
- a pass made no file local, so another pass would repeat it;
- three reads in a row timed out, which is what an offline Mac looks like; the whole run stops at once and prints `stopped=timeouts`. With the default timeout an offline run ends after about 15 minutes. Alternative considered: four reads in parallel, as in the one measured run — faster but harder to time out and to test under the system `/bin/bash` 3.2; left for later if sequential reads prove too slow. The default for `DROPBOX_FIX_READ_WAIT` is an estimate (300 seconds); the measurement that would confirm it is the time a single large online-only file takes in the maintainer's test folder.

### Check free space before the first read

`download` sums `st_size` of the online-only files and compares it with the free space that `df -Pk` reports for the volume holding PATH (the Available column of its single data line, times 1024, so `free_bytes` is always a multiple of 1024). When free space is smaller, it reads nothing and exits 4. Confirmed by the maintainer on 2026-11-14.

### Accept only paths inside a Dropbox folder under CloudStorage

Both subcommands resolve PATH with physical paths (symlinks followed) and accept it only when it lies under `$HOME/Library/CloudStorage/` in a top-level folder whose name starts with `Dropbox`. Anything else exits 1 before any read. This keeps `download` from reading through arbitrary folders. `find` runs without `-L`, so a symlink inside the Dropbox folder is not followed out of it.

### The dropbox-use skill always asks before download

Chosen by the maintainer in spectra-discuss: no size threshold. The skill states, when asking, the number of online-only files, their total size, the free disk space, and that downloaded files can be evicted again. A single file that Claude simply reads is outside the skill: reading it downloads it anyway.

### Copying guidance carries its verification status

The skill tells the user that a plain `cp` copies Dropbox's internal attributes and that the effect is not yet verified; it shows the copy that preserves modification times and drops extended attributes (the method used in the session that produced #2) with its evidence status. The guidance is updated after the test-folder experiment; until then it is labelled unverified.

## Implementation Contract

**Behavior**

- `dropbox-fix.sh local-status PATH` prints, one per line and in this order: `files=<regular files under PATH>`, `online_only=<files with the dataless flag>`, `online_only_bytes=<sum of their st_size>`, `free_bytes=<free bytes on PATH's volume>`. It reads no file content and exits 0.
- `dropbox-fix.sh download PATH` first runs the same count. With no online-only files it prints `online_only=0` and exits 0 without reading. Otherwise it checks free space, then reads online-only files as described, then prints `stopped=timeouts` when the run ended on three consecutive timed-out reads, then `downloaded=<files no longer online-only>` and `still_online_only=<count>`, followed by one `online_only_file=<path relative to PATH>` line per file still online-only.
- Neither subcommand modifies, moves or deletes any file, and neither changes Dropbox settings or touches Dropbox's database.

**Interface / data shape**

- New subcommands in the `case` dispatch of `dropbox-fix.sh` and in the usage text at the top of the script.
- New environment override `DROPBOX_FIX_READ_WAIT` (seconds per file), alongside the existing `DROPBOX_FIX_*` overrides.

**Failure modes and exit codes** (confirmed by the maintainer on 2026-11-14)

| Exit | Meaning | Output |
| --- | --- | --- |
| 0 | `local-status` finished; or `download` left no online-only file | stdout as above |
| 1 | PATH missing, not a directory or file, or outside a Dropbox folder under CloudStorage | one line on stderr naming the reason |
| 2 | `download` ended its retries (three passes, a pass with no progress, or three consecutive timed-out reads) and some files are still online-only | stdout lists them |
| 4 | `download` refused: free space smaller than the online-only total | stderr states both numbers; nothing was read |
| 64 | no PATH given | usage text |

**Acceptance criteria**

- `bash tests/test_local.sh` passes; each test is tagged `spec-example: <capability> / <Example title>` and stubs `stat`, `df` and the per-file read on PATH, as `tests/test_probe.sh` stubs `pgrep`, `fileproviderctl` and `kill`.
- `/bin/bash -n` passes on every script; `scripts/check-privacy.sh` passes; `dropbox-fix.sh validate` still passes.
- The skill's table test confirms `local-status` is listed under "directly" and `download` under "ask first".
- A manual run on a test folder in the maintainer's Dropbox is recorded in README's verification table with the macOS and Dropbox versions.

**Scope boundaries**

- In scope: the two subcommands, `tests/test_local.sh`, `plugin/skills/dropbox-use/SKILL.md`, README, CLAUDE.md, CHANGELOG, the plugin manifest, and the marketplace description sync in MacHelpdesk/mac-helpdesk.
- Out of scope: everything listed under Non-Goals.

## Risks / Trade-offs

- [A large file needs longer than the per-file timeout on a slow connection] → `DROPBOX_FIX_READ_WAIT` is configurable; the file is reported, not silently skipped; the default is an estimate to be checked in the test folder.
- [Stubbed `stat` output differs from real File Provider flags] → the manual test-folder run checks the real flags; the verification table separates "stub tests pass" from "checked on a real Dropbox folder".
- [Downloaded files are evicted again by the system later] → the skill says so and gives the Finder "Make Available Offline" step; the script does not claim permanence.
- [Free space can shrink while downloading] → the precheck is a guard against the obvious case only; a mid-run failure shows up as files still online-only and exit 2.
- [Sequential reads are slower than the parallel run that was measured] → accepted for simplicity; revisit with measured timings.
- [A read blocked in the kernel ignores TERM] → bounded wait, then KILL, then report and move on; stub tests cannot show this, so the offline step of the real-folder check confirms that stopping a read of a real online-only file works.
- [Three consecutive timeouts can also come from three very large files on a slow but working connection, or from small files queued behind one large download: Dropbox downloaded one file at a time in the real-folder run, and four tiny files each waited 78 to 123 seconds behind a 200 MB file] → the run stops and lists them; a stopped read does not cancel Dropbox's download (the 200 MB file read in 1 second on the next pass), so running again, or raising `DROPBOX_FIX_READ_WAIT`, picks them up.

## Migration Plan

No data migration. The plugin manifest moves to 0.2.0 so that installed users receive the new skill and subcommands; the marketplace description is updated in the same release window. Rollback is reverting the commits; existing subcommands are untouched.

## Open Questions

None open. The maintainer confirmed on 2026-11-14 every recommendation that had been listed here: the `local-status` output keys and the `download` exit codes 0, 1, 2, 4, 64; refusing `download` when free space is smaller than the online-only total; what the skill states before `download` (file count, total size, free space, eviction); the four-item "never" list; and the 300-second default per-file timeout, which stays an estimate until the real-folder check measures it. The stop-after-three-consecutive-timeouts rule was added and confirmed the same day.
