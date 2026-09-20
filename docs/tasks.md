# 實作投資帳戶相關功能

完成手動投資帳戶（`INVESTMENT`）的端到端 UI 流程，包含帳戶建立與管理、資產總覽、帳戶明細，以及買入、賣出、利息與損益調整交易。

## 範圍與基礎

1. 本階段實作一般帳戶（`GENERAL`）與投資帳戶（`INVESTMENT`）共存的 UI 流程，不開放股票帳戶（`STOCK`）的建立或交易入口。
2. 沿用現有 `PortfolioDataApi`、SQLite schema 與投資交易計算規則；若實作時發現必須變更 Data API 或資料庫，應先停止並取得使用者同意。
3. UI 依 `docs/prototype`、`docs/schema.md` 與各 view spec 實作；若 prototype 與 schema 或 spec 衝突，以 schema 與 spec 為準。
4. 一般帳戶既有功能必須保持可用，不得因加入投資帳戶而改變現有帳務語意或 routing。
5. 帳目相關行為依 `docs/testing.md` 與現有 data tests 驗證；UI 只新增 routing 與必要的狀態測試，不測試元件的具體位置。

## 已確認的產品規則

- AccountManagerView 新增帳戶時，本階段只提供「一般帳戶」與「投資帳戶」；不顯示股票帳戶選項。
- 從 AssetView 的「＋」進入 AccountTransactionView 時，可選一般與投資的全部交易類型。
- 從一般帳戶詳情新增交易時，只顯示收入、支出與轉帳；從投資帳戶詳情新增交易時，只顯示買入、賣出、利息與損益調整，並預填目前投資帳戶。
- 交易類型變更時，各帳戶下拉選單只能顯示該類型允許的帳戶；原選值若不再有效必須清除。
- 投資買入、賣出與利息先依投資帳戶幣別，篩選同幣別、未封存的一般帳戶，並預設選中該投資帳戶的 `FUNDING_ACCOUNT_ID`；使用者可改選其他符合條件的一般帳戶。
- 損益調整不顯示一般資金帳戶。
- 建立新投資帳戶時，改選幣別必須立即重新篩選資金來源，並清除不相容選值。若無符合帳戶，資金來源下拉選單停用並顯示「無符合帳戶」。
- 投資買入、賣出與利息在一般資金帳戶中顯示對應現金流投影；兩個 view 共用同一交易 ID，編輯或刪除會同步更新兩端。
- 編輯既有交易時可變更為同一族群的其他類型；一般交易與投資交易不可互相轉換。

## 明確不在本次範圍

- 估值快照（snapshot）的建立、更新、查詢或測試。
- ReportView 的 graph view、趨勢圖、配置圖或其他報表視覺化。
- 股票帳戶的建立、編輯、明細、交易或行情。
- 帳戶建立後的幣別變更；這是後續會影響多份 spec 的獨立任務，本次不修改相關規格或行為。
- 在投資帳戶表單中嵌套新增一般帳戶流程。

## 驗證與測試原則

- 實作帳務行為前，先對照 `docs/testing.md`；若未有測試則先建立失敗的單元測試，通過後同步勾選。
- UI 測試聚焦 routing、入口可用性、表單初始狀態及切換後的可用帳戶；不斷言元件具體座標或排版細節。
- 每個階段先執行相關聚焦測試，最後執行 `flutter analyze`、`flutter test` 與 `git diff --check`。
- Flutter UI 修改期間依 `Agents.md` 使用 `flutter attach` 與 hot reload；若 attach 失敗立即停止並回報。

## 階段任務

### 1. 基礎契約與現況驗證

- [x] 對照 `docs/schema.md`、`docs/data_api.md` 與現有 data tests，確認建立／編輯投資帳戶、四種投資交易、交易投影與重播驗證的 Data API 可直接使用。
- [x] 依 `codegraph` 確認 AccountManagerView、AccountEditView、AccountTransactionView、AssetView、AccountDetailView 與 `PortfolioDataApi` 的依賴路徑，並記錄必須修改的最小檔案範圍。
- [x] 若現有 Data API 無法支援已確認行為，停止實作並向使用者說明需要變更的 API／schema，不自行擴張資料層範圍。

### 2. AccountManagerView 與帳戶類型分流

- [x] AccountManagerView 清單顯示一般與投資帳戶的名稱、類型、分類、幣別、狀態，以及投資帳戶的預設資金來源。
- [x] 新增帳戶流程只提供一般與投資帳戶；一般帳戶使用 AccountEditView，投資帳戶使用 AccountEditView-invest，不顯示股票帳戶選項。
- [x] 點選未封存投資帳戶進入 AccountEditView-invest；封存與重新啟用行為沿用現有帳戶管理規則。
- [x] 建立、編輯、封存或重新啟用完成後，返回 AccountManagerView 並重新載入清單；失敗時保留當前畫面並顯示原因。

### 3. AccountEditView-invest

- [x] 建立投資帳戶時可輸入名稱、分類、幣別、初始成本、初始價值、資金來源與備註，並透過現有 Data API 建立 `INVESTMENT` 帳戶。
- [x] 新建表單改選幣別時，只列出同幣別、未封存的一般帳戶，並清除已不相容的資金來源選值。
- [x] 無符合的資金來源時，下拉選單為 disabled 並顯示「無符合帳戶」，且不能儲存投資帳戶。
- [x] 編輯未封存投資帳戶時載入已保存的名稱、分類、幣別、初始成本、初始價值、預設資金來源與備註；帳戶類型維持唯讀。
- [x] 編輯初始值或預設資金來源時，沿用現有全歷史重播與驗證規則；無效修改整筆拒絕並保留表單。

### 4. AssetView 與 AccountDetailView

- [x] AssetView 同時顯示未封存的一般與投資帳戶，投資帳戶列以原始幣別顯示成本、現值、收益與收益率，不重複計入資金帳戶投影。
- [x] 點選投資帳戶進入 AccountDetailView，顯示投資帳戶摘要、已實現／未實現損益與依日期排序的投資交易。
- [x] 投資帳戶詳情的新增交易入口進入 AccountTransactionView，只提供買入、賣出、利息與損益調整，並預填目前投資帳戶。
- [x] 一般資金帳戶的明細會顯示投資買入、賣出與利息的現金流投影；點選投影進入同一交易 ID 的 AccountTransactionView。
- [x] 損益調整只顯示在投資帳戶明細，不在一般帳戶建立現金流投影。
- [x] 投資帳戶明細的編輯帳戶入口進入 AccountEditView-invest；封存期間保持只讀且不提供新增交易。

### 5. AccountTransactionView 的類型與候選帳戶

- [x] 交易類型加入投資買入、賣出、利息與損益調整；從 AssetView 進入時同時提供三種一般交易與四種投資交易。
- [x] 從帳戶詳情進入時，交易類型清單依帳戶類型限制；編輯既有交易時只能在原交易族群內變更類型。
- [x] 切換交易類型時重建對應的帳戶候選清單，並清除不再符合帳戶類型、封存狀態或幣別條件的選值。
- [x] 投資買入、賣出與利息的投資帳戶下拉選單只列出未封存的 `INVESTMENT` 帳戶；資金帳戶只列出同幣別、未封存的 `GENERAL` 帳戶。
- [x] 選定投資帳戶後，買入、賣出與利息預設帶入該帳戶的 `FUNDING_ACCOUNT_ID`；使用者可改選其他符合條件的一般帳戶。
- [x] 損益調整只顯示投資帳戶與調整金額，不顯示資金帳戶或費用欄位。
- [x] 無任何適用帳戶時顯示「尚未建立資料」；只缺少某一必要候選集時，對應下拉選單 disabled 並顯示「無符合帳戶」。

### 6. 四種投資交易表單

- [x] 實作買入：投資帳戶、扣款一般帳戶、日期時間、`AMOUNT`、`FEE` 與備註。
- [x] 實作賣出：投資帳戶、入款一般帳戶、日期時間、`AMOUNT`、`FEE` 與備註。
- [x] 實作利息：投資帳戶、入款一般帳戶、日期時間、`AMOUNT` 與備註。
- [x] 實作損益調整：投資帳戶、日期時間、調整到輸入金額，或是可正可負的 `VALUE_ADJUSTMENT` 與備註；不顯示資金帳戶或費用欄位。
- [x] 儲存時依表單類型建立對應 input 並直接呼叫 create/update；失敗時保留表單與使用者輸入，成功後返回並刷新受影響帳戶。
- [x] 編輯既有投資交易時完整載入類型、帳戶、日期時間、金額、費用與備註；可切換為其他投資交易類型，但不可切換為一般交易。
- [x] 刪除投資交易時同步移除投資帳戶與一般資金帳戶的投影；若會使後續交易無效，整筆拒絕並保留原資料。

### 7. Routing 與回歸驗證

- [x] 新增 routing 測試：AccountManagerView 新增投資帳戶 → AccountEditView-invest → 儲存後返回並刷新 AccountManagerView。
- [x] 新增 routing 測試：AssetView 點選投資帳戶 → AccountDetailView，新增交易時進入限制為投資類型的 AccountTransactionView。
- [x] 新增 routing 測試：從一般資金帳戶的投資現金流投影進入原投資交易，返回後刷新詳情。
- [x] 驗證從 AssetView 進入時可選全部一般／投資交易，從一般或投資帳戶詳情進入時只顯示對應交易族群。
- [x] 驗證切換交易類型或投資帳戶後，帳戶下拉選單候選值、預設值與 disabled 狀態符合帳戶類型、幣別與封存規則。
- [x] 同步更新 `docs/testing.md`，只將已有且通過的測試項目標記為 `[x]`。

### 8. 完整驗證與收尾

- [x] 確認一般帳戶的建立、編輯、詳情與三種交易流程無回歸。
- [x] 確認投資帳戶的建立、編輯、封存／重新啟用、總覽、明細與四種交易可端到端完成。
- [x] 確認本次 diff 不包含 snapshot、ReportView graph、股票帳戶或已建立帳戶幣別變更。
- [x] 執行所有相關聚焦測試、`flutter analyze`、`flutter test` 與 `git diff --check`。
- [ ] 使用 `flutter attach` 與 hot reload 完成 iOS Simulator 人工驗證：一般／投資帳戶分流、資金來源篩選、四種交易表單、投影導覽與錯誤狀態。
