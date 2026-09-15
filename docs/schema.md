# Database Schema

## Conventions

- Database: SQLite with `PRAGMA foreign_keys = ON`.
- ID fields use application-generated UUID strings.
- Calendar dates use `YYYY-MM-DD`. User transaction times use `YYYY-MM-DD HH:mm` (24-hour clock) in the fixed `Asia/Taipei` timezone. System timestamps (UPDATED_AT, CAPTURED_AT and quote/retrieval times) use UTC ISO 8601 strings.
- All business dates, Monday–Sunday week boundaries and archive dates are determined in Asia/Taipei, independent of device timezone.
- Monetary calculations use exact integer/rational arithmetic and round to the currency's smallest stored unit using nearest rounding, with ties away from zero (四捨五入). Round gross stock trade amounts before adding/subtracting fees; round allocated costs without first rounding allocation ratios. Final disposals absorb remaining cost exactly.
- Currency codes use ISO 4217 uppercase strings. The base currency is fixed to `TWD` in the first version.
- Field names omit scaling suffixes (for example, `FEE`, `RATE`, `QUANTITY`); storage multipliers are defined in an application constant lookup table, not a database table or per-row field.
- Money uses scaled `INTEGER` values: stored value = amount × `MONEY_MULTIPLIER[currencyCode]`.
- Currency precision is defined by application constants, not database columns: `MONEY_DECIMAL_PLACES = {TWD: 0, JPY: 0, USD: 2, EUR: 2}`; `MONEY_MULTIPLIER = {TWD: 1, JPY: 1, USD: 100, EUR: 100}`.
- The currency of each field determines its multiplier, including prices, fees, settlement amounts and snapshots. For example, TWD 123 is stored as 123; USD 123.45 is stored as 12345.
- Unsupported currencies require an explicit precision constant before use; never infer a default multiplier.
- Precision constants are part of the versioned schema/backup contract. Changing an existing currency multiplier requires a schema migration and compatible import conversion, even though the constants are not stored per row.
- All exchange rates use two decimal places, independent of currency-specific money precision. Application constants: `EXCHANGE_RATE_DECIMAL_PLACES = 2`, `EXCHANGE_RATE_MULTIPLIER = 100`; for example, rate 32.15 is stored as 3215.
- Share quantities use scaled `INTEGER` values: stored value = display value × 10000, supporting four decimal places.
- Public Data API callers always pass and receive actual monetary amounts, exchange rates and share quantities. Multipliers are applied only when values cross the database boundary.
- Boolean values use `INTEGER` constrained to `0` or `1`.
- UPDATED_AT records creation time on insert and the latest modification time on update; a separate original creation timestamp is not retained.
- Financial source rows are stored; holdings, balances, FIFO results, summaries and view projections are derived.

## SCHEMA_METADATA

- KEY (TEXT PRIMARY KEY): Metadata key, such as `SCHEMA_VERSION`.
- VALUE (TEXT NOT NULL): Metadata value exported with the database tables.

## CATEGORIES

- ID (TEXT PRIMARY KEY): Stable category UUID; renaming does not change this value.
- NAME (TEXT NOT NULL): User-visible category name.
- COLOR_ARGB (INTEGER NOT NULL): Category color stored as a 32-bit ARGB value.
- SORT_ORDER (INTEGER NOT NULL): User-defined display order.
- UPDATED_AT (TEXT NOT NULL): UTC timestamp set on creation and refreshed on each modification.

Rules:

- `NAME` cannot be blank and `SORT_ORDER` cannot be negative.
- Category names are unique after trimming and compared case-insensitively by the Data API.
- A new database seeds three ordinary, editable categories in this order: `default` / 「未分類」, `deposit` / 「存款」, and `investment` / 「投資」. They are not protected system categories.
- A category referenced by any archived account cannot be deleted. Otherwise, referenced active accounts must be atomically reassigned before deletion; no operation may edit an archived account.
- At least one category must always remain.

## ACCOUNTS

- ID (TEXT PRIMARY KEY): Stable account UUID.
- NAME (TEXT NOT NULL): User-visible account name.
- CATEGORY_ID (TEXT NOT NULL REFERENCES CATEGORIES.ID): Current reporting category.
- CURRENCY_CODE (TEXT NOT NULL): Account ledger currency.
- ACCOUNT_TYPE (TEXT NOT NULL): Immutable account type selected at creation: `GENERAL` (一般帳戶), `STOCK` (股票帳戶), or `INVESTMENT` (手動投資帳戶). Independent of reporting category.
- FUNDING_ACCOUNT_ID (TEXT NULL REFERENCES ACCOUNTS.ID): Default GENERAL account used to settle new STOCK or INVESTMENT transactions.
- INITIAL_COST (INTEGER NOT NULL): Initial cost in account currency × the currency multiplier; fixed to 0 for STOCK accounts.
- INITIAL_VALUE (INTEGER NOT NULL): Initial value in account currency × the currency multiplier; fixed to 0 for STOCK accounts.
- NOTE (TEXT NULL): Optional user note.
- IS_ARCHIVED (INTEGER NOT NULL): Current archive state. Archived accounts keep all relations but contribute zero from the archive date onward.
- UPDATED_AT (TEXT NOT NULL): UTC timestamp set on creation and refreshed on each modification.

Rules:

- `FUNDING_ACCOUNT_ID` is required for STOCK and INVESTMENT accounts and must be null for general accounts; it cannot reference the same account.
- Every `FUNDING_ACCOUNT_ID`, including transaction-level overrides, must reference a general account (`ACCOUNT_TYPE = GENERAL`); newly selected funding accounts must also be non-archived.
- Enforce the general-account requirement on account and stock-transaction inserts/updates and backup import. Foreign keys alone only validate existence.
- Default and actual funding accounts must share their STOCK or INVESTMENT account currency; account edits and backup import must preserve this constraint.
- Changing a default funding account affects only new transactions; each transaction stores its actual account relation.
- Accounts are never deleted. `ACCOUNT_TYPE` cannot be updated after insertion, even when the account has no financial history. Existing financial history also prevents changing currency.
- Initial values form the account opening baseline before its transaction history; UPDATED_AT changes do not change when that baseline applies.
- Active GENERAL and INVESTMENT accounts may edit initial values. Replay and validate the entire affected transaction history atomically; reject invalid changes, including subsequent overselling. Existing snapshots remain unchanged. STOCK initial values remain zero.
- STOCK accounts require INITIAL_COST = 0 and INITIAL_VALUE = 0: enforce CHECK (ACCOUNT_TYPE <> 'STOCK' OR (INITIAL_COST = 0 AND INITIAL_VALUE = 0)). Apply the same rule on creation and backup import. Stock holdings and cost originate from stock transactions, not opening amounts.
- Negative initial values are valid for non-STOCK accounts; negative general-account balances are valid.
- While `IS_ARCHIVED = 1`, the account cannot be edited; its `UPDATED_AT` therefore identifies the archive time. For historical reports, convert it to the Asia/Taipei calendar date and count the account as zero from that date onward.
- Reactivation sets `IS_ARCHIVED = 0` and refreshes `UPDATED_AT`. Archive intervals are not historical data: after reactivation, treat the account as active for all historical dates and calculate them from snapshots normally.

## SECURITIES

- ID (TEXT PRIMARY KEY): Stable security UUID.
- SYMBOL (TEXT NOT NULL): Market ticker or security code.
- NAME (TEXT NOT NULL): User-visible security name.
- MARKET_CODE (TEXT NOT NULL): Stable market code such as `TW` or `US`.
- CURRENCY_CODE (TEXT NOT NULL): Trading and quote currency.
- QUOTE_SYMBOL (TEXT NULL): Optional external provider lookup symbol.
- UPDATED_AT (TEXT NOT NULL): UTC timestamp set on creation and refreshed on each modification.

Rules:

- `(MARKET_CODE, SYMBOL)` is unique using normalized uppercase values.
- Securities with transactions are retained even after all positions are closed.

## TRANSACTIONS

- ID (TEXT PRIMARY KEY): Stable economic-event UUID shared by every view projection.
- KIND (TEXT NOT NULL): One of `STOCK_BUY`, `STOCK_SELL`, `STOCK_DIVIDEND`, `ACCOUNT_TRANSFER`, `ACCOUNT_INCOME`, `ACCOUNT_EXPENSE`, `INVESTMENT_BUY`, `INVESTMENT_SELL`, `INVESTMENT_INTEREST`, `INVESTMENT_PNL_ADJUSTMENT`.
- OCCURRED_AT (TEXT NOT NULL): User-entered transaction time as `YYYY-MM-DD HH:mm`, interpreted in Asia/Taipei; minute precision, no seconds.
- ENTRY_ORDER (INTEGER NOT NULL UNIQUE): System-assigned positive insertion sequence, allocated atomically; immutable on edits and preserved in backup/restore. It is not a timestamp or user-editable field.
- NOTE (TEXT NULL): Optional user note.
- UPDATED_AT (TEXT NOT NULL): UTC timestamp set on creation and refreshed on each modification.

Rules:

- New forms default to the current Taipei minute; users may change it. Reject future transaction times for creation and edits; scheduled or pending transactions are out of scope.
- Replay events in ascending `(OCCURRED_AT, ENTRY_ORDER)` order; same-minute trades use insertion order. Edits retain ENTRY_ORDER, including date/time edits. Allocate new orders after the greatest retained order, including after restore; never use UPDATED_AT or random UUID order to break ties.
- Reject creation, editing or deletion if any participating account is archived. For edits, check accounts referenced both before and after the change; reactivation is required first.
- Exactly one matching subtype row must exist in either `STOCK_TRANSACTIONS` or `ACCOUNT_TRANSACTIONS`.
- Editing or deleting an event and all of its effects is one SQLite transaction.
- Deleting an event removes its subtype row; derived balances, positions and FIFO results are recalculated.

## STOCK_TRANSACTIONS

- TRANSACTION_ID (TEXT PRIMARY KEY REFERENCES TRANSACTIONS.ID ON DELETE CASCADE): Parent stock event.
- SECURITY_ID (TEXT NOT NULL REFERENCES SECURITIES.ID): Traded security or dividend-paying security.
- STOCK_ACCOUNT_ID (TEXT NOT NULL REFERENCES ACCOUNTS.ID): STOCK account owning the position or income.
- FUNDING_ACCOUNT_ID (TEXT NOT NULL REFERENCES ACCOUNTS.ID): Actual general account used for deduction or receipt.
- QUANTITY (INTEGER NULL): Buy/sell quantity stored using the application share-quantity multiplier; null for dividends.
- UNIT_PRICE (INTEGER NULL): Buy/sell unit price stored using the common currency multiplier; null for dividends.
- DIVIDEND_AMOUNT (INTEGER NULL): Dividend received, stored using the common currency multiplier; required only for dividends.
- FEE (INTEGER NULL): Combined buy/sell fee and tax in the common currency; nonnegative and zero when no fee is charged. Must be null for dividends.

Rules:

- STOCK_ACCOUNT_ID must reference ACCOUNT_TYPE = STOCK; FUNDING_ACCOUNT_ID must reference ACCOUNT_TYPE = GENERAL. Only STOCK_BUY, STOCK_SELL and STOCK_DIVIDEND belong to stock accounts.

- Security currency, stock-account currency and funding-account currency must all match, including manually overridden funding accounts.
- Currency is derived from these references; no transaction currency, exchange rate or duplicate settlement amount is stored.
- Buy/sell require positive quantity and unit price, a nonnegative fee and null dividend amount. Dividend requires a positive dividend amount and null quantity, unit price and fee.
- Buy cost and funding deduction = quantity × unit price + fee.
- Sell proceeds and funding receipt = quantity × unit price − fee.
- Dividend funding receipt and stock-account realized income = dividend amount; dividends have no fees.
- Gross buy/sell amounts and net settlement amounts are calculated, not stored.
- FIFO matches sales to purchase lots for the same security and stock account. Lot cost includes purchase fees; partial disposals allocate those fees by quantity, with the final disposal absorbing rounding remainder.
- Sale realized profit = net proceeds − disposed FIFO cost. Remaining unrealized profit = remaining market value − remaining FIFO cost.
- Sale quantity cannot exceed holdings. Funding-account balances may be negative.
- Dividend does not change holding quantity, cost or stock-account value.
- Editing/deleting events revalidates subsequent FIFO results atomically; weekly snapshots remain unchanged.

## ACCOUNT_TRANSACTIONS

- TRANSACTION_ID (TEXT PRIMARY KEY REFERENCES TRANSACTIONS.ID ON DELETE CASCADE): Parent general-account or manual-investment event.
- INVESTMENT_ACCOUNT_ID (TEXT NULL REFERENCES ACCOUNTS.ID): ACCOUNT_TYPE = INVESTMENT account for manual buy, sell, interest or value adjustment.
- SOURCE_ACCOUNT_ID (TEXT NULL REFERENCES ACCOUNTS.ID): GENERAL account from which cash is deducted.
- TARGET_ACCOUNT_ID (TEXT NULL REFERENCES ACCOUNTS.ID): GENERAL account into which cash is received.
- SOURCE_AMOUNT (INTEGER NULL): Actual deduction in source-account currency; used only by general transfers and expenses.
- TARGET_AMOUNT (INTEGER NULL): Actual receipt in target-account currency; used only by general transfers and income.
- AMOUNT (INTEGER NULL): Manual buy/sell amount before fees, or interest amount; uses investment-account currency.
- VALUE_ADJUSTMENT (INTEGER NULL): Signed investment value change; positive increases value and negative decreases it.
- FEE (INTEGER NULL): Combined fee and tax for INVESTMENT_BUY or INVESTMENT_SELL only, in the shared investment/funding currency; nonnegative, zero when absent.

Rules:

- All monetary integers use their currency's application multiplier.
- Only ACCOUNT_TRANSFER may involve different currencies; both accounts must be GENERAL.
- ACCOUNT_INCOME and ACCOUNT_EXPENSE belong only to GENERAL accounts. They record actual cash flow and have no FEE field value.
- INVESTMENT accounts may own only INVESTMENT_BUY, INVESTMENT_SELL, INVESTMENT_INTEREST and INVESTMENT_PNL_ADJUSTMENT. They cannot own stock transactions; STOCK accounts cannot own manual investment transactions.
- Funding cash-flow projections of stock/manual investment events may appear in GENERAL account histories without creating a second transaction or changing the parent KIND.
- Source and target references are GENERAL accounts; manual investments use INVESTMENT_ACCOUNT_ID exclusively to identify the investment account. All participating accounts for manual investment events must share the same currency.
- Transfer records both actual amounts with no fee or historical exchange rate field.
- General income/expense changes the account cost and value equally by the actual receipt/deduction.
- Manual buy: funding deduction and added investment cost = AMOUNT + FEE; added investment value = AMOUNT. Do not store duplicate cost/value/cash-flow amounts.
- Manual sell uses proportional average cost. Let C and V be the remaining investment cost and value immediately before this event, derived from initial values and preceding events (including value adjustments).
- Sale proportion = AMOUNT / V; disposed cost = C × AMOUNT / V. Use exact integer/rational arithmetic without rounding the proportion first; round the disposed cost to the account currency's smallest stored unit.
- Funding receipt = AMOUNT − FEE; realized profit for this sale = funding receipt − disposed cost. Add this profit to cumulative realized profit.
- Remaining cost = C − disposed cost; remaining value = V − AMOUNT; remaining unrealized profit = remaining value − remaining cost. FEE reduces funding receipt and realized profit, not the value removed from the investment.
- Require V > 0 and 0 < AMOUNT <= V. When AMOUNT = V, dispose of all remaining C exactly so that remaining cost and value both become zero, absorbing any prior allocation rounding remainder.
- Example in display units: C = 1,000, V = 1,200, AMOUNT = 600, FEE = 10 gives disposed cost 500, funding receipt 590, realized profit 90, remaining cost 500, remaining value 600 and unrealized profit 100.
- Disposed cost, sale proportion and profit are derived, not separate stored fields. Editing/deleting earlier events must revalidate and recalculate later manual sales atomically; saved weekly snapshots remain unchanged.
- Interest: AMOUNT is both the funding receipt and investment realized income. No fee; investment cost/value are unchanged.
- Value adjustment changes investment value and unrealized profit only; no cash flow or fee.
- Fields omitted from a kind below must be null. Applicable FEE fields are required and nonnegative. AMOUNT and actual cash amounts must be positive; sell FEE cannot exceed AMOUNT. General-account balances may be negative.
- All events use one parent and one subtype row; two-account effects are projections of the same event.

### Fields used by each KIND

All kinds use TRANSACTIONS.ID, KIND, OCCURRED_AT, ENTRY_ORDER, UPDATED_AT and optional NOTE. Each subtype uses TRANSACTION_ID.

| KIND | Subtype | Additional fields used |
|---|---|---|
| STOCK_BUY | STOCK_TRANSACTIONS | SECURITY_ID, STOCK_ACCOUNT_ID, FUNDING_ACCOUNT_ID, QUANTITY, UNIT_PRICE, FEE |
| STOCK_SELL | STOCK_TRANSACTIONS | SECURITY_ID, STOCK_ACCOUNT_ID, FUNDING_ACCOUNT_ID, QUANTITY, UNIT_PRICE, FEE |
| STOCK_DIVIDEND | STOCK_TRANSACTIONS | SECURITY_ID, STOCK_ACCOUNT_ID, FUNDING_ACCOUNT_ID, DIVIDEND_AMOUNT |
| ACCOUNT_TRANSFER | ACCOUNT_TRANSACTIONS | SOURCE_ACCOUNT_ID, TARGET_ACCOUNT_ID, SOURCE_AMOUNT, TARGET_AMOUNT |
| ACCOUNT_INCOME | ACCOUNT_TRANSACTIONS | TARGET_ACCOUNT_ID, TARGET_AMOUNT |
| ACCOUNT_EXPENSE | ACCOUNT_TRANSACTIONS | SOURCE_ACCOUNT_ID, SOURCE_AMOUNT |
| INVESTMENT_BUY | ACCOUNT_TRANSACTIONS | INVESTMENT_ACCOUNT_ID, SOURCE_ACCOUNT_ID, AMOUNT, FEE |
| INVESTMENT_SELL | ACCOUNT_TRANSACTIONS | INVESTMENT_ACCOUNT_ID, TARGET_ACCOUNT_ID, AMOUNT, FEE |
| INVESTMENT_INTEREST | ACCOUNT_TRANSACTIONS | INVESTMENT_ACCOUNT_ID, TARGET_ACCOUNT_ID, AMOUNT |
| INVESTMENT_PNL_ADJUSTMENT | ACCOUNT_TRANSACTIONS | INVESTMENT_ACCOUNT_ID, VALUE_ADJUSTMENT |

## STOCK_PRICES

- SECURITY_ID (TEXT PRIMARY KEY REFERENCES SECURITIES.ID): Security whose last successful quote is stored.
- PRICE (INTEGER NOT NULL): Latest successful price in quote currency × the currency multiplier.
- CURRENCY_CODE (TEXT NOT NULL): Quote currency; normally equal to the security currency.
- QUOTED_AT (TEXT NOT NULL): Provider quote timestamp in UTC.
- RETRIEVED_AT (TEXT NOT NULL): Successful retrieval timestamp in UTC.

Rules:

- Only the latest successful quote is retained; quote history is not stored.
- A failed refresh never replaces this row with zero or stale failure data.

## EXCHANGE_RATES

- FROM_CURRENCY_CODE (TEXT PRIMARY KEY): Source currency.
- TO_CURRENCY_CODE (TEXT NOT NULL): Fixed to `TWD` in the first version.
- RATE (INTEGER NOT NULL): Latest successful conversion rate with two decimal places × `EXCHANGE_RATE_MULTIPLIER` (100).
- QUOTED_AT (TEXT NOT NULL): Provider rate timestamp in UTC.
- RETRIEVED_AT (TEXT NOT NULL): Successful retrieval timestamp in UTC.

Rules:

- Only the latest successful rate for each source currency is retained; rate history is not stored.
- `TWD` uses an implicit rate of `1.00` and does not require a row.
- A failed refresh never replaces the last successful row.

## ACCOUNT_WEEKLY_SNAPSHOTS

- ID (TEXT PRIMARY KEY): Stable snapshot UUID.
- ACCOUNT_ID (TEXT NOT NULL REFERENCES ACCOUNTS.ID): Account represented by this snapshot.
- SNAPSHOT_DATE (TEXT NOT NULL): Valuation date as `YYYY-MM-DD` in Asia/Taipei, including year, month and day; not merely a week or month label.
- WEEK_START_DATE (TEXT NOT NULL): Monday date of the week containing SNAPSHOT_DATE, derived and validated by the application for uniqueness; not an independently editable date.
- ACCOUNT_CURRENCY_CODE (TEXT NOT NULL): Account currency at capture time.
- COST (INTEGER NOT NULL): Cost in account currency × the currency multiplier at capture time.
- VALUE (INTEGER NOT NULL): Value in account currency × the currency multiplier at capture time.
- REALIZED_PNL (INTEGER NOT NULL): Cumulative realized profit in account currency × the currency multiplier at capture time.
- BASE_CURRENCY_CODE (TEXT NOT NULL): Fixed to `TWD` in the first version.
- BASE_COST (INTEGER NOT NULL): Captured cost converted to TWD × the currency multiplier.
- BASE_VALUE (INTEGER NOT NULL): Captured value converted to TWD × the currency multiplier.
- BASE_REALIZED_PNL (INTEGER NOT NULL): Captured realized profit converted to TWD × the currency multiplier.
- CAPTURED_AT (TEXT NOT NULL): Actual snapshot creation timestamp in UTC.

Rules:

- `(ACCOUNT_ID, WEEK_START_DATE)` is unique, enforcing at most one snapshot per account per Monday–Sunday week. Validate WEEK_START_DATE against SNAPSHOT_DATE on insert and import.
- Each call evaluates every active account independently and creates a snapshot only when its current valuation and required conversion rate are available. Do not overwrite a snapshot already present for that week.
- Missing required cached data skips only the affected account; a later call may capture it after data becomes available. The snapshot API uses the latest successfully saved quote/rate and does not track whether a separate refresh attempt most recently failed. No fabricated backfill is created automatically for missed weeks.
- Snapshot values are immutable historical facts and are never updated by later prices or exchange rates.
- For target date D, each account uses its snapshot with the greatest `SNAPSHOT_DATE <= D`; when no such snapshot exists, its cost, value and realized profit are all zero.
- A historical report date does not require snapshots for every account and has no complete/incomplete state. A prior snapshot carries forward until a later snapshot supersedes it. This differs from missing-price status in current valuations.
- The report's “now” point is computed from current account balances/positions and latest successful market data, not from the last snapshot. Missing current valuation inputs must be explicitly reported, never replaced with zero or purchase prices.
- If the account is currently archived, it contributes zero when D is the Asia/Taipei archive date derived from `ACCOUNTS.UPDATED_AT` or later; earlier dates still use the last-snapshot rule. Retained snapshots are not deleted.
- If the account is currently active, apply the last-snapshot rule to every date. A reactivated account is treated as historically active; previous archive intervals are intentionally not reconstructed.

## APP_SETTINGS

- ID (INTEGER PRIMARY KEY): Singleton row constrained to `1`.
- THEME_MODE (TEXT NOT NULL): One of `SYSTEM`, `LIGHT`, `DARK`.
- LANGUAGE_CODE (TEXT NOT NULL): Selected application language code.
- MARKET_UPDATE_MODE (TEXT NOT NULL): One of `MANUAL`, `EVERY_15_MINUTES`, `AFTER_MARKET_CLOSE`.
- IS_BIOMETRIC_LOCK_ENABLED (INTEGER NOT NULL): User preference only; no biometric credential is stored.
- UPDATED_AT (TEXT NOT NULL): UTC timestamp set on creation and refreshed on each modification.

## Recommended Indexes

- `ACCOUNTS(CATEGORY_ID, IS_ARCHIVED)` for asset and account filters.
- `TRANSACTIONS(OCCURRED_AT DESC, ENTRY_ORDER DESC)` for stable event ordering.
- `STOCK_TRANSACTIONS(SECURITY_ID, STOCK_ACCOUNT_ID)` for holdings and FIFO queries.
- `STOCK_TRANSACTIONS(STOCK_ACCOUNT_ID)` and `STOCK_TRANSACTIONS(FUNDING_ACCOUNT_ID)` for account projections.
- `ACCOUNT_TRANSACTIONS(SOURCE_ACCOUNT_ID)` and `ACCOUNT_TRANSACTIONS(TARGET_ACCOUNT_ID)` for account histories.
- `ACCOUNT_WEEKLY_SNAPSHOTS(SNAPSHOT_DATE, ACCOUNT_ID)` for report trends.

# Data API

The signatures below describe the public methods of the concrete Dart `PortfolioDataApi` class. Public monetary values use `Money(currencyCode, units)`, where `units` is the actual caller-facing amount; share quantities likewise use actual shares. Integer scaling is an internal database-boundary detail and is never required from a caller. Fee inputs and outputs use one combined fee-and-tax amount only for STOCK_BUY, STOCK_SELL, INVESTMENT_BUY and INVESTMENT_SELL; all other kinds have no fee. Only general-account transfers allow differing currencies; stock security and both accounts must share one currency, and all manual investment funding accounts must match their investment account. Funding-account options and submitted overrides are restricted to general accounts. List queries use stable ordering and support pagination when the result can grow without bound. All writes validate input first and commit every related effect atomically.

Public numeric precision:

- `Money.units` is an actual `double`: TWD and JPY accept integers; USD and EUR accept at most two decimal places.
- `ShareQuantity.units` is an actual `double` share count with at most four decimal places.
- Exchange-rate input is an actual `double` with at most two decimal places.
- Report fields named `baseCost`, `baseValue` or `baseRealizedPnl` are TWD integer display units because TWD has zero decimal places.

## Shared interaction contract

- All operations are one-shot asynchronous calls (Future in Dart); signatures below show the resolved result type. There are no watch methods, Streams, subscriptions or database change notifications.
- `PortfolioDataApi.open(databasePath, now?, authenticateBiometric?, marketDataRefresher?) -> PortfolioDataApi` opens or creates the SQLite store and injects optional platform boundaries. `close() -> void` closes its owned connection and is safe to call repeatedly. Other calls after close fail with `DataApiException` using the `closed` error code.
- The logic layer explicitly reloads relevant queries when a view opens or resumes after navigation, and after successful writes, market refreshes or backup restore. Other affected views reload on their next entry. Automatic market-refresh completion must trigger re-querying the currently visible affected view; the Data API does not push updates. Failed writes keep the form/current data and expose an error.

- On confirmation, the caller constructs input from the form and calls create/update directly. Preview is optional, read-only and never a prerequisite or a staging store. Writes re-read and validate within the database transaction; success returns TransactionId (create) or completes (update), and failure throws a typed DataApiException. Keep form values on failure.
- Transaction lists use descending `(OCCURRED_AT, ENTRY_ORDER)` order with stable pagination; financial replay uses ascending order.
- Missing quotes do not prevent recording trades or calculating holdings/cost. If no successful quote or required conversion rate exists, the affected `value` or aggregate total is null and `isValuationComplete` is false; missing data is not represented as zero or purchase price. The current public result DTOs do not expose quote/rate timestamps or a stale flag.

## StockView

- `getStockOverview(marketCode?, stockAccountId?) -> StockOverview`: Fetch filtered active and closed positions, optional TWD totals and `isValuationComplete`.
- `listStockPositions(marketCode?, stockAccountId?, cursor?, limit) -> Page<StockPositionSummary>`: Page through the filtered position list.
- `refreshMarketData() -> MarketRefreshResult`: Refresh quotes and rates without discarding last successful data on failure.

## StockDetailView

- `getStockDetail(securityId, stockAccountId?) -> StockDetail`: Fetch aggregated quantity, FIFO cost, current value, realized/unrealized profit and income.
- `listStockTransactions(securityId, stockAccountId?, kinds?, cursor?, limit) -> Page<AccountTransactionItem>`: List the security's source events in descending transaction-time and insertion order. Items currently contain transaction identity, time, entry order, kind and note.

## StockTransactionView

- `getStockTransactionForm(transactionId?) -> StockTransactionFormData`: Return the security choices and, when editing, the decoded existing transaction. Account choices and funding defaults are not part of this DTO.
- `searchSecurities(query, marketCode?, limit) -> List<SecurityOption>`: Find existing securities by case-insensitive symbol or name, optionally restricted by market.
- `resolveSecurity(input) -> SecurityId`: Validate and create a previously unknown market/symbol pair before its first transaction, or return the existing stable ID.
- `previewStockTransaction(input) -> StockTransactionPreview`: Validate the candidate values and return only the calculated settlement amount without writing. FIFO effects are validated again by create/update.
- `createStockTransaction(input) -> TransactionId`: Atomically create the stock event and funding-account projection.
- `updateStockTransaction(transactionId, input) -> void`: Atomically replace editable values and revalidate all affected later FIFO events.
- `deleteStockTransaction(transactionId) -> void`: Delete the source event only when the remaining history is valid, then recalculate derived results.

## AssetView

- `getAssetOverview(categoryId?) -> AssetOverview`: Fetch filtered account summaries, optional TWD totals and `isValuationComplete`.
- `listAssetAccounts(categoryId?, cursor?, limit) -> Page<AccountSummary>`: Page through non-archived accounts without double-counting investment positions.
- `refreshMarketData() -> MarketRefreshResult`: Share the same quote/rate refresh contract used by `StockView`.

## AccountDetailView

- `getAccountDetail(accountId) -> AccountDetail`: Fetch account metadata, derived cost/value, realized/unrealized profit and archive state.
- `listAccountTransactions(accountId, kinds?, direction?, cursor?, limit) -> Page<AccountTransactionItem>`: List source events and read-only projections with their owning editor type.

## AccountTransactionView

- `getAccountTransactionForm(transactionId?, accountId?) -> AccountTransactionFormData`: Validate an optional initiating account and, when editing, return the decoded existing transaction. Valid kinds and related-account choices are not part of this DTO; STOCK-owned events use StockTransactionView.
- `previewAccountTransaction(input) -> AccountTransactionPreview`: Validate and calculate cost, value, cash-flow and profit effects without writing.
- `createAccountTransaction(input) -> TransactionId`: Atomically create one general-account or manual-investment event.
- `updateAccountTransaction(transactionId, input) -> void`: Atomically replace the event and all derived effects.
- `deleteAccountTransaction(transactionId) -> void`: Atomically delete an account-owned source event; reject stock-owned projections.

## AccountEditView

- `getAccountEditor(accountId?) -> AccountEditorData`: Load categories and optional existing GENERAL account data. For an existing account, the DTO separately includes the saved `initialCost`, `initialValue`, and `note`; these are editable source values and must not be inferred from the calculated current summary. Supported currencies and account-type options are application constants/UI choices, not fields in this DTO.
- `createAccount(input) -> AccountId`: Create a general account with initial cost and value.
- `updateAccount(accountId, input) -> void`: Update permitted metadata and initial values with full-history validation; reject archived accounts. The input never accepts `accountType`.
- `archiveAccount(accountId) -> void`: Archive when no active funding dependency prevents it.
- `reactivateAccount(accountId) -> void`: Restore the same account and history.

## AccountEditView-invest

- `getInvestmentAccountEditor(accountId?, createAccountType?) -> InvestmentAccountEditorData`: For creation, accept the selected STOCK or INVESTMENT type; for editing, return the existing account. Load categories and all active GENERAL funding-account candidates; create/update performs the final same-currency validation.
- `createInvestmentAccount(input) -> AccountId`: Create the explicitly selected STOCK or INVESTMENT account type with a required same-currency GENERAL funding account.
- `updateInvestmentAccount(accountId, input) -> void`: Update permitted STOCK/INVESTMENT metadata and the default for future settlements only; allow INVESTMENT initial-value edits with full-history validation, keep STOCK initial values zero, and reject archived accounts. The input never accepts `accountType`.
- `archiveAccount(accountId) -> void`: Use the shared account archive contract.
- `reactivateAccount(accountId) -> void`: Use the shared account reactivation contract.

## ReportView

- `getCurrentAllocation() -> AllocationReport`: Derive current TWD value and percentage by current category without double-counting positions.
- `getCurrentCostValueComparison(groupBy) -> CostValueReport`: Compare current cost and value by category or account.
- `captureWeeklySnapshots(snapshotDate) -> int`: For the requested Taipei `YYYY-MM-DD` date, insert at most one snapshot per active account for that week, skipping accounts whose current valuation or conversion rate is unavailable; return the number inserted.
- `getHistoricalTrend(period) -> HistoricalTrendReport`: Return dated historical points from weekly account snapshots, carrying forward each account's latest snapshot at or before each date, using zero when absent and applying the archive-date rule. Include a separately identified “now” point calculated from current account totals, not snapshots; expose missing valuation inputs. Period options remain 3M, 6M, 1Y, 3Y and all.

## Market data boundary

- `refreshMarketData() -> MarketRefreshResult`: Invoke the injected market-data refresher. The result contains quote-success count, rate-success count and failure messages; when no refresher was injected, throw `DataApiException` with the `unavailable` error code.
- `saveStockPrice(securityId, price, quotedAt) -> void`: Insert or replace the latest successful positive quote. `price` must use the security currency; `quotedAt` is converted to UTC.
- `saveExchangeRate(fromCurrencyCode, rate, quotedAt) -> void`: Insert or replace the latest successful non-TWD-to-TWD rate. `rate` is a positive actual value with at most two decimals; `quotedAt` is converted to UTC.

## SettingView

- `getAppSettings() -> AppSettings`: Fetch persisted theme, language, update mode and biometric-lock preference.
- `updateAppSettings(patch) -> AppSettings`: Atomically persist only supplied preference fields.
- `setBiometricLockEnabled(enabled) -> AppSettings`: Persist the preference only after the platform authentication boundary succeeds.

## CategoryManagerView

- `listCategories() -> List<CategorySummary>`: Fetch categories in user-defined order with current account usage counts.
- `createCategory(input) -> CategoryId`: Create a category with a stable ID.
- `updateCategory(categoryId, input) -> void`: Rename or recolor without changing historical financial data.
- `reorderCategories(orderedCategoryIds) -> void`: Atomically replace category display order.
- `deleteCategory(categoryId, replacementCategoryId?) -> void`: Reject if any archived account references the category; otherwise atomically reassign active accounts when required, then delete. Never leave zero categories.

## AccountManagerView

- `listManagedAccounts(status?, accountType?, categoryId?) -> List<ManagedAccountSummary>`: Fetch active and archived accounts with funding dependencies.
- `archiveAccount(accountId) -> void`: Reject archive when another active STOCK or INVESTMENT account still depends on it as funding source.
- `reactivateAccount(accountId) -> void`: Reactivate the same stable account.

## DataManagerView

- `exportBackup(destination) -> ExportResult`: Export every database table as CSV files plus a checksummed manifest inside one ZIP archive. Return the written path and exported table count.
- `inspectBackup(source) -> BackupInspection`: Validate archive format, checksums, schema version, table structure and values without modifying the database. Return source path, schema version, creation timestamp and row counts by table.
- `replaceFromBackup(source) -> ImportResult`: Validate and atomically replace all database rows, or leave the original database unchanged on failure. Return imported row counts by table.
