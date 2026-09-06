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
- **精準損益計算**：嚴謹區分「未實現損益（持股中）」與「已實現損益（已結清持股）」，精準還原投資回報率。
- **隱私與資料自主**：提供離線優先架構與完整的 CSV/檔案匯入匯出備份機制，支援生物辨識（Face ID）。

---

## 2. App 架構

### 2.1 Routing
主畫面按照 BottomNavigatorBar 分成四個主要的 views。以下為 routing 和每個畫面的具體 spec:
- BottomNavigator
  - [StockView](./docs/specs/StockView.md)
    - 點選某個股票 → [StockDetailView](./docs/specs/StockDetailView.md)
      - 點選某筆交易 → [StockTransactionView](./docs/specs/StockTransactionView.md)
    - 新增一筆交易 → [StockTransactionView](./docs/specs/StockTransactionView.md)
  - [AssetView](./docs/specs/AssetView.md)
    - 點選某個帳戶 → [AccountDetailView](./docs/specs/AccountDetailView.md)
      - 點選某筆交易 → [AccountTransactionView](./docs/specs/AccountTransactionView.md)
      - 點選「編輯帳戶」 → [AccountEditView](./docs/specs/AccountEditView.md)
        - 開啟「投資帳戶」toggle → [AccountEditView-invest](./docs/specs/AccountEditView-invest.md)
    - 新增一筆交易 → [AccountTransactionView](./docs/specs/AccountTransactionView.md)
  - [ReportView](./docs/specs/ReportView.md)
  - [SettingView](./docs/specs/SettingView.md)
    - [CategoryManagerView](./docs/specs/CategoryManagerView.md)
    - [AccountManagerView](./docs/specs/AccountManagerView.md)
    - [DataManagerView](./docs/specs/DataManagerView.md)

### 2.2 General specs
- app 介面提供多國語言，預設為中文
- 基礎幣別預設為 TWD；原幣資料與換算資料的語意必須分開。
- 投資帳戶的成本與現值為其持有部位總和；個別部位與帳戶彙總不可重複計入全資產。
- 股票賣出採 FIFO 沖銷買入批次；費用與稅納入損益，股息不改變持股成本。
- 一筆經濟事件可投影到多個 view，但只能有一份可維護的來源資料。
- 歷史現值採當時的月估值快照，不以最新行情或匯率回算。
- 行情或匯率更新失敗時沿用最後成功資料並標示時間，不得清零或建立新快照。
- 帳戶不可永久刪除，只能封存；封存不移除任何歷史關聯。
- loading、empty、error 與 stale data 必須是明確且可恢復的 UI 狀態。

### 2.3 Prototype Notes
畫面的 prototype 定義在 `docs/prototype`
- 畫面上的數字只作為畫面展示，不符合數學上的一致性
- 畫面上的說明文字和元件位置只作為畫面的表達，不一定符合最終呈現，且需要考慮跨view的一致性

---

## 3. 視覺設計與互動規範 (Design System & UI Specs)

- **主色調 (Primary)**：翡翠綠 / 薄荷綠（象徵財富、成長、穩健收益；`#10B981` / `#059669` 系列）。
- **輔助色 (Accents)**：暖金黃、亮橘、沉穩藍、科技紫（用於各資產分類之圖表顏色映射）。
- **字型層級**：以乾淨俐落的無襯線字體（Inter / SF Pro / PingFang TC）呈現高對比數字與資訊架構。
- **版面風格**：iOS 原生 Modern Clean 風格、大圓角白色卡片（Subtle Shadow）、清晰的資訊邊界與充足的留白節奏。

---

## 4. Tech Stack
- 使用 Dart + Flutter 開發，UI 框架用 Forui

---

## 5. Develop Workflow
- 利用 `codegraph` 查找程式間依賴的關係
- 針對帳目相關的函式建立 unitest 後再開始實作

---
