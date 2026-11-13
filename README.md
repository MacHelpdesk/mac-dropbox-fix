# mac-dropbox-fix

Dropbox 在 Mac 上卡住不同步時，量測 Dropbox 與 macOS File Provider 的狀態，對照一份已知問題的知識庫找出是哪一種，再照每個解法標明的界線處理。

與 [`mac-printer-setup`](https://github.com/MacHelpdesk/mac-printer-setup)、[`mac-network-test`](https://github.com/MacHelpdesk/mac-network-test) 同一個系列：先量測，再判讀，最後才動手。

> **狀態：v0.1.0。** 兩筆條目在 macOS 27.3、Dropbox 280.3.5012 上實際發生並處理過，各一次。其餘條目來自更早的事故紀錄或沒有實測，知識庫裡每一筆都標了狀態。

## 它解決什麼

Dropbox 在 Mac 上分成兩半：選單列的主程式，以及由 macOS 的 `fileproviderd` 帶起來的延伸 `DropboxFileProvider`。實際搬檔案的是延伸。主程式看起來正常、同步卻完全不動時，問題常常在 `fileproviderd` 那一側，從 Dropbox 的畫面看不出來。

| 你遇到的 | 原因 | 知識庫條目 |
|---|---|---|
| 當機或強制關機後重開，Dropbox 一直顯示同步中但數字不動 | `fileproviderd` 啟動 Dropbox 的 domain 時自己的資料庫被鎖，啟動失敗後不會重試 | `fileprovider-domain-startup-locked` |
| 重開機後 `fileproviderd` 很吃 CPU，以為卡住 | 正在重建 Spotlight 索引，這跟檔案同步是兩件事 | `spotlight-reindex-after-unclean-shutdown` |
| 某天開始完全不同步，重開機也沒用 | 可能是同步進度指標損壞，或延伸卡死。這兩筆是線索，要另外確認 | `sync-anchor-dropped`、`fileprovider-xpc-deadlock` |
| 同步卡住，先前有人對 Dropbox 的資料庫跑過 `sqlite3` | 殘留的程序可能握著鎖 | `stray-sqlite3-on-nucleus` |

範圍是封閉的：Mac 上以 File Provider 運作的 Dropbox（資料夾在 `~/Library/CloudStorage` 底下）。Dropbox 帳號、空間額度、分享連結、選擇性同步的設定、其他雲端服務都不處理。

## 三個部分

| 部分 | 位置 | 做什麼 |
|---|---|---|
| skill | `/mac-dropbox-fix:dropbox-fix` | 量測 → 對照知識庫 → 向你說明 → 依界線處理 → 再量一次並記錄 |
| 知識庫 | `plugin/data/problems.json` | 每筆問題的症狀、量得到的訊號、原因、解法、試過無效的做法、驗證到哪裡 |
| 腳本 | `plugin/scripts/dropbox-fix.sh` | 量測與比對；只有一個子命令會改動東西 |

## 安裝

```bash
/plugin marketplace add MacHelpdesk/mac-helpdesk
/plugin install mac-dropbox-fix@mac-helpdesk
```

## 使用

```
Dropbox 卡住了，同步數字一直不動
→ /mac-dropbox-fix:dropbox-fix
```

腳本不透過 Claude Code 也能用。clone 這個 repo 之後：

```bash
plugin/scripts/dropbox-fix.sh probe      # 量測，一行一個 訊號=值
plugin/scripts/dropbox-fix.sh match      # 量測並列出符合的已知問題：id、驗證狀態、來源、標題（結束碼 3：沒有符合的）
plugin/scripts/dropbox-fix.sh list       # 知識庫裡的每一筆
plugin/scripts/dropbox-fix.sh show <id>  # 一筆的完整內容
plugin/scripts/dropbox-fix.sh validate   # 檢查知識庫與你自己的條目

plugin/scripts/dropbox-fix.sh restart-fileproviderd   # 會改動東西，見下一節
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

## 會改動東西的只有一個子命令

`restart-fileproviderd` 對目前使用者的 `fileproviderd` 送結束訊號，等 launchd 啟動新的。iCloud 雲碟、Google Drive、OneDrive 這些同一個 daemon 管的雲端資料夾會跟著中斷幾秒再重連。它不動任何資料庫檔，也不動 Dropbox 的帳號連結。

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

## 要知道的四件事

1. **實際同步檔案的是延伸，不是主程式。** 選單列的圖示在，不代表延伸在跑。`probe` 的 `dropbox_extension` 才是答案。
2. **重開 Dropbox 主程式救不回啟動失敗的 domain。** domain 的狀態在 `fileproviderd` 裡，主程式重開時它已經是錯誤狀態。
3. **`launchctl kickstart -k` 不能用來重啟 `fileproviderd`。** 它受 SIP 保護，會回結束碼 150。一般的結束訊號可以。
4. **`fileproviderd` 很忙不等於卡住。** 不正常關機後它會把整個 Dropbox 資料夾重新交給 Spotlight 索引，上百萬個項目要跑很久；看 `pending_indexable` 有沒有在下降。

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
| 其他 macOS 與 Dropbox 版本 | 未驗證。`fileproviderctl dump` 的格式沒有公開文件 |

## 需求

- macOS（實測 27.3），內建的 `fileproviderctl`、`pgrep`、`osascript`
- 不需要另外安裝任何東西；讀 JSON 用的是 macOS 內建的 JavaScript（`osascript -l JavaScript`）
- 不需要管理者權限

## 相關

- [`mac-helpdesk`](https://github.com/MacHelpdesk/mac-helpdesk)：這個系列的索引與共用規則
