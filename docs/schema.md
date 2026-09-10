# Database Schema

## Conventions

- Database: SQLite with `PRAGMA foreign_keys = ON`.
- ID fields use application-generated UUID strings.
- Dates use ISO 8601 `YYYY-MM-DD`; timestamps use UTC ISO 8601 strings; snapshot months use `YYYY-MM`.
- Currency codes use ISO 4217 uppercase strings. The base currency is fixed to `TWD` in the first version.
- Field names omit scaling suffixes (for example, `FEE`, `RATE`, `QUANTITY`); storage multipliers are defined in an application constant lookup table, not a database table or per-row field.
- Money uses scaled `INTEGER` values: stored value = amount × `MONEY_MULTIPLIER[currencyCode]`.
- Currency precision is defined by application constants, not database columns: `MONEY_DECIMAL_PLACES = {TWD: 0, JPY: 0, USD: 2, EUR: 2}`; `MONEY_MULTIPLIER = {TWD: 1, JPY: 1, USD: 100, EUR: 100}`.
- The currency of each field determines its multiplier, including prices, fees, settlement amounts and snapshots. For example, TWD 123 is stored as 123; USD 123.45 is stored as 12345.
- Unsupported currencies require an explicit precision constant before use; never infer a default multiplier.
- Precision constants are part of the versioned schema/backup contract. Changing an existing currency multiplier requires a schema migration and compatible import conversion, even though the constants are not stored per row.
- All exchange rates use two decimal places, independent of currency-specific money precision. Application constants: `EXCHANGE_RATE_DECIMAL_PLACES = 2`, `EXCHANGE_RATE_MULTIPLIER = 100`; for example, rate 32.15 is stored as 3215.
- Share quantities use scaled `INTEGER` values: stored value = display value × 100.
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
- A category referenced by an account cannot be deleted until those accounts are atomically reassigned.
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
- IS_ARCHIVED (INTEGER NOT NULL): Current archive state. Archived accounts keep all relations but contribute zero from the archive month onward.
- UPDATED_AT (TEXT NOT NULL): UTC timestamp set on creation and refreshed on each modification.

Rules:

- `FUNDING_ACCOUNT_ID` is required for STOCK and INVESTMENT accounts and must be null for general accounts; it cannot reference the same account.
- Every `FUNDING_ACCOUNT_ID`, including transaction-level overrides, must reference a general account (`ACCOUNT_TYPE = GENERAL`); newly selected funding accounts must also be non-archived.
- Enforce the general-account requirement on account and stock-transaction inserts/updates and backup import. Foreign keys alone only validate existence.
- Default and actual funding accounts must share their STOCK or INVESTMENT account currency; account edits and backup import must preserve this constraint.
- Changing a default funding account affects only new transactions; each transaction stores its actual account relation.
- Accounts are never deleted. `ACCOUNT_TYPE` cannot be updated after insertion, even when the account has no financial history. Existing financial history also prevents changing currency.
- Initial values form the account opening baseline before its transaction history; UPDATED_AT changes do not change when that baseline applies.
- STOCK accounts require INITIAL_COST = 0 and INITIAL_VALUE = 0: enforce CHECK (ACCOUNT_TYPE <> 'STOCK' OR (INITIAL_COST = 0 AND INITIAL_VALUE = 0)). Apply the same rule on creation and backup import. Stock holdings and cost originate from stock transactions, not opening amounts.
- Negative initial values are valid for non-STOCK accounts; negative general-account balances are valid.
- While `IS_ARCHIVED = 1`, the account cannot be edited; its `UPDATED_AT` therefore identifies the archive time. For monthly reports, convert it to the archive month and count the account as zero from that month onward.
- Reactivation sets `IS_ARCHIVED = 0` and refreshes `UPDATED_AT`. Archive intervals are not historical data: after reactivation, treat the account as active for all historical months and calculate them from snapshots normally.

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
- OCCURRED_ON (TEXT NOT NULL): User-entered event date as `YYYY-MM-DD`.
- NOTE (TEXT NULL): Optional user note.
- UPDATED_AT (TEXT NOT NULL): UTC timestamp set on creation and refreshed on each modification.

Rules:

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
- Editing/deleting events revalidates subsequent FIFO results atomically; monthly snapshots remain unchanged.

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
- Disposed cost, sale proportion and profit are derived, not separate stored fields. Editing/deleting earlier events must revalidate and recalculate later manual sales atomically; saved monthly snapshots remain unchanged.
- Interest: AMOUNT is both the funding receipt and investment realized income. No fee; investment cost/value are unchanged.
- Value adjustment changes investment value and unrealized profit only; no cash flow or fee.
- Fields omitted from a kind below must be null. Applicable FEE fields are required and nonnegative. AMOUNT and actual cash amounts must be positive; sell FEE cannot exceed AMOUNT. General-account balances may be negative.
- All events use one parent and one subtype row; two-account effects are projections of the same event.

### Fields used by each KIND

All kinds use TRANSACTIONS.ID, KIND, OCCURRED_ON, UPDATED_AT and optional NOTE. Each subtype uses TRANSACTION_ID.

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

## ACCOUNT_MONTHLY_SNAPSHOTS

- ID (TEXT PRIMARY KEY): Stable snapshot UUID.
- ACCOUNT_ID (TEXT NOT NULL REFERENCES ACCOUNTS.ID): Account represented by this snapshot.
- SNAPSHOT_MONTH (TEXT NOT NULL): Calendar month as `YYYY-MM`.
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

- `(ACCOUNT_ID, SNAPSHOT_MONTH)` is unique.
- Snapshot values are immutable historical facts and are never updated by later prices or exchange rates.
- For target month D, each account uses its snapshot with the greatest `SNAPSHOT_MONTH <= D`; when no such snapshot exists, its cost, value and realized profit are all zero.
- A report month does not require snapshots for every account and has no complete/incomplete state. A prior snapshot carries forward until a later snapshot supersedes it.
- If the account is currently archived, it contributes zero when D is the archive month derived from `ACCOUNTS.UPDATED_AT` or later; earlier months still use the last-snapshot rule. Retained snapshots are not deleted.
- If the account is currently active, apply the last-snapshot rule to every month. A reactivated account is treated as historically active; previous archive intervals are intentionally not reconstructed.

## APP_SETTINGS

- ID (INTEGER PRIMARY KEY): Singleton row constrained to `1`.
- THEME_MODE (TEXT NOT NULL): One of `SYSTEM`, `LIGHT`, `DARK`.
- LANGUAGE_CODE (TEXT NOT NULL): Selected application language code.
- MARKET_UPDATE_MODE (TEXT NOT NULL): One of `MANUAL`, `EVERY_15_MINUTES`, `AFTER_MARKET_CLOSE`.
- IS_BIOMETRIC_LOCK_ENABLED (INTEGER NOT NULL): User preference only; no biometric credential is stored.
- UPDATED_AT (TEXT NOT NULL): UTC timestamp set on creation and refreshed on each modification.

## Recommended Indexes

- `ACCOUNTS(CATEGORY_ID, IS_ARCHIVED)` for asset and account filters.
- `TRANSACTIONS(OCCURRED_ON DESC, ID)` for stable event ordering.
- `STOCK_TRANSACTIONS(SECURITY_ID, STOCK_ACCOUNT_ID)` for holdings and FIFO queries.
- `STOCK_TRANSACTIONS(STOCK_ACCOUNT_ID)` and `STOCK_TRANSACTIONS(FUNDING_ACCOUNT_ID)` for account projections.
- `ACCOUNT_TRANSACTIONS(SOURCE_ACCOUNT_ID)` and `ACCOUNT_TRANSACTIONS(TARGET_ACCOUNT_ID)` for account histories.
- `ACCOUNT_MONTHLY_SNAPSHOTS(SNAPSHOT_MONTH, ACCOUNT_ID)` for report trends.

# Data API

The signatures below describe repository contracts, not concrete Dart classes. All monetary inputs and outputs carry a currency code and an integer scaled by the application currency constants. Fee inputs and outputs use one combined fee-and-tax amount only for STOCK_BUY, STOCK_SELL, INVESTMENT_BUY and INVESTMENT_SELL; all other kinds have no fee. Only general-account transfers allow differing currencies; stock security and both accounts must share one currency, and all manual investment funding accounts must match their investment account; funding-account options and submitted overrides are restricted to general accounts; list queries use stable ordering and support pagination when the result can grow without bound. All writes validate input first and commit every related effect atomically.

## StockView

- `watchStockOverview(marketCode?, stockAccountId?) -> StockOverview`: Observe filtered active and closed positions, totals, quote/rate timestamps and stale state.
- `listStockPositions(marketCode?, stockAccountId?, cursor?, limit) -> Page<StockPositionSummary>`: Page through the filtered position list.
- `refreshMarketData() -> MarketRefreshResult`: Refresh quotes and rates without discarding last successful data on failure.

## StockDetailView

- `watchStockDetail(securityId, stockAccountId?) -> StockDetail`: Observe aggregated quantity, FIFO cost, current value, realized/unrealized profit and income.
- `listStockTransactions(securityId, stockAccountId?, kinds?, cursor?, limit) -> Page<StockTransactionItem>`: List the security's source events in descending date order.

## StockTransactionView

- `getStockTransactionForm(transactionId?) -> StockTransactionFormData`: Load an existing event or creation options, including securities, eligible STOCK accounts and same-currency GENERAL funding defaults.
- `searchSecurities(marketCode, query, limit) -> List<SecurityOption>`: Find existing securities by normalized symbol or name for a new transaction.
- `resolveSecurity(input) -> SecurityId`: Validate and create a previously unknown market/symbol pair before its first transaction, or return the existing stable ID.
- `previewStockTransaction(input) -> StockTransactionPreview`: Validate input and calculate trade, settlement and projected FIFO effects without writing.
- `createStockTransaction(input) -> TransactionId`: Atomically create the stock event and funding-account projection.
- `updateStockTransaction(transactionId, input) -> void`: Atomically replace editable values and revalidate all affected later FIFO events.
- `deleteStockTransaction(transactionId) -> void`: Delete the source event only when the remaining history is valid, then recalculate derived results.

## AssetView

- `watchAssetOverview(categoryId?) -> AssetOverview`: Observe filtered account summaries, totals, conversion timestamps and stale state.
- `listAssetAccounts(categoryId?, cursor?, limit) -> Page<AccountSummary>`: Page through non-archived accounts without double-counting investment positions.
- `refreshMarketData() -> MarketRefreshResult`: Share the same quote/rate refresh contract used by `StockView`.

## AccountDetailView

- `watchAccountDetail(accountId) -> AccountDetail`: Observe account metadata, derived cost/value, realized/unrealized profit and archive state.
- `listAccountTransactions(accountId, kinds?, direction?, cursor?, limit) -> Page<AccountTransactionItem>`: List source events and read-only projections with their owning editor type.

## AccountTransactionView

- `getAccountTransactionForm(transactionId?, accountId?) -> AccountTransactionFormData`: Load valid kinds for GENERAL or INVESTMENT accounts, eligible related accounts, currencies and existing values; STOCK-owned events use StockTransactionView.
- `previewAccountTransaction(input) -> AccountTransactionPreview`: Validate and calculate cost, value, cash-flow and profit effects without writing.
- `createAccountTransaction(input) -> TransactionId`: Atomically create one general-account or manual-investment event.
- `updateAccountTransaction(transactionId, input) -> void`: Atomically replace the event and all derived effects.
- `deleteAccountTransaction(transactionId) -> void`: Atomically delete an account-owned source event; reject stock-owned projections.

## AccountEditView

- `getAccountEditor(accountId?) -> AccountEditorData`: Load categories, supported currencies, the three account-type options and existing account data.
- `createAccount(input) -> AccountId`: Create a general account with initial cost and value.
- `updateAccount(accountId, input) -> void`: Update permitted metadata; the input never accepts `accountType`.
- `archiveAccount(accountId) -> void`: Archive when no active funding dependency prevents it.
- `reactivateAccount(accountId) -> void`: Restore the same account and history.

## AccountEditView-invest

- `getInvestmentAccountEditor(accountId?, createAccountType?) -> InvestmentAccountEditorData`: For creation, accept the selected STOCK or INVESTMENT type; for editing, derive the immutable type from `accountId`. Load categories and same-currency GENERAL funding accounts.
- `createInvestmentAccount(input) -> AccountId`: Create the explicitly selected STOCK or INVESTMENT account type with a required same-currency GENERAL funding account.
- `updateInvestmentAccount(accountId, input) -> void`: Update permitted STOCK/INVESTMENT metadata and the default for future settlements only; the input never accepts `accountType`.
- `archiveAccount(accountId) -> void`: Use the shared account archive contract.
- `reactivateAccount(accountId) -> void`: Use the shared account reactivation contract.

## ReportView

- `getCurrentAllocation() -> AllocationReport`: Derive current TWD value and percentage by current category without double-counting positions.
- `getCurrentCostValueComparison(groupBy) -> CostValueReport`: Compare current cost and value by category or account.
- `getMonthlyTrend(period) -> MonthlyTrendReport`: For each month and account, carry forward the latest snapshot at or before that month, use zero when absent, apply the current archive rule, then aggregate TWD cost, value and realized profit.

## SettingView

- `watchAppSettings() -> AppSettings`: Observe persisted theme, language, update mode and biometric-lock preference.
- `updateAppSettings(patch) -> AppSettings`: Atomically persist only supplied preference fields.
- `setBiometricLockEnabled(enabled) -> AppSettings`: Persist the preference only after the platform authentication boundary succeeds.

## CategoryManagerView

- `watchCategories() -> List<CategorySummary>`: Observe categories in user-defined order with current account usage counts.
- `createCategory(input) -> CategoryId`: Create a category with a stable ID.
- `updateCategory(categoryId, input) -> void`: Rename or recolor without changing historical financial data.
- `reorderCategories(orderedCategoryIds) -> void`: Atomically replace category display order.
- `deleteCategory(categoryId, replacementCategoryId?) -> void`: Atomically reassign all current accounts when required, then delete; never leave zero categories.

## AccountManagerView

- `watchManagedAccounts(status?, accountType?, categoryId?) -> List<ManagedAccountSummary>`: Observe active and archived accounts with funding dependencies.
- `archiveAccount(accountId) -> void`: Reject archive when another active STOCK or INVESTMENT account still depends on it as funding source.
- `reactivateAccount(accountId) -> void`: Reactivate the same stable account.

## DataManagerView

- `exportBackup(destination) -> ExportResult`: Export schema metadata and every database table as CSV files inside one archive.
- `inspectBackup(source) -> BackupInspection`: Validate archive integrity, schema compatibility, table structure and relations without modifying the database.
- `replaceFromBackup(source) -> ImportResult`: After confirmation, atomically replace all database rows or leave the original database unchanged.
