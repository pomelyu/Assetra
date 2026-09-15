# 實作一般帳戶基本功能

提供所有只涉及到一般帳戶的功能，建立 AssetView, AccountManagerView, AccountDetailView, AccountTransactionView, CategoryManagerView, SettingView 的頁面

## 範圍與基礎

1. 限制本階段 UI 只處理一般帳戶；不實作股票帳戶、投資帳戶、報表、快照與行情。
2. 以應用程式文件目錄中的 `assetra.sqlite` 啟動 `PortfolioDataApi`，並注入一般帳戶相關畫面。
3. 依 `docs/prototype` 確認 Asset、設定、帳戶編輯與交易頁的版面結構。
4. 建立 Asset、設定、帳戶管理、分類管理及交易編輯入口的路由測試。
5. 任何涉及 data api 或是 database 的變更，需要經過使用者的同意

## 規格變更
- AssetView 取消「新增帳戶」的功能，此功能移到 AccountManagerView
- AssetView 的 「＋」為新增交易，對應到 AccountTransactionView
- AccountManagerView 新增「新增帳戶」的功能。對應到 AccountEditView 或 AccountEditView-invest
- AssetView, AccountTransactionView, AccountManagerView, CategoryManagerView 沒有資料時顯示「尚未建立資料」。
- account category 預設可編輯的「存款」、「投資」標籤。和不可編輯的「未分類」標籤。

## 驗證與測試
- 新增路由相關的測試並通過測試。並同步更新 `docs/testing.md`
- 其餘測試交由開發者回饋

## 階段任務

### 導覽與共通狀態

- [x] AssetView 的右下「＋」進入 AccountTransactionView；返回後回到 AssetView。
- [x] AccountManagerView 的右下「＋」進入 AccountEditView；返回後回到 AccountManagerView。
- [x] SettingView 的帳戶管理與分類管理選項分別進入 AccountManagerView 與 CategoryManagerView。
- [x] AssetView、AccountManagerView、AccountTransactionView 與 CategoryManagerView 無資料時顯示「尚未建立資料」。
- [x] 所有一般帳戶相關頁面依 `docs/prototype` 完成佈局。

### AssetView 與 AccountDetailView

- [x] AssetView 顯示資產總覽卡、分類膠囊篩選列及未封存一般帳戶清單。
- [x] AssetView 的帳戶列以原始幣別顯示成本、現值、收益與收益率。
- [x] AssetView 點選帳戶進入 AccountDetailView；返回後回到 AssetView。
- [x] AccountDetailView 顯示帳戶摘要、按日期排序的交易列表與右下新增交易 FAB。
- [x] AccountDetailView 沒有交易紀錄時，交易區塊顯示「尚未建立資料」。
- [x] AccountDetailView 點選交易進入 AccountTransactionView；返回後回到 AccountDetailView。
- [x] AccountDetailView 新增交易時。第一個顯示的帳戶會是當前的帳戶（收入的目標帳戶、支出的來源帳戶、轉帳的來源帳戶）

### AccountManagerView 與 AccountEditView

- [x] 新增一般帳戶表單可載入分類、選擇 TWD／USD／JPY／EUR，並透過 Data API 建立帳戶。
- [x] 建立帳戶後返回 AccountManagerView 並重新載入清單。
- [x] AccountManagerView 依 prototype 顯示使用中與已封存一般帳戶的清單與空狀態。
- [x] AccountEditView 依 prototype 顯示取消／儲存頂列、基本資訊、初始數值與備註分段卡片。
- [x] 支援編輯未封存一般帳戶，並正確載入期初成本、期初價值與備註。
- [x] 在帳戶管理與編輯頁提供封存；在帳戶管理頁提供重新啟用。
- [x] 封存、重新啟用或 API 驗證失敗時保留畫面狀態並顯示原因。

### CategoryManagerView

- [x] 新資料庫預設建立「未分類」、「存款」、「投資」標籤。
- [x] CategoryManagerView 顯示分類、色彩、排序與帳戶使用數。
- [x] 實作分類新增、重新命名、色彩修改與排序。
- [x] 實作刪除分類前的替代分類選擇與 API 錯誤顯示。

### AccountTransactionView

- [x] AccountTransactionView 依 prototype 完成取消／儲存頂列與圓角分段卡片。
- [x] 實作收入：選擇目標一般帳戶、日期時間、金額與備註。
- [x] 實作支出：選擇來源一般帳戶、日期時間、金額與備註。
- [x] 實作轉帳：選擇來源與目標一般帳戶、兩端實際金額、日期時間與備註。
- [x] 支援一般帳戶交易的編輯與刪除；交易完成後刷新受影響帳戶。
- [x] UI 不呈現或建立股票、投資類型交易。

### 驗證與收尾

- [x] 路由測試涵蓋 AssetView 的交易 FAB、AccountManagerView 的新增帳戶入口，以及設定頁管理入口。
- [x] 補齊一般帳戶頁面的必要路由測試並同步更新 `docs/testing.md`。
- [x] 完成後執行 `flutter analyze`、`flutter test` 與 `git diff --check`。
