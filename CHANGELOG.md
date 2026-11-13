# Changelog

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
