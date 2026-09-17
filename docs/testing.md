# Test Catalog

本文件是 `test/` 的完整測試目錄。章節名稱與對應的英文 `*_test.dart` 檔名一致；`[x]` 表示已有同名測試，`[ ]` 表示可預期但尚未測試的行為。

## Common Numeric and Time Rules

File: `test/data/common_numeric_and_time_rules_test.dart`

- [x] Money.units 使用實際貨幣金額: 驗證 TWD 整數、USD 兩位小數與過度精確的輸入。
- [x] ShareQuantity.units 支援最多四位小數
- [x] 剛好半個最小單位時以遠離零方向四捨五入
- [ ] JPY 金額只接受整數
- [ ] EUR 金額支援兩位小數
- [ ] USD 與 EUR 超過兩位小數時拒絕
- [ ] 金額與股數拒絕 NaN、正負無限大及溢位
- [ ] 匯率拒絕超過兩位小數、零、負數及不支援幣別
- [ ] 股票成交總額為半個最小貨幣單位時正確四捨五入
- [ ] FIFO 成本分攤為半個最小單位時正確處理正負四捨五入
- [ ] 無效日期時拒絕交易
- [ ] 交易時間包含秒、格式錯誤或時分非法時拒絕
- [ ] 系統時間欄位使用 UTC ISO 8601 格式: 包含 UPDATED_AT、CAPTURED_AT、QUOTED_AT 與 RETRIEVED_AT。
- [ ] 修改資料後 UPDATED_AT 確實更新
- [ ] 產生的 UUID 格式正確且不重複

## Categories

File: `test/data/categories_test.dart`

- [x] 建立及修改分類時拒絕空白名稱
- [x] 建立及修改分類時拒絕去除空白後的重複名稱: 名稱比較不分大小寫。
- [ ] 成功建立分類
- [ ] 成功修改分類且 ID 不變
- [ ] accountUsageCount 正確反映使用帳戶數
- [ ] 成功重新排列全部分類
- [ ] 分類排序清單缺少、重複或包含不存在的 ID 時拒絕
- [ ] 「未分類」不可重新命名、變更色彩或刪除，「存款」與「投資」可編輯
- [ ] 最後一個分類不可刪除
- [ ] 使用中的分類未提供替代分類時不可刪除
- [ ] 使用替代分類刪除後原帳戶會原子性移轉
- [ ] 已封存帳戶使用的分類不可刪除
- [ ] SORT_ORDER 的資料庫約束拒絕負數
- [ ] 分類操作失敗時完整回滾

## Accounts

File: `test/data/accounts_test.dart`

- [x] 帳戶不可指定自己為資金來源帳戶
- [x] 封存的一般帳戶不可修改
- [x] 一般帳戶被啟用帳戶作為資金來源時不可封存
- [ ] 一般、股票及投資帳戶可成功建立
- [ ] 一般及投資帳戶的初始成本與現值可不同
- [ ] 股票帳戶初始成本與現值必須為零
- [ ] 股票帳戶非零初始值受到資料庫 CHECK 約束
- [ ] 股票及投資帳戶未指定資金來源時拒絕
- [ ] 資金來源為股票、投資或封存帳戶時拒絕
- [ ] 資金來源與股票或投資帳戶幣別不同時拒絕
- [ ] 一般帳戶不得保存 FUNDING_ACCOUNT_ID
- [ ] 帳戶建立後不可變更類型
- [ ] 有交易歷史後不可變更幣別
- [ ] 更換預設資金來源只影響後續交易
- [ ] 一般、股票及投資帳戶可成功修改
- [ ] 修改初始值後完整重播交易
- [ ] 修改初始值造成後續超賣時完整回滾
- [ ] 修改初始值不改變既有快照
- [ ] 一般及投資帳戶允許負初始值
- [ ] 一般帳戶允許負餘額
- [ ] 帳戶可封存及重新啟用
- [ ] 封存投資帳戶不可修改
- [ ] 封存時間正確保存於 UPDATED_AT

## Securities

Planned file: `test/data/securities_test.dart`

- [ ] 市場及股票代號會轉為大寫並去除前後空白
- [ ] 相同市場及股票代號會回傳同一 SecurityId
- [ ] 相同市場及股票代號使用不同幣別時拒絕
- [ ] 股票代號、名稱或市場為空白時拒絕
- [ ] 股票全部賣出後標的仍保留
- [ ] QUOTE_SYMBOL 可保存及讀取

## Transactions

File: `test/data/transactions_test.dart`

- [x] 交易涉及封存帳戶時拒絕新增
- [x] 同分鐘交易依建立順序由新到舊回傳
- [x] 拒絕建立未來時間的交易
- [x] 股票及手動投資買賣拒絕負股數、負價格與負金額
- [ ] 修改交易後保留原本 ENTRY_ORDER
- [ ] 備份還原後新交易從最大 ENTRY_ORDER 繼續
- [ ] ENTRY_ORDER 的資料庫約束拒絕非正數及重複值
- [ ] 同分鐘的財務重播依建立順序進行
- [ ] 修改或刪除涉及封存帳戶的交易時拒絕
- [ ] 一筆交易主表只能對應一筆相符 subtype
- [ ] NOTE 可保存、修改及備份還原
- [ ] 交易更新失敗時原交易完整保留
- [ ] 刪除交易後主表與 subtype 同時移除

## Stock Transactions

File: `test/data/stock_transactions_test.dart`

- [x] 股票買入以單一事件增加股票成本並扣除資金帳戶餘額
- [x] 股票賣出依 FIFO 計算並分攤買入手續費
- [x] 股息以單一事件增加現金與股票已實現損益
- [x] 股票交易類型拒絕不相容的帳戶類型
- [x] 刪除早期買入導致後續賣出無效時完整回滾
- [ ] 股票買入及賣出拒絕零股數或零價格
- [ ] 股票交易拒絕負手續費
- [ ] 股票賣出手續費大於成交總額時的行為符合規格
- [ ] 股息拒絕零或負數
- [ ] 股票帳戶、資金帳戶、標的或 Money 幣別不一致時拒絕
- [ ] 直接建立股票超賣交易時拒絕
- [ ] 全數或多次部分賣出後成本精確歸零
- [ ] 股票賣出後一般帳戶增加正確淨收入
- [ ] 股票買入後未實現損益等於市場價值減 FIFO 成本
- [ ] 股息不改變股數、成本及股票現值
- [ ] 股票交易投影到一般帳戶時仍只有一個交易 ID
- [ ] 修改股票買賣後重新計算後續 FIFO
- [ ] 修改或刪除股票交易不改變既有快照
- [ ] 股票 subtype 未使用的欄位保持 NULL

## General Account Transactions

File: `test/data/general_account_transactions_test.dart`

- [x] 跨幣別轉帳分別保存兩端的實際金額
- [x] 一般帳戶收入增加成本與現值並拒絕負數
- [x] 一般帳戶支出降低成本與現值並拒絕負數
- [x] 一般帳戶交易類型拒絕股票及投資帳戶
- [ ] 轉帳來源與目標相同時拒絕
- [ ] 轉帳兩端金額拒絕零或負數
- [ ] 收入及支出拒絕零金額
- [ ] 轉帳、收入及支出的 Money 幣別與帳戶不符時拒絕
- [ ] 一般帳戶轉帳後允許餘額為負數
- [ ] 轉帳、收入及支出的 FEE 保持 NULL
- [ ] 轉帳不保存歷史匯率
- [ ] 修改轉帳時完整移除兩端舊效果後套用新效果
- [ ] 刪除雙帳戶交易後兩端同時還原

## Manual Investment Transactions

File: `test/data/manual_investment_transactions_test.dart`

- [x] 手動投資賣出依比例平均成本計算
- [x] 手動買入、利息與損益調整只影響指定帳本
- [x] 手動投資交易類型只接受投資帳戶
- [ ] 手動投資買賣拒絕零金額或負手續費
- [ ] 手動投資賣出手續費大於 AMOUNT 時拒絕
- [ ] 投資帳戶、資金帳戶或 Money 幣別不一致時拒絕
- [ ] 投資現值非正數或賣出金額大於現值時拒絕
- [ ] 全數或多次部分賣出後成本及現值精確歸零
- [ ] 投資利息拒絕零或負數
- [ ] 投資利息不改變投資成本及現值
- [ ] 負損益調整可降低投資現值
- [ ] 零損益調整時拒絕
- [ ] 損益調整不產生一般帳戶現金流
- [ ] 修改或刪除早期事件造成後續賣出失效時回滾
- [ ] 修改或刪除手動投資交易不改變既有快照
- [ ] 手動投資 subtype 未使用的欄位保持 NULL

## Market Data

Planned file: `test/data/market_data_test.dart`

- [ ] 可成功保存股票價格及匯率
- [ ] 同一標的或幣別的第二次行情覆蓋第一筆
- [ ] TWD 使用隱含 1.00 且不建立匯率資料列
- [ ] 禁止保存 TWD 到 TWD 匯率
- [ ] 股票價格拒絕零、負數或錯誤幣別
- [ ] 匯率拒絕零、負數或超過兩位小數
- [ ] 行情更新失敗後保留舊價格與匯率
- [ ] 行情失敗不建立快照
- [ ] QUOTED_AT 與 RETRIEVED_AT 正確保存
- [ ] View DTO 不輸出 stale 狀態與行情時間

## Weekly Snapshots and Historical Reports

Planned file: `test/data/weekly_snapshots_and_historical_reports_test.dart`

- [ ] WEEK_START_DATE 為快照日期所在週的星期一
- [ ] 不同帳戶同週各自建立快照且下一週可再次建立
- [ ] 不需行情的一般及投資帳戶可直接建立快照
- [ ] 缺少報價或匯率時只略過受影響帳戶
- [ ] 同週資料更新後重試可補建先前略過的快照
- [ ] 已存在快照不被後續資料修改覆寫
- [ ] 指定日期前沒有快照的帳戶按零計算
- [ ] 每個帳戶採用日期以前最近的快照並延續到下一份快照
- [ ] 歷史日期不因部分帳戶缺少快照而標示 incomplete
- [ ] 現在點使用目前帳戶計算並反映估值完整性
- [ ] 封存日前使用快照且從封存當日起貢獻為零
- [ ] 封存後快照保留且重新啟用後視為一直啟用
- [ ] 3M、6M、1Y、3Y 及全部期間可正確過濾
- [ ] 匯入快照時驗證 WEEK_START_DATE

## Settings

Planned file: `test/data/settings_test.dart`

- [ ] 預設語言、更新模式及生物辨識狀態正確
- [ ] Partial patch 未提供的設定欄位保持不變
- [ ] 設定在關閉並重開資料庫後仍存在
- [ ] 生物辨識失敗或未提供 callback 時不可啟用鎖定
- [ ] 關閉生物辨識不要求驗證
- [ ] APP_SETTINGS.ID 的資料庫約束只接受 1
- [ ] Theme mode 與 update mode 的資料庫約束拒絕未知值

## Backup and Restore

File: `test/data/backup_and_restore_test.dart`

- [x] 每週快照不重複且備份可還原完整資料: 驗證同週唯一性、基本檢查、完整覆蓋與 now point。
- [ ] 每張資料表都匯出為 CSV 且 NULL 值可還原
- [ ] Manifest 包含 table 清單、row count 及 checksum
- [ ] 備份損壞、checksum 不符或缺少檔案時拒絕
- [ ] Schema version 或 CSV 欄位不相容時拒絕
- [ ] 非本程式格式的 ZIP 或 CSV 時拒絕
- [ ] 匯入資料違反帳戶、幣別、funding 或 subtype 規則時拒絕
- [ ] 匯入失敗時原資料完整保留
- [ ] 所有資料表可完整還原
- [ ] 還原後 UUID 與 ENTRY_ORDER 保持不變

## Data API Contract

File: `test/data/data_api_contract_test.dart`

- [x] 應用程式只能透過公開 barrel 匯入資料層
- [x] 所有公開 Data API 函式都有輸入輸出文件

## Database Infrastructure

File: `test/data/database_infrastructure_test.dart`

- [x] 資料庫 schema 可持久化並強制外鍵及交易回滾

## Data API Integration

File: `test/data/data_api_integration_test.dart`

- [x] 分類、設定、行情更新與帳戶生命週期 API 可共同運作
- [x] 股票交易預覽、表單、查詢與行情 API 可共同運作
- [x] 帳戶交易預覽、表單、修改與刪除 API 可共同運作

## UI Smoke Test

File: `test/ui_smoke_test.dart`

- [x] 底部導航預設顯示股市並可切換四個主要 view
- [x] 底部導航依 locale 顯示中文或英文並套用 fallback: `zh_*` 與 `yue_*` 使用繁中，其他不支援 locale 使用英文。

## UI Routing

File: `test/ui_routing_test.dart`

- [x] 資產交易 FAB 與帳戶管理可導向正確編輯頁
- [x] 資產帳戶可進入詳情，再進入一般帳戶交易編輯頁
- [x] 從帳戶詳情新增交易時，收入目標、支出來源與轉帳來源會帶入當前帳戶
