# Data API 與 DB 結構草案

本文件說明已實作的 Data API 與內部模組邊界。欄位與規則以 [schema](schema.md)、[股票交易](specs/StockTransactionView.md)及[帳戶交易](specs/AccountTransactionView.md)為準；公開入口位於 `lib/data/data.dart`。

## 1. 模組與預計位置

```text
lib/
├── logic/                              # 未來的畫面狀態與操作流程
└── data/
    ├── data.dart                       # 唯一公開 import 入口，只負責 export
    ├── portfolio_data_api.dart         # 具體 class PortfolioDataApi，實作所有公開 API 方法
    ├── models/
    │   ├── money.dart                  # Money、ShareQuantity：公開實值與內部整數轉換
    │   ├── transaction_input.dart      # StockTransactionInput、AccountTransactionInput
    │   │                               # 及 StockBuyInput、AccountTransferInput 等子類
    │   ├── transaction_result.dart     # TransactionId、Preview、交易查詢結果
    │   └── ...                         # 帳戶、分類、報表、設定、備份的輸入／結果與錯誤型別
    └── src/                            # 內部實作，不由 data.dart 匯出
        ├── validation/
        │   └── transaction_validator.dart # 純函式：欄位、帳戶類型、幣別、封存狀態
        ├── ledger/
        │   └── ledger_calculator.dart  # 純函式：重播交易，推導成本、餘額與 FIFO
        ├── queries/
        │   └── portfolio_queries.dart  # 組合來源資料、帳務結果與行情，產生 view DTO
        └── database/
            ├── portfolio_database.dart # class：SQLite 連線、transaction、生命週期
            ├── schema.dart             # 建表、約束、索引、版本遷移
            └── transaction_store.dart  # 內部 SQL 讀寫與 row mapping
```

這裡的「模組」指職責，不代表全部都是 class。目前 `PortfolioDataApi` 包含 API 協調與查詢實作；SQLite schema、連線／transaction 及精確整數運算已分離至 `src/`。未來若內部程式持續增長，可在不改公開 API 的前提下再抽出 store、validator 與 query 檔案，不預先建立空的 service class。

`data.dart` 只匯出具體的 `PortfolioDataApi` 和公開資料型別，不再維護一份獨立抽象介面、另一份 SQLite API class 或獨立工廠函式檔案。穩定契約由公開方法的型別、行為說明及測試維護，不靠繼承層級達成。

Dart 的 `_` 隱私範圍是 library，不是資料夾；`src/` 是內部使用慣例，未來以依賴檢查測試禁止其他層直接 import。內部 SQL row／Map 及 DB 連線不傳出公開 API。

## 2. 哪些是 API 的實作介面？

此處「介面」是指呼叫端能使用的公開方法，不是 Dart 的 `interface class`。

| 項目 | 是否對外 API | 用途 |
|---|---|---|
| `PortfolioDataApi` 的公開方法 | 是 | 邏輯層唯一的資料操作管道，方法有實際內容，負責協調驗證、計算及讀寫 |
| `Money`、交易 input、查詢結果、`DataApiException` | 公開資料型別 | API 的參數、結果與錯誤，不直接讀寫 DB |
| `data.dart` | 只是 import 入口 | 匯出上述 class 與型別，不執行交易 |
| `PortfolioDatabase`、`TransactionStore` | 否，內部 class | 管理連線、SQLite transaction、SQL 與 row mapping |
| validator、calculator、queries | 否，內部函式模組 | 驗證與計算、組合查詢結果，不讓邏輯層繞過 API 使用 |

### 2.1 具體 class 骨架

以下只示意公開 class 的形狀；正式實作位於同名 Dart 檔案，沒有 `UnimplementedError`。

```dart
// 預計：lib/data/portfolio_data_api.dart
class PortfolioDataApi {
  final PortfolioDatabase _database;

  // 私有建構子，外部不需要知道 PortfolioDatabase。
  PortfolioDataApi._(PortfolioDatabase database) : _database = database;

  // 普通 static 非同步方法，不是 Dart factory constructor。
  static Future<PortfolioDataApi> open({required String databasePath}) async {
    // 開啟 SQLite、完成必要的 schema migration，再建立 API。
    final database = await PortfolioDatabase.open(databasePath);
    return PortfolioDataApi._(database);
  }

  Future<TransactionId> createStockTransaction(
    StockTransactionInput input,
  ) async {
    // 在同一 DB transaction 中讀取、驗證、計算及寫入；commit 後回傳結果。
    throw UnimplementedError('文件骨架：股票交易儲存');
  }

  Future<TransactionId> createAccountTransaction(
    AccountTransactionInput input,
  ) async {
    // 一筆主表＋一筆帳戶交易明細，失敗完整回滾。
    throw UnimplementedError('文件骨架：帳戶交易儲存');
  }

  Future<AccountDetail> getAccountDetail(String accountId) async {
    // 查詢當下的帳戶資料並回傳一次，不建立持續訂閱。
    throw UnimplementedError('文件骨架：帳戶資料查詢');
  }

  Future<void> close() async {
    // 正式實作須先處理待完成操作，再關閉底層 DB。
    throw UnimplementedError('文件骨架：釋放資源');
  }
}
```

應用初始化時呼叫一次並共用，不是每次交易建立一個 API：

```dart
import 'package:assetra/data/data.dart';

final api = await PortfolioDataApi.open(databasePath: path);
// 將 api 傳給需要資料的邏輯層；無須 DI 框架。
// 擁有此實例的初始化程式／測試在不再使用時呼叫 await api.close()。
```

`open` 保留非同步初始化的必要工作，但歸在同一個 class，不另外增加工廠 class 或檔案。一般資料操作只接受業務 input，不接受 SQL 或 DB 物件。

### 2.2 畫面重新載入時機

- 開啟明細／總覽頁時呼叫一次對應 get/list 方法。
- 新增、修改、刪除等操作成功後，返回來源頁並重新查詢；失敗保留表單及既有資料。
- 其他受影響頁面在下次進入或返回時重新查詢，不依賴長期保留的舊結果。
- 手動／自動行情更新或備份還原完成後，由協調該操作的邏輯層重新載入目前受影響畫面；不是 DB 推播。
- 資料 API 不持有畫面或回呼，不自行導航。畫面內部仍可用 Flutter 的狀態管理呈現查詢結果，與資料 API 是否使用 Stream 無關。

```dart
// 畫面進入或返回時，由邏輯層執行。
final detail = await api.getAccountDetail(accountB);
// 將 detail 放入畫面狀態。
```

### 2.3 公開方法清單

下列全是 `PortfolioDataApi` 預計實作的公開方法，不另外建立同名抽象宣告。完整參數、回傳型別及規則以 [schema 的 Data API](docs/schema.md#data-api) 為準；本表按功能分組，不表示還要分成多個 API class。

| 功能 | 公開方法 |
|---|---|
| 初始化／釋放 | `PortfolioDataApi.open`、`close`（資源生命週期，不是 view 業務操作） |
| 股票總覽／明細 | `getStockOverview`、`listStockPositions`、`getStockDetail`、`listStockTransactions` |
| 股票交易 | `getStockTransactionForm`、`searchSecurities`、`resolveSecurity`、`createStockTransaction`、`updateStockTransaction`、`deleteStockTransaction` |
| 帳戶總覽／明細 | `getAssetOverview`、`listAssetAccounts`、`getAccountDetail`、`listAccountTransactions` |
| 一般／投資交易 | `getAccountTransactionForm`、`createAccountTransaction`、`updateAccountTransaction`、`deleteAccountTransaction` |
| 可選交易估算 | `previewStockTransaction`、`previewAccountTransaction`；不寫入，不是 create/update 的必要前置操作 |
| 帳戶編輯／管理 | `getAccountEditor`（含原始期初成本、期初價值與備註）、`createAccount`、`updateAccount`、`getInvestmentAccountEditor`、`createInvestmentAccount`、`updateInvestmentAccount`、`listManagedAccounts`、`archiveAccount`、`reactivateAccount` |
| 分類 | `listCategories`、`createCategory`、`updateCategory`、`reorderCategories`、`deleteCategory` |
| 報表 | `getCurrentAllocation`、`getCurrentCostValueComparison`、`getHistoricalTrend` |
| 設定 | `getAppSettings`、`updateAppSettings`、`setBiometricLockEnabled` |
| 行情 | `refreshMarketData` |
| 備份 | `exportBackup`、`inspectBackup`、`replaceFromBackup` |

所有資料操作皆回傳 Future，一次呼叫只取得一次結果；不使用 watch、Stream、訂閱或資料變更通知。create 成功回傳 ID，失敗拋出 `DataApiException`；不另外以 true／false 隱藏失敗原因。不能將相同 create 呼叫視為可安全自動重試：第一版由畫面防止重複提交，API 未承諾 idempotency key。

`StockBuyInput` 與 `AccountTransferInput` 是不可變輸入 class，分別屬於兩種交易輸入的 sealed class 家族。股息、轉帳等輸入不提供不適用的 fee 欄位。公開 API 中 `Money.units` 是實際幣別金額，`ShareQuantity.units` 是實際股數；呼叫端不接觸資料庫倍率。Data API 寫入時才將金額、匯率及股數轉為 schema 規定的整數，讀出時還原為實際數值。

## 3. 案例一：A 使用 B 的資金買入台積電

前提：A 是 TWD 股票帳戶，預設資金來源為 B；B 是 TWD 一般帳戶，兩者未封存。台積電標的已存在（市場 TW、代號 2330、幣別 TWD）。A、B、security2330 都是實際 UUID 的示意別名。以下日期僅為範例。

```dart
// 使用者填完表單按「確定」後才執行以下程式。
// 未來 logic 層；只 import package:assetra/data/data.dart
final input = StockBuyInput(
  occurredAt: '2026-09-11 10:00', // 台北時間，精度到分
  securityId: security2330,
  stockAccountId: accountA,
  fundingAccountId: accountB,
  quantity: ShareQuantity(units: 10), // 呼叫端直接輸入 10 股
  unitPrice: Money(currencyCode: 'TWD', units: 2412),
  fee: Money(currencyCode: 'TWD', units: 10),
);

try {
  final transactionId = await api.createStockTransaction(input);
  // 成功：返回上一頁並顯示儲存完成。
} on DataApiException catch (error) {
  // 失敗：保留表單並顯示原因。
}
```

模組協作：

1. `PortfolioDataApi.createStockTransaction` 接收輸入，透過內部 `PortfolioDatabase` 開啟 DB transaction；中間沒有另一個抽象介面或 API 實作 class。
2. `TransactionStore` 在同一 transaction 中讀取 A、B、標的及受影響交易歷史。
3. `transaction_validator.dart` 驗證 A 為 STOCK、B 為 GENERAL，相關幣別皆為 TWD、帳戶可用，股數／價格為正且費用非負。
4. `ledger_calculator.dart` 將候選事件加入歷史重播，得到新增持股 10 股、成本 24,130 元、B 扣款 24,130 元，並驗證後續事件仍有效。
5. `TransactionStore` 寫入一筆主表及一筆股票明細；DB commit 後 API 才回傳交易 ID，呼叫端得知儲存成功。
6. 呼叫端返回明細頁後主動呼叫 `getAccountDetail`；內部 `portfolio_queries.dart` 組成並回傳當下的帳戶／持股摘要。

新增資料（只列使用欄位；NOTE 未填則為 null）：

| Table | 欄位與範例值 |
|---|---|
| TRANSACTIONS | ID = t1、KIND = STOCK_BUY、OCCURRED_AT = 2026-09-11 10:00、ENTRY_ORDER = 系統分配的新增順序、UPDATED_AT = 寫入時 UTC 時間 |
| STOCK_TRANSACTIONS | TRANSACTION_ID = t1、SECURITY_ID = security2330、STOCK_ACCOUNT_ID = A、FUNDING_ACCOUNT_ID = B、QUANTITY = 100000（10 股的 DB 內部值）、UNIT_PRICE = 2412、FEE = 10 |

結果：A 的持股成本增加 **TWD 24,130**；B 的成本及現值各減少 **TWD 24,130**，允許變成負數。不另外建立 B 的支出事件，也不更新 ACCOUNTS 的初始值或存入衍生餘額。

A 的持股現值依最新成功行情推導，不能把成交價自動當成目前報價。若報價恰為 2,412 元，這次新增部位的現值是 24,120 元、未實現損益為 -10 元；沒有報價時需明確呈現缺少行情，而非宣稱此估值已成立。FIFO 批次由交易推導，不新增持倉資料表。

## 4. 案例二：美元帳戶 C 轉帳到 B

前提：C 是 USD 一般帳戶，B 仍為 TWD 一般帳戶，兩者未封存且不同帳戶。使用者尚未指定金額；以下**僅示範 C 實扣 USD 100.00、B 實收 TWD 3,200**，不是要求程式以匯率推算收款。

```dart
// 使用者按「確定」後，從表單建立 input。
final input = AccountTransferInput(
  occurredAt: '2026-09-11 10:00', // 台北時間，精度到分
  sourceAccountId: accountC,
  targetAccountId: accountB,
  sourceAmount: Money(currencyCode: 'USD', units: 100),
  targetAmount: Money(currencyCode: 'TWD', units: 3200),
);

try {
  final transactionId = await api.createAccountTransaction(input);
  // 成功：返回上一頁。
} on DataApiException catch (error) {
  // 失敗：保留表單並顯示原因。
}
```

使用同一組內部模組：`PortfolioDataApi.createAccountTransaction` 開啟 transaction → Store 讀取帳戶／歷史 → validator 確認兩端為 GENERAL、金額為正且幣別與各帳戶一致 → calculator 推導兩端效果 → Store 寫入主表與帳戶明細 → commit 並回傳成功 → 呼叫端主動查詢 → Query 回傳最新摘要。外部只呼叫第一個方法，其他步驟都是內部實作。

| Table | 欄位與範例值 |
|---|---|
| TRANSACTIONS | ID = t2、KIND = ACCOUNT_TRANSFER、OCCURRED_AT = 2026-09-11 10:00、ENTRY_ORDER = 系統分配的新增順序、UPDATED_AT = 寫入時 UTC 時間 |
| ACCOUNT_TRANSACTIONS | TRANSACTION_ID = t2、SOURCE_ACCOUNT_ID = C、TARGET_ACCOUNT_ID = B、SOURCE_AMOUNT = 10000、TARGET_AMOUNT = 3200 |

結果：C 的成本及現值各減少 **USD 100.00**；B 的成本及現值各增加 **TWD 3,200**。不儲存 FEE 或交易匯率、不呼叫行情供應商，也不另外產生收入／支出事件。若接續案例一，B 的合計變動為 **TWD -20,930**；原有初始值及其他交易不受影響。

## 5. 共通邊界與後續 TDD

- 預覽是選擇性的畫面估算，不是儲存前置步驟；API 不保存表單，也不靠 preview 傳遞輸入。使用者按確定後建立 input，直接呼叫 create/update。預覽和儲存共用純驗證／計算；預覽不寫入，儲存時在 DB transaction 內重新讀取並驗證，不信任先前預覽仍有效。
- 讀取、歷史驗證及主／明細寫入必須處於同一原子操作；失敗全部回滾，不能留下半筆事件，成功提交後才回傳成功，由呼叫端主動重新查詢。
- 買股和轉帳是兩筆獨立經濟事件，各自原子提交；這兩個案例不代表一個必須共同成功的大交易。
- 交易採台北時間（Asia/Taipei）、精度到分，不接受未來時間；同分鐘依 ENTRY_ORDER 新增順序計算，編輯保留此值。日期範例只適用於該時間已發生時。
- 金額及分攤成本四捨五入至幣別最小單位；完整賣出吸收成本尾差。一般／投資帳戶可改初始值，但須重播全部受影響歷史，失敗回滾；股票初始值固定零。
- 涉及封存帳戶的交易禁止新增、修改與刪除；有封存帳戶使用的分類不能刪除。封存日期按 UTC UPDATED_AT 換算台北日期，當天起歷史貢獻為零；重新啟用後視為從未封存。
- 週快照使用 ACCOUNT_WEEKLY_SNAPSHOTS，保存 SNAPSHOT_DATE 與衍生 WEEK_START_DATE，按每帳戶／週起日唯一；台北時間週一至週日，當週首次成功估值各自建立，缺值或更新失敗不建立，不阻擋其他帳戶。
- 歷史取各帳戶指定日期以前最近快照，無則零；「現在」從目前帳戶總和計算，缺行情則標示估值未齊全，不使用最後快照代替。
- 週快照不因這兩筆交易或後續編修而覆寫。備份、行情更新與週快照模組不在本次骨架展開。
- 預計測試位置：`test/data/ledger/` 測計算；`test/data/api/` 使用測試 SQLite 驗證公開契約、重開後持久化及失敗回滾；`test/architecture/` 檢查 import 邊界。
- 正式實作先寫失敗測試：買入成本／B 扣款皆為 24,130、跨幣別轉帳保存兩端實額、錯誤帳戶／幣別拒絕、明細寫入失敗不留主表、預覽不落 DB。再逐項補實作；本文件不宣稱已有可執行測試。
