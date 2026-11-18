---
name: dropbox-fix
description: Dropbox 在 Mac 上卡住、不同步時，量測 Dropbox 與 macOS File Provider 的狀態，對照已知問題的知識庫找出原因並處理。使用者說「Dropbox 卡住了」「Dropbox 不同步」「同步數字不動」「Dropbox 一直顯示同步中」「當機重開之後 Dropbox 怪怪的」「Dropbox 很吃 CPU」時使用；要把新遇到的 Dropbox 問題記進知識庫時也用。只處理 Mac 上以 File Provider 運作的 Dropbox（資料夾在 ~/Library/CloudStorage 底下）；Dropbox 帳號、空間額度、分享連結、選擇性同步的設定、其他雲端服務都不在範圍。
allowed-tools:
  - Read
  - Bash(pgrep *)
---

# dropbox-fix：Dropbox 不同步時，先量測，再對照已知問題

Dropbox 在 Mac 上分成兩半：主程式（選單列那個圖示），以及由 macOS 的 `fileproviderd` 帶起來的延伸 `DropboxFileProvider`，實際搬檔案的是延伸。「卡住」常常是延伸根本沒在跑，或 `fileproviderd` 那一側出了狀況，而主程式看起來一切正常。所以這個 skill 不從 Dropbox 的畫面猜，先量兩邊的狀態，再拿量到的訊號去對一份已知問題的清單。

**實測範圍**：標「verified」的條目在 macOS 27.3、Dropbox 280.3.5012 上實際發生並處理過（2026-11-13），每一筆只實測過一次。標「reported」的來自更早的事故紀錄，步驟沒有用這個工具重新跑過。標「unverified」的沒有實測。跟使用者說明時，把這個狀態一起說出來。

## Step 0：建立任務清單

用 TaskCreate 建立下面五個 task（subject 直接複製），一次建完。做完一個就標 completed。

| # | subject | 類型 |
|---|---|---|
| 1 | 量測 Dropbox 與 File Provider 的狀態 | 機械 |
| 2 | 對照知識庫 | 機械 |
| 3 | ⚠️ 向使用者說明量到什麼、是哪一種問題、驗證到哪裡 | **判斷** |
| 4 | 依界線處理 | **判斷** |
| 5 | 再量一次並記錄 | 驗證 |

第 3 步不能省：比對到條目之後很容易直接動手，但每個解法的副作用與驗證狀態要先讓使用者知道。

## 腳本與知識庫的位置

- 腳本：`${CLAUDE_PLUGIN_ROOT}/scripts/dropbox-fix.sh`。這個路徑讀不到時，改用載入本 skill 時顯示的 base directory 往上兩層的 `scripts/dropbox-fix.sh`。下文寫成 `dropbox-fix.sh <子命令>`。
- 知識庫：`${CLAUDE_PLUGIN_ROOT}/data/problems.json`，隨 plugin 發布，不要改它（它在 plugin 的快取裡，改了下次更新就不見）。
- 使用者自己的條目：`~/.config/mac-dropbox-fix/problems.local.json`。腳本兩份一起讀。

## 行為界線

每個解法在知識庫裡有一個 `class`，只有三種：`direct`、`ask`、`user`。下面四張表是封閉列舉，不得依性質相似類推。知識庫裡的 `class` 與這裡不一致時，以比較嚴的那一邊為準。

### 直接做，做完回報：只有這五件

| # | 動作 |
|---|---|
| 1 | `dropbox-fix.sh` 的 `probe`、`match`、`list`、`show`、`validate`（都只讀） |
| 2 | 隨 plugin 發布的條目（來源欄是 `shipped`）裡 `confirm` 列的指令。目前只有三支程式：`pgrep`、`log show`、`sample`，都不改動設定；`sample` 會在暫存資料夾留一份報告檔 |
| 3 | `open -a Dropbox`（只在 `dropbox_app=not_running` 時） |
| 4 | 在 `~/.config/mac-dropbox-fix/records/` 寫一份這次的紀錄 |
| 5 | 在 `~/.config/mac-dropbox-fix/problems.local.json` 新增一筆條目（見〈新增條目〉），寫完跑 `validate` |

### 先問，使用者在這次對話同意才做：只有這兩件

| # | 動作 | 問的時候要說的 |
|---|---|---|
| 1 | `dropbox-fix.sh restart-fileproviderd` | iCloud 雲碟、Google Drive、OneDrive 這些同一個 daemon 管的雲端資料夾會跟著中斷幾秒再重連；不動資料庫檔，不動 Dropbox 帳號 |
| 2 | 結束指令列提到 `nucleus.sqlite3` 的 sqlite3 程序（一般的結束訊號，不用 `-9`） | 先把 `pgrep -fl 'sqlite3.*nucleus'` 的清單給使用者看，確認不是他正在用的 |

來自 `problems.local.json` 的條目（`match` 與 `list` 的第三欄是 `local`，`show` 的第三行寫「來源：個人條目」），它的 `confirm` 與解法裡的每一道指令，不論 `class` 寫什麼，一律先給使用者看、同意才執行。那份檔案沒有經過審查，上面〈直接做〉的第 2 項不適用於它。

### 只說明步驟，由使用者自己做：只有這兩件

| # | 動作 | 原因 |
|---|---|---|
| 1 | 在 Dropbox 的偏好設定解除這台電腦的帳號連結，再重新登入 | 會重建整份同步狀態、重新掃描全部檔案，可能要幾小時到幾天 |
| 2 | 重新開機 | 使用者手上的工作都會中斷 |

### 不做

`dropbox-fix.sh show <id>` 的最後一段會印出知識庫的 `never` 清單，一共四項。最重要的一項：**不直接碰 Dropbox 的 `nucleus.sqlite3`**，不複製、不換檔、不對運作中的檔案跑 `sqlite3`。先前的事故紀錄裡，這樣做之後只能解除帳號連結才救得回來。

沒有比對到條目時，也不拿「看起來相近」的條目的解法來試。

## Step 1：量測

```bash
dropbox-fix.sh probe
```

把輸出原樣給使用者看。每個訊號的意思在知識庫的 `signals`；最常用的三個：

| 訊號 | 看什麼 |
|---|---|
| `dropbox_extension` | `not_running` 表示實際搬檔案的延伸沒在跑，主程式開著也沒用 |
| `domain_state` | `alive` 正常；`startup_failed` 是 `fileproviderd` 那一側啟動失敗；`no_process` 是已註冊但沒人服務 |
| `dump_result` | `timeout` 表示 20 秒內沒有讀到 domain 的欄位，不論 dump 前面印了什麼。系統很忙時也會這樣，等一分鐘再量一次，兩次都 `timeout` 才當成訊號。`failed` 表示 dump 指令本身出錯，把這一點告訴使用者，不往下比對 |

`dump_result=no_provider` 或 `domain_state=absent` 表示這台 Mac 上的 Dropbox 沒有 File Provider domain（沒登入、沒裝，或是舊式的同步方式）。這不在範圍內，照實告訴使用者，停在這裡。

`domain_count` 大於 1（連結了兩個 Dropbox 帳號）時，`probe` 不讀 domain 的狀態，`domain_state` 是 `unknown`。這一版只讀得了一個 domain，照實告訴使用者，停在這裡；不要拿其中一個的狀態當成全部。

`pending_indexable` 與 `total_indexable` 有時沒有：系統很忙時 `fileproviderd` 回報逾時而不是數字。少了這兩行不代表有問題，隔幾分鐘再量。

## Step 2：對照知識庫

```bash
dropbox-fix.sh match
```

每行是一個比對到的條目：`id`、驗證狀態、來源（`shipped` 或 `local`）、標題，越前面越優先。對每個 `id` 跑 `dropbox-fix.sh show <id>` 讀完整內容。來源是 `shipped` 的條目，執行它的 `confirm` 指令（有的話）確認；來源是 `local` 的，`confirm` 指令先給使用者看、同意才執行。

- **比對到 `spotlight-reindex-after-unclean-shutdown`**：這一筆只說明 `fileproviderd` 為什麼忙，它不是同步卡住的證據，也不證明同步正常（`probe` 沒有量同步本身）。隔幾分鐘再量一次，`pending_indexable` 有在下降，而且沒有比對到別的條目，就告訴使用者這部分不用處理；他仍覺得檔案沒有在動時，請他放一個小檔案進去，看幾分鐘後 dropbox.com 上有沒有。
- **比對到 `sync-anchor-dropped`**：這一筆是線索。它讀的是 Spotlight 索引那一側的欄位；看 `last_drop_date` 是不是這次出問題前後，並照條目的說明確認檔案真的沒有在上傳下載，才向使用者提它的解法。
- **比對到 `fileprovider-xpc-deadlock`**：它的訊號只有「延伸在跑而 dump 沒回應」，系統忙的時候也會這樣。要用它的 `confirm` 指令看到延伸的執行緒停在 `mach_msg`，才能下這個判斷；看不到就當作沒比對到。
- **結束碼 3，沒有比對到**：照實說知識庫裡沒有這種情況，把訊號給使用者。接下來只做唯讀的查證，例如 `domain_state=startup_failed` 而錯誤不是資料庫被鎖時，把 `fileproviderctl dump com.getdropbox.dropbox.fileprovider` 開頭關於那個 domain 的錯誤行給使用者看。問題解決之後，照〈新增條目〉把它記下來。

## Step 3：向使用者說明

動手之前，用幾句話說清楚：

1. 量到什麼（引用訊號）。
2. 對到哪一筆、原因是什麼。
3. 這一筆驗證到哪裡（verified、reported、unverified，以及實測的版本）。
4. 打算用哪個解法、它的副作用、它屬於哪一類（直接做、先問、要使用者自己做）。
5. 知識庫記載試過無效的做法（`not_fixes`），免得使用者自己再試一次。

## Step 4：依界線處理

照條目的 `fixes` 由上往下，一次只做一個，照〈行為界線〉的分類決定誰動手。做完一個就進 Step 5 驗證，沒有解決才考慮下一個；不要連做兩個再一起驗。

`restart-fileproviderd` 的結束碼：0 是新的 `fileproviderd` 已經出現；1 是它本來就沒在跑或訊號送不出去；2 是送了訊號但 30 秒內沒有新的程序，這時請使用者在 Finder 點一下 Dropbox 資料夾再量一次。

## Step 5：再量一次並記錄

等解法的 `verify` 寫的時間（通常一兩分鐘），再跑一次 `dropbox-fix.sh probe`，對照 `verify` 的條件。把前後兩次的訊號並排給使用者看。

沒有解決就照實說，不要改口說「應該好了」；回到 Step 4 看下一個解法，或說明知識庫的解法都試過了。

寫一份紀錄到 `~/.config/mac-dropbox-fix/records/`，檔名 `YYYY-MM-DDTHHMM±HHMM.md`，內容是：處理前後的訊號、比對到的條目、做了什麼、結果。這份紀錄只留在使用者的電腦上。

## 新增條目

遇到知識庫沒有的問題，解決之後記進 `~/.config/mac-dropbox-fix/problems.local.json`：

```json
{
  "schema_version": 1,
  "problems": [
    {
      "id": "kebab-case-的名稱",
      "title": "一句話",
      "symptoms": ["使用者看得到的現象"],
      "match": { "all": [ { "signal": "domain_state", "op": "equals", "value": "startup_failed" } ] },
      "cause": "原因",
      "fixes": [
        { "id": "做法的名稱", "action": "做什麼", "class": "ask", "command": "指令（可省略）",
          "side_effects": "副作用（可省略）", "verify": "怎樣算解決（可省略）", "evidence": "verified" }
      ],
      "not_fixes": [ { "action": "試過的做法", "observed": "看到的結果" } ],
      "evidence": { "status": "verified", "date": "YYYY-MM-DD", "macos": "版本", "dropbox": "版本", "note": "實測了什麼、沒測什麼" }
    }
  ]
}
```

- `signal` 只能用知識庫 `signals` 列出的名稱；`op` 只有 `equals`、`not_equals`、`gte`、`lte`；`class` 只有 `direct`、`ask`、`user`；`evidence` 只有 `verified`、`reported`、`unverified`。寫完跑 `dropbox-fix.sh validate`，它會擋下不在這些清單裡的值。
- `evidence` 照實寫。只有這次真的做過、而且再量一次確認解決的解法才寫 `verified`；聽來的、推論的寫 `unverified`。
- 試過無效的做法記進 `not_fixes`，它跟解法一樣有用。
- 現有訊號分不出這個問題時（例如它跟另一筆的訊號完全相同），在 `symptoms` 與 `evidence.note` 寫清楚要另外看什麼，不要為了讓它比對得到而寫一個過寬的條件。
- 條目裡不要有這台電腦的識別資訊：家目錄路徑、帳號、資料夾名稱、UUID。

這個問題別人也可能遇到時，問使用者要不要回報給這個工具的 repo（`MacHelpdesk/mac-dropbox-fix` 的 issue）。那是公開的地方，使用者同意、而且內容拿掉識別資訊之後才開。

## 驗證到哪裡

| 行為 | 狀態 |
|---|---|
| `probe` 讀得出 domain 啟動失敗（資料庫被鎖）與正常兩種狀態 | 已實測（macOS 27.3） |
| `probe` 在 domain 正常、dump 有上百萬行時，幾秒內讀到需要的欄位並結束 dump（量到 1 到 3 秒） | 已實測 |
| 對 `fileproviderd` 送結束訊號後，launchd 在 12 秒內啟動新的，Dropbox 的延伸隨後被叫起來，同步恢復 | 已實測一次。當時是手動送訊號；`restart-fileproviderd` 子命令做的是同一件事，本身只在測試裡用替身指令驗過 |
| `launchctl kickstart -k` 重啟 `fileproviderd` | 已實測：被 SIP 擋下，不能用 |
| 其餘訊號（sync anchor、殘留的 sqlite3、沒有程序、dump 沒回應或出錯、超過一個 domain）的判讀 | 只在測試裡用合成的 dump 與替身指令驗過 |
| 結束殘留的 sqlite3、解除帳號連結重新登入 | 來自更早的事故紀錄（reported），沒有用這個工具重新做過 |
| `open -a Dropbox` | 未驗證 |
| plugin 的 hook：訊息提到 Dropbox 卡住或不同步時，隨訊息附上這個 skill 的說明（每個 session 最多一次） | 已實測一次（Claude Code 2.1.327、macOS 27.3，2026-11-18）：說明送到模型，模型第一個動作是載入這個 skill；那則訊息本身就提到不同步，分不出是不是說明的作用。判斷規則只在 `tests/test_hooks.sh` 驗過 |
| 其他 macOS 版本、其他 Dropbox 版本 | 未驗證。`fileproviderctl dump` 的格式沒有公開文件，版本不同可能讀不出來；讀不出來時訊號會是 `unknown` 或缺少，不會被當成比對到 |
