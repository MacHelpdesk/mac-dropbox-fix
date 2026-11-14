---
name: dropbox-use
description: 在 Mac 的 Dropbox 資料夾裡讀取、複製、備份、搬移一批檔案之前，先確認檔案是不是已經在這台 Mac 上；有僅線上的檔案時，先問使用者再下載，並說清楚哪些做法實測過、哪些沒有。使用者說「這些是不是僅線上」「先下載再整理」「整理 Dropbox 裡的資料夾」「複製一份備份」「搬 Dropbox 裡的檔案」時使用；Claude 自己要大量讀取、複製或搬移 ~/Library/CloudStorage 底下 Dropbox 資料夾的檔案時也用。只處理 Mac 上以 File Provider 運作的 Dropbox；Dropbox 不同步用 dropbox-fix，Dropbox 的網頁與 API、其他雲端服務都不在範圍。
allowed-tools:
  - Read
---

# dropbox-use：在 Dropbox 資料夾裡動檔案之前，先確認它在不在這台 Mac 上

Dropbox 以 File Provider 運作時，資料夾裡的檔案可能只是佔位檔（僅線上）：`ls -l` 顯示完整大小，內容卻還在雲端。讀它會觸發下載，大檔要很久；拿一批佔位檔去複製或搬移，等於邊下載邊做，中途斷線就做了一半。所以這個 skill 先量，需要時先問再下載，最後才做使用者原本要做的事。

**實測範圍**：見最後的〈驗證到哪裡〉。跟使用者說明時，把每一項的驗證狀態一起說出來。

## Step 0：建立任務清單

用 TaskCreate 建立下面四個 task（subject 直接複製），一次建完。做完一個就標 completed。

| # | subject | 類型 |
|---|---|---|
| 1 | 量測檔案在不在這台 Mac 上 | 機械 |
| 2 | ⚠️ 向使用者說明量到什麼；要下載就先問 | **判斷** |
| 3 | 下載並再量一次 | 機械 |
| 4 | 做使用者原本要做的事，說明複製方法的驗證狀態 | **判斷** |

沒有僅線上的檔案時，第 3 個 task 標 completed 並註明「不需要下載」。

## 腳本的位置

- 腳本：`${CLAUDE_PLUGIN_ROOT}/scripts/dropbox-fix.sh`，與 `dropbox-fix` skill 共用。這個路徑讀不到時，改用載入本 skill 時顯示的 base directory 往上兩層的 `scripts/dropbox-fix.sh`。下文寫成 `dropbox-fix.sh <子命令>`。
- 兩個子命令都只接受 `~/Library/CloudStorage` 底下 Dropbox 資料夾裡的路徑，其他路徑結束碼是 1。

## 行為界線

下面四張表是封閉列舉，不得依性質相似類推。

### 直接做，做完回報：只有這一件

| # | 動作 |
|---|---|
| 1 | `dropbox-fix.sh local-status PATH`：只讀，不讀任何檔案的內容 |

### 先問，使用者在這次對話同意才做：只有這一件

| # | 動作 | 問之前要說的 |
|---|---|---|
| 1 | `dropbox-fix.sh download PATH` | `local-status` 量到的 `online_only`（幾個僅線上檔案）、`online_only_bytes`（總共多大）、`free_bytes`（剩餘空間）；以及下載完之後，系統之後仍可能把檔案回收成僅線上（要避免，見下一張表） |

### 只說明步驟，由使用者自己做：只有這一件

| # | 動作 | 怎麼做 |
|---|---|---|
| 1 | 把資料夾設為離線存取，避免下載完又被系統回收成僅線上 | 在 Finder 對資料夾按右鍵，選 Dropbox 選單的「設為離線存取」（繁體中文介面的文字；同一個選單裡的「設為僅供線上存取」是反方向，會移除本機的下載） |

### 不做：只有這四件

| # | 不做的事 |
|---|---|
| 1 | 把檔案設回僅線上（替使用者騰出空間也不做） |
| 2 | 改 Dropbox 的任何設定 |
| 3 | 碰 Dropbox 的 `nucleus.sqlite3`：不複製、不換檔、不對它跑 `sqlite3` |
| 4 | 處理 `~/Library/CloudStorage` 底下 Dropbox 資料夾以外的路徑 |

## Step 1：量測

```bash
dropbox-fix.sh local-status PATH
```

把輸出原樣給使用者看。四個值：

| 鍵 | 意思 |
|---|---|
| `files` | PATH 底下的一般檔案數 |
| `online_only` | 其中僅線上的檔案數（檔案帶 `dataless` flag；不看大小） |
| `online_only_bytes` | 僅線上檔案的大小加總，也就是要下載的量 |
| `free_bytes` | PATH 所在磁碟的剩餘空間（讀不到時這一行不會出現） |

結束碼 1：路徑不存在，或不在 Dropbox 資料夾裡。把 stderr 的原因告訴使用者，停在這裡。

## Step 2：說明，要下載就先問

- `online_only=0`：檔案都在這台 Mac 上，不需要下載，直接進 Step 4。
- `free_bytes` 小於 `online_only_bytes`：空間不夠，`download` 會拒絕（結束碼 4）。告訴使用者兩個數字，請他先清出空間，或縮小 PATH。
- 其餘情況，使用者原本的工作要讀取、複製或搬移這些檔案時，照〈行為界線〉先問。

只讀一兩個檔案時不需要這個 skill：一般的讀取本來就會讓那個檔案下載。

## Step 3：下載並再量一次

```bash
dropbox-fix.sh download PATH
```

| 結束碼 | 意思 | 接下來 |
|---|---|---|
| 0 | 僅線上的檔案都下載了 | 進 Step 4 |
| 2 | 還有檔案是僅線上，輸出逐一列出 `online_only_file=` | 把清單給使用者看，不要對這些檔案做原本的工作 |
| 4 | 剩餘空間不夠，一個檔都沒讀 | 見 Step 2 |
| 1 | 路徑錯誤 | 見 Step 1 |

stderr 每讀一個檔印一行 `pass <輪>, file <第幾個>/<這輪共幾個>: <路徑>`，讀完印 `done in`、`failed after` 或 `stopped after` 加秒數，長時間沒有結果時可以看出卡在哪個檔。

逾時被停掉不一定代表下載失敗。2026-11-14 實測一次：200 MB 的檔第一輪讀到 300 秒被停掉，第二輪 1 秒就讀完，被停掉的讀取沒有讓下載從頭來過；同一輪裡，四個幾十 byte 的小檔各花了 78 到 123 秒，當時那個大檔正在下載。這兩點都只看過一次。

輸出有 `stopped=timeouts` 時，表示連續三個檔案讀取逾時就停了。最常見的原因是這台 Mac 沒有網路；網路正常時，也可能是有一個很大的檔正在下載，接下來的幾個檔都等太久。請使用者確認網路後再跑一次。每個檔案的讀取上限是 `DROPBOX_FIX_READ_WAIT` 秒（預設 300）；網路正常但檔案很大時，可以設大一點再跑。

下載完再跑一次 `local-status`，確認 `online_only=0`。

## Step 4：做使用者原本要做的事

照使用者的原始要求做。要複製或備份時，照下一節說明每個方法的驗證狀態。

## 複製或備份 Dropbox 裡的檔案

每個檔案都帶 `com.dropbox.attrs` 與 `com.dropbox.internal` 兩個延伸屬性，而 macOS 的 `cp` 預設會連延伸屬性一起複製。下表是目前知道的做法：

| 做法 | 實際發生什麼 | 驗證狀態 |
|---|---|---|
| 先 `download`，再用 `cp -pRX` 複製（保留修改時間、不帶延伸屬性），之後只補回 `com.apple.FinderInfo` | 117 個檔的副本與原檔 sha256 全部一致，修改時間保留；剛複製完的幾分鐘副本沒有 `com.dropbox.*` 屬性，幾小時後再看，117 個副本中 116 個有了 Dropbox 自己的屬性 | verified：macOS 27.3、Dropbox 280.3.5020，2026-11-14 實測一次；Dropbox 有沒有上傳副本沒量 |
| 先 `download`，再在同一個 Dropbox 資料夾裡 `mv`（改名或搬到子資料夾） | 搬移前後 sha256 一致，修改時間保留 | verified：macOS 27.3、Dropbox 280.3.5020，2026-11-14 實測一次；對僅線上檔案直接 `mv` 沒量 |
| 一般的 `cp -p`，副本帶著原檔的 `com.dropbox.attrs` 與 `com.dropbox.internal` | 90 秒內 Dropbox 換上副本自己的 `com.dropbox.attrs`，沒有出現衝突的複本，副本沒有被當成原檔；不帶屬性的 `cp -pX` 副本同樣在 90 秒內拿到自己的屬性 | verified：macOS 27.3、Dropbox 280.3.5020，2026-11-14 實測一次（一個 40 byte 的檔）；副本有沒有出現在 dropbox.com 沒有在網頁上核對 |

`-X` 也會丟掉 Finder 的顏色標記（`com.apple.FinderInfo`）。要保留時，對原本帶這個屬性的檔案逐一補回：`xattr -wx com.apple.FinderInfo "$(xattr -px com.apple.FinderInfo 原檔 | tr -d ' \n')" 副本`。另外，檔案經過「設為僅供線上存取」再下載之後，Finder 顏色標記本身也會消失（2026-11-14 觀察一次），所以重要的標記不要只靠 Finder 顏色保存。

複製完用 hash 比對：對來源與副本各做一份相對路徑的 `shasum -a 256` 清單，兩份要完全相同。

## 驗證到哪裡

| 行為 | 狀態 |
|---|---|
| 僅線上的檔案帶 `dataless` flag，`ls -l` 仍顯示完整大小 | 已實測（macOS 27.3、Dropbox 280.3.5020，2026-11-14） |
| 讀取檔案內容會讓 File Provider 下載它 | 已實測一次：117 個檔、約 117 MB、約 18 分鐘；當時是四個檔平行讀取，不是 `download` 子命令 |
| `local-status` 與 `download` 的輸出、結束碼、空間檢查、逾時、連續逾時就停 | 只在測試裡用替身指令驗過（`tests/test_local.sh`） |
| `local-status` 在真的 Dropbox 資料夾上，分得出本機與僅線上 | 已實測（macOS 27.3、Dropbox 280.3.5020，2026-11-14）：5 個檔設為僅供線上存取後量到 `online_only=5` |
| `download` 在真的 Dropbox 資料夾上跑 | 已實測一次（macOS 27.3、Dropbox 280.3.5020，2026-11-14）：5 個檔、200 MB，712 秒，結束碼 0；大檔第一輪 300 秒被停、第二輪 1 秒讀完；沒有留下讀取程序 |
| 連線狀態下，讀到上限時停掉真的讀取 | 已實測兩次（macOS 27.3、Dropbox 280.3.5020，2026-11-14）：`stopped after 300s`，之後沒有殘留的讀取程序 |
| 離線時 `download` 停得下來（`stopped=timeouts`） | 未驗證（只在替身測試裡驗過） |
| Finder 右鍵選單裡 Dropbox 的「設為離線存取」與「設為僅供線上存取」 | 選單文字已核對（macOS 27.3、Dropbox 280.3.5020，繁體中文介面，2026-11-14）；英文介面的文字未核對 |
| 下載後被系統回收成僅線上 | 未驗證 |
| 其他 macOS 版本、其他 Dropbox 版本 | 未驗證 |
