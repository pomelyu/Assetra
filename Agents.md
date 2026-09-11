# Assetra
## 1. Overview

### 1.1 產品定位
一款個人資產管理的行動應用程式（iOS 體驗優先）。讓使用者能一站式掌握多國市場、多種資產的即時現值、投資成本，並以視覺化報表顯示歷史收益和配置百分比。

### 1.2 目標使用者 (Target Audience)
- **多市場投資人**：同時佈局台股、美股等多國證券市場，需統一幣別統整損益與多帳戶管理的投資者。
- **多元資產配置者**：除股市外，同時持有多幣種帳戶、定存、黃金或其他投資帳戶，需要全面性資產總覽。
- **數據與復盤導向者**：重視資產成長軌跡、配置權重佔比，並習慣透過報表做再平衡檢視的族群。

### 1.3 核心價值主張
- **全局視野**：打破券商與銀行各自獨立的藩籬，合併計算全資產總現值與總損益。
- **精準損益計算**：嚴謹區分「未實現損益（剩餘部位）」與「已實現損益（賣出、股息及利息）」，精準還原投資回報率。
- **隱私與資料自主**：提供離線優先架構與完整的 CSV/檔案匯入匯出備份機制，支援生物辨識（Face ID）。

---

## 2. App 架構

### 2.1 Routing
主畫面按照 BottomNavigatorBar 分成四個主要的 views。資料欄位、計算規則與 Data API 以 [docs/schema.md](./docs/schema.md) 為準；各 view spec 描述對應的產品行為。

以下為 routing 和每個畫面的具體 spec:

- BottomNavigator
  - [StockView](./docs/specs/StockView.md)
    - 點選某個股票 → [StockDetailView](./docs/specs/StockDetailView.md)
      - 點選某筆交易 → [StockTransactionView](./docs/specs/StockTransactionView.md)
    - 新增一筆交易 → [StockTransactionView](./docs/specs/StockTransactionView.md)
  - [AssetView](./docs/specs/AssetView.md)
    - 點選某個帳戶 → [AccountDetailView](./docs/specs/AccountDetailView.md)
      - 點選一般／手動投資事件 → [AccountTransactionView](./docs/specs/AccountTransactionView.md)
      - 點選股票事件（含一般帳戶中的投影） → [StockTransactionView](./docs/specs/StockTransactionView.md)
      - 新增交易：一般／投資帳戶進入 AccountTransactionView；股票帳戶進入 StockTransactionView
      - 點選「編輯帳戶」 → [AccountEditView](./docs/specs/AccountEditView.md)
        - 選擇「股票帳戶」或「投資帳戶」類型 → [AccountEditView-invest](./docs/specs/AccountEditView-invest.md)
    - 新增一筆交易 → [AccountTransactionView](./docs/specs/AccountTransactionView.md)
  - [ReportView](./docs/specs/ReportView.md)
  - [SettingView](./docs/specs/SettingView.md)
    - [CategoryManagerView](./docs/specs/CategoryManagerView.md)
    - [AccountManagerView](./docs/specs/AccountManagerView.md)
    - [DataManagerView](./docs/specs/DataManagerView.md)

### 2.2 General specs
- app 介面提供多國語言，預設為中文
- 第一版基礎幣別固定為 TWD；原幣資料與換算資料的語意必須分開。
- 帳戶類型為一般（GENERAL）、股票（STOCK）、投資（INVESTMENT），與報表分類獨立。
- 帳戶類型只在建立帳戶時選擇；帳戶建立後不可變更類型。
- 一般帳戶可建立轉帳、收入、支出；股票帳戶可建立股票買入、賣出、股息；投資帳戶可建立手動買入、賣出、利息、損益調整。
- 股票與投資帳戶都必須指定同幣別的一般帳戶為資金來源；一般帳戶沒有資金來源設定。
- 只有一般帳戶轉帳允許跨幣別，分別記錄兩端實際金額；股票交易的標的與兩個帳戶必須同幣別。交易不保存歷史匯率。
- 一般帳戶可有負初始值或負餘額；股票不可超賣，手動賣出金額不可超過賣出前現值。
- 股票帳戶的初始成本與初始價值固定為 0，持股由股票交易建立並彙總；投資帳戶由初始值與手動事件推導成本及現值，不混入股票。個別股票與帳戶彙總不可重複計入全資產。
- 股票買入成本及扣款＝股數 × 單價 ＋ FEE；賣出淨收入＝股數 × 單價 − FEE。賣出採 FIFO 沖銷含分攤買入費用的批次成本。
- 手動買入只輸入 AMOUNT、FEE：成本與扣款增加 AMOUNT + FEE，現值增加 AMOUNT。手動賣出以 AMOUNT／賣出前現值的比例沖銷賣出前成本；已實現損益＝AMOUNT − FEE − 沖銷成本，全數賣出須沖銷全部剩餘成本。
- 只有股票及手動投資的買入、賣出有合併手續費與稅的 FEE。轉帳、一般收入／支出、股息、利息與損益調整都沒有費用欄位。
- 股息／利息等額增加歸屬帳戶的已實現損益與一般資金帳戶的成本、現值，不增加股票／投資帳戶現值。損益調整只改變投資現值及未實現損益。
- 一筆經濟事件以一筆交易主表及一筆類型明細保存，可投影到多個 view；兩端效果必須一起更新或刪除，不建立重複事件。
- 金額依程式常數儲存：TWD／JPY 整數、USD／EUR 兩位小數；匯率兩位小數。股數精度遵循目前 schema（倍率 100、兩位小數）。
- 一般資料建立與修改共用 UPDATED_AT，不另存 CREATED_AT；交易日期、報價時間及週快照時間仍各自保留。
- 每個未封存帳戶每週最多一份估值快照，儲存完整日期 YYYY-MM-DD；以台北時間週一至週日為界，當週首次成功取得所需行情／匯率後各自建立，資料不足不阻擋其他帳戶。保存當時原幣及 TWD 成本、現值、累計已實現損益；後續行情、匯率或交易編修不覆寫歷史快照。行情與匯率本身只保留最後成功值。
- 計算某日期的歷史總資產時，每個帳戶取該日（含）以前最近一份快照；不存在則以 0 計算，不要求所有帳戶在同週都有快照，也沒有歷史日期完整性標籤。報表「現在」依目前帳戶總和計算，不使用最後快照。
- 行情或匯率更新失敗時沿用最後成功資料並標示時間，不得清零或建立新快照。
- 帳戶不可永久刪除，只能封存或重新啟用；封存不移除快照，但自 `UPDATED_AT` 換算為台北日期的當天起以 0 計入歷史總資產，且封存期間不可編輯。重新啟用後視為從未封存，所有歷史日期重新按最近快照計算，不保留封存期間。仍被使用中股票／投資帳戶指定為資金來源時須先改派。帳戶建立後不可變更類型；有財務歷史時不可變更幣別。
- 備份以本程式各 table 的 CSV 封裝匯出；只支援相容備份驗證後完整覆蓋還原，不合併資料。
- 交易時間採台北時間（Asia/Taipei），24 小時制且精度到分；不得輸入未來交易。同分鐘依系統保存的新增順序計算，編輯不改變新增順序，與 UPDATED_AT 無關。
- 使用者按確定後建立 input 並直接呼叫 create/update；preview 只用於選擇性的畫面估算，不是必要前置步驟。失敗保留表單。
- 成交金額及分攤成本採四捨五入至幣別最小單位，比例不先取整，全部賣出吸收剩餘成本尾差。
- 缺少行情不阻擋記帳或成本計算；未曾取得報價時，現值標示尚無報價，相關目前總覽標示估值未齊全，不以零或買入價替代。
- 未封存的一般／投資帳戶可修改初始值，須原子性重算並驗證全部受影響交易，無效則拒絕；既有快照不變。
- 交易任一端涉及封存帳戶即禁止新增、修改或刪除；改換交易帳戶亦不得繞過限制。有封存帳戶使用的分類不能刪除。
- loading、empty、error 與 stale data 必須是明確且可恢復的 UI 狀態。

### 2.3 Prototype Notes
畫面的 prototype 定義在 `docs/prototype`
- 畫面上的數字只作為畫面展示，不符合數學上的一致性
- 畫面上的說明文字和元件位置只作為畫面的表達，不一定符合最終呈現，且需要考慮跨view的一致性
- 如果 Prototype 中與 schema 或 spec 有衝突，以 `schema.md` 或 spec 為準。
- Prototype 中舊有的兩類帳戶 toggle、交易費用欄位與初始值文案，須依 `schema.md` 及 view specs 解讀。

---

## 3. 視覺設計與互動規範 (Design System & UI Specs)

- **主色調 (Primary)**：翡翠綠 / 薄荷綠（象徵財富、成長、穩健收益；`#10B981` / `#059669` 系列）。
- **輔助色 (Accents)**：暖金黃、亮橘、沉穩藍、科技紫（用於各資產分類之圖表顏色映射）。
- **字型層級**：以乾淨俐落的無襯線字體（Inter / SF Pro / PingFang TC）呈現高對比數字與資訊架構。
- **版面風格**：iOS 原生 Modern Clean 風格、大圓角白色卡片（Subtle Shadow）、清晰的資訊邊界與充足的留白節奏。

---

## 4. Tech Stack
- 使用 Dart + Flutter 開發，UI 框架用 Forui
- 本地資料庫使用 SQLite；資料 schema 與各 view Data API 見 `docs/schema.md` 與 `docs/data_api.md` 

---

## 5. Develop Workflow
- 利用 `codegraph` 查找程式間依賴的關係
- 針對帳目相關的函式建立 unitest 後再開始實作

---
