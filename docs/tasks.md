# 股票帳戶完整功能

完成股票帳戶從代號目錄同步、行情更新、股票總覽／明細到買入、賣出及股息交易的完整流程。本階段不處理 `ReportView`、`GraphView` 或任何 snapshot 的建立、更新、查詢與測試。

## 已確認規格

- 參考 `/Users/cychien/Documents/Workspace/StockBook` 的資料來源、抓取及解析規則，改寫成 Assetra 可在 Dart／Flutter 內使用的實作，不依賴 StockBook 的 Python backend。
- 股票代號目錄來源為 TWSE Open API `t187ap03_L`、TPEX Open API `mopsfin_t187ap03_O`、NASDAQ Trader `nasdaqlisted.txt` 與 `otherlisted.txt`。
- 台股以交易所中文簡稱顯示，並保存 Yahoo Finance 所需的 `.TW`／`.TWO` quote symbol；美股以股票代號顯示，目錄名稱仍可保存供搜尋。
- `SettingView` 直接新增獨立股票資料區塊與「更新股票代號」按鈕；`DataManagerView` 維持只處理備份／還原。
- 代號同步採 upsert：新增代號、更新既有名稱及 quote symbol。同步結果不再出現的證券不得刪除；標記為不可用於新交易，日後再次出現則恢復可用。
- 只有完整成功取得的市場來源才能用來判定該來源中哪些既有證券已停用；單一來源失敗不得誤停用既有資料，其餘成功來源仍可局部提交。
- 尚未成功同步過股票代號時，`StockTransactionView` 不允許新增交易；股票下拉選單沒有可新增選項，顯示「無符合股票」並引導到 `SettingView`。
- 新增交易只能選擇目前可交易的證券；編輯既有交易仍須載入已停用證券，但不可改選另一個停用證券。
- `StockView` 的同步按鈕更新所有曾有買入或賣出交易的證券行情；零持股及只存在於封存股票帳戶的證券仍納入。只有股息、從未買賣的證券不納入。
- 行情同步使用 Yahoo Finance 相容代號；成功項目覆寫最後價格與時間，失敗項目保留最後成功資料。部分成功必須保存成功項目並回報失敗清單。
- 股票帳戶建立／編輯沿用 `AccountEditView-invest`：必須指定同幣別、未封存的一般資金來源；帳戶建立後不可變更類型，有財務歷史時不可變更幣別。
- `StockTransactionView` 支援買入、賣出及股息；建立後不可改變交易類型，交易名稱、FIFO、費用、資金帳戶投影及封存限制沿用既有 schema／spec。
- 股票或交易類型變更時，帳戶下拉選單只顯示可完成該交易的帳戶；沒有符合的股票帳戶或資金來源時欄位 disabled 並顯示「無符合帳戶」。
- loading、empty、error 與 stale data 必須明確且可恢復；同步期間不得清空現有目錄、行情、部位或歷史。

## 現況與範圍界線

- 已有股票帳戶 schema、買入／賣出／股息 Data API、FIFO、資金帳戶投影、股票總覽／明細 query 與資料層測試基礎。
- `StockView` 仍是占位畫面；`StockDetailView` 與 `StockTransactionView` 尚未實作 UI。
- `SECURITIES` 尚無可交易狀態；既有 `resolveSecurity` 允許任意建立證券，需收斂為同步目錄主導的新交易流程。
- `refreshMarketData` 目前只有可注入 callback 契約，尚無正式網路 provider；`STOCK_PRICES` 已能保存最後成功價格。
- 股票帳戶建立／編輯已與投資帳戶共用畫面及 API；只補股票流程必要差異與回歸驗證，不重寫一般／投資帳戶功能。
- 不修改 `ReportView`，不新增 `GraphView`，不呼叫或修改週快照邏輯，也不新增 snapshot 測試。

## 實作原則

- 依 `docs/testing.md`，帳務或資料行為先寫失敗測試，再做最小實作；只把確實通過的測試項目標記 `[x]`。
- 網路抓取、解析與 SQLite 寫入分層；Data API 不依賴 widget，UI 不解析供應商 payload。
- 外部 HTTP client／provider 必須可注入，以 fixture 測試解析、部分失敗、timeout 與 stale-data 行為；測試不得依賴即時網路。
- 目錄同步、行情同步與交易寫入各自維持清楚的原子邊界，失敗不得留下半筆交易或清空最後成功資料。
- 每個垂直切片先跑聚焦測試；最後執行 `flutter analyze`、`flutter test` 與 `git diff --check`。
- Flutter UI 前先 `flutter attach`；若失敗立即停止 UI 驗證並回報。修改後使用 hot reload，必要時才 hot restart。

## 階段任務

### 1. 股票目錄狀態與 migration

- [x] 先新增 schema／Data API 失敗測試，定義可交易狀態、來源識別、同步結果及停用後歷史仍可讀取。
- [x] 擴充 `SECURITIES`，區分可供新交易選擇與已停用證券；保留 stable ID、交易、最後行情及名稱。
- [x] 實作 schema v2 → v3 migration；既有證券預設保持可用，備份 schema version 與 CSV 欄位同步升版。
- [x] 新資料庫直接建立新版 schema；migration／還原不得破壞交易名稱或帳務資料。
- [x] 更新 domain model，讓 `SecurityOption`、既有交易 form 與同步結果表達 active／inactive、來源及顯示文字。

**驗證：** `flutter test test/data/database_infrastructure_test.dart test/data/backup_and_restore_test.dart test/data/stock_transactions_test.dart`

### 2. 代號目錄同步 Data API

- [x] 建立可注入 HTTP catalog provider，解析四個來源；忽略空代號、測試股票、檔尾 metadata 與 malformed rows，正規化 market、symbol、quote symbol、currency、display name。
- [x] 台股上市保存 `SYMBOL = 公司代號`、`NAME = 公司簡稱`、`QUOTE_SYMBOL = 代號.TW`；上櫃使用 `.TWO`。美股 symbol 正規化為大寫，交易畫面顯示 symbol。
- [x] 在 `PortfolioDataApi` 加入目錄同步方法與結果 DTO，回報各來源成功／失敗、新增、更新、停用、恢復數量及最後成功時間。
- [x] 同步採按來源安全 upsert；只有來源完整成功時才停用缺席證券，來源失敗時保留其舊資料。重複代號須有確定且可測試的去重規則。
- [x] 移除新交易任意 `resolveSecurity` 建立未知證券的路徑；新交易與搜尋只接受 active 證券，既有 inactive 證券仍可依 ID 解碼。（`resolveSecurity` 僅保留給匯入／測試資料，不供交易表單使用。）
- [x] 新增 fixture 測試：四來源解析、中文名稱、`.TW`／`.TWO`、測試代號排除、重複資料、名稱更新、停用、恢復、全失敗與部分失敗。

**驗證：** `flutter test test/data/stock_catalog_sync_test.dart test/data/stock_transactions_test.dart test/data/data_api_integration_test.dart`

### Checkpoint A：股票目錄

- [x] 新資料庫及 v2 migration 後皆可保存證券可交易狀態。
- [x] 任一來源失敗不會清空或誤停用該來源既有證券。
- [x] 未同步目錄時不能新增股票交易，既有交易仍可完整讀取。

### 3. 追蹤集合與行情同步 Data API

- [x] 先新增資料測試，定義 tracked securities 為至少有一筆買入或賣出的 security；包含零持股、停用證券及封存股票帳戶，排除僅有股息者。
- [x] 建立可注入 Yahoo Finance quote provider，依 `QUOTE_SYMBOL` 批次取得最新價格及 quote time；批次與解析規則參考 StockBook 的 yfinance 行為。
- [x] 將正式 provider 接到 `refreshMarketData`；只更新 tracked securities，並保留既有匯率更新契約。
- [x] 成功時更新 `STOCK_PRICES`；缺值、非正值、錯誤或 timeout 不覆寫最後成功資料。
- [x] 回傳成功數及逐項失敗資訊；部分成功提交成功項目，全部失敗仍可使用 stale data。
- [x] 測試持有中、已結清、封存帳戶、僅股息、inactive security、部分／全部失敗及重試成功。

**驗證：** `flutter test test/data/market_data_refresh_test.dart test/data/data_api_integration_test.dart test/data/stock_transactions_test.dart`

### 4. 股票帳戶建立與編輯整合

- [x] 補 routing 測試，確認 `AccountManagerView` 進入 `AccountEditView-invest` 的股票模式。
- [x] 新建股票帳戶的初始成本／現值固定為 0；資金來源只列同幣別、未封存的一般帳戶。
- [x] 無符合資金來源時下拉選單 disabled 並顯示「無符合帳戶」，不可儲存。
- [x] 編輯時類型唯讀；有財務歷史時幣別唯讀。封存帳戶不可編輯，變更預設資金來源不改寫既有交易。
- [x] 回歸驗證新增、編輯、封存、重新啟用及仍被依賴時禁止封存。

**驗證：** `flutter test test/data/accounts_test.dart test/ui_routing_test.dart`

### 5. StockTransactionView 垂直切片

- [x] 建立 view 與 routing；可從 `StockView`、`StockDetailView`、股票 `AccountDetailView` 新增，並從股票事件編輯同一 transaction。
- [x] 表單最上方加入選填交易名稱，並實作股票、類型、台北日期時間、股票帳戶、資金來源、備註及依類型切換欄位。
- [x] 新建只能選 active securities；未同步或無結果時股票欄位 disabled、顯示「無符合股票」，並提供前往 `SettingView` 的操作。
- [x] 編輯載入保存名稱及原 security；類型唯讀。inactive security 顯示停用狀態並允許其他合法修改，但不出現在改選清單。
- [x] 股票或類型變更後，股票帳戶只列可執行交易且幣別相符的未封存帳戶；資金來源只列同幣別未封存一般帳戶。無選項時 disabled 並顯示「無符合帳戶」。
- [x] 買入／賣出顯示股數、單價與合併費用；股息只顯示股息金額。選擇股票帳戶後預填其預設資金來源。
- [x] 建立、修改、刪除呼叫既有 Data API；成功返回並重新載入，失敗保留表單，送出中防止重複提交。
- [x] widget/routing 測試只驗證入口、預填、欄位切換、disabled／empty、類型唯讀及成功返回，不測具體位置。

**驗證：** `flutter test test/data/stock_transactions_test.dart test/ui_routing_test.dart`

### Checkpoint B：可完成股票交易

- [x] 股票帳戶可建立，且只有合法資金來源可選。
- [x] 目錄同步後可完成買入、賣出及股息；兩個帳戶的投影、FIFO 與交易名稱一致。
- [x] 未同步、無相符帳戶、超賣、封存帳戶及 provider error 不留下部分寫入。

### 6. StockView 總覽與行情同步

- [x] 以 `getStockOverview`／`listStockPositions` 實作 loading、empty、error、stale data；empty 提供新增交易入口。
- [x] 顯示持有中股票的 TWD 總成本、總現值、未實現損益與報酬率；缺行情／匯率時標示估值未齊全。
- [x] 股票列顯示台股中文名稱、美股代號，以及市場、成本、現值、未實現損益與報酬率；跨帳戶依 spec 合併。
- [x] 實作市場與未封存股票帳戶篩選，摘要與篩選清單一致；已結清區塊預設收合並保留累計已實現損益。
- [x] 同步按鈕呼叫 `refreshMarketData`；同步中保留資料並防止重複送出，完成後顯示時間、成功數與非阻斷式失敗。
- [x] 點選股票進入 `StockDetailView`；新增交易預填帳戶篩選，返回後保留篩選脈絡並重新查詢。
- [x] 測試空狀態、持有／結清入口、篩選、同步成功／部分失敗及 stale data。

**驗證：** `flutter test test/data/data_api_integration_test.dart test/ui_routing_test.dart test/ui_smoke_test.dart`

### 7. StockDetailView 明細與歷史

- [x] 以 `getStockDetail`／`listStockTransactions` 顯示名稱／代號、行情時間、股數、FIFO 成本、現值、未實現損益、賣出已實現損益及股息。
- [x] 顯示買入、賣出、股息歷史；交易名稱為主標題，依台北日期分組、按完整時間與 entry order 倒序。
- [x] 實作股票帳戶與事件類型篩選；篩選只影響呈現。
- [x] 點選事件進入 `StockTransactionView`；新增預填 security 與帳戶。涉及封存帳戶的事件只可瀏覽。
- [x] 已結清股票仍可開啟完整歷史；尚無報價時保留成本與歷史並明確標示。
- [x] 測試持有中、已結清、缺行情、封存事件及返回 `StockView`。

**驗證：** `flutter test test/data/stock_transactions_test.dart test/ui_routing_test.dart`

### 8. SettingView 股票代號更新

- [x] 直接新增「股票資料」區塊及「更新股票代號」按鈕，不導向或修改 `DataManagerView`。
- [x] 顯示同步進度並防止重複提交；完成後顯示新增、更新、停用、恢復、來源失敗摘要與最後成功時間。
- [x] 全部或部分來源失敗時保留既有目錄並提供重試；成功來源結果仍保存。
- [x] 從交易表單 empty state 導向 SettingView 時，能辨識並說明更新入口。
- [x] 測試同步成功、部分／全部失敗、重試及從交易表單導向。

**驗證：** `flutter test test/ui_routing_test.dart`

### Checkpoint C：端到端股票流程

- [ ] SettingView 更新代號 → 建立股票帳戶 → 買入 → StockView 同步行情 → StockDetailView 查看 → 編輯／刪除交易可完整走通。
- [x] 零持股、封存帳戶及 inactive security 的行情與歷史符合規格。
- [x] 台股全流程使用中文名稱，美股主要顯示股票代號。

### 9. 文件、備份與完整驗證

- [x] 同步更新 `AGENTS.md`、`docs/schema.md`、`docs/data_api.md`、`docs/testing.md`、`SettingView.md`、`StockView.md`、`StockDetailView.md`、`StockTransactionView.md` 及受影響帳戶規格。
- [x] 更新 v3 CSV 匯出／檢查／覆蓋還原測試，確認 security 狀態、quote symbol、行情與交易關聯完整保留；不新增 snapshot 測試。
- [x] 執行全部聚焦測試、`flutter test`、`flutter analyze` 與 `git diff --check`。
- [ ] 使用既有 `flutter attach` session hot reload，人工驗證目錄同步、股票帳戶、三種交易、總覽、明細、篩選、缺行情、部分失敗及 stale data。
- [x] 確認 diff 沒有修改 `ReportView`、新增 `GraphView`，或改動 snapshot 建立／更新／查詢邏輯。

## 完成條件

- [x] SettingView 可同步目前台股上市／上櫃及美股 NASDAQ／NYSE／AMEX 代號，台股顯示中文名稱。
- [x] 下市證券不刪除歷史，不能用於新交易，再次出現時可恢復使用。
- [x] 未同步代號時無法新增股票交易；既有交易及 inactive securities 仍可瀏覽與合法編輯。
- [x] 股票帳戶及買入、賣出、股息可從指定入口建立、查看、編輯與刪除，帳戶選單只提供合法選項。
- [x] StockView 只同步曾有買賣的 securities，包含零持股及封存帳戶歷史，排除僅股息者；失敗不清除最後行情。
- [x] StockView／StockDetailView 的成本、現值、FIFO、損益及資金帳戶投影符合既有 schema 與測試。
- [x] loading、empty、error、partial failure 與 stale data 均可辨識、可重試且不造成資料遺失。
- [x] 所有測試與靜態檢查通過；`ReportView`、`GraphView` 與 snapshot 未納入此次實作。
