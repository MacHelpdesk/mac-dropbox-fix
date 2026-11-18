<!-- SPECTRA:START v1.3.0 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `docs/spectra/specs/`, change proposals in `docs/spectra/changes/`.

## Skills

Each `/spectra-*` skill carries its own trigger description; these are the groups:

- Shape and plan → `/spectra-discuss`, `/spectra-propose`
- Continue tasks for an identified change → `/spectra-apply`
- Update requirements or plans for an identified change → `/spectra-ingest`
- Quality gate → `/spectra-verify`, `/spectra-review`, `/spectra-analyze`, `/spectra-audit`, `/spectra-drift`, `/spectra-debug`
- Finish → `/spectra-archive`, `/spectra-commit`

Explicit skill invocation takes precedence. Apply existing authorization within its unchanged scope.

## Workflow

discuss? → propose → apply ⇄ ingest → verify / review → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `docs/spectra/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `/spectra-apply` and `/spectra-ingest` skills disclose parking and restore when the named operation is already explicitly requested; respect a known refusal, otherwise ask for missing authorization.

<!-- SPECTRA:END -->

# mac-dropbox-fix — CLAUDE.md

## Purpose

Dropbox 在 Mac 上不同步時的量測與修復，以及在 Dropbox 資料夾裡動檔案之前確認檔案在不在本機。五個部分：兩個 skill（`dropbox-fix`、`dropbox-use`）、一份已知問題的知識庫（JSON）、一支量測、比對、檢查與下載的腳本、兩個在用得上時告訴 Claude 有這些 skill 的 hook（每則訊息與每個 Bash 指令都會啟動 hook 的腳本）。

與 [`mac-printer-setup`](https://github.com/MacHelpdesk/mac-printer-setup) 同一個系列：先量測，再判讀，最後才動手。

範圍是**封閉的，只有 Mac 上以 File Provider 運作的 Dropbox，而且只有兩件事**：不同步時的量測與處理；整理、複製、搬移 Dropbox 資料夾裡的檔案之前，確認檔案在不在這台 Mac 上並在使用者同意時下載。Dropbox 帳號、空間額度、分享、選擇性同步的設定、Dropbox 的網頁與 API、其他雲端服務都不涵蓋，遇到就說明沒涵蓋，不依性質相似類推。

## Skills

| Skill | 用途 |
|-------|------|
| `/mac-dropbox-fix:dropbox-fix` | 量測 → 對照知識庫 → 向使用者說明 → 依界線處理 → 再量一次並記錄；也負責把新問題記進使用者自己的條目 |
| `/mac-dropbox-fix:dropbox-use` | 動檔案之前：`local-status` 量 → 要下載就先問 → `download` 並再量一次 → 說明複製方法的驗證狀態 |

兩個 skill 各有一套〈行為界線〉，不互相類推：`dropbox-fix` 的表不適用於 `dropbox-use`，反之亦然。

## Repo 結構

```
mac-dropbox-fix/
├── plugin/                    # 被安裝進 Claude Code 的部分
│   ├── .claude-plugin/plugin.json
│   ├── skills/dropbox-fix/SKILL.md
│   ├── skills/dropbox-use/SKILL.md
│   ├── data/problems.json     # 知識庫
│   ├── hooks/hooks.json       # 兩個 hook：UserPromptSubmit、PreToolUse(Bash)
│   └── scripts/dropbox-fix.sh、kb.js、skill-hint.sh、hint.js
├── tests/test_probe.sh、test_kb.sh、test_local.sh、test_skill_use.sh、test_hooks.sh、fixtures/
├── docs/spectra/              # Spectra 的規格與 change
├── scripts/                   # 開發用的檢查腳本，不會被安裝
└── README.md、CLAUDE.md、AGENTS.md、CHANGELOG.md、LICENSE
```

marketplace 索引在 [`MacHelpdesk/mac-helpdesk`](https://github.com/MacHelpdesk/mac-helpdesk)，用 `git-subdir` 來源指向這個 repo 的 `plugin/`。

## Scripts

| 腳本 | 用途 | 會不會改動東西 |
|---|---|---|
| `plugin/scripts/dropbox-fix.sh` `probe`／`match`／`list`／`show`／`validate` | 量測、比對、讀知識庫 | 不會 |
| `plugin/scripts/dropbox-fix.sh restart-fileproviderd` | 對目前使用者的 `fileproviderd` 送結束訊號，等新的出現 | 會：所有雲端資料夾短暫重連 |
| `plugin/scripts/dropbox-fix.sh local-status PATH` | Dropbox 資料夾裡的檔數、僅線上的檔數與大小、剩餘空間 | 不會 |
| `plugin/scripts/dropbox-fix.sh download PATH` | 逐檔讀取僅線上的檔，讓 Dropbox 下載 | 會：檔案下載到本機，用掉網路與磁碟；不修改、搬移或刪除檔案 |
| `plugin/scripts/kb.js` | 由 `dropbox-fix.sh` 呼叫，用 `osascript -l JavaScript` 讀 JSON | 不會 |
| `plugin/scripts/skill-hint.sh prompt`／`bash` | hook 的入口：從 stdin 讀 hook 的輸入，印出零個或一個 JSON 物件，結束碼一律是 0 | 會：在 plugin 的資料目錄寫空的記號檔；`bash` 模式每個 session 會讓一個指令被擋一次 |
| `plugin/scripts/hint.js` | 由 `skill-hint.sh` 呼叫，解讀 hook 的輸入並判斷；詞表、動詞、路徑的封閉列舉在檔案開頭 | 不會 |

測試用替身指令取代 `pgrep`、`fileproviderctl`、`kill`（`test_probe.sh`）與 `stat`、`df`、`dd`（`test_local.sh`），不碰真的 daemon 與 Dropbox：

```bash
bash tests/test_probe.sh
bash tests/test_kb.sh
bash tests/test_local.sh       # local-status、download
bash tests/test_skill_use.sh   # dropbox-use 的四張表與複製標籤
bash tests/test_hooks.sh       # hook 腳本、hooks.json、文件裡對 hook 的說明
```

## 紀律

- **隱私**：這是公開 repo。`fileproviderctl dump` 會印出 domain 的 UUID 與家目錄底下的路徑，這些都不寫進任何檔案。`tests/fixtures/` 的 dump 是手寫的合成檔，UUID 一律是全零，路徑沒有使用者名稱；不要把真實的 dump 貼進來再改。使用者的條目與紀錄只存在他自己的 `~/.config/mac-dropbox-fix/`。
- **只寫實測過的行為**：知識庫每筆條目與每個解法都有 `evidence`，只有三種值。只有真的做過、再量一次確認解決的才寫 `verified`，並寫上日期與版本。README、skill、CHANGELOG 各有一張「驗證到哪裡」的表，改了行為就三處一起改。
- **動作的界線寫在各 skill 的〈行為界線〉**，每個 skill 各有四張封閉列舉的表。知識庫解法的 `class` 只有 `direct`、`ask`、`user`，`kb.js` 的 `validate` 會擋其他值。
- **新增一個 `class` 是 `direct` 或 `ask` 的解法時**，同時改三處：`problems.json`、skill〈行為界線〉對應的那張表、README。只改 JSON，skill 的表會比 JSON 嚴，那個解法實際上不會被執行。
- **新增訊號時**，同時改四處：`dropbox-fix.sh` 的 `probe`、`problems.json` 的 `signals`、`tests/test_probe.sh`、README 的輸出範例。
- **`probe` 沒有回報的訊號，以及值是 `unknown` 的訊號，條件一律不成立**（`kb.js` 的 `holds`；指名要 `unknown` 的 `equals` 除外）。讀不到 domain 時不可以輸出猜測的值；寧可少一行。
- **不要解析 dump 裡會翻譯的文字**。結構性的字（`alive`、`unable to startup`、`needs-auth`、`SqliteErrorDomain 5`）與 `last-drop-reason` 的值不會跟著系統語言變（在繁體中文的系統上看到的是英文）；`NSError` 行裡的說明文字會，所以不解析。
- **結束 `fileproviderctl dump` 要明確 kill**。把它接到提早結束的讀取端，它不會跟著停（實測掛了兩分鐘以上）。`read_dump` 要直接呼叫，不可以放在 `$(...)` 裡：它設定的 `DUMP_PID` 要留在主 shell，中途被打斷時 `cleanup` 才結束得了那個 dump。暫存檔一律放在 `need_tmpd` 建的資料夾裡。
- **`dump_result` 先看有沒有讀到欄位，再看有沒有 Dropbox**。dump 印出 provider 標頭後卡住是 `timeout`，不是「沒有 domain」；這正是延伸卡死時的樣子。
- **`domain_count` 不算隱藏的預設 domain**。`Domains.plist` 最上層除了每個帳號一個鍵，還有一個 `NSFileProviderDomainDefaultIdentifier`；只連結一個帳號的 Mac 上有兩個鍵。合成的 plist 沒帶這個鍵時測試照樣會過，這個錯是實機跑出來的，所以 `tests/fixtures/domains_*.plist` 都帶著它。
- **每一行輸出都帶來源**（`shipped` 或 `local`）。skill 靠它決定確認指令能不能直接執行；新增會印出條目的子命令時要帶上。
- **腳本維持 bash 3.2 相容**（macOS 內建的 `/bin/bash`）：不用關聯陣列、不用 `local -n`。執行期不依賴 `jq`、`python3`、`timeout`，這些 macOS 都沒有內建或不保證存在；`python3` 只出現在 CI 與 `scripts/` 的開發用檢查。
- **`download` 的每一次讀取都有上限**。讀取在背景跑，`DROPBOX_FIX_READ_WAIT` 秒後 TERM，有上限地等，再 KILL；任何地方都不可以無限期 `wait` 一個讀取（真的佔位檔讀取卡在核心裡時，TERM 不一定馬上生效）。`read_one` 要直接呼叫，不可以放在 `$(...)` 裡：它設定的 `READ_PID` 要留在主 shell，`cleanup` 才結束得了它。
- **僅線上只看 `dataless` flag，不看大小**。佔位檔的 `st_size` 是完整大小。`find` 不加 `-L`；直接給的檔案路徑是 symlink 時拒絕。
- **`download` 印出的路徑要過 `relative`**：控制字元換成 `?`，否則檔名能在 stdout 多造一行 `key=value`。不要改用 `printf %q`，它會把中文檔名變成跳脫碼。
- **hook 任何失敗都放行，而且每個 session 最多擋一次**。`skill-hint.sh` 的結束碼一律是 0；先用 noclobber 建立記號檔，建立成功才印出擋下的 JSON。不要把這個順序倒過來，也不要加會讓它在失敗時擋下的路徑。**`skill-hint.sh` 不可以刪記號檔**（依時間清理也不行）：記號被刪，接回來的舊 session 就會被擋第二次。記號目錄只有兩個來源：`DROPBOX_FIX_HINT_DIR`（測試用）與 `CLAUDE_PLUGIN_DATA/hints`，都沒有就什麼都不印。`hooks.json` 的每個 hook 都要有 `timeout`（`PreToolUse` 的預設是 600 秒）。
- **hook 只比對解碼後的 `prompt`、`tool_input.command`、`cwd`**。原始輸入裡的 `transcript_path` 與 `description` 也可能含 Dropbox；`skill-hint.sh` 對原始輸入做的只是「要不要啟動 `osascript`」的粗篩；原始輸入裡有 `\u00` 加兩個十六進位數字時一律交給 `hint.js`，因為這種跳脫可以把粗篩要找的字藏起來；粗篩之前只用 bash 內建指令（不用 `cat`、`dirname`）。測試用的家目錄是固定的假字串，不可以改回暫存目錄底下的路徑（路徑裡剛好有動詞字樣時，計數的測試會失敗）。
- **改 `hint.js` 開頭的三個列舉（詞表、動詞、子命令）時**，同時改四處：規格 `skill-trigger-hooks`、`tests/test_hooks.sh`、README〈plugin 會自己做的事〉、CHANGELOG。擋下時的說明文字會影響模型載不載入 skill（實測過兩種寫法，結果不同），改了要用 `claude -p --plugin-dir plugin` 重跑。
- **`kb.js` 與 `hint.js` 跑在 JXA**：沒有 `console.log` 以外的標準輸出函式，輸出一律走檔案開頭的 `out`／`err`。語法維持 ES5，JXA 對較新的語法支援不一致。

## Git 流程

整個 MacHelpdesk 系列共用，正本在 [`mac-helpdesk` 的 CLAUDE.md](https://github.com/MacHelpdesk/mac-helpdesk/blob/main/CLAUDE.md)。這個 repo 的重點：

- `main` 永遠是可發布狀態。工作在短分支 `idd/<issue>-<slug>`，開 PR，squash merge。
- 發布是一個 PR 裡的三件事：bump `plugin.json` 的 version、更新 `CHANGELOG.md`、合併後在 `main` 打 tag `vX.Y.Z`。
- marketplace 索引追這個 repo 的 `main`，沒有釘版本。所以改了 `plugin/`（包含只改 `problems.json`）就要 bump 版本，CI 會檢查。
- CI（`.github/workflows/ci.yml`）跑六項：`/bin/bash -n`、測試、manifest 與知識庫是合法 JSON、知識庫通過 `validate`、`scripts/check-privacy.sh`、PR 上的 `scripts/check-version-bump.sh`。

## Development

- 每次改動都 bump `plugin/.claude-plugin/plugin.json` 的 version，並更新 `CHANGELOG.md`
- 改了 skill 的 description，同步 `README.md`，以及 `mac-helpdesk` 索引裡這個 plugin 的描述
- 本機測 plugin：`claude --plugin-dir plugin`；格式檢查：`claude plugin validate plugin`
- skill 內用 `${CLAUDE_PLUGIN_ROOT}/scripts/` 與 `${CLAUDE_PLUGIN_ROOT}/data/` 找腳本與知識庫
