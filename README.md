# mac-dropbox-fix

Dropbox 在 Mac 上卡住不同步時，量測 Dropbox 與 macOS File Provider 的狀態，對照一份已知問題的知識庫找出是哪一種，再照每個解法標明的界線處理。要在 Dropbox 資料夾裡整理、複製、搬移一批檔案時，也能先確認檔案在不在這台 Mac 上，需要時先問再下載。

與 [`mac-printer-setup`](https://github.com/MacHelpdesk/mac-printer-setup)、[`mac-network-test`](https://github.com/MacHelpdesk/mac-network-test) 同一個系列：先量測，再判讀，最後才動手。

> **狀態：v0.3.0。** 不同步的知識庫裡，兩筆條目在 macOS 27.3、Dropbox 280.3.5012 上實際發生並處理過，各一次；其餘來自更早的事故紀錄或沒有實測，每一筆都標了狀態。檢查與下載僅線上檔案的部分，在 macOS 27.3、Dropbox 280.3.5020 的測試資料夾實測過一次；離線時的行為還沒實測。0.3.0 加上兩個 hook，在 Claude Code 2.1.327 上各實跑過，次數很少，見〈驗證到哪裡〉。

## 它解決什麼

Dropbox 在 Mac 上分成兩半：選單列的主程式，以及由 macOS 的 `fileproviderd` 帶起來的延伸 `DropboxFileProvider`。實際搬檔案的是延伸。主程式看起來正常、同步卻完全不動時，問題常常在 `fileproviderd` 那一側，從 Dropbox 的畫面看不出來。

| 你遇到的 | 原因 | 知識庫條目 |
|---|---|---|
| 當機或強制關機後重開，Dropbox 一直顯示同步中但數字不動 | `fileproviderd` 啟動 Dropbox 的 domain 時自己的資料庫被鎖，啟動失敗後不會重試 | `fileprovider-domain-startup-locked` |
| 重開機後 `fileproviderd` 很吃 CPU，以為卡住 | 正在重建 Spotlight 索引，這跟檔案同步是兩件事 | `spotlight-reindex-after-unclean-shutdown` |
| 某天開始完全不同步，重開機也沒用 | 可能是同步進度指標損壞，或延伸卡死。這兩筆是線索，要另外確認 | `sync-anchor-dropped`、`fileprovider-xpc-deadlock` |
| 同步卡住，先前有人對 Dropbox 的資料庫跑過 `sqlite3` | 殘留的程序可能握著鎖 | `stray-sqlite3-on-nucleus` |

另一種情況是同步正常，但你要動資料夾裡的檔案：

| 你遇到的 | 原因 | 用哪個 |
|---|---|---|
| `ls` 看起來檔案都在、大小也對，讀起來卻很慢，或複製到一半卡住 | 檔案是僅線上的佔位檔，內容還在雲端；讀它才會下載 | `dropbox-use`（先 `local-status` 量，再決定要不要 `download`） |
| 想先把整個資料夾下載下來再整理 | 這版 macOS 的 `fileproviderctl` 沒有下載的指令 | `download` 逐檔讀取，讓 Dropbox 下載 |

範圍是封閉的：Mac 上以 File Provider 運作的 Dropbox（資料夾在 `~/Library/CloudStorage` 底下），只處理兩件事：不同步時的量測與處理，以及動檔案之前確認它們在不在這台 Mac 上。Dropbox 帳號、空間額度、分享連結、選擇性同步的設定、Dropbox 的網頁與 API、其他雲端服務都不處理。

## 五個部分

| 部分 | 位置 | 做什麼 |
|---|---|---|
| skill | `/mac-dropbox-fix:dropbox-fix` | 不同步時：量測 → 對照知識庫 → 向你說明 → 依界線處理 → 再量一次並記錄 |
| skill | `/mac-dropbox-fix:dropbox-use` | 動檔案之前：量哪些是僅線上 → 要下載就先問 → 下載並再量一次 → 說明複製方法的驗證狀態 |
| 知識庫 | `plugin/data/problems.json` | 每筆問題的症狀、量得到的訊號、原因、解法、試過無效的做法、驗證到哪裡 |
| 腳本 | `plugin/scripts/dropbox-fix.sh` | 量測、比對、檢查與下載僅線上的檔案；會改動東西的子命令見下文 |
| hook | `plugin/hooks/hooks.json`、`plugin/scripts/skill-hint.sh` | 在用得上 skill 的時候告訴 Claude 有這個 skill；見〈plugin 會自己做的事〉 |

## 安裝

```bash
/plugin marketplace add MacHelpdesk/mac-helpdesk
/plugin install mac-dropbox-fix@mac-helpdesk
```

## 使用

```
Dropbox 卡住了，同步數字一直不動
→ /mac-dropbox-fix:dropbox-fix

我要整理 Dropbox 裡的這個資料夾，先確認檔案都在本機
→ /mac-dropbox-fix:dropbox-use
```

腳本不透過 Claude Code 也能用。clone 這個 repo 之後：

```bash
plugin/scripts/dropbox-fix.sh probe      # 量測，一行一個 訊號=值
plugin/scripts/dropbox-fix.sh match      # 量測並列出符合的已知問題：id、驗證狀態、來源、標題（結束碼 3：沒有符合的）
plugin/scripts/dropbox-fix.sh list       # 知識庫裡的每一筆
plugin/scripts/dropbox-fix.sh show <id>  # 一筆的完整內容
plugin/scripts/dropbox-fix.sh validate   # 檢查知識庫與你自己的條目

plugin/scripts/dropbox-fix.sh local-status <路徑>     # 路徑底下幾個檔、幾個僅線上、要下載多少、剩多少空間

plugin/scripts/dropbox-fix.sh restart-fileproviderd   # 會改動東西，見下一節
plugin/scripts/dropbox-fix.sh download <路徑>         # 會下載檔案，見下一節
```

`local-status` 的輸出長這樣（路徑只接受 `~/Library/CloudStorage` 底下 Dropbox 資料夾裡的）：

```
files=5
online_only=5
online_only_bytes=209715307
free_bytes=31457280000
```

`probe` 的輸出長這樣：

```
dropbox_app=running
dropbox_extension=not_running
fileproviderd=running
stray_sqlite3=0
dump_result=ok
domain_state=startup_failed
domain_startup_error=sqlite_locked
needs_auth=no
index_dropped=no
sync_anchor_drop=no
last_drop_reason=Error while indexing a batch
last_drop_date=2026-01-01 00:00:00 +0000
pending_indexable=734720
total_indexable=1283295
```

讀得到 Dropbox 的 `Domains.plist` 時還會有一行 `domain_count`。讀不到的值不會出現，或寫成 `unknown`：系統很忙時 `fileproviderd` 對兩個索引數字回報逾時，那兩行就沒有。連結了兩個 Dropbox 帳號（`domain_count` 大於 1）時，這一版不讀 domain 的狀態。

## plugin 會自己做的事

裝了很多 skill 的機器上，Claude Code 的 skill 清單會把描述拿掉、只留名稱，Claude 就看不到「什麼時候該用這個 skill」。所以這個 plugin 帶了兩個 hook，在用得上的時候告訴 Claude。裝了這個 plugin，下面兩件事就會發生：

| 事件 | 什麼時候有動作 | 做什麼 |
|---|---|---|
| `UserPromptSubmit`（你送出每一則訊息時） | 訊息提到 Dropbox，而且有「卡住、不同步」這一類的詞 | 隨訊息附上一段說明，告訴 Claude 有 `mac-dropbox-fix:dropbox-fix`。你的訊息照常送出 |
| `PreToolUse`（Claude 執行每一個 Bash 指令之前） | 指令用到 `cp`、`mv`、`rsync`、`ditto`、`tar`、`zip`，而且指令或工作目錄指向 Dropbox 資料夾 | **這個指令這一次不執行**，改把 `mac-dropbox-fix:dropbox-use` 的說明回給 Claude。Claude 可以先載入 skill 量一下，或直接再送一次 |

- **每個 session 最多各一次。** 說明出現過、或指令被擋過一次之後，同一個 session 不會再有第二次；指令重送就照常執行。
- **成本。** 每則訊息與每個 Bash 指令都會啟動一次 `skill-hint.sh`。輸入裡沒有 `dropbox` 字樣（Bash 那一半再加上沒有上面六個動詞）時，它在第一步就結束，實測約 6 ms；有的話才用 `osascript` 解讀輸入，約 52 ms（macOS 27.3，各 10 次平均）。這裡的「輸入」是 Claude Code 交給 hook 的整份資料，裡面有工作目錄與對話紀錄檔的路徑：**在 Dropbox 資料夾裡開的 session，每則訊息都會走到 `osascript` 那一步**；Bash 那一半的六個動詞是在整份資料裡找字樣（指令、說明文字、路徑都算），所以這種 session 裡像 `npm start`（含 `tar`）這樣的指令也會走到。粗篩之前腳本不啟動其他程式。
- **出錯時放行。** 輸入讀不懂、`osascript` 失敗、記號檔寫不了、逾時（10 秒），訊息與指令都照常進行，不會因為 hook 壞掉而被擋。
- **已經在用 skill 就不打擾。** 指令在執行 plugin 自己的 `dropbox-fix.sh`（或把它的路徑存進變數），或訊息是 `/mac-dropbox-fix:…` 開頭時，不擋、不附說明。`dropbox-fix.sh` 只是別的指令的參數（例如被打包的檔案）時不算。
- **會誤判。** 判斷只看指令的文字，不解析 shell 語法。會多擋的情況：指令裡同時出現動詞與 Dropbox 路徑、其實沒有動到 Dropbox 檔案；工作目錄在 Dropbox 資料夾裡、指令有那六個動詞之一但沒有寫任何 Dropbox 路徑（例如 `git mv`）。會漏掉的情況：Dropbox 路徑先存進變數、在另一個指令才用到；動詞經過別名或函式；程式名稱用引號包住或前面加反斜線；Dropbox 路徑後面直接接萬用字元；路徑的大小寫與實際不同；同一行裡既執行 `dropbox-fix.sh` 又複製（整行放行）。多擋的只會發生一次，重送就執行。
- **只擋 Bash 工具的指令。** 用其他工具讀寫 Dropbox 資料夾裡的檔案不在範圍內。
- **寫入的東西。** 每個 session 最多兩個空的記號檔，放在 Claude Code 給這個 plugin 的資料目錄（`CLAUDE_PLUGIN_DATA`）底下的 `hints/`，檔名是 session 的代號。hook 不會刪這些檔：記號在，同一個 session 才不會被擋第二次，隔多久接回來都一樣。想清掉可以自己刪 `hints/` 資料夾，影響只是進行中的 session 可能再被告知一次。Claude Code 沒有提供這個資料目錄時，hook 什麼都不做。hook 不讀你的檔案內容，不連網路。
- 詞表、動詞與路徑的寫法是封閉列舉，在 `plugin/scripts/hint.js` 開頭。不想要這兩個 hook，目前的做法是停用這個 plugin，兩個 skill 也會一起停用。只關掉這個 plugin 的 hook、留下 skill 的做法，沒有驗證過。

## 會改動東西的兩個子命令

`restart-fileproviderd` 對目前使用者的 `fileproviderd` 送結束訊號，等 launchd 啟動新的。iCloud 雲碟、Google Drive、OneDrive 這些同一個 daemon 管的雲端資料夾會跟著中斷幾秒再重連。它不動任何資料庫檔，也不動 Dropbox 的帳號連結。

`download` 逐檔讀取路徑底下僅線上的檔案，讓 Dropbox 把它們下載到這台 Mac；會用掉網路與磁碟空間，但不修改、搬移或刪除任何檔案。

- 剩餘空間小於要下載的總量時，一個檔都不讀，結束碼 4。
- 每個檔讀 `DROPBOX_FIX_READ_WAIT` 秒（預設 300）沒讀完就停掉這次讀取。實測一次：200 MB 的檔第一輪被停掉之後，第二輪 1 秒就讀完。
- 上一輪有檔案下載成功才跑下一輪，最多三輪；連續三個檔逾時就停（`stopped=timeouts`），這通常是沒有網路。
- 結束時還是僅線上的檔逐一列成 `online_only_file=`，結束碼 2；stderr 每讀一個檔印一行進度。

其餘子命令不改動任何設定。`probe` 會啟動 `fileproviderctl dump`，讀到需要的欄位就把它結束掉：domain 正常時這份 dump 有上百萬行。

## 知識庫

`plugin/data/problems.json` 的一筆條目：

| 欄位 | 內容 |
|---|---|
| `id`、`title`、`symptoms` | 名稱與使用者看得到的現象 |
| `match.all` | 一組條件，全部成立才算符合。條件只能用 `signals` 列出的訊號，運算只有 `equals`、`not_equals`、`gte`、`lte` |
| `cause` | 原因 |
| `confirm` | 進一步確認用的指令，不改動設定 |
| `fixes` | 解法，由上往下試。每個解法有 `class`：`direct`（直接做）、`ask`（先問）、`user`（只能由你自己做） |
| `not_fixes` | 試過無效的做法與當時看到的結果 |
| `evidence` | `verified`（實際做過並確認解決）、`reported`（來自事故紀錄，沒有重新跑過）、`unverified` |

檔案最上面的 `never` 列出任何情況都不做的事，一共四項。第一項是不直接碰 Dropbox 自己的資料庫 `nucleus.sqlite3`。

`problems` 的順序就是比對的優先順序。`probe` 沒有回報的訊號，以及值是 `unknown` 的訊號，條件一律不成立（指名要 `unknown` 的 `equals` 除外）：讀不到不會被當成符合。

### 加你自己遇過的問題

寫在 `~/.config/mac-dropbox-fix/problems.local.json`，格式相同，只需要 `schema_version` 與 `problems`。腳本兩份一起讀；你的檔案格式有錯時會被略過並印出原因，不會蓋掉內建的條目。`id` 不能跟內建的重複。

`match`、`list`、`show` 都會標出每一筆的來源（`shipped` 或 `local`）。skill 對兩者的處理不同：內建條目的確認指令可以直接執行；你自己的條目沒有經過審查，裡面的每一道指令都會先問你。

```bash
plugin/scripts/dropbox-fix.sh validate
```

不要改 plugin 安裝目錄裡的 `problems.json`，下次更新就會被換掉。覺得某一筆別人也用得到，歡迎開 issue 或 PR；請先拿掉家目錄路徑、帳號、資料夾名稱與 UUID。

## 這個 repo 只放方法與工具

這個 repo 是公開的。你的條目與處理紀錄在你家目錄的 `~/.config/mac-dropbox-fix/`：

- `problems.local.json`：你自己加的條目。
- `records/`：每次處理的紀錄，一次一個檔案，內容是處理前後的訊號、符合的條目、做了什麼。
- 想留修改紀錄，就在那個資料夾 `git init`，只留在本機就好。

`fileproviderctl dump` 的輸出含有 domain 的 UUID 與家目錄底下的路徑。回報問題時把 UUID 換成 `00000000-0000-0000-0000-000000000000`，路徑拿掉使用者名稱。這個 repo 的 `.gitignore` 擋掉 `problems.local.json`、`records/`、`results/`，CI 也會檢查追蹤的檔案裡有沒有家目錄路徑與真實的 UUID。

## 要知道的六件事

1. **實際同步檔案的是延伸，不是主程式。** 選單列的圖示在，不代表延伸在跑。`probe` 的 `dropbox_extension` 才是答案。
2. **重開 Dropbox 主程式救不回啟動失敗的 domain。** domain 的狀態在 `fileproviderd` 裡，主程式重開時它已經是錯誤狀態。
3. **`launchctl kickstart -k` 不能用來重啟 `fileproviderd`。** 它受 SIP 保護，會回結束碼 150。一般的結束訊號可以。
4. **`fileproviderd` 很忙不等於卡住。** 不正常關機後它會把整個 Dropbox 資料夾重新交給 Spotlight 索引，上百萬個項目要跑很久；看 `pending_indexable` 有沒有在下降。
5. **檔案大小不能說明檔案在不在本機。** 僅線上的佔位檔在 `ls -l` 裡顯示完整大小；看 `ls -lO` 的 `dataless`，或用 `local-status`。
6. **大檔下載中時，小檔也可能很慢。** 實測一次：一個 200 MB 的檔下載時，四個幾十 byte 的檔各花了 78 到 123 秒。

## 驗證到哪裡

| 行為 | 狀態 |
|---|---|
| `probe` 讀得出 domain 啟動失敗（資料庫被鎖）與正常兩種狀態 | 已實測 |
| `probe` 在 dump 有上百萬行時幾秒內讀完並結束 dump（量到 1 到 3 秒） | 已實測 |
| 對 `fileproviderd` 送結束訊號後 12 秒內出現新的，延伸隨後啟動，同步恢復 | 已實測一次，當時是手動送訊號 |
| `restart-fileproviderd` 子命令本身、其餘訊號的判讀、知識庫的檢查 | 只在測試裡用替身指令與合成的 dump 驗過（127 項） |
| 結束殘留的 sqlite3、解除帳號連結重新登入 | 來自更早的事故紀錄，沒有用這個工具重新做過 |
| `open -a Dropbox` | 未驗證 |
| 連結兩個 Dropbox 帳號的 Mac | 不支援：`probe` 只回報有幾個 domain |
| `local-status` 分得出本機與僅線上的檔 | 已實測（macOS 27.3、Dropbox 280.3.5020，2026-11-14）：設為僅供線上存取的 5 個檔量到 `online_only=5` |
| `download` 在真的 Dropbox 資料夾上下載 | 已實測一次：5 個檔、200 MB，712 秒，結束碼 0，沒有留下讀取程序；大檔第一輪 300 秒被停、第二輪 1 秒讀完 |
| `cp -p` 帶著原檔的 Dropbox 屬性複製 | 已實測一次：90 秒內 Dropbox 換上副本自己的屬性，沒有衝突的複本；副本有沒有出現在 dropbox.com 沒在網頁上核對 |
| `local-status`、`download` 的輸出、結束碼、空間檢查、逾時、重試與停止規則；`dropbox-use` 的四張表 | 只在測試裡用替身指令驗過（`tests/test_local.sh` 92 項、`tests/test_skill_use.sh` 27 項） |
| 連線狀態下，讀到上限時停掉真的讀取 | 已實測兩次：之後沒有殘留的讀取程序 |
| 離線時 `download` 停得下來；「設為離線存取」之後檔案還會不會被回收 | 未驗證（追蹤在 #3） |
| hook 腳本對合成輸入的判斷：詞表、動詞與路徑、每個 session 一次、失敗時放行、只看解碼後的欄位 | 只在測試裡驗過（`tests/test_hooks.sh` 82 項） |
| hook 在真的 Claude Code 裡：`UserPromptSubmit` 的說明送到模型；`PreToolUse` 在指令執行前擋下，同一個 session 第二次照常執行 | 已實測（Claude Code 2.1.327、macOS 27.3，`claude -p --plugin-dir plugin`，2026-11-18 與 11-19）：說明送到 2 次；擋下 5 次，每次重送都照常執行。兩個情境在最後的程式上各重跑過一次 |
| 模型收到 hook 的說明之後載入對應的 skill | 已實測，次數很少（同上的版本，模型是 Sonnet）：訊息情境 2 次中 2 次載入 `dropbox-fix`，但訊息本身就提到 Dropbox 不同步，分不出是不是說明的作用；用現在的說明文字，3 次中 3 次先載入 `dropbox-use` 再跑 `local-status`（備份整個資料夾 1 次、複製單一路徑 2 次）。hook 不保證模型一定載入 |
| 從 marketplace 安裝後的 hook、subagent 裡的 hook、工作目錄在 Dropbox 資料夾裡的實際 session | 未驗證 |
| 其他 macOS 與 Dropbox 版本 | 未驗證。`fileproviderctl dump` 的格式沒有公開文件 |

## 需求

- macOS（實測 27.3），內建的 `fileproviderctl`、`pgrep`、`osascript`；`local-status` 與 `download` 另外用到內建的 `find`、`stat`、`df`、`dd`
- 不需要另外安裝任何東西；讀 JSON 用的是 macOS 內建的 JavaScript（`osascript -l JavaScript`）
- 不需要管理者權限

## 相關

- [`mac-helpdesk`](https://github.com/MacHelpdesk/mac-helpdesk)：這個系列的索引與共用規則
