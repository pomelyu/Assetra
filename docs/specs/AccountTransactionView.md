# AccountTransactionView

## Purpose

維護一般帳戶現金流及投資帳戶的手動事件。股票帳戶交易由 StockTransactionView 維護。資料欄位及 API 依 [schema](../schema.md)。

## Transaction Types

- 一般帳戶（GENERAL）：ACCOUNT_TRANSFER、ACCOUNT_INCOME、ACCOUNT_EXPENSE。
- 投資帳戶（INVESTMENT）：INVESTMENT_BUY、INVESTMENT_SELL、INVESTMENT_INTEREST、INVESTMENT_PNL_ADJUSTMENT。
- 一般帳戶中的股票現金流投影仍屬股票事件，須導向 StockTransactionView；不另建同額交易。

## Inputs

- 共通：類型、交易日期、相關帳戶與可選備註；幣別由帳戶決定。
- 轉帳：來源、目標一般帳戶，以及 SOURCE_AMOUNT、TARGET_AMOUNT 兩端實際金額；不提供費用或歷史匯率欄位。
- 收入／支出：一般帳戶及實際入款 TARGET_AMOUNT／扣款 SOURCE_AMOUNT；無費用欄位。
- 手動買入：投資帳戶、扣款一般帳戶、AMOUNT、FEE。
- 手動賣出：投資帳戶、入款一般帳戶、AMOUNT、FEE；成本與現值減少額由系統推導，不另行輸入。
- 利息：投資帳戶、入款一般帳戶及 AMOUNT；無費用欄位。
- 損益調整：投資帳戶及帶正負號的 VALUE_ADJUSTMENT；無現金帳戶或費用欄位。

## Data and Rules

- 只有一般帳戶間轉帳可跨幣別。手動投資買入、賣出及利息的投資帳戶與一般資金帳戶必須同幣別。
- 轉帳兩端為同一事件，不能分開維護；一般收入、支出、轉帳使各端成本及現值等額變動。
- 手動買入：增加成本與一般帳戶扣款＝AMOUNT + FEE；增加投資現值＝AMOUNT。
- 手動賣出前成本為 C、現值為 V：售出比例＝AMOUNT ÷ V，沖銷成本＝C × AMOUNT ÷ V。
- 一般帳戶入款＝AMOUNT − FEE；本次已實現損益＝入款 − 沖銷成本，加入累計已實現損益。
- 賣出後成本＝C − 沖銷成本；現值＝V − AMOUNT；剩餘未實現損益＝剩餘現值 − 剩餘成本。
- 比例運算不先捨入；沖銷成本依幣別最小單位取整。全部賣出時完整沖銷剩餘成本，吸收尾差。
- 利息全額增加投資帳戶已實現損益及一般帳戶成本、現值，不改變投資成本或現值。
- 損益調整只改變投資現值與未實現損益，不改變成本或現金流。
- 費用只適用手動買賣，合併手續費與稅為 FEE；其他類型不接受費用值。

## Actions, Validation and States

- 新交易的帳戶須未封存、類型與幣別有效；無可選帳戶時顯示引導。
- 手動賣出要求 V > 0、0 < AMOUNT <= V、0 <= FEE <= AMOUNT；一般帳戶可為負餘額。
- 儲存刷新受影響摘要與歷史；取消不保存。編修或刪除必須原子性重算兩端與後續手動交易，無效則整筆回復。
- 既有月快照不隨交易編修改寫。儲存中防止重複提交；失敗保留表單。

## Acceptance Criteria

- 一般交易、利息及損益調整均不提供費用欄位；只有轉帳可選不同幣別帳戶。
- 手動買賣只需 AMOUNT、FEE，成本及入出款皆正確推導。
- C = 1,000、V = 1,200、AMOUNT = 600、FEE = 10 的賣出結果為：沖銷成本 500、入款 590、已實現損益 90、剩餘成本 500、現值 600、未實現損益 100。
- 全部賣出後成本與現值皆為零；跨帳戶事件只建立一次。
