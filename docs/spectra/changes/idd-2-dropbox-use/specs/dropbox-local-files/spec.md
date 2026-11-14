## Purpose

The `local-status` and `download` subcommands of `dropbox-fix.sh` tell whether files in a Dropbox folder on macOS are present on this Mac and download the ones that are online-only. They exist because online-only files report their full size and this macOS has no command-line download.

## ADDED Requirements

### Requirement: local-status reports online-only files by the dataless flag

`dropbox-fix.sh local-status PATH` SHALL count regular files under PATH, SHALL treat a file as online-only exactly when `stat -f %Sf` lists `dataless`, and SHALL print `files=`, `online_only=`, `online_only_bytes=` (sum of the online-only files' `st_size`) and `free_bytes=` (free space on PATH's volume as `df -Pk` reports it, converted to bytes, so a multiple of 1024), one per line in that order. It SHALL NOT read any file's content and SHALL exit 0.

#### Scenario: count online-only files without reading them

- **WHEN** `local-status` runs on a Dropbox folder that holds both local and online-only files
- **THEN** it prints the four lines, exits 0, and no file content is read

##### Example: two of three files online-only

- **GIVEN** a Dropbox folder holding `a.pdf` (1000 bytes, flags `compressed,dataless`), `sub/b.docx` (500 bytes, flags `dataless`) and `c.txt` (20 bytes, no flags), and 5000 KB available as reported by `df -Pk`
- **WHEN** `dropbox-fix.sh local-status <folder>` runs
- **THEN** stdout is `files=3`, `online_only=2`, `online_only_bytes=1500`, `free_bytes=5120000`, the exit code is 0, and the stubbed read records no calls

### Requirement: both subcommands accept only paths inside a Dropbox folder under CloudStorage

`local-status` and `download` SHALL resolve PATH to a physical path and SHALL accept it only when it lies under `$HOME/Library/CloudStorage/` inside a top-level folder whose name starts with `Dropbox`. Otherwise they SHALL print one reason line on stderr, read nothing, and exit 1.

#### Scenario: path outside Dropbox is refused before any read

- **WHEN** PATH does not resolve into a Dropbox folder under CloudStorage
- **THEN** the subcommand exits 1, prints the reason on stderr, and reads no file

##### Example: path scope cases

| PATH given | Exit | Notes |
| --- | --- | --- |
| `$HOME/Library/CloudStorage/Dropbox/work` | 0 | inside the Dropbox folder |
| `$HOME/Library/CloudStorage/Dropbox-Personal/work` | 0 | folder name starts with Dropbox |
| `$HOME/Documents/work` | 1 | not under CloudStorage |
| `$HOME/Library/CloudStorage/GoogleDrive-x/work` | 1 | another provider |
| `$HOME/Library/CloudStorage/Dropbox/link-out` where `link-out` is a symlink to `$HOME/Documents` | 1 | resolved physically, lands outside |
| `$HOME/Library/CloudStorage/Dropbox/missing` | 1 | does not exist |

### Requirement: download reads online-only files until none remain

`dropbox-fix.sh download PATH` SHALL read the content of every online-only file under PATH, one file at a time, and SHALL re-check the `dataless` flag after each pass. When no online-only file remains it SHALL print `downloaded=<count>` and `still_online_only=0` and exit 0. When PATH holds no online-only file it SHALL print `online_only=0`, read nothing, and exit 0.

#### Scenario: all online-only files become local

- **WHEN** `download` runs and every read makes its file local
- **THEN** it reports the number downloaded, reports zero still online-only, and exits 0

##### Example: two files downloaded in the first pass

- **GIVEN** a Dropbox folder with `a.pdf` and `sub/b.docx` online-only and `c.txt` local, where reading a file clears its `dataless` flag
- **WHEN** `dropbox-fix.sh download <folder>` runs
- **THEN** exactly `a.pdf` and `sub/b.docx` are read once each, stdout contains `downloaded=2` and `still_online_only=0`, and the exit code is 0

##### Example: nothing to download

- **GIVEN** a Dropbox folder whose files are all local
- **WHEN** `dropbox-fix.sh download <folder>` runs
- **THEN** stdout contains `online_only=0`, no file is read, and the exit code is 0

### Requirement: download reports files still online-only when its retries end

`download` SHALL start another pass over the files still online-only only while fewer than three passes have run and the previous pass made at least one file local. When its retries end with files still online-only, it SHALL print `downloaded=<count>`, `still_online_only=<count>` and one `online_only_file=<path relative to PATH>` line per remaining file, and SHALL exit 2. In each printed path, every control character (bytes 0x01 to 0x1F and 0x7F) SHALL be replaced by `?`, so a file name cannot add lines to the output; other characters, including non-ASCII names, SHALL be printed unchanged.

#### Scenario: a file never becomes local

- **WHEN** reading a file does not clear its `dataless` flag
- **THEN** that file is read again only after a pass that made another file local, then listed, and the exit code is 2

##### Example: one stubborn file among two

- **GIVEN** `a.pdf` becomes local when read and `sub/big.pptx` stays `dataless` whatever happens
- **WHEN** `dropbox-fix.sh download <folder>` runs
- **THEN** `sub/big.pptx` is read twice (the first pass made `a.pdf` local, the second made nothing local), stdout contains `downloaded=1`, `still_online_only=1` and `online_only_file=sub/big.pptx`, and the exit code is 2

##### Example: a file name with a newline stays on one line

- **GIVEN** an online-only file that never becomes local, named `evil`, a newline, then `stopped=timeouts.pdf`, and an online-only file `報告.pdf` that never becomes local
- **WHEN** `dropbox-fix.sh download <folder>` runs
- **THEN** stdout contains `online_only_file=evil?stopped=timeouts.pdf` and `online_only_file=報告.pdf`, no line of stdout is `stopped=timeouts`, and the exit code is 2

### Requirement: download refuses when free space is smaller than the online-only total

Before its first read, `download` SHALL compare the online-only total (`st_size` sum) with the free space on PATH's volume. When free space is smaller it SHALL print both numbers on stderr, read nothing, and exit 4.

#### Scenario: not enough disk space

- **WHEN** free space is smaller than the online-only total
- **THEN** no file is read and the exit code is 4

##### Example: 1024 bytes free for 1500 bytes needed

- **GIVEN** online-only files totalling 1500 bytes and 1 KB available as reported by `df -Pk`
- **WHEN** `dropbox-fix.sh download <folder>` runs
- **THEN** stderr names 1024 and 1500, the stubbed read records no calls, and the exit code is 4

### Requirement: each download read is bounded by a timeout

`download` SHALL stop a read that has not finished after `DROPBOX_FIX_READ_WAIT` seconds (TERM, then KILL after a bounded wait), SHALL count that file as still online-only for this pass, and SHALL continue with the next file unless the stop rule for consecutive timeouts applies.

#### Scenario: a read hangs

- **WHEN** a read does not finish within `DROPBOX_FIX_READ_WAIT` seconds
- **THEN** that read is stopped and the remaining files are still processed

##### Example: hanging read stopped after two seconds

- **GIVEN** `DROPBOX_FIX_READ_WAIT=2`, `hang.pdf` whose read never returns, and `a.pdf` that becomes local when read
- **WHEN** `dropbox-fix.sh download <folder>` runs
- **THEN** each read of `hang.pdf` is stopped after about two seconds, `a.pdf` is downloaded, stdout contains `online_only_file=hang.pdf`, no read process is left running, and the exit code is 2

### Requirement: download stops after three consecutive timed-out reads

When three reads in a row time out, `download` SHALL stop the whole run without reading further files, SHALL print `stopped=timeouts` before the counts, SHALL list every file still online-only, and SHALL exit 2. A read that finishes resets the count.

#### Scenario: an offline Mac

- **WHEN** every read times out
- **THEN** the run ends after the third timed-out read and the exit code is 2

##### Example: offline run stops after three timeouts

- **GIVEN** `DROPBOX_FIX_READ_WAIT=1` and five online-only files `c1.pdf` to `c5.pdf` whose reads never return
- **WHEN** `dropbox-fix.sh download <folder>` runs
- **THEN** exactly three reads are started, stdout contains `stopped=timeouts`, `downloaded=0`, `still_online_only=5` and five `online_only_file=` lines, no read process is left running, and the exit code is 2

### Requirement: missing PATH is a usage error

`local-status` and `download` without a PATH argument SHALL print the usage text on stderr and exit 64.

#### Scenario: no argument

- **WHEN** either subcommand is called without PATH
- **THEN** it exits 64

##### Example: download with no argument

- **GIVEN** no PATH argument
- **WHEN** `dropbox-fix.sh download` runs
- **THEN** the usage text is printed on stderr and the exit code is 64
