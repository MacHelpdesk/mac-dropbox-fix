# mac-dropbox-fix — CLAUDE.md

## Purpose

Dropbox 在 Mac 上不同步時的量測與修復。三個部分：一個 skill、一份已知問題的知識庫（JSON）、一支量測與比對的腳本。

與 [`mac-printer-setup`](https://github.com/MacHelpdesk/mac-printer-setup) 同一個系列：先量測，再判讀，最後才動手。

範圍是**封閉的，只有 Mac 上以 File Provider 運作的 Dropbox**。Dropbox 帳號、空間額度、分享、選擇性同步的設定、其他雲端服務都不涵蓋，遇到就說明沒涵蓋，不依性質相似類推。

## Skills

| Skill | 用途 |
|-------|------|
| `/mac-dropbox-fix:dropbox-fix` | 量測 → 對照知識庫 → 向使用者說明 → 依界線處理 → 再量一次並記錄；也負責把新問題記進使用者自己的條目 |

## Repo 結構

```
mac-dropbox-fix/
├── plugin/                    # 被安裝進 Claude Code 的部分
│   ├── .claude-plugin/plugin.json
│   ├── skills/dropbox-fix/SKILL.md
│   ├── data/problems.json     # 知識庫
│   └── scripts/dropbox-fix.sh、kb.js
├── tests/test_probe.sh、test_kb.sh、fixtures/
├── scripts/                   # 開發用的檢查腳本，不會被安裝
└── README.md、CLAUDE.md、CHANGELOG.md、LICENSE
```

marketplace 索引在 [`MacHelpdesk/mac-helpdesk`](https://github.com/MacHelpdesk/mac-helpdesk)，用 `git-subdir` 來源指向這個 repo 的 `plugin/`。

## Scripts

| 腳本 | 用途 | 會不會改動東西 |
|---|---|---|
| `plugin/scripts/dropbox-fix.sh` `probe`／`match`／`list`／`show`／`validate` | 量測、比對、讀知識庫 | 不會 |
| `plugin/scripts/dropbox-fix.sh restart-fileproviderd` | 對目前使用者的 `fileproviderd` 送結束訊號，等新的出現 | 會：所有雲端資料夾短暫重連 |
| `plugin/scripts/kb.js` | 由 `dropbox-fix.sh` 呼叫，用 `osascript -l JavaScript` 讀 JSON | 不會 |

測試用替身指令取代 `pgrep`、`fileproviderctl`、`kill`，不碰真的 daemon：

```bash
bash tests/test_probe.sh
bash tests/test_kb.sh
```

## 紀律

- **隱私**：這是公開 repo。`fileproviderctl dump` 會印出 domain 的 UUID 與家目錄底下的路徑，這些都不寫進任何檔案。`tests/fixtures/` 的 dump 是手寫的合成檔，UUID 一律是全零，路徑沒有使用者名稱；不要把真實的 dump 貼進來再改。使用者的條目與紀錄只存在他自己的 `~/.config/mac-dropbox-fix/`。
- **只寫實測過的行為**：知識庫每筆條目與每個解法都有 `evidence`，只有三種值。只有真的做過、再量一次確認解決的才寫 `verified`，並寫上日期與版本。README、skill、CHANGELOG 各有一張「驗證到哪裡」的表，改了行為就三處一起改。
- **動作的界線寫在 skill 的〈行為界線〉**，是四張封閉列舉的表。知識庫解法的 `class` 只有 `direct`、`ask`、`user`，`kb.js` 的 `validate` 會擋其他值。
- **新增一個 `class` 是 `direct` 或 `ask` 的解法時**，同時改三處：`problems.json`、skill〈行為界線〉對應的那張表、README。只改 JSON，skill 的表會比 JSON 嚴，那個解法實際上不會被執行。
- **新增訊號時**，同時改四處：`dropbox-fix.sh` 的 `probe`、`problems.json` 的 `signals`、`tests/test_probe.sh`、README 的輸出範例。
- **`probe` 沒有回報的訊號，以及值是 `unknown` 的訊號，條件一律不成立**（`kb.js` 的 `holds`；指名要 `unknown` 的 `equals` 除外）。讀不到 domain 時不可以輸出猜測的值；寧可少一行。
- **不要解析 dump 裡會翻譯的文字**。結構性的字（`alive`、`unable to startup`、`needs-auth`、`SqliteErrorDomain 5`）與 `last-drop-reason` 的值不會跟著系統語言變（在繁體中文的系統上看到的是英文）；`NSError` 行裡的說明文字會，所以不解析。
- **結束 `fileproviderctl dump` 要明確 kill**。把它接到提早結束的讀取端，它不會跟著停（實測掛了兩分鐘以上）。`read_dump` 要直接呼叫，不可以放在 `$(...)` 裡：它設定的 `DUMP_PID` 要留在主 shell，中途被打斷時 `cleanup` 才結束得了那個 dump。暫存檔一律放在 `need_tmpd` 建的資料夾裡。
- **`dump_result` 先看有沒有讀到欄位，再看有沒有 Dropbox**。dump 印出 provider 標頭後卡住是 `timeout`，不是「沒有 domain」；這正是延伸卡死時的樣子。
- **`domain_count` 不算隱藏的預設 domain**。`Domains.plist` 最上層除了每個帳號一個鍵，還有一個 `NSFileProviderDomainDefaultIdentifier`；只連結一個帳號的 Mac 上有兩個鍵。合成的 plist 沒帶這個鍵時測試照樣會過，這個錯是實機跑出來的，所以 `tests/fixtures/domains_*.plist` 都帶著它。
- **每一行輸出都帶來源**（`shipped` 或 `local`）。skill 靠它決定確認指令能不能直接執行；新增會印出條目的子命令時要帶上。
- **腳本維持 bash 3.2 相容**（macOS 內建的 `/bin/bash`）：不用關聯陣列、不用 `local -n`。執行期不依賴 `jq`、`python3`、`timeout`，這些 macOS 都沒有內建或不保證存在；`python3` 只出現在 CI 與 `scripts/` 的開發用檢查。
- **`kb.js` 跑在 JXA**：沒有 `console.log` 以外的標準輸出函式，輸出一律走檔案開頭的 `out`／`err`。語法維持 ES5，JXA 對較新的語法支援不一致。

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
