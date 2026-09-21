# 新增交易名稱

為所有一般、投資及股票交易加入正式的「交易名稱」。交易名稱由使用者選填；未填時由 Data API 依交易內容產生一次預設名稱並保存，作為各交易清單的主要辨識文字。

## 已確認規格

- `TRANSACTIONS` 新增持久化交易名稱欄位，不是 UI 顯示時才產生的 fallback。
- `AccountTransactionView` 與 `StockTransactionView` 的最上方皆提供「交易名稱」輸入欄位。
- 儲存前移除頭尾空白；空字串或純空白視為未填。
- 自訂名稱最多 30 個字元；UI 與 Data API 都必須拒絕超長內容，不得截斷。
- 一般及投資交易未填名稱時，依儲存當下的類型產生：「轉帳」、「收入」、「支出」、「投資買入」、「投資賣出」、「利息」或「損益調整」。
- 股票交易未填名稱時：
  - 買入：`買入 xxx n股`
  - 賣出：`賣出 xxx n股`
  - 股息：`xxx 配息`
- `xxx` 在台股（`MARKET_CODE = TW`）使用標的顯示名稱；其他市場一律使用股票代號。
- 股數使用公開 API 的實際值，保留必要小數並移除無意義尾零，例如 `10股`、`1.25股`。
- 預設名稱只在 create／update 收到空白名稱時產生並寫入。已保存名稱不因股票、帳戶、金額或股數等內容變更而自動更新；使用者再次清空並儲存時，才依原交易類型及修改後內容重新產生。
- 交易類型只在建立交易時選擇；任何一般、投資或股票交易建立後皆不可變更類型。編輯時交易類型須唯讀，Data API 也必須拒絕以 update 改變既有 `KIND`。
- 交易清單以交易名稱作為主要文字；備註仍是獨立欄位，不再代替交易名稱。
- 既有資料庫升級時直接執行 migration，依每筆既有交易內容回填預設名稱。

## 現況與範圍界線

- schema version 已升為 2，`TRANSACTIONS.NAME` 與 v1 → v2 啟動 migration 已完成。
- `PortfolioDatabase.open` 會在建表與 seed 前後的同一開啟 transaction 中完成必要 migration。
- `StockTransactionInput`、`AccountTransactionInput`、create/update/form/list API 與 CSV 備份皆受影響。
- `AccountTransactionView` 已實作，可完整加入名稱欄位。
- 目前沒有 `StockTransactionView` 實作，`StockView` 仍是占位畫面。本任務包含股票名稱的資料契約、預設值、migration、清單資料與測試；不從零建立整套股票交易 UI。未來實作該 view 時必須依本文件加入名稱欄位。
- 不改變交易金額、成本、現值、已實現／未實現損益、投影、重播、FIFO 或快照計算。
- 不因本功能主動改寫既有名稱；只有使用者清空後儲存才重新產生。

## 實作原則

- 依 `docs/testing.md` 先新增失敗測試，再實作最小修改；依本次指示不新增 migration 專用測試或保留 migration script。
- 預設名稱由 Data API 產生與驗證，不能只依賴 UI。
- 一筆經濟事件只有一份 `TRANSACTIONS.NAME`；各帳戶中的投影共用相同名稱。
- migration、create 與 update 必須原子化；失敗不得留下部分資料。
- migration 回填須依 parent transaction、subtype 與 security 關聯取得完整內容，不以備註代替名稱。
- 每階段先跑聚焦測試；最後執行 `flutter analyze`、`flutter test` 與 `git diff --check`。

## 階段任務

### 1. Schema 契約與 migration

- [x] 更新 `docs/schema.md`：在 `TRANSACTIONS` 定義 `NAME`、非空白、最多 30 個字元、正規化與預設名稱規則。
- [x] 將程式 schema version 由 1 升為 2，讓新資料庫直接建立含名稱約束的 `TRANSACTIONS`。
- [x] 建立 v1 → v2 migration：在單一 transaction 中加入欄位、回填所有既有交易、建立約束，成功後才更新 `SCHEMA_METADATA`。
- [x] 股票回填時，台股使用 `SECURITIES.NAME`，其他市場使用 `SECURITIES.SYMBOL`；買賣包含格式化股數，股息不含股數。
- [x] migration 遇到缺少 subtype/security 或無法產生合法名稱時整體回滾並回報錯誤。
- [x] 依使用者指示直接 migration Simulator 的 v1 資料庫並確認六筆既有交易名稱；不新增 migration 專用測試或保留 script。

**驗證：** `flutter test test/data/database_infrastructure_test.dart`

### 2. 公開 model、驗證與預設名稱

- [x] 在 `StockTransactionInput` 與 `AccountTransactionInput` 共通欄位加入可選 `name`，existing form decode 回傳保存名稱。
- [x] 在 `AccountTransactionItem` 加入必填名稱，使清單不需自行推測標題。
- [x] 建立單一內部正規化流程：trim、空白時產生預設名稱、超過 30 字元拋出 `DataApiException`；create/update 共用。
- [x] 一般／投資預設名稱只依當次 `TransactionKind` 產生；非空名稱保持不變。
- [x] 股票預設名稱依 market、名稱／代號、方向與實際股數產生；台股使用顯示名稱，其他市場使用代號，股數不得顯示縮放整數或多餘尾零。
- [x] update 時比對既有 `TRANSACTIONS.KIND` 與 input kind；不同時原子性拒絕，不得刪除或重建原事件，也不得改變名稱、順序、帳務或投影。
- [x] 新增 Data API 測試：名稱 trim／預設／長度拒絕、一般與股票交易改變類型被拒絕且原資料不變。

**驗證：** `flutter test test/data/general_account_transactions_test.dart test/data/manual_investment_transactions_test.dart test/data/stock_transactions_test.dart`

### Checkpoint A：資料契約

- [x] 新資料庫與已直接升級的 v1 Simulator 資料庫都保證每筆交易有合法名稱。
- [x] create/update/form/list API 可完整往返名稱。
- [x] 既有帳務重播、投影、FIFO 與回滾測試保持通過。

### 3. 寫入、清單與投影整合

- [x] 修改一般、投資與股票寫入流程，將正規化名稱與 parent transaction 原子性保存。
- [x] update 使用呼叫端名稱；只有 null／空白才依更新後內容產生新預設名稱。
- [x] `listAccountTransactions` 與 `listStockTransactions` 回傳 parent 保存名稱；同一事件的各帳戶投影因此共用名稱。
- [x] 帳戶明細交易列以 `item.name` 為主要文字；備註保留為獨立資料，不再作為標題 fallback。
- [x] routing 回歸測試確認一般與投資投影使用 parent 保存名稱並可進入同一事件；刪除與失敗回滾沿用既有原子性測試。

**驗證：** `flutter test test/data/transactions_test.dart test/ui_routing_test.dart`

### 4. AccountTransactionView

- [x] 在表單最上方加入選填「交易名稱」，最多 30 字元，並提供穩定 semantic key。
- [x] 新建時名稱保持空白並交由 Data API 生成，UI 不複製生成規則。
- [x] 編輯時載入保存名稱；改變帳戶、金額或其他可編輯內容時不自動修改名稱。
- [x] 編輯既有交易時將交易類型顯示為唯讀，不提供切換選項；新建交易時仍可選擇適用類型。
- [x] 清空名稱後儲存時傳入空值，由 Data API 依原交易類型及修改後內容重產生；再次開啟須顯示新名稱。
- [x] 超過 30 字元時顯示可恢復錯誤並保留表單；Data API 仍有第二層驗證。
- [x] 新增 widget/routing 測試：預設名稱、自訂名稱、編輯載入、清空重產生、超長拒絕，以及既有交易的類型不可切換。

**驗證：** `flutter test test/ui_routing_test.dart`

### 5. StockTransactionView 契約

- [x] 更新 `docs/specs/StockTransactionView.md`：加入名稱輸入、30 字元驗證、台股／其他市場預設格式與只在空白儲存時產生的規則。
- [x] 在 `StockTransactionView` 規格中明定新建時可選類型、編輯時類型唯讀，並由 Data API 拒絕變更既有股票交易類型。
- [x] 更新股票 Data API 文件與測試，涵蓋台股名稱、其他市場代號、整數／小數股數、股息及自訂名稱。
- [ ] 「在表單最上方加入交易名稱並完整往返 Data API」保持未完成，待 `StockTransactionView` 實作時完成；本任務不從零建立整套股票交易 UI。

**驗證：** `flutter test test/data/stock_transactions_test.dart test/data/data_api_integration_test.dart`

### 6. CSV 備份、還原與版本相容性

- [x] `TRANSACTIONS.csv` 匯出包含 `NAME`；匯入由 v2 table schema 驗證非空白與 30 字元上限。
- [x] 備份 manifest version 與資料庫 schema version 同步升至 2，不再硬編碼版本 1。
- [x] 依「只支援相容備份」規則，v2 程式明確拒絕 v1 備份，且不得改動目前資料庫。
- [ ] 新增 v2 匯出／檢查／覆蓋還原測試，確認自訂及預設名稱保持不變，破損或超長名稱備份原子性拒絕。
- [x] 更新 `docs/data_api.md` 的版本、欄位與相容性說明；`DataManagerView` 的既有「只接受相容備份」規則無需改動。

**驗證：** `flutter test test/data/backup_and_restore_test.dart`

### Checkpoint B：端到端資料流程

- [x] 建立、編輯、列出、投影、匯出與還原皆使用同一保存名稱。
- [x] migration 與備份還原不改變帳務數值或交易順序。
- [x] v1 DB 已直接升級；v1 備份依相容性規則安全拒絕。

### 7. 文件與完整驗證

- [x] 同步更新 `AGENTS.md`、`docs/schema.md`、`docs/data_api.md`、`docs/specs/AccountTransactionView.md`、`docs/specs/StockTransactionView.md`、`docs/specs/AccountDetailView.md`、`docs/specs/StockDetailView.md` 與其他受影響文件；`DataManagerView` 既有相容備份規則無需改動。
- [x] 移除既有文件中「編輯時可在同一交易族群切換類型」的舊規則，統一改為所有交易建立後類型不可變更。
- [x] 更新 `docs/testing.md`；只有已建立且通過的測試標記 `[x]`。
- [x] 執行全部聚焦測試、`flutter test`、`flutter analyze` 與 `git diff --check`。
- [ ] 以既有 `flutter attach` session hot reload，人工確認 AccountTransactionView 名稱欄位、建立後清單標題、編輯保留、清空重產生及錯誤狀態。
- [ ] 人工確認同一交易在投資帳戶與一般資金帳戶投影中顯示同一名稱。

## 完成條件

- [x] 所有新建與 migration 後的交易都有非空白且不超過 30 個字元的保存名稱。
- [x] 預設名稱只由 Data API 產生；UI、清單與備份不各自維護另一套規則。
- [x] 已保存名稱不隨交易內容自動改變，清空後儲存才重新產生。
- [x] 所有已實作交易 UI 的既有類型為唯讀，且任何繞過 UI 的 update 變更類型都會被原子性拒絕。
- [x] 一般、投資及股票 Data API 的預設格式符合已確認規則。
- [x] AccountTransactionView 與現有交易清單完成整合；StockTransactionView UI 待其畫面實作時依契約完成。
- [x] 完整測試與靜態檢查通過，且沒有改變既有帳務計算。
