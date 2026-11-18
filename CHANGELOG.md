# Changelog

## 0.3.0 — 2026-11-18

plugin 帶兩個 hook，在用得上 skill 的時候告訴 Claude（#9）。裝了很多 skill 的機器上，skill 清單只剩名稱，兩個 skill 幾乎不會自己被載入。

### Hook

- `UserPromptSubmit`：訊息提到 Dropbox，而且有「卡住、不同步」這一類的詞時，隨訊息附上 `mac-dropbox-fix:dropbox-fix` 的說明。
- `PreToolUse`（Bash）：指令用到 `cp`、`mv`、`rsync`、`ditto`、`tar`、`zip`，而且指令或工作目錄指向 Dropbox 資料夾時，這個指令這一次不執行，改把 `mac-dropbox-fix:dropbox-use` 的說明回給 Claude。
- 兩者在每個 session 最多各動作一次；指令重送就照常執行。
- 任何失敗都放行：結束碼一律是 0，每個 hook 的 `timeout` 是 10 秒。
- 指令是 plugin 自己的 `dropbox-fix.sh`，或訊息是 `/mac-dropbox-fix:…` 開頭時，不擋、不附說明。
- 成本：每則訊息與每個 Bash 指令啟動一次腳本，交給 hook 的資料裡沒有 `dropbox` 字樣時約 6 ms 就結束（macOS 27.3 實測）。在 Dropbox 資料夾裡開的 session，每則訊息都會多走 `osascript` 那一步，約 52 ms。
- 記號檔放在 Claude Code 給 plugin 的資料目錄底下的 `hints/`，hook 不會刪它；沒有那個目錄時 hook 什麼都不做。
- 認得的寫法：動詞在命令位置（開頭，或空白、`;`、`&`、`|`、`(`、反引號、引號之後，前面可以有絕對路徑）；Dropbox 路徑後面接 `/`、空白、引號、`;`、`)`、`|`、`&`、`<`、`>`、反引號或結尾。

### Scripts

- 新增 `plugin/scripts/skill-hint.sh`（hook 的入口）與 `plugin/scripts/hint.js`（解讀輸入並判斷）。只比對解碼後的 `prompt`、`tool_input.command`、`cwd`。
- 新增 `plugin/hooks/hooks.json`。
- `dropbox-fix.sh`、`kb.js`、知識庫不變。

### 實測範圍

Claude Code 2.1.327、macOS 27.3，`claude -p --plugin-dir plugin`，模型是 Sonnet（2026-11-18）。

- 已實測：`UserPromptSubmit` 的說明送到模型（1 次）。`PreToolUse` 在指令執行前擋下，同一個 session 重送照常執行（4 次）。
- 已實測，次數很少：擋下時的說明文字試過兩種寫法。第一種寫明「再送一次就會照常執行」，2 次中模型都直接重送、沒有載入 skill；現在的寫法寫明「動一批檔案之前先載入它」，2 次中 2 次先載入 `dropbox-use` 再跑 `local-status`（備份整個資料夾、複製單一路徑各 1 次）。hook 不保證模型一定載入。
- 只在測試裡驗過：判斷規則（`tests/test_hooks.sh` 68 項）。
- 未驗證：從 marketplace 安裝後的 hook、subagent 裡的 hook、工作目錄在 Dropbox 資料夾裡的實際 session、其他模型。

## 0.2.0 — 2026-11-14

在 Dropbox 資料夾裡動檔案之前，先確認檔案在不在這台 Mac 上（#2）。

### Skill

- 新增 `dropbox-use`：整理、複製、搬移 Dropbox 資料夾裡的一批檔案之前，先用 `local-status` 量；有僅線上的檔案時，說明檔數、大小、剩餘空間與「下載後仍可能被回收」，使用者同意才 `download`。行為界線是四張封閉列舉的表；複製方法逐項標驗證狀態。
- `dropbox-fix` 不變。

### Scripts

- `dropbox-fix.sh local-status PATH`：只讀。印出 `files`、`online_only`、`online_only_bytes`、`free_bytes`；以 `dataless` flag 判斷僅線上，不看大小。
- `dropbox-fix.sh download PATH`：逐檔讀取，讓 File Provider 下載。剩餘空間不夠時一個檔都不讀（結束碼 4）；每檔讀取上限 `DROPBOX_FIX_READ_WAIT` 秒（預設 300），逾時先 TERM、有上限地等，再 KILL；上一輪有檔案下載成功才重試，最多三輪；連續三次逾時就停（`stopped=timeouts`）；仍僅線上的檔逐一列出（結束碼 2）；每讀一個檔在 stderr 印進度。
- 兩個子命令都只接受 `~/Library/CloudStorage` 底下 Dropbox 資料夾裡的路徑。
- 印出的路徑裡，控制字元換成 `?`，檔名不能在輸出裡多造一行（提交後的安全審查抓到的）。
- 用法說明改成印到檔頭清單結束為止，不再寫死行號。

### 實測範圍

macOS 27.3、Dropbox 280.3.5020，維護者 Dropbox 裡的測試資料夾（2026-11-14）。

- 已實測：`local-status` 在設為僅供線上存取的 5 個檔上量到 `online_only=5`；`download` 下載 5 個檔、200 MB，712 秒，結束碼 0，沒有留下讀取程序。200 MB 的檔第一輪讀到 300 秒被停掉，第二輪 1 秒就讀完；同一輪裡四個小檔各花 78 到 123 秒。連線狀態下停掉真的讀取，看過兩次（之後沒有殘留的讀取程序）。
- 已實測：`cp -p` 的副本一開始帶著原檔的 `com.dropbox.attrs`，90 秒內 Dropbox 換上它自己的，沒有出現衝突的複本；`cp -pX` 的副本同樣拿到自己的屬性。副本有沒有出現在 dropbox.com 沒在網頁上核對。
- 已觀察：檔案「設為僅供線上存取」再下載之後，Finder 顏色標記消失（一次）。Finder 右鍵選單的文字是「設為離線存取」「設為僅供線上存取」（繁體中文介面）。
- 只在測試裡驗過：`local-status` 與 `download` 的輸出、結束碼、空間檢查、逾時、重試與停止規則（`tests/test_local.sh` 92 項）；skill 的四張表與複製標籤（`tests/test_skill_use.sh` 27 項）。
- 未驗證：離線時 `download` 停得下來、真的讀取停得掉；「設為離線存取」之後檔案還會不會被回收；英文介面的選單文字；其他 macOS 與 Dropbox 版本。

## 0.1.0 — 2026-11-13

第一版。

### Skill

- `dropbox-fix`：Dropbox 不同步時，量測 Dropbox 與 File Provider 的狀態，對照知識庫，向使用者說明後依界線處理，再量一次並記錄。

### 知識庫

`plugin/data/problems.json`，六筆：

- `fileprovider-domain-startup-locked`（verified）
- `spotlight-reindex-after-unclean-shutdown`（verified；說明 fileproviderd 為什麼忙，不是同步狀態的判斷）
- `stray-sqlite3-on-nucleus`（reported）
- `fileprovider-xpc-deadlock`、`sync-anchor-dropped`（reported；兩筆都是線索，要另外確認）
- `dropbox-app-not-running`（unverified）

使用者自己的條目放 `~/.config/mac-dropbox-fix/problems.local.json`。

### Scripts

- `dropbox-fix.sh`：`probe`、`match`、`list`、`show`、`validate` 只讀；`restart-fileproviderd` 對目前使用者的 `fileproviderd` 送結束訊號。
- `kb.js`：用 macOS 內建的 JavaScript 讀知識庫、檢查封閉列舉、比對訊號。

### 實測範圍

macOS 27.3、Dropbox 280.3.5012，一次 kernel panic 重開後的事故（2026-11-13）。

- 已實測：`probe` 對啟動失敗與正常兩種狀態的判讀；dump 有上百萬行時提早結束；對 `fileproviderd` 送結束訊號後同步恢復（手動送訊號，一次）；`launchctl kickstart -k` 被 SIP 擋下；待索引數隨時間下降。
- 已實測：以 `claude --plugin-dir plugin` 載入時 skill 以 `mac-dropbox-fix:dropbox-fix` 出現。
- 只在測試裡驗過：`restart-fileproviderd` 子命令、其餘訊號的判讀、知識庫與個人條目的檢查（`tests/test_probe.sh` 84 項、`tests/test_kb.sh` 43 項）。
- 來自更早的事故紀錄、沒有重新做過：結束殘留的 sqlite3、解除帳號連結重新登入。
- 未驗證：`open -a Dropbox`；其他 macOS 與 Dropbox 版本；透過 marketplace 安裝；GitHub 的 macOS 執行機上的 `osascript -l JavaScript`。
- 不支援：連結兩個 Dropbox 帳號的 Mac（`probe` 只回報有幾個 domain）。

### 發布前的獨立審查

一位沒有參與撰寫的審查者對照腳本、知識庫與文件，回報 2 個阻擋級、5 個該修，以及若干小問題、文件與程式不符、測試缺口。這一版都改了：

- dump 印出 provider 標頭後卡住，原本被回報成「沒有 domain」。那正是延伸卡死時的樣子。現在沒有讀到欄位一律是 `timeout`；dump 指令出錯是新的 `failed`。
- 個人條目在輸出裡與內建條目沒有分別，agent 無從套用「個人條目的指令先問」。現在 `match`、`list`、`show` 都標來源，skill 的規則也涵蓋確認用的指令。
- `probe` 被打斷時會留下還在跑的 dump 與暫存檔。現在 dump 的程序編號留在主 shell，暫存檔都在同一個資料夾。
- `not_equals` 會比對到值是 `unknown` 的訊號。現在不會。
- 連結兩個帳號時只讀第一個 domain。現在回報 `domain_count`，超過一個就不讀狀態。
- `sync-anchor-dropped` 只看一段會一直留著的歷史文字就建議解除帳號連結。現在還要求索引目前是丟棄狀態，並標成線索。
- 一個解法裡夾了行為界線沒有涵蓋的動作（刪除暫存資料夾裡的資料庫副本），已刪掉。
- 幾處措辭說得比證據多：兩次啟動相撞的過程、「沒有卡住」、解除連結「不會刪除檔案」、殘留程序「握著鎖」，都改成看到什麼寫什麼。

修正後在實機重跑時又抓到一個測試沒涵蓋的錯：`Domains.plist` 把隱藏的預設 domain 也列為一個鍵，只連結一個帳號的 Mac 被數成兩個 domain。已修正，測試用的 plist 也補上這個鍵。

測試從 65 項增加到 127 項，補上審查者用改壞程式的方式找出的缺口（色碼、只查目前使用者的程序、新舊程序編號相同、清理、運算子、沒回報的訊號）。修正之後沒有再送第二次審查。
