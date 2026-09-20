import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'models/data_api_exception.dart';
import 'models/domain.dart';
import 'models/money.dart';
import 'src/database/portfolio_database.dart';
import 'src/ledger/arithmetic.dart';

typedef BiometricAuthenticator = Future<bool> Function();
typedef MarketDataRefresher = Future<MarketRefreshResult> Function(
  PortfolioDataApi api,
);

class PortfolioDataApi {
  final PortfolioDatabase _database;
  final DateTime Function() _now;
  final Uuid _uuid;
  final BiometricAuthenticator? _authenticateBiometric;
  final MarketDataRefresher? _marketDataRefresher;
  bool _closed = false;

  PortfolioDataApi._(
    this._database,
    this._now,
    this._uuid,
    this._authenticateBiometric,
    this._marketDataRefresher,
  );

  /// Opens and initializes the portfolio data store.
  ///
  /// Parameters
  /// ----------
  /// databasePath : `String`
  ///     Path of the SQLite database to open or create.
  /// now : `DateTime Function()?`
  ///     Optional clock used for validation and timestamps.
  /// authenticateBiometric : `BiometricAuthenticator?`
  ///     Optional biometric callback used when enabling the lock.
  /// marketDataRefresher : `MarketDataRefresher?`
  ///     Optional callback used to refresh quotes and exchange rates.
  ///
  /// Returns
  /// -------
  /// `Future<PortfolioDataApi>`
  ///     An initialized API instance that owns the database connection.
  ///
  /// Raises
  /// ------
  /// `SqliteException`
  ///     If the database cannot be opened or initialized.
  static Future<PortfolioDataApi> open({
    required String databasePath,
    DateTime Function()? now,
    BiometricAuthenticator? authenticateBiometric,
    MarketDataRefresher? marketDataRefresher,
  }) async {
    return PortfolioDataApi._(
      PortfolioDatabase.open(databasePath),
      now ?? DateTime.now,
      const Uuid(),
      authenticateBiometric,
      marketDataRefresher,
    );
  }

  /// Closes the database connection owned by this API.
  ///
  /// Parameters
  /// ----------
  /// `None`
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after the connection is closed; repeated calls are safe.
  ///
  /// Raises
  /// ------
  /// `None`
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      _database.close();
    }
  }

  /// Creates a general account.
  ///
  /// Parameters
  /// ----------
  /// input : `CreateAccountInput`
  ///     Name, category, currency, opening values, and optional note.
  ///
  /// Returns
  /// -------
  /// `Future<AccountId>`
  ///     The stable ID of the newly created account.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If a field, currency, precision, or category is invalid.
  Future<AccountId> createAccount(CreateAccountInput input) async {
    _ensureOpen();
    _validateAccountFields(input.name, input.categoryId, input.currencyCode);
    final id = _uuid.v4();
    _database.insert('ACCOUNTS', {
      'ID': id,
      'NAME': input.name.trim(),
      'CATEGORY_ID': input.categoryId,
      'CURRENCY_CODE': input.currencyCode,
      'ACCOUNT_TYPE': 'GENERAL',
      'FUNDING_ACCOUNT_ID': null,
      'INITIAL_COST': Money(
        currencyCode: input.currencyCode,
        units: input.initialCost,
      ).scaledUnits,
      'INITIAL_VALUE': Money(
        currencyCode: input.currencyCode,
        units: input.initialValue,
      ).scaledUnits,
      'NOTE': input.note,
      'IS_ARCHIVED': 0,
      'UPDATED_AT': _utcNow(),
    });
    return id;
  }

  /// Creates a stock or manually valued investment account.
  ///
  /// Parameters
  /// ----------
  /// input : `CreateInvestmentAccountInput`
  ///     Account values, immutable type, and funding account relation.
  ///
  /// Returns
  /// -------
  /// `Future<AccountId>`
  ///     The stable ID of the newly created account.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If fields are invalid or the funding account is incompatible.
  Future<AccountId> createInvestmentAccount(
    CreateInvestmentAccountInput input,
  ) async {
    _ensureOpen();
    _validateAccountFields(input.name, input.categoryId, input.currencyCode);
    if (input.accountType == AccountType.general) {
      _fail('Investment editor accepts STOCK or INVESTMENT');
    }
    if (input.fundingAccountId.trim().isEmpty) {
      _fail('Funding account is required');
    }
    final funding = _account(input.fundingAccountId);
    _requireActive(funding);
    if (_accountType(funding) != AccountType.general ||
        funding['CURRENCY_CODE'] != input.currencyCode) {
      _fail('Funding account must be same-currency GENERAL');
    }
    if (input.accountType == AccountType.stock &&
        (input.initialCost != 0 || input.initialValue != 0)) {
      _fail('Stock initial values must be zero');
    }
    final id = _uuid.v4();
    _database.insert('ACCOUNTS', {
      'ID': id,
      'NAME': input.name.trim(),
      'CATEGORY_ID': input.categoryId,
      'CURRENCY_CODE': input.currencyCode,
      'ACCOUNT_TYPE': _accountTypeText(input.accountType),
      'FUNDING_ACCOUNT_ID': input.fundingAccountId,
      'INITIAL_COST': Money(
        currencyCode: input.currencyCode,
        units: input.initialCost,
      ).scaledUnits,
      'INITIAL_VALUE': Money(
        currencyCode: input.currencyCode,
        units: input.initialValue,
      ).scaledUnits,
      'NOTE': input.note,
      'IS_ARCHIVED': 0,
      'UPDATED_AT': _utcNow(),
    });
    return id;
  }

  /// Updates an active general account without changing its type.
  ///
  /// Parameters
  /// ----------
  /// id : `AccountId`
  ///     ID of the general account to update.
  /// input : `UpdateAccountInput`
  ///     Complete replacement values for editable account fields.
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after the update and ledger replay succeed.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the account is missing, archived, incompatible, or invalid.
  Future<void> updateAccount(AccountId id, UpdateAccountInput input) async =>
      _updateAccount(id, input, allowInvestment: false);

  /// Updates an active stock or investment account without changing its type.
  ///
  /// Parameters
  /// ----------
  /// id : `AccountId`
  ///     ID of the stock or investment account to update.
  /// input : `UpdateAccountInput`
  ///     Complete replacement values for editable account fields.
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after the update and ledger replay succeed.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the account or funding relation is invalid.
  Future<void> updateInvestmentAccount(
    AccountId id,
    UpdateAccountInput input,
  ) async => _updateAccount(id, input, allowInvestment: true);
  Future<void> _updateAccount(
    String id,
    UpdateAccountInput input, {
    required bool allowInvestment,
  }) async {
    _ensureOpen();
    _validateAccountFields(input.name, input.categoryId, input.currencyCode);
    _database.atomic(() {
      final old = _account(id);
      _requireActive(old);
      final type = _accountType(old);
      if ((type == AccountType.general) == allowInvestment) {
        _fail('Wrong account editor');
      }
      if (type == AccountType.stock &&
          (input.initialCost != 0 || input.initialValue != 0)) {
        _fail('Stock initial values must be zero');
      }
      final hasHistory = _transactionRowsForAccount(id).isNotEmpty;
      if (hasHistory && old['CURRENCY_CODE'] != input.currencyCode) {
        _fail('Currency cannot change after financial history');
      }
      String? funding;
      if (type != AccountType.general) {
        funding = input.fundingAccountId;
        if (funding == null || funding.trim().isEmpty) {
          _fail('Funding account is required');
        }
        final row = _account(funding);
        _requireActive(row);
        if (_accountType(row) != AccountType.general ||
            row['CURRENCY_CODE'] != input.currencyCode) {
          _fail('Funding account must be same-currency GENERAL');
        }
      }
      _database.raw.execute(
        'UPDATE ACCOUNTS SET NAME=?,CATEGORY_ID=?,CURRENCY_CODE=?,FUNDING_ACCOUNT_ID=?,INITIAL_COST=?,INITIAL_VALUE=?,NOTE=?,UPDATED_AT=? WHERE ID=?',
        [
          input.name.trim(),
          input.categoryId,
          input.currencyCode,
          funding,
          Money(
            currencyCode: input.currencyCode,
            units: input.initialCost,
          ).scaledUnits,
          Money(
            currencyCode: input.currencyCode,
            units: input.initialValue,
          ).scaledUnits,
          input.note,
          _utcNow(),
          id,
        ],
      );
      _validateAllHistory();
    });
  }

  /// Archives an active account without deleting its history.
  ///
  /// Parameters
  /// ----------
  /// id : `AccountId`
  ///     ID of the account to archive.
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after the archive flag and timestamp are saved.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the account is missing, already archived, or still funds an active account.
  Future<void> archiveAccount(AccountId id) async {
    _database.atomic(() {
      final row = _account(id);
      _requireActive(row);
      final dependencies = _database.raw.select(
        "SELECT 1 FROM ACCOUNTS WHERE FUNDING_ACCOUNT_ID=? AND IS_ARCHIVED=0 LIMIT 1",
        [id],
      );
      if (dependencies.isNotEmpty) {
        _conflict('Account is an active funding source');
      }
      _database.raw.execute(
        'UPDATE ACCOUNTS SET IS_ARCHIVED=1,UPDATED_AT=? WHERE ID=?',
        [_utcNow(), id],
      );
    });
  }

  /// Reactivates an archived account.
  ///
  /// Parameters
  /// ----------
  /// id : `AccountId`
  ///     ID of the archived account to reactivate.
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after the account is active again.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the account state or funding relation is invalid.
  Future<void> reactivateAccount(AccountId id) async {
    final row = _account(id);
    if (row['IS_ARCHIVED'] != 1) _conflict('Account is not archived');
    if (_accountType(row) != AccountType.general) {
      final funding = _account(row['FUNDING_ACCOUNT_ID'] as String);
      _requireActive(funding);
    }
    _database.raw.execute(
      'UPDATE ACCOUNTS SET IS_ARCHIVED=0,UPDATED_AT=? WHERE ID=?',
      [_utcNow(), id],
    );
  }

  /// Finds a security by market and symbol or creates it when absent.
  ///
  /// Parameters
  /// ----------
  /// input : `ResolveSecurityInput`
  ///     Normalized identity, display name, currency, and optional quote symbol.
  ///
  /// Returns
  /// -------
  /// `Future<SecurityId>`
  ///     The existing or newly generated security ID.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If fields are invalid or an existing security uses another currency.
  Future<SecurityId> resolveSecurity(ResolveSecurityInput input) async {
    _ensureOpen();
    final symbol = input.symbol.trim().toUpperCase(),
        market = input.marketCode.trim().toUpperCase();
    if (symbol.isEmpty ||
        input.name.trim().isEmpty ||
        market.isEmpty ||
        !moneyMultipliers.containsKey(input.currencyCode)) {
      _fail('Invalid security');
    }
    final existing = _database.raw.select(
      'SELECT ID,CURRENCY_CODE FROM SECURITIES WHERE MARKET_CODE=? AND SYMBOL=?',
      [market, symbol],
    );
    if (existing.isNotEmpty) {
      if (existing.first['CURRENCY_CODE'] != input.currencyCode) {
        _conflict('Existing security has another currency');
      }
      return existing.first['ID'] as String;
    }
    final id = _uuid.v4();
    _database.insert('SECURITIES', {
      'ID': id,
      'SYMBOL': symbol,
      'NAME': input.name.trim(),
      'MARKET_CODE': market,
      'CURRENCY_CODE': input.currencyCode,
      'QUOTE_SYMBOL': input.quoteSymbol,
      'UPDATED_AT': _utcNow(),
    });
    return id;
  }

  /// Creates one stock buy, sell, or dividend event atomically.
  ///
  /// Parameters
  /// ----------
  /// input : `StockTransactionInput`
  ///     Complete event data using actual money amounts and share quantities.
  ///
  /// Returns
  /// -------
  /// `Future<TransactionId>`
  ///     The ID shared by all projections of the new economic event.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If time, accounts, currencies, amounts, or resulting holdings are invalid.
  Future<TransactionId> createStockTransaction(
    StockTransactionInput input,
  ) async => _writeStock(null, input);

  /// Replaces an existing stock transaction while retaining its insertion order.
  ///
  /// Parameters
  /// ----------
  /// id : `TransactionId`
  ///     ID of the stock transaction to replace.
  /// input : `StockTransactionInput`
  ///     Complete replacement event data.
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after atomic replacement and ledger replay.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the event is missing, archived, malformed, or makes history invalid.
  Future<void> updateStockTransaction(
    TransactionId id,
    StockTransactionInput input,
  ) async {
    await _writeStock(id, input);
  }

  Future<TransactionId> _writeStock(
    String? id,
    StockTransactionInput input,
  ) async {
    _validateOccurredAt(input.occurredAt);
    _validateStockAmounts(input);
    return _database.atomic(() {
      final stock = _account(input.stockAccountId),
          funding = _account(input.fundingAccountId),
          security = _security(input.securityId);
      _requireActive(stock);
      _requireActive(funding);
      if (_accountType(stock) != AccountType.stock ||
          _accountType(funding) != AccountType.general) {
        _fail('Invalid stock/funding account type');
      }
      if ({
            stock['CURRENCY_CODE'],
            funding['CURRENCY_CODE'],
            security['CURRENCY_CODE'],
          }.length !=
          1) {
        _fail('Security and accounts must share currency');
      }
      final inputCurrencies = input is StockDividendInput
          ? [input.dividendAmount.currencyCode]
          : input is StockBuyInput
          ? [input.unitPrice.currencyCode, input.fee.currencyCode]
          : [
              (input as StockSellInput).unitPrice.currencyCode,
              input.fee.currencyCode,
            ];
      if (inputCurrencies.any(
        (currency) => currency != stock['CURRENCY_CODE'],
      )) {
        _fail('Stock amounts must use account currency');
      }
      var order = 0;
      if (id != null) {
        final old = _stockEvent(id);
        _requireEventAccountsActive(old);
        order = old['ENTRY_ORDER'] as int;
        _database.raw.execute('DELETE FROM TRANSACTIONS WHERE ID=?', [id]);
      }
      final transactionId = id ?? _uuid.v4();
      if (id == null) order = _nextOrder();
      _insertParent(
        transactionId,
        input.kind,
        input.occurredAt,
        order,
        input.note,
      );
      final buy = input is StockBuyInput,
          sell = input is StockSellInput,
          dividend = input is StockDividendInput;
      _database.insert('STOCK_TRANSACTIONS', {
        'TRANSACTION_ID': transactionId,
        'SECURITY_ID': input.securityId,
        'STOCK_ACCOUNT_ID': input.stockAccountId,
        'FUNDING_ACCOUNT_ID': input.fundingAccountId,
        'QUANTITY': buy
            ? input.quantity.scaledUnits
            : sell
            ? input.quantity.scaledUnits
            : null,
        'UNIT_PRICE': buy
            ? input.unitPrice.scaledUnits
            : sell
            ? input.unitPrice.scaledUnits
            : null,
        'DIVIDEND_AMOUNT': dividend ? input.dividendAmount.scaledUnits : null,
        'FEE': buy
            ? input.fee.scaledUnits
            : sell
            ? input.fee.scaledUnits
            : null,
      });
      _validateAllHistory();
      return transactionId;
    });
  }

  /// Deletes a stock transaction when the remaining history stays valid.
  ///
  /// Parameters
  /// ----------
  /// id : `String`
  ///     ID of the stock transaction to delete.
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after atomic deletion and ledger replay.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the event is missing, involves an archived account, or deletion invalidates history.
  Future<void> deleteStockTransaction(String id) async {
    _database.atomic(() {
      final row = _stockEvent(id);
      _requireEventAccountsActive(row);
      _database.raw.execute('DELETE FROM TRANSACTIONS WHERE ID=?', [id]);
      _validateAllHistory();
    });
  }

  /// Creates one general-account or manual-investment event atomically.
  ///
  /// Parameters
  /// ----------
  /// input : `AccountTransactionInput`
  ///     Complete transfer, income, expense, investment, interest, or adjustment data.
  ///
  /// Returns
  /// -------
  /// `Future<TransactionId>`
  ///     The ID shared by all projections of the new economic event.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If time, participants, currencies, amounts, or resulting ledgers are invalid.
  Future<TransactionId> createAccountTransaction(
    AccountTransactionInput input,
  ) async => _writeAccountEvent(null, input);

  /// Replaces an account transaction while retaining its insertion order.
  ///
  /// Parameters
  /// ----------
  /// id : `String`
  ///     ID of the account transaction to replace.
  /// input : `AccountTransactionInput`
  ///     Complete replacement event data.
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after atomic replacement and ledger replay.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the event is missing, archived, malformed, or makes history invalid.
  Future<void> updateAccountTransaction(
    String id,
    AccountTransactionInput input,
  ) async {
    await _writeAccountEvent(id, input);
  }

  Future<TransactionId> _writeAccountEvent(
    String? id,
    AccountTransactionInput input,
  ) async {
    _validateOccurredAt(input.occurredAt);
    _validateAccountEventAmounts(input);
    return _database.atomic(() {
      if (id != null) {
        final old = _accountEvent(id);
        _requireEventAccountsActive(old);
        final order = old['ENTRY_ORDER'] as int;
        _database.raw.execute('DELETE FROM TRANSACTIONS WHERE ID=?', [id]);
        _insertAccountEvent(id, input, order);
        _validateAllHistory();
        return id;
      }
      final newId = _uuid.v4();
      _insertAccountEvent(newId, input, _nextOrder());
      _validateAllHistory();
      return newId;
    });
  }

  void _insertAccountEvent(
    String id,
    AccountTransactionInput input,
    int order,
  ) {
    final fields = <String, Object?>{
      'TRANSACTION_ID': id,
      'INVESTMENT_ACCOUNT_ID': null,
      'SOURCE_ACCOUNT_ID': null,
      'TARGET_ACCOUNT_ID': null,
      'SOURCE_AMOUNT': null,
      'TARGET_AMOUNT': null,
      'AMOUNT': null,
      'VALUE_ADJUSTMENT': null,
      'FEE': null,
    };
    if (input is AccountTransferInput) {
      fields.addAll({
        'SOURCE_ACCOUNT_ID': input.sourceAccountId,
        'TARGET_ACCOUNT_ID': input.targetAccountId,
        'SOURCE_AMOUNT': input.sourceAmount.scaledUnits,
        'TARGET_AMOUNT': input.targetAmount.scaledUnits,
      });
    } else if (input is AccountIncomeInput) {
      fields.addAll({
        'TARGET_ACCOUNT_ID': input.targetAccountId,
        'TARGET_AMOUNT': input.targetAmount.scaledUnits,
      });
    } else if (input is AccountExpenseInput) {
      fields.addAll({
        'SOURCE_ACCOUNT_ID': input.sourceAccountId,
        'SOURCE_AMOUNT': input.sourceAmount.scaledUnits,
      });
    } else if (input is InvestmentBuyInput) {
      fields.addAll({
        'INVESTMENT_ACCOUNT_ID': input.investmentAccountId,
        'SOURCE_ACCOUNT_ID': input.sourceAccountId,
        'AMOUNT': input.amount.scaledUnits,
        'FEE': input.fee.scaledUnits,
      });
    } else if (input is InvestmentSellInput) {
      fields.addAll({
        'INVESTMENT_ACCOUNT_ID': input.investmentAccountId,
        'TARGET_ACCOUNT_ID': input.targetAccountId,
        'AMOUNT': input.amount.scaledUnits,
        'FEE': input.fee.scaledUnits,
      });
    } else if (input is InvestmentInterestInput) {
      fields.addAll({
        'INVESTMENT_ACCOUNT_ID': input.investmentAccountId,
        'TARGET_ACCOUNT_ID': input.targetAccountId,
        'AMOUNT': input.amount.scaledUnits,
      });
    } else if (input is InvestmentPnlAdjustmentInput) {
      fields.addAll({
        'INVESTMENT_ACCOUNT_ID': input.investmentAccountId,
        'VALUE_ADJUSTMENT': input.valueAdjustment.scaledUnits,
      });
    }
    for (final key in [
      'INVESTMENT_ACCOUNT_ID',
      'SOURCE_ACCOUNT_ID',
      'TARGET_ACCOUNT_ID',
    ]) {
      final accountId = fields[key] as String?;
      if (accountId != null) _requireActive(_account(accountId));
    }
    _validateAccountEventRelations(input);
    _insertParent(id, input.kind, input.occurredAt, order, input.note);
    _database.insert('ACCOUNT_TRANSACTIONS', fields);
  }

  /// Deletes an account transaction when the remaining history stays valid.
  ///
  /// Parameters
  /// ----------
  /// id : `String`
  ///     ID of the account transaction to delete.
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after atomic deletion and ledger replay.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the event is missing, archived, or deletion invalidates history.
  Future<void> deleteAccountTransaction(String id) async {
    _database.atomic(() {
      final row = _accountEvent(id);
      _requireEventAccountsActive(row);
      _database.raw.execute('DELETE FROM TRANSACTIONS WHERE ID=?', [id]);
      _validateAllHistory();
    });
  }

  /// Calculates the current detail of one account from opening values and events.
  ///
  /// Parameters
  /// ----------
  /// id : `String`
  ///     Account ID to calculate.
  ///
  /// Returns
  /// -------
  /// `Future<AccountDetail>`
  ///     Current cost, value, profit, status, and valuation completeness.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the account does not exist or its stored history is invalid.
  Future<AccountDetail> getAccountDetail(String id) async =>
      _calculateAccount(id);

  /// Lists transactions projected onto one account in reverse chronological order.
  ///
  /// Parameters
  /// ----------
  /// accountId : `String`
  ///     Account whose projected transactions are requested.
  /// kinds : `Set<TransactionKind>?`
  ///     Optional transaction-kind filter.
  /// direction : `TransactionDirection?`
  ///     Optional incoming or outgoing filter.
  /// cursor : `String?`
  ///     Optional transaction ID after which the page begins.
  /// limit : `int`
  ///     Maximum number of returned items.
  ///
  /// Returns
  /// -------
  /// `Future<Page<AccountTransactionItem>>`
  ///     One page of transaction projections and an optional next cursor.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the account, cursor, or limit is invalid.
  Future<Page<AccountTransactionItem>> listAccountTransactions(
    String accountId, {
    Set<TransactionKind>? kinds,
    TransactionDirection? direction,
    String? cursor,
    int limit = 50,
  }) async {
    _account(accountId);
    _validateLimit(limit);
    final rows = _transactionRowsForAccount(accountId)
        .where(
          (r) => kinds == null || kinds.contains(_kind(r['KIND'] as String)),
        )
        .where(
          (r) =>
              direction == null || _matchesDirection(r, accountId, direction),
        )
        .toList();
    return _pageTransactions(rows, cursor, limit);
  }

  /// Calculates a stock transaction settlement without writing data.
  ///
  /// Parameters
  /// ----------
  /// input : `StockTransactionInput`
  ///     Candidate stock transaction using actual amounts and shares.
  ///
  /// Returns
  /// -------
  /// `Future<StockTransactionPreview>`
  ///     Gross amount adjusted by the applicable fee.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If time, account references, currency, quantity, price, or fee is invalid.
  Future<StockTransactionPreview> previewStockTransaction(
    StockTransactionInput input,
  ) async {
    _validateOccurredAt(input.occurredAt);
    _validateStockAmounts(input);
    final currency =
        (_account(input.fundingAccountId)['CURRENCY_CODE'] as String);
    if (input is StockDividendInput) {
      return StockTransactionPreview(input.dividendAmount);
    }
    late int q, p, fee;
    final isBuy = input is StockBuyInput;
    if (input is StockBuyInput) {
      q = input.quantity.scaledUnits;
      p = input.unitPrice.scaledUnits;
      fee = input.fee.scaledUnits;
    } else {
      final sell = input as StockSellInput;
      q = sell.quantity.scaledUnits;
      p = sell.unitPrice.scaledUnits;
      fee = sell.fee.scaledUnits;
    }
    final gross = roundRatio(
      BigInt.from(q) * BigInt.from(p),
      BigInt.from(shareMultiplier),
    );
    return StockTransactionPreview(
      Money.fromScaledUnits(
        currencyCode: currency,
        units: isBuy ? checkedAdd(gross, fee) : checkedAdd(gross, -fee),
      ),
    );
  }

  /// Calculates ledger changes for an account transaction without writing data.
  ///
  /// Parameters
  /// ----------
  /// input : `AccountTransactionInput`
  ///     Candidate general-account or manual-investment event.
  ///
  /// Returns
  /// -------
  /// `Future<AccountTransactionPreview>`
  ///     Expected changes to funding, cost, value, and realized-profit ledgers.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If amounts are invalid or a manual sale exceeds current value.
  Future<AccountTransactionPreview> previewAccountTransaction(
    AccountTransactionInput input,
  ) async {
    _validateAccountEventAmounts(input);
    if (input is AccountTransferInput) {
      return AccountTransactionPreview(
        sourceChange: Money.fromScaledUnits(
          currencyCode: input.sourceAmount.currencyCode,
          units: -input.sourceAmount.scaledUnits,
        ),
        targetChange: input.targetAmount,
      );
    }
    if (input is AccountIncomeInput) {
      return AccountTransactionPreview(targetChange: input.targetAmount);
    }
    if (input is AccountExpenseInput) {
      return AccountTransactionPreview(
        sourceChange: Money.fromScaledUnits(
          currencyCode: input.sourceAmount.currencyCode,
          units: -input.sourceAmount.scaledUnits,
        ),
      );
    }
    if (input is InvestmentBuyInput) {
      return AccountTransactionPreview(
        sourceChange: Money.fromScaledUnits(
          currencyCode: input.amount.currencyCode,
          units: -(input.amount.scaledUnits + input.fee.scaledUnits),
        ),
        investmentCostChange: Money.fromScaledUnits(
          currencyCode: input.amount.currencyCode,
          units: input.amount.scaledUnits + input.fee.scaledUnits,
        ),
        investmentValueChange: input.amount,
      );
    }
    if (input is InvestmentSellInput) {
      final before = _calculateAccount(input.investmentAccountId);
      if (before.value == null ||
          before.value!.scaledUnits <= 0 ||
          input.amount.scaledUnits > before.value!.scaledUnits) {
        _fail('Investment sale exceeds value');
      }
      final disposed = input.amount.scaledUnits == before.value!.scaledUnits
          ? before.cost.scaledUnits
          : roundRatio(
              BigInt.from(before.cost.scaledUnits) *
                  BigInt.from(input.amount.scaledUnits),
              BigInt.from(before.value!.scaledUnits),
            );
      return AccountTransactionPreview(
        targetChange: Money.fromScaledUnits(
          currencyCode: input.amount.currencyCode,
          units: input.amount.scaledUnits - input.fee.scaledUnits,
        ),
        investmentCostChange: Money.fromScaledUnits(
          currencyCode: input.amount.currencyCode,
          units: -disposed,
        ),
        investmentValueChange: Money.fromScaledUnits(
          currencyCode: input.amount.currencyCode,
          units: -input.amount.scaledUnits,
        ),
        realizedPnlChange: Money.fromScaledUnits(
          currencyCode: input.amount.currencyCode,
          units: input.amount.scaledUnits - input.fee.scaledUnits - disposed,
        ),
      );
    }
    if (input is InvestmentInterestInput) {
      return AccountTransactionPreview(
        targetChange: input.amount,
        realizedPnlChange: input.amount,
      );
    }
    final adjustment = (input as InvestmentPnlAdjustmentInput).valueAdjustment;
    return AccountTransactionPreview(investmentValueChange: adjustment);
  }

  /// Lists all reporting categories in user-defined order.
  ///
  /// Parameters
  /// ----------
  /// `None`
  ///
  /// Returns
  /// -------
  /// `Future<List<CategorySummary>>`
  ///     Every category ordered by sort position and ID.
  ///
  /// Raises
  /// ------
  /// `None`
  Future<List<CategorySummary>> listCategories() async => _database.raw
      .select(
        'SELECT C.*,COUNT(A.ID) USE_COUNT FROM CATEGORIES C LEFT JOIN ACCOUNTS A ON A.CATEGORY_ID=C.ID GROUP BY C.ID ORDER BY C.SORT_ORDER,C.ID',
      )
      .map(
        (r) => CategorySummary(
          id: r['ID'] as String,
          name: r['NAME'] as String,
          colorArgb: r['COLOR_ARGB'] as int,
          sortOrder: r['SORT_ORDER'] as int,
          accountUsageCount: r['USE_COUNT'] as int,
        ),
      )
      .toList();

  /// Creates a reporting category at the end of the current order.
  ///
  /// Parameters
  /// ----------
  /// input : `CreateCategoryInput`
  ///     Category name and ARGB color.
  ///
  /// Returns
  /// -------
  /// `Future<CategoryId>`
  ///     The stable ID of the new category.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the name is blank or duplicates another category.
  Future<CategoryId> createCategory(CreateCategoryInput input) async {
    final name = input.name.trim();
    if (name.isEmpty) _fail('Category name cannot be blank');
    _ensureUniqueCategoryName(name);
    final id = _uuid.v4(),
        next =
            (_database.raw
                    .select(
                      'SELECT COALESCE(MAX(SORT_ORDER),-1)+1 N FROM CATEGORIES',
                    )
                    .first['N']
                as int);
    _database.insert('CATEGORIES', {
      'ID': id,
      'NAME': name,
      'COLOR_ARGB': input.colorArgb,
      'SORT_ORDER': next,
      'UPDATED_AT': _utcNow(),
    });
    return id;
  }

  /// Updates a reporting category.
  ///
  /// Parameters
  /// ----------
  /// id : `String`
  ///     Category ID to update.
  /// input : `UpdateCategoryInput`
  ///     Replacement name and ARGB color.
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after the category is updated.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the category is missing or its replacement values are invalid.
  Future<void> updateCategory(String id, UpdateCategoryInput input) async {
    final name = input.name.trim();
    if (name.isEmpty) _fail('Category name cannot be blank');
    _requireCategory(id);
    _ensureUniqueCategoryName(name, excludingId: id);
    _database.raw.execute(
      'UPDATE CATEGORIES SET NAME=?,COLOR_ARGB=?,UPDATED_AT=? WHERE ID=?',
      [name, input.colorArgb, _utcNow(), id],
    );
  }

  void _ensureUniqueCategoryName(String name, {String? excludingId}) {
    final duplicate = _database.raw.select(
      'SELECT 1 FROM CATEGORIES WHERE lower(NAME)=lower(?) AND (? IS NULL OR ID<>?) LIMIT 1',
      [name, excludingId, excludingId],
    );
    if (duplicate.isNotEmpty) _conflict('Category name already exists');
  }

  /// Replaces the ordering of all reporting categories.
  ///
  /// Parameters
  /// ----------
  /// ids : `List<String>`
  ///     Every existing category ID exactly once, in the desired order.
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after all sort positions are updated atomically.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the list is incomplete, duplicated, or contains an unknown ID.
  Future<void> reorderCategories(List<String> ids) async {
    _database.atomic(() {
      final existing = _database.raw
          .select('SELECT ID FROM CATEGORIES')
          .map((r) => r['ID'])
          .toSet();
      if (ids.length != existing.length ||
          ids.toSet().length != ids.length ||
          !ids.toSet().containsAll(existing)) {
        _fail('Category order must contain every category once');
      }
      for (var i = 0; i < ids.length; i++) {
        _database.raw.execute(
          'UPDATE CATEGORIES SET SORT_ORDER=?,UPDATED_AT=? WHERE ID=?',
          [i, _utcNow(), ids[i]],
        );
      }
    });
  }

  /// Deletes a category after optionally reassigning active accounts.
  ///
  /// Parameters
  /// ----------
  /// id : `String`
  ///     Category ID to delete.
  /// replacementCategoryId : `String?`
  ///     Destination category for active accounts that currently use [id].
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after reassignment and deletion succeed atomically.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If deletion would remove the last category or affect archived accounts.
  Future<void> deleteCategory(
    String id, {
    String? replacementCategoryId,
  }) async {
    _database.atomic(() {
      final categories = _database.raw.select('SELECT ID FROM CATEGORIES');
      if (categories.length <= 1) {
        _conflict('At least one category must remain');
      }
      _requireCategory(id);
      final archived = _database.raw.select(
        'SELECT 1 FROM ACCOUNTS WHERE CATEGORY_ID=? AND IS_ARCHIVED=1 LIMIT 1',
        [id],
      );
      if (archived.isNotEmpty) _conflict('Archived account uses category');
      final active = _database.raw.select(
        'SELECT 1 FROM ACCOUNTS WHERE CATEGORY_ID=? LIMIT 1',
        [id],
      );
      if (active.isNotEmpty) {
        if (replacementCategoryId == null || replacementCategoryId == id) {
          _fail('Replacement category is required');
        }
        _requireCategory(replacementCategoryId);
        _database.raw.execute(
          'UPDATE ACCOUNTS SET CATEGORY_ID=?,UPDATED_AT=? WHERE CATEGORY_ID=?',
          [replacementCategoryId, _utcNow(), id],
        );
      }
      _database.raw.execute('DELETE FROM CATEGORIES WHERE ID=?', [id]);
    });
  }

  /// Reads the current application settings.
  ///
  /// Parameters
  /// ----------
  /// `None`
  ///
  /// Returns
  /// -------
  /// `Future<AppSettings>`
  ///     Current theme, language, refresh mode, and biometric-lock state.
  ///
  /// Raises
  /// ------
  /// `None`
  Future<AppSettings> getAppSettings() async => _settings(
    _database.raw.select('SELECT * FROM APP_SETTINGS WHERE ID=1').single,
  );

  /// Applies a partial application-settings update.
  ///
  /// Parameters
  /// ----------
  /// patch : `AppSettingsPatch`
  ///     Optional replacement values; omitted values remain unchanged.
  ///
  /// Returns
  /// -------
  /// `Future<AppSettings>`
  ///     The complete settings value after saving the patch.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If a supplied setting value is unsupported.
  Future<AppSettings> updateAppSettings(AppSettingsPatch patch) async {
    final old = await getAppSettings();
    final next = AppSettings(
      themeMode: patch.themeMode ?? old.themeMode,
      languageCode: patch.languageCode ?? old.languageCode,
      marketUpdateMode: patch.marketUpdateMode ?? old.marketUpdateMode,
      isBiometricLockEnabled: old.isBiometricLockEnabled,
    );
    _saveSettings(next);
    return next;
  }

  /// Enables or disables biometric locking.
  ///
  /// Parameters
  /// ----------
  /// enabled : `bool`
  ///     Desired biometric-lock state.
  ///
  /// Returns
  /// -------
  /// `Future<AppSettings>`
  ///     Complete settings after the state is saved.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If enabling is requested and biometric authentication is unavailable or fails.
  Future<AppSettings> setBiometricLockEnabled(bool enabled) async {
    final old = await getAppSettings();
    if (enabled) {
      final authenticate = _authenticateBiometric;
      if (authenticate == null || !await authenticate()) {
        throw const DataApiException(
          DataErrorCode.authentication,
          'Biometric authentication failed',
        );
      }
    }
    final next = AppSettings(
      themeMode: old.themeMode,
      languageCode: old.languageCode,
      marketUpdateMode: old.marketUpdateMode,
      isBiometricLockEnabled: enabled,
    );
    _saveSettings(next);
    return next;
  }

  /// Runs the configured market-data refresher.
  ///
  /// Parameters
  /// ----------
  /// `None`
  ///
  /// Returns
  /// -------
  /// `Future<MarketRefreshResult>`
  ///     Counts and timestamps reported by the configured refresher.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If no market-data refresher is configured.
  Future<MarketRefreshResult> refreshMarketData() async {
    final refresh = _marketDataRefresher;
    if (refresh == null) {
      throw const DataApiException(
        DataErrorCode.unavailable,
        'No market data provider configured',
      );
    }
    return refresh(this);
  }

  /// Saves the latest successful price for one security.
  ///
  /// Parameters
  /// ----------
  /// securityId : `String`
  ///     Security whose latest price is replaced.
  /// price : `Money`
  ///     Positive actual price in the security currency.
  /// quotedAt : `DateTime`
  ///     Provider timestamp associated with the quote.
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after the latest-price row is inserted or replaced.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the security is missing or the price is nonpositive or in another currency.
  Future<void> saveStockPrice({
    required String securityId,
    required Money price,
    required DateTime quotedAt,
  }) async {
    final security = _security(securityId);
    if (security['CURRENCY_CODE'] != price.currencyCode || price.units <= 0) {
      _fail('Invalid quote');
    }
    _database.raw.execute(
      'INSERT INTO STOCK_PRICES(SECURITY_ID,PRICE,CURRENCY_CODE,QUOTED_AT,RETRIEVED_AT) VALUES(?,?,?,?,?) ON CONFLICT(SECURITY_ID) DO UPDATE SET PRICE=excluded.PRICE,CURRENCY_CODE=excluded.CURRENCY_CODE,QUOTED_AT=excluded.QUOTED_AT,RETRIEVED_AT=excluded.RETRIEVED_AT',
      [
        securityId,
        price.scaledUnits,
        price.currencyCode,
        quotedAt.toUtc().toIso8601String(),
        _utcNow(),
      ],
    );
  }

  /// Saves the latest successful exchange rate from one currency to TWD.
  ///
  /// Parameters
  /// ----------
  /// fromCurrencyCode : `String`
  ///     Supported non-TWD source currency.
  /// rate : `double`
  ///     Positive actual exchange rate with at most two decimal places.
  /// quotedAt : `DateTime`
  ///     Provider timestamp associated with the rate.
  ///
  /// Returns
  /// -------
  /// `Future<void>`
  ///     Completes after the latest-rate row is inserted or replaced.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the currency or rate is unsupported, nonpositive, or too precise.
  Future<void> saveExchangeRate({
    required String fromCurrencyCode,
    required double rate,
    required DateTime quotedAt,
  }) async {
    final scaledRate = _scaleExchangeRate(rate);
    if (!moneyMultipliers.containsKey(fromCurrencyCode) || scaledRate <= 0) {
      _fail('Invalid exchange rate');
    }
    if (fromCurrencyCode == 'TWD') _fail('TWD rate is implicit');
    _database.raw.execute(
      "INSERT INTO EXCHANGE_RATES(FROM_CURRENCY_CODE,TO_CURRENCY_CODE,RATE,QUOTED_AT,RETRIEVED_AT) VALUES(?,'TWD',?,?,?) ON CONFLICT(FROM_CURRENCY_CODE) DO UPDATE SET RATE=excluded.RATE,QUOTED_AT=excluded.QUOTED_AT,RETRIEVED_AT=excluded.RETRIEVED_AT",
      [
        fromCurrencyCode,
        scaledRate,
        quotedAt.toUtc().toIso8601String(),
        _utcNow(),
      ],
    );
  }

  void _ensureOpen() {
    if (_closed) {
      throw const DataApiException(DataErrorCode.closed, 'Data API is closed');
    }
  }

  String _utcNow() => _now().toUtc().toIso8601String();
  Never _fail(String message) =>
      throw DataApiException(DataErrorCode.validation, message);
  Never _conflict(String message) =>
      throw DataApiException(DataErrorCode.conflict, message);
  Map<String, Object?> _one(ResultSet rows, String what) {
    if (rows.isEmpty) {
      throw DataApiException(DataErrorCode.notFound, '$what not found');
    }
    return Map<String, Object?>.from(rows.first);
  }

  Map<String, Object?> _account(String id) => _one(
    _database.raw.select('SELECT * FROM ACCOUNTS WHERE ID=?', [id]),
    'Account',
  );
  Map<String, Object?> _security(String id) => _one(
    _database.raw.select('SELECT * FROM SECURITIES WHERE ID=?', [id]),
    'Security',
  );
  Map<String, Object?> _stockEvent(String id) => _one(
    _database.raw.select(
      'SELECT T.*,S.* FROM TRANSACTIONS T JOIN STOCK_TRANSACTIONS S ON S.TRANSACTION_ID=T.ID WHERE T.ID=?',
      [id],
    ),
    'Stock transaction',
  );
  Map<String, Object?> _accountEvent(String id) => _one(
    _database.raw.select(
      'SELECT T.*,A.* FROM TRANSACTIONS T JOIN ACCOUNT_TRANSACTIONS A ON A.TRANSACTION_ID=T.ID WHERE T.ID=?',
      [id],
    ),
    'Account transaction',
  );
  void _requireCategory(String id) {
    _one(
      _database.raw.select('SELECT ID FROM CATEGORIES WHERE ID=?', [id]),
      'Category',
    );
  }

  void _requireActive(Map<String, Object?> row) {
    if (row['IS_ARCHIVED'] == 1) {
      _conflict('Archived account cannot be changed');
    }
  }

  AccountType _accountType(Map<String, Object?> r) =>
      switch (r['ACCOUNT_TYPE']) {
        'GENERAL' => AccountType.general,
        'STOCK' => AccountType.stock,
        'INVESTMENT' => AccountType.investment,
        _ => throw StateError('Corrupt account type'),
      };
  String _accountTypeText(AccountType t) => switch (t) {
    AccountType.general => 'GENERAL',
    AccountType.stock => 'STOCK',
    AccountType.investment => 'INVESTMENT',
  };
  String _kindText(TransactionKind k) => [
    'STOCK_BUY',
    'STOCK_SELL',
    'STOCK_DIVIDEND',
    'ACCOUNT_TRANSFER',
    'ACCOUNT_INCOME',
    'ACCOUNT_EXPENSE',
    'INVESTMENT_BUY',
    'INVESTMENT_SELL',
    'INVESTMENT_INTEREST',
    'INVESTMENT_PNL_ADJUSTMENT',
  ][k.index];
  TransactionKind _kind(String s) =>
      TransactionKind.values[[
        'STOCK_BUY',
        'STOCK_SELL',
        'STOCK_DIVIDEND',
        'ACCOUNT_TRANSFER',
        'ACCOUNT_INCOME',
        'ACCOUNT_EXPENSE',
        'INVESTMENT_BUY',
        'INVESTMENT_SELL',
        'INVESTMENT_INTEREST',
        'INVESTMENT_PNL_ADJUSTMENT',
      ].indexOf(s)];
  void _validateAccountFields(String name, String category, String currency) {
    if (name.trim().isEmpty) _fail('Account name cannot be blank');
    _requireCategory(category);
    if (!moneyMultipliers.containsKey(currency)) _fail('Unsupported currency');
  }

  void _validateOccurredAt(String value) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) ([01]\d|2[0-3]):([0-5]\d)$')
        .firstMatch(value);
    if (m == null) _fail('Transaction time must be YYYY-MM-DD HH:mm');
    final wall = DateTime.utc(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
      int.parse(m[4]!),
      int.parse(m[5]!),
    );
    if ('${_dateText(wall)} ${wall.hour.toString().padLeft(2, '0')}:${wall.minute.toString().padLeft(2, '0')}' !=
        value) {
      _fail('Invalid transaction date');
    }
    final instant = wall.subtract(const Duration(hours: 8));
    if (instant.isAfter(_now().toUtc())) {
      _fail('Future transactions are not supported');
    }
  }

  int _nextOrder() =>
      ((_database.raw
              .select(
                'SELECT COALESCE(MAX(ENTRY_ORDER),0)+1 N FROM TRANSACTIONS',
              )
              .first['N'])
          as int);
  void _insertParent(
    String id,
    TransactionKind kind,
    String occurred,
    int order,
    String? note,
  ) => _database.insert('TRANSACTIONS', {
    'ID': id,
    'KIND': _kindText(kind),
    'OCCURRED_AT': occurred,
    'ENTRY_ORDER': order,
    'NOTE': note,
    'UPDATED_AT': _utcNow(),
  });
  void _validateStockAmounts(StockTransactionInput input) {
    if (input is StockDividendInput) {
      if (input.dividendAmount.units <= 0) _fail('Dividend must be positive');
      return;
    }
    late double q;
    late Money p, fee;
    if (input is StockBuyInput) {
      q = input.quantity.units;
      p = input.unitPrice;
      fee = input.fee;
    } else {
      final sell = input as StockSellInput;
      q = sell.quantity.units;
      p = sell.unitPrice;
      fee = sell.fee;
    }
    if (q <= 0 ||
        p.units <= 0 ||
        fee.units < 0 ||
        p.currencyCode != fee.currencyCode) {
      _fail('Invalid stock amount');
    }
  }

  void _validateAccountEventAmounts(AccountTransactionInput i) {
    Iterable<Money> positive = [];
    Money? fee;
    if (i is AccountTransferInput) {
      positive = [i.sourceAmount, i.targetAmount];
      if (i.sourceAccountId == i.targetAccountId) {
        _fail('Transfer accounts must differ');
      }
    } else if (i is AccountIncomeInput) {
      positive = [i.targetAmount];
    } else if (i is AccountExpenseInput) {
      positive = [i.sourceAmount];
    } else if (i is InvestmentBuyInput) {
      positive = [i.amount];
      fee = i.fee;
    } else if (i is InvestmentSellInput) {
      positive = [i.amount];
      fee = i.fee;
      if (i.fee.units > i.amount.units) _fail('Fee exceeds sale amount');
    } else if (i is InvestmentInterestInput) {
      positive = [i.amount];
    } else if (i is InvestmentPnlAdjustmentInput) {
      if (i.valueAdjustment.units == 0) _fail('Adjustment cannot be zero');
    }
    if (positive.any((m) => m.units <= 0) || fee != null && fee.units < 0) {
      _fail('Amounts must be positive and fees nonnegative');
    }
  }

  void _validateAccountEventRelations(AccountTransactionInput i) {
    String? investment, source, target;
    final monies = <Money>[];
    if (i is AccountTransferInput) {
      source = i.sourceAccountId;
      target = i.targetAccountId;
      if (_account(source)['CURRENCY_CODE'] != i.sourceAmount.currencyCode ||
          _account(target)['CURRENCY_CODE'] != i.targetAmount.currencyCode) {
        _fail('Transfer money currency mismatch');
      }
    } else if (i is AccountIncomeInput) {
      target = i.targetAccountId;
      monies.add(i.targetAmount);
    } else if (i is AccountExpenseInput) {
      source = i.sourceAccountId;
      monies.add(i.sourceAmount);
    } else if (i is InvestmentBuyInput) {
      investment = i.investmentAccountId;
      source = i.sourceAccountId;
      monies.addAll([i.amount, i.fee]);
    } else if (i is InvestmentSellInput) {
      investment = i.investmentAccountId;
      target = i.targetAccountId;
      monies.addAll([i.amount, i.fee]);
    } else if (i is InvestmentInterestInput) {
      investment = i.investmentAccountId;
      target = i.targetAccountId;
      monies.add(i.amount);
    } else if (i is InvestmentPnlAdjustmentInput) {
      investment = i.investmentAccountId;
      monies.add(i.valueAdjustment);
    }
    if (source != null &&
        _accountType(_account(source)) != AccountType.general) {
      _fail('Source must be GENERAL');
    }
    if (target != null &&
        _accountType(_account(target)) != AccountType.general) {
      _fail('Target must be GENERAL');
    }
    final currency = investment == null
        ? (source ?? target) == null
              ? null
              : _account(source ?? target!)['CURRENCY_CODE'] as String
        : _account(investment)['CURRENCY_CODE'] as String;
    if (monies.any((m) => m.currencyCode != currency)) {
      _fail('Amount currency does not match account');
    }
    if (investment != null) {
      final inv = _account(investment);
      if (_accountType(inv) != AccountType.investment) {
        _fail('Investment account required');
      }
      for (final id in [source, target]) {
        if (id != null &&
            _account(id)['CURRENCY_CODE'] != inv['CURRENCY_CODE']) {
          _fail('Investment participants must share currency');
        }
      }
    }
  }

  void _requireEventAccountsActive(Map<String, Object?> row) {
    for (final key in [
      'STOCK_ACCOUNT_ID',
      'FUNDING_ACCOUNT_ID',
      'INVESTMENT_ACCOUNT_ID',
      'SOURCE_ACCOUNT_ID',
      'TARGET_ACCOUNT_ID',
    ]) {
      final id = row[key] as String?;
      if (id != null) _requireActive(_account(id));
    }
  }

  List<Map<String, Object?>> _allEvents() => _database.raw
      .select(
        '''SELECT T.*,
    S.SECURITY_ID,S.STOCK_ACCOUNT_ID,S.FUNDING_ACCOUNT_ID,S.QUANTITY,S.UNIT_PRICE,S.DIVIDEND_AMOUNT,S.FEE STOCK_FEE,
    A.INVESTMENT_ACCOUNT_ID,A.SOURCE_ACCOUNT_ID,A.TARGET_ACCOUNT_ID,A.SOURCE_AMOUNT,A.TARGET_AMOUNT,A.AMOUNT,A.VALUE_ADJUSTMENT,A.FEE ACCOUNT_FEE
    FROM TRANSACTIONS T LEFT JOIN STOCK_TRANSACTIONS S ON S.TRANSACTION_ID=T.ID
    LEFT JOIN ACCOUNT_TRANSACTIONS A ON A.TRANSACTION_ID=T.ID ORDER BY T.OCCURRED_AT,T.ENTRY_ORDER''',
      )
      .map((r) => Map<String, Object?>.from(r))
      .toList();
  List<Map<String, Object?>> _transactionRowsForAccount(String id) =>
      _allEvents()
          .where(
            (r) =>
                r['STOCK_ACCOUNT_ID'] == id ||
                r['FUNDING_ACCOUNT_ID'] == id ||
                r['INVESTMENT_ACCOUNT_ID'] == id ||
                r['SOURCE_ACCOUNT_ID'] == id ||
                r['TARGET_ACCOUNT_ID'] == id,
          )
          .toList()
        ..sort((a, b) {
          final c = (b['OCCURRED_AT'] as String).compareTo(
            a['OCCURRED_AT'] as String,
          );
          return c != 0
              ? c
              : (b['ENTRY_ORDER'] as int).compareTo(a['ENTRY_ORDER'] as int);
        });
  bool _matchesDirection(
    Map<String, Object?> r,
    String id,
    TransactionDirection direction,
  ) {
    final incoming =
        r['TARGET_ACCOUNT_ID'] == id ||
        ((r['FUNDING_ACCOUNT_ID'] == id) &&
            {'STOCK_SELL', 'STOCK_DIVIDEND'}.contains(r['KIND']));
    return direction == TransactionDirection.incoming ? incoming : !incoming;
  }

  Page<AccountTransactionItem> _pageTransactions(
    List<Map<String, Object?>> rows,
    String? cursor,
    int limit,
  ) {
    _validateLimit(limit);
    var start = 0;
    if (cursor != null) {
      start = rows.indexWhere((r) => r['ID'] == cursor) + 1;
      if (start == 0) _fail('Invalid cursor');
    }
    final page = rows.skip(start).take(limit + 1).toList();
    final hasMore = page.length > limit;
    if (hasMore) page.removeLast();
    return Page(
      items: page
          .map(
            (r) => AccountTransactionItem(
              id: r['ID'] as String,
              occurredAt: r['OCCURRED_AT'] as String,
              entryOrder: r['ENTRY_ORDER'] as int,
              kind: _kind(r['KIND'] as String),
              note: r['NOTE'] as String?,
            ),
          )
          .toList(),
      nextCursor: hasMore ? page.last['ID'] as String : null,
    );
  }

  void _validateLimit(int limit) {
    if (limit < 1 || limit > 200) _fail('Limit must be from 1 to 200');
  }

  AccountDetail _calculateAccount(String id) {
    final a = _account(id),
        currency = a['CURRENCY_CODE'] as String,
        type = _accountType(a);
    var cost = a['INITIAL_COST'] as int,
        value = a['INITIAL_VALUE'] as int,
        realized = 0;
    var complete = true;
    if (type == AccountType.general) {
      for (final e in _allEvents()) {
        var delta = 0;
        if (e['SOURCE_ACCOUNT_ID'] == id) {
          delta -=
              e['SOURCE_AMOUNT'] as int? ??
              ((e['AMOUNT'] as int? ?? 0) + (e['ACCOUNT_FEE'] as int? ?? 0));
        }
        if (e['TARGET_ACCOUNT_ID'] == id) {
          delta +=
              e['TARGET_AMOUNT'] as int? ??
              ((e['AMOUNT'] as int? ?? 0) - (e['ACCOUNT_FEE'] as int? ?? 0));
        }
        if (e['FUNDING_ACCOUNT_ID'] == id) {
          final kind = e['KIND'];
          if (kind == 'STOCK_BUY') {
            delta -= _stockSettlement(e, buy: true);
          } else if (kind == 'STOCK_SELL') {
            delta += _stockSettlement(e, buy: false);
          } else if (kind == 'STOCK_DIVIDEND') {
            delta += e['DIVIDEND_AMOUNT'] as int;
          }
        }
        cost = checkedAdd(cost, delta);
        value = checkedAdd(value, delta);
      }
    } else if (type == AccountType.investment) {
      for (final e in _allEvents().where(
        (e) => e['INVESTMENT_ACCOUNT_ID'] == id,
      )) {
        switch (e['KIND']) {
          case 'INVESTMENT_BUY':
            final amount = e['AMOUNT'] as int, fee = e['ACCOUNT_FEE'] as int;
            cost = checkedAdd(cost, amount + fee);
            value = checkedAdd(value, amount);
          case 'INVESTMENT_SELL':
            final amount = e['AMOUNT'] as int, fee = e['ACCOUNT_FEE'] as int;
            if (value <= 0 || amount > value) {
              _fail('Investment history oversells value');
            }
            final disposed = amount == value
                ? cost
                : roundRatio(
                    BigInt.from(cost) * BigInt.from(amount),
                    BigInt.from(value),
                  );
            cost -= disposed;
            value -= amount;
            realized += amount - fee - disposed;
          case 'INVESTMENT_INTEREST':
            realized += e['AMOUNT'] as int;
          case 'INVESTMENT_PNL_ADJUSTMENT':
            value = checkedAdd(value, e['VALUE_ADJUSTMENT'] as int);
        }
      }
    } else {
      final aggregate = _stockAggregate(stockAccountId: id);
      cost = aggregate.cost;
      value = aggregate.value ?? 0;
      realized = aggregate.realized;
      complete = aggregate.complete;
    }
    return AccountDetail(
      id: id,
      name: a['NAME'] as String,
      categoryId: a['CATEGORY_ID'] as String,
      currencyCode: currency,
      fundingAccountId: a['FUNDING_ACCOUNT_ID'] as String?,
      accountType: type,
      cost: Money.fromScaledUnits(currencyCode: currency, units: cost),
      value: complete
          ? Money.fromScaledUnits(currencyCode: currency, units: value)
          : null,
      realizedPnl: Money.fromScaledUnits(
        currencyCode: currency,
        units: realized,
      ),
      unrealizedPnl: Money.fromScaledUnits(
        currencyCode: currency,
        units: complete ? value - cost : 0,
      ),
      isArchived: a['IS_ARCHIVED'] == 1,
      isValuationComplete: complete,
    );
  }

  int _stockSettlement(Map<String, Object?> e, {required bool buy}) {
    final gross = roundRatio(
      BigInt.from(e['QUANTITY'] as int) * BigInt.from(e['UNIT_PRICE'] as int),
      BigInt.from(shareMultiplier),
    );
    final fee = e['STOCK_FEE'] as int;
    return buy ? checkedAdd(gross, fee) : checkedAdd(gross, -fee);
  }

  _StockAggregate _stockAggregate({
    String? stockAccountId,
    String? securityId,
  }) {
    final lots = <String, List<_Lot>>{}, quantities = <String, int>{};
    var realized = 0, dividends = 0;
    for (final e in _allEvents().where(
      (e) =>
          (stockAccountId == null || e['STOCK_ACCOUNT_ID'] == stockAccountId) &&
          (securityId == null || e['SECURITY_ID'] == securityId) &&
          e['SECURITY_ID'] != null,
    )) {
      final key = '${e['STOCK_ACCOUNT_ID']}:${e['SECURITY_ID']}';
      if (e['KIND'] == 'STOCK_BUY') {
        final q = e['QUANTITY'] as int;
        lots
            .putIfAbsent(key, () => [])
            .add(_Lot(q, _stockSettlement(e, buy: true)));
        quantities[key] = (quantities[key] ?? 0) + q;
      } else if (e['KIND'] == 'STOCK_SELL') {
        var left = e['QUANTITY'] as int;
        var disposed = 0;
        final queue = lots.putIfAbsent(key, () => []);
        if ((quantities[key] ?? 0) < left) {
          _fail('Stock history oversells holdings');
        }
        while (left > 0) {
          final lot = queue.first;
          final take = left < lot.quantity ? left : lot.quantity;
          final part = take == lot.quantity
              ? lot.cost
              : roundRatio(
                  BigInt.from(lot.cost) * BigInt.from(take),
                  BigInt.from(lot.quantity),
                );
          lot.quantity -= take;
          lot.cost -= part;
          disposed += part;
          left -= take;
          if (lot.quantity == 0) queue.removeAt(0);
        }
        quantities[key] = (quantities[key] ?? 0) - (e['QUANTITY'] as int);
        realized += _stockSettlement(e, buy: false) - disposed;
      } else {
        final d = e['DIVIDEND_AMOUNT'] as int;
        dividends += d;
        realized += d;
      }
    }
    var cost = lots.values
        .expand((v) => v)
        .fold(0, (sum, l) => checkedAdd(sum, l.cost));
    var value = 0, complete = true;
    for (final entry in quantities.entries.where((e) => e.value > 0)) {
      final parts = entry.key.split(':');
      final quote = _database.raw.select(
        'SELECT PRICE FROM STOCK_PRICES WHERE SECURITY_ID=?',
        [parts.last],
      );
      if (quote.isEmpty) {
        complete = false;
        continue;
      }
      value = checkedAdd(
        value,
        roundRatio(
          BigInt.from(entry.value) * BigInt.from(quote.first['PRICE'] as int),
          BigInt.from(shareMultiplier),
        ),
      );
    }
    return _StockAggregate(
      cost,
      complete ? value : null,
      realized,
      dividends,
      quantities.values.fold(0, (a, b) => a + b),
      complete,
    );
  }

  void _validateAllHistory() {
    _validateStoredStructure();
    for (final a in _database.raw.select(
      "SELECT ID,ACCOUNT_TYPE FROM ACCOUNTS WHERE ACCOUNT_TYPE IN ('STOCK','INVESTMENT')",
    )) {
      _calculateAccount(a['ID'] as String);
    }
  }

  void _validateStoredStructure() {
    for (final account in _database.raw.select('SELECT * FROM ACCOUNTS')) {
      final type = _accountType(Map<String, Object?>.from(account)),
          funding = account['FUNDING_ACCOUNT_ID'] as String?;
      if (type == AccountType.general && funding != null) {
        _fail('GENERAL funding must be null');
      }
      if (type != AccountType.general) {
        if (funding == null) _fail('Investment funding is required');
        final f = _account(funding);
        if (_accountType(f) != AccountType.general ||
            f['CURRENCY_CODE'] != account['CURRENCY_CODE']) {
          _fail('Invalid default funding account');
        }
      }
    }
    for (final event in _database.raw.select(
      '''SELECT T.ID,T.KIND,T.OCCURRED_AT,
      (SELECT COUNT(*) FROM STOCK_TRANSACTIONS S WHERE S.TRANSACTION_ID=T.ID) SC,
      (SELECT COUNT(*) FROM ACCOUNT_TRANSACTIONS A WHERE A.TRANSACTION_ID=T.ID) AC FROM TRANSACTIONS T''',
    )) {
      _validateOccurredAt(event['OCCURRED_AT'] as String);
      final kind = event['KIND'] as String,
          stockKinds = {'STOCK_BUY', 'STOCK_SELL', 'STOCK_DIVIDEND'},
          sc = event['SC'] as int,
          ac = event['AC'] as int;
      if (sc + ac != 1 || (stockKinds.contains(kind) ? sc != 1 : ac != 1)) {
        _fail('Transaction subtype does not match KIND');
      }
      if (sc == 1) {
        final row = _stockEvent(event['ID'] as String),
            type = _kind(kind),
            currency = _account(
              row['STOCK_ACCOUNT_ID'] as String,
            )['CURRENCY_CODE'];
        if (_accountType(_account(row['STOCK_ACCOUNT_ID'] as String)) !=
                AccountType.stock ||
            _accountType(_account(row['FUNDING_ACCOUNT_ID'] as String)) !=
                AccountType.general ||
            _security(row['SECURITY_ID'] as String)['CURRENCY_CODE'] !=
                currency ||
            _account(row['FUNDING_ACCOUNT_ID'] as String)['CURRENCY_CODE'] !=
                currency) {
          _fail('Invalid stored stock relation');
        }
        if (type == TransactionKind.stockDividend) {
          if (row['DIVIDEND_AMOUNT'] == null ||
              row['QUANTITY'] != null ||
              row['UNIT_PRICE'] != null ||
              row['FEE'] != null) {
            _fail('Invalid dividend fields');
          }
        } else if (row['QUANTITY'] == null ||
            row['UNIT_PRICE'] == null ||
            row['FEE'] == null ||
            row['DIVIDEND_AMOUNT'] != null) {
          _fail('Invalid stock trade fields');
        }
        _validateStockAmounts(_decodeStockInput(row));
      } else {
        final input = _decodeAccountInput(_accountEvent(event['ID'] as String));
        _validateAccountEventAmounts(input);
        _validateAccountEventRelations(input);
      }
    }
  }

  /// Lists stock positions, including positions with realized activity.
  ///
  /// Parameters
  /// ----------
  /// marketCode : `String?`
  ///     Optional market filter.
  /// stockAccountId : `String?`
  ///     Optional stock-account filter.
  /// cursor : `String?`
  ///     Optional security ID after which the page begins.
  /// limit : `int`
  ///     Maximum number of returned positions.
  ///
  /// Returns
  /// -------
  /// `Future<Page<StockPositionSummary>>`
  ///     One position page with actual share quantities and monetary values.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If a filter, cursor, or limit is invalid.
  Future<Page<StockPositionSummary>> listStockPositions({
    String? marketCode,
    String? stockAccountId,
    String? cursor,
    int limit = 50,
  }) async {
    _validateLimit(limit);
    final securities = _database.raw
        .select('SELECT * FROM SECURITIES ORDER BY MARKET_CODE,SYMBOL')
        .where((s) => marketCode == null || s['MARKET_CODE'] == marketCode)
        .toList();
    final positions = <StockPositionSummary>[];
    for (final s in securities) {
      final ag = _stockAggregate(
        stockAccountId: stockAccountId,
        securityId: s['ID'] as String,
      );
      if (ag.quantity == 0 && ag.realized == 0) continue;
      positions.add(
        StockPositionSummary(
          securityId: s['ID'] as String,
          symbol: s['SYMBOL'] as String,
          name: s['NAME'] as String,
          cost: Money.fromScaledUnits(
            currencyCode: s['CURRENCY_CODE'] as String,
            units: ag.cost,
          ),
          value: ag.complete
              ? Money.fromScaledUnits(
                  currencyCode: s['CURRENCY_CODE'] as String,
                  units: ag.value!,
                )
              : null,
          quantityUnits: ag.quantity / shareMultiplier,
        ),
      );
    }
    var start = 0;
    if (cursor != null) {
      final index = positions.indexWhere((p) => p.securityId == cursor);
      if (index < 0) _fail('Invalid cursor');
      start = index + 1;
    }
    final items = positions.skip(start).take(limit + 1).toList();
    final more = items.length > limit;
    if (more) items.removeLast();
    return Page(items: items, nextCursor: more ? items.last.securityId : null);
  }

  /// Builds the current stock overview in the TWD base currency.
  ///
  /// Parameters
  /// ----------
  /// marketCode : `String?`
  ///     Optional market filter.
  /// stockAccountId : `String?`
  ///     Optional stock-account filter.
  ///
  /// Returns
  /// -------
  /// `Future<StockOverview>`
  ///     Positions, converted totals, and valuation-completeness state.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If a supplied account or stored relation is invalid.
  Future<StockOverview> getStockOverview({
    String? marketCode,
    String? stockAccountId,
  }) async {
    final positions = (await listStockPositions(
      marketCode: marketCode,
      stockAccountId: stockAccountId,
      limit: 200,
    )).items;
    var cost = 0, value = 0, costComplete = true, valueComplete = true;
    for (final p in positions) {
      final rate = _rate(p.cost.currencyCode);
      if (rate == null) {
        costComplete = false;
        valueComplete = false;
        continue;
      }
      cost += _toTwd(p.cost.scaledUnits, p.cost.currencyCode, rate);
      if (p.value == null) {
        valueComplete = false;
      } else {
        value += _toTwd(p.value!.scaledUnits, p.value!.currencyCode, rate);
      }
    }
    return StockOverview(
      positions: positions,
      totalCost: costComplete
          ? Money.fromScaledUnits(currencyCode: 'TWD', units: cost)
          : null,
      totalValue: valueComplete
          ? Money.fromScaledUnits(currencyCode: 'TWD', units: value)
          : null,
      isValuationComplete: valueComplete,
    );
  }

  /// Calculates the current position detail for one security.
  ///
  /// Parameters
  /// ----------
  /// securityId : `String`
  ///     Security to calculate.
  /// stockAccountId : `String?`
  ///     Optional stock account used to narrow the calculation.
  ///
  /// Returns
  /// -------
  /// `Future<StockDetail>`
  ///     Actual shares, cost, value, dividends, and realized profit.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the security or supplied account does not exist.
  Future<StockDetail> getStockDetail(
    String securityId, {
    String? stockAccountId,
  }) async {
    final s = _security(securityId),
        ag = _stockAggregate(
          stockAccountId: stockAccountId,
          securityId: securityId,
        ),
        currency = s['CURRENCY_CODE'] as String;
    return StockDetail(
      securityId: securityId,
      symbol: s['SYMBOL'] as String,
      name: s['NAME'] as String,
      cost: Money.fromScaledUnits(currencyCode: currency, units: ag.cost),
      value: ag.complete
          ? Money.fromScaledUnits(currencyCode: currency, units: ag.value!)
          : null,
      quantityUnits: ag.quantity / shareMultiplier,
      realizedPnl: Money.fromScaledUnits(
        currencyCode: currency,
        units: ag.realized,
      ),
      dividendIncome: Money.fromScaledUnits(
        currencyCode: currency,
        units: ag.dividends,
      ),
    );
  }

  /// Lists transactions for one security in reverse chronological order.
  ///
  /// Parameters
  /// ----------
  /// securityId : `String`
  ///     Security whose transactions are requested.
  /// stockAccountId : `String?`
  ///     Optional stock-account filter.
  /// cursor : `String?`
  ///     Optional transaction ID after which the page begins.
  /// limit : `int`
  ///     Maximum number of returned transactions.
  ///
  /// Returns
  /// -------
  /// `Future<Page<AccountTransactionItem>>`
  ///     One transaction page and an optional next cursor.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the security, cursor, account filter, or limit is invalid.
  Future<Page<AccountTransactionItem>> listStockTransactions(
    String securityId, {
    String? stockAccountId,
    Set<TransactionKind>? kinds,
    String? cursor,
    int limit = 50,
  }) async {
    final rows =
        _allEvents()
            .where(
              (r) =>
                  r['SECURITY_ID'] == securityId &&
                  (stockAccountId == null ||
                      r['STOCK_ACCOUNT_ID'] == stockAccountId) &&
                  (kinds == null || kinds.contains(_kind(r['KIND'] as String))),
            )
            .toList()
          ..sort((a, b) {
            final c = (b['OCCURRED_AT'] as String).compareTo(
              a['OCCURRED_AT'] as String,
            );
            return c != 0
                ? c
                : (b['ENTRY_ORDER'] as int).compareTo(a['ENTRY_ORDER'] as int);
          });
    return _pageTransactions(rows, cursor, limit);
  }

  /// Lists active asset accounts.
  ///
  /// Parameters
  /// ----------
  /// categoryId : `String?`
  ///     Optional reporting-category filter.
  /// cursor : `String?`
  ///     Optional account ID after which the page begins.
  /// limit : `int`
  ///     Maximum number of returned accounts.
  ///
  /// Returns
  /// -------
  /// `Future<Page<AccountSummary>>`
  ///     One account page with current calculated details.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the cursor, category, or limit is invalid.
  Future<Page<AccountSummary>> listAssetAccounts({
    String? categoryId,
    String? cursor,
    int limit = 50,
  }) async {
    _validateLimit(limit);
    final rows = _database.raw.select(
      'SELECT ID FROM ACCOUNTS WHERE IS_ARCHIVED=0 AND (? IS NULL OR CATEGORY_ID=?) ORDER BY NAME,ID',
      [categoryId, categoryId],
    );
    final details = rows
        .map((r) => AccountSummary(_calculateAccount(r['ID'] as String)))
        .toList();
    var start = 0;
    if (cursor != null) {
      final index = details.indexWhere((x) => x.detail.id == cursor);
      if (index < 0) _fail('Invalid cursor');
      start = index + 1;
    }
    final items = details.skip(start).take(limit + 1).toList();
    final more = items.length > limit;
    if (more) items.removeLast();
    return Page(items: items, nextCursor: more ? items.last.detail.id : null);
  }

  /// Builds the current all-assets overview in TWD.
  ///
  /// Parameters
  /// ----------
  /// categoryId : `String?`
  ///     Optional reporting-category filter.
  ///
  /// Returns
  /// -------
  /// `Future<AssetOverview>`
  ///     Matching accounts, converted totals, and valuation completeness.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the category or stored account history is invalid.
  Future<AssetOverview> getAssetOverview({String? categoryId}) async {
    final accounts = (await listAssetAccounts(
      categoryId: categoryId,
      limit: 200,
    )).items;
    final converted = <({int cost, int value})>[];
    var complete = true;
    for (final a in accounts) {
      final d = a.detail;
      if (d.value == null) {
        complete = false;
        continue;
      }
      final rate = _rate(d.currencyCode);
      if (rate == null) {
        complete = false;
        continue;
      }
      converted.add((
        cost: _toTwd(d.cost.scaledUnits, d.currencyCode, rate),
        value: _toTwd(d.value!.scaledUnits, d.currencyCode, rate),
      ));
    }
    return AssetOverview(
      accounts: accounts,
      totalCost: complete
          ? Money.fromScaledUnits(
              currencyCode: 'TWD',
              units: converted.fold(0, (s, x) => s + x.cost),
            )
          : null,
      totalValue: complete
          ? Money.fromScaledUnits(
              currencyCode: 'TWD',
              units: converted.fold(0, (s, x) => s + x.value),
            )
          : null,
      isValuationComplete: complete,
    );
  }

  int? _rate(String currency) {
    if (currency == 'TWD') return exchangeRateMultiplier;
    final r = _database.raw.select(
      'SELECT RATE FROM EXCHANGE_RATES WHERE FROM_CURRENCY_CODE=?',
      [currency],
    );
    return r.isEmpty ? null : r.first['RATE'] as int;
  }

  int _toTwd(int units, String sourceCurrency, int rate) => roundRatio(
    BigInt.from(units) * BigInt.from(rate),
    BigInt.from(moneyMultipliers[sourceCurrency]! * exchangeRateMultiplier),
  );

  int _scaleExchangeRate(double rate) {
    if (!rate.isFinite) _fail('Invalid exchange rate');
    final scaled = rate * exchangeRateMultiplier;
    final rounded = scaled.round();
    if ((scaled - rounded).abs() > 0.0000001) {
      _fail('Exchange rate accepts at most two decimal places');
    }
    return rounded;
  }

  /// Loads data required by the stock-transaction form.
  ///
  /// Parameters
  /// ----------
  /// transactionId : `String?`
  ///     Existing transaction to edit, or null for a new form.
  ///
  /// Returns
  /// -------
  /// `Future<StockTransactionFormData>`
  ///     Security choices and optional existing transaction values.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the requested transaction does not exist or has the wrong type.
  Future<StockTransactionFormData> getStockTransactionForm({
    String? transactionId,
  }) async => StockTransactionFormData(
    securities: await searchSecurities(query: '', limit: 200),
    existing: transactionId == null
        ? null
        : _decodeStockInput(_stockEvent(transactionId)),
  );

  /// Searches securities by symbol or display name.
  ///
  /// Parameters
  /// ----------
  /// query : `String`
  ///     Case-insensitive text to match.
  /// marketCode : `String?`
  ///     Optional market filter.
  /// limit : `int`
  ///     Maximum number of returned options.
  ///
  /// Returns
  /// -------
  /// `Future<List<SecurityOption>>`
  ///     Matching security options in stable order.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the limit is invalid.
  Future<List<SecurityOption>> searchSecurities({
    String? marketCode,
    required String query,
    int limit = 20,
  }) async {
    _validateLimit(limit);
    final q = '%${query.trim().toUpperCase()}%';
    return _database.raw
        .select(
          'SELECT * FROM SECURITIES WHERE (? IS NULL OR MARKET_CODE=?) AND (SYMBOL LIKE ? OR upper(NAME) LIKE ?) ORDER BY MARKET_CODE,SYMBOL LIMIT ?',
          [marketCode, marketCode, q, q, limit],
        )
        .map(
          (r) => SecurityOption(
            id: r['ID'] as String,
            symbol: r['SYMBOL'] as String,
            name: r['NAME'] as String,
            marketCode: r['MARKET_CODE'] as String,
            currencyCode: r['CURRENCY_CODE'] as String,
          ),
        )
        .toList();
  }

  StockTransactionInput _decodeStockInput(Map<String, Object?> r) {
    ({
      String funding,
      String? note,
      String occurred,
      String security,
      String stock,
    })
    common(
      String occurred,
      String security,
      String stock,
      String funding,
      String? note,
    ) => (
      occurred: r['OCCURRED_AT'] as String,
      security: r['SECURITY_ID'] as String,
      stock: r['STOCK_ACCOUNT_ID'] as String,
      funding: r['FUNDING_ACCOUNT_ID'] as String,
      note: r['NOTE'] as String?,
    );
    final c = common('', '', '', '', null);
    switch (r['KIND']) {
      case 'STOCK_BUY':
        return StockBuyInput(
          occurredAt: c.occurred,
          securityId: c.security,
          stockAccountId: c.stock,
          fundingAccountId: c.funding,
          note: c.note,
          quantity: ShareQuantity.fromScaledUnits(r['QUANTITY'] as int),
          unitPrice: Money.fromScaledUnits(
            currencyCode: _account(c.stock)['CURRENCY_CODE'] as String,
            units: r['UNIT_PRICE'] as int,
          ),
          fee: Money.fromScaledUnits(
            currencyCode: _account(c.stock)['CURRENCY_CODE'] as String,
            units: r['FEE'] as int,
          ),
        );
      case 'STOCK_SELL':
        return StockSellInput(
          occurredAt: c.occurred,
          securityId: c.security,
          stockAccountId: c.stock,
          fundingAccountId: c.funding,
          note: c.note,
          quantity: ShareQuantity.fromScaledUnits(r['QUANTITY'] as int),
          unitPrice: Money.fromScaledUnits(
            currencyCode: _account(c.stock)['CURRENCY_CODE'] as String,
            units: r['UNIT_PRICE'] as int,
          ),
          fee: Money.fromScaledUnits(
            currencyCode: _account(c.stock)['CURRENCY_CODE'] as String,
            units: r['FEE'] as int,
          ),
        );
      default:
        return StockDividendInput(
          occurredAt: c.occurred,
          securityId: c.security,
          stockAccountId: c.stock,
          fundingAccountId: c.funding,
          note: c.note,
          dividendAmount: Money.fromScaledUnits(
            currencyCode: _account(c.stock)['CURRENCY_CODE'] as String,
            units: r['DIVIDEND_AMOUNT'] as int,
          ),
        );
    }
  }

  /// Loads data required by the general or investment transaction form.
  ///
  /// Parameters
  /// ----------
  /// transactionId : `String?`
  ///     Existing transaction to edit, or null for a new form.
  /// accountId : `String?`
  ///     Optional account that initiated a new form.
  ///
  /// Returns
  /// -------
  /// `Future<AccountTransactionFormData>`
  ///     Optional existing transaction values for form initialization.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If a requested account or transaction is missing or incompatible.
  Future<AccountTransactionFormData> getAccountTransactionForm({
    String? transactionId,
    String? accountId,
  }) async {
    if (accountId != null) _account(accountId);
    return AccountTransactionFormData(
      existing: transactionId == null
          ? null
          : _decodeAccountInput(_accountEvent(transactionId)),
    );
  }

  AccountTransactionInput _decodeAccountInput(Map<String, Object?> r) {
    final o = r['OCCURRED_AT'] as String, n = r['NOTE'] as String?;
    Money money(String account, int units) => Money.fromScaledUnits(
      currencyCode: _account(account)['CURRENCY_CODE'] as String,
      units: units,
    );
    switch (r['KIND']) {
      case 'ACCOUNT_TRANSFER':
        return AccountTransferInput(
          occurredAt: o,
          note: n,
          sourceAccountId: r['SOURCE_ACCOUNT_ID'] as String,
          targetAccountId: r['TARGET_ACCOUNT_ID'] as String,
          sourceAmount: money(
            r['SOURCE_ACCOUNT_ID'] as String,
            r['SOURCE_AMOUNT'] as int,
          ),
          targetAmount: money(
            r['TARGET_ACCOUNT_ID'] as String,
            r['TARGET_AMOUNT'] as int,
          ),
        );
      case 'ACCOUNT_INCOME':
        return AccountIncomeInput(
          occurredAt: o,
          note: n,
          targetAccountId: r['TARGET_ACCOUNT_ID'] as String,
          targetAmount: money(
            r['TARGET_ACCOUNT_ID'] as String,
            r['TARGET_AMOUNT'] as int,
          ),
        );
      case 'ACCOUNT_EXPENSE':
        return AccountExpenseInput(
          occurredAt: o,
          note: n,
          sourceAccountId: r['SOURCE_ACCOUNT_ID'] as String,
          sourceAmount: money(
            r['SOURCE_ACCOUNT_ID'] as String,
            r['SOURCE_AMOUNT'] as int,
          ),
        );
      case 'INVESTMENT_BUY':
        final i = r['INVESTMENT_ACCOUNT_ID'] as String;
        return InvestmentBuyInput(
          occurredAt: o,
          note: n,
          investmentAccountId: i,
          sourceAccountId: r['SOURCE_ACCOUNT_ID'] as String,
          amount: money(i, r['AMOUNT'] as int),
          fee: money(i, r['FEE'] as int),
        );
      case 'INVESTMENT_SELL':
        final i = r['INVESTMENT_ACCOUNT_ID'] as String;
        return InvestmentSellInput(
          occurredAt: o,
          note: n,
          investmentAccountId: i,
          targetAccountId: r['TARGET_ACCOUNT_ID'] as String,
          amount: money(i, r['AMOUNT'] as int),
          fee: money(i, r['FEE'] as int),
        );
      case 'INVESTMENT_INTEREST':
        final i = r['INVESTMENT_ACCOUNT_ID'] as String;
        return InvestmentInterestInput(
          occurredAt: o,
          note: n,
          investmentAccountId: i,
          targetAccountId: r['TARGET_ACCOUNT_ID'] as String,
          amount: money(i, r['AMOUNT'] as int),
        );
      default:
        final i = r['INVESTMENT_ACCOUNT_ID'] as String;
        return InvestmentPnlAdjustmentInput(
          occurredAt: o,
          note: n,
          investmentAccountId: i,
          valueAdjustment: money(i, r['VALUE_ADJUSTMENT'] as int),
        );
    }
  }

  /// Loads categories and saved editable values for the general-account editor.
  ///
  /// Parameters
  /// ----------
  /// accountId : `String?`
  ///     Existing general account to edit, or null when creating one.
  ///
  /// Returns
  /// -------
  /// `Future<AccountEditorData>`
  ///     Editor categories, calculated account detail, and saved opening values.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the requested account does not exist.
  Future<AccountEditorData> getAccountEditor({String? accountId}) async {
    final row = accountId == null ? null : _account(accountId);
    if (row != null && _accountType(row) != AccountType.general) {
      _fail('General editor requires GENERAL account');
    }
    return AccountEditorData(
      existing: accountId == null ? null : _calculateAccount(accountId),
      categories: await listCategories(),
      initialCost: row == null
          ? null
          : Money.fromScaledUnits(
              currencyCode: row['CURRENCY_CODE'] as String,
              units: row['INITIAL_COST'] as int,
            ),
      initialValue: row == null
          ? null
          : Money.fromScaledUnits(
              currencyCode: row['CURRENCY_CODE'] as String,
              units: row['INITIAL_VALUE'] as int,
            ),
      note: row?['NOTE'] as String?,
    );
  }

  /// Loads data for the stock or investment account editor.
  ///
  /// Parameters
  /// ----------
  /// accountId : `String?`
  ///     Existing account to edit, or null when creating one.
  /// createAccountType : `AccountType?`
  ///     STOCK or INVESTMENT type selected for a new account.
  ///
  /// Returns
  /// -------
  /// `Future<InvestmentAccountEditorData>`
  ///     Existing values, categories, and eligible funding accounts.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If an account is missing or GENERAL is supplied as the create type.
  Future<InvestmentAccountEditorData> getInvestmentAccountEditor({
    String? accountId,
    AccountType? createAccountType,
  }) async {
    if (accountId == null && createAccountType == AccountType.general) {
      _fail('Investment editor requires STOCK or INVESTMENT');
    }
    final existing = accountId == null ? null : _calculateAccount(accountId);
    final funding = _database.raw
        .select(
          "SELECT ID FROM ACCOUNTS WHERE ACCOUNT_TYPE='GENERAL' AND IS_ARCHIVED=0 ORDER BY NAME",
        )
        .map((r) => _calculateAccount(r['ID'] as String))
        .toList();
    return InvestmentAccountEditorData(
      existing: existing,
      categories: await listCategories(),
      createAccountType: createAccountType,
      fundingAccounts: funding,
      initialCost: existing == null
          ? null
          : Money.fromScaledUnits(
              currencyCode: existing.currencyCode,
              units: _account(existing.id)['INITIAL_COST'] as int,
            ),
      initialValue: existing == null
          ? null
          : Money.fromScaledUnits(
              currencyCode: existing.currencyCode,
              units: _account(existing.id)['INITIAL_VALUE'] as int,
            ),
      note: existing == null ? null : _account(existing.id)['NOTE'] as String?,
    );
  }

  /// Lists accounts for the account-management view.
  ///
  /// Parameters
  /// ----------
  /// status : `AccountStatus`
  ///     Active, archived, or all accounts.
  /// accountType : `AccountType?`
  ///     Optional immutable account-type filter.
  /// categoryId : `String?`
  ///     Optional reporting-category filter.
  ///
  /// Returns
  /// -------
  /// `Future<List<ManagedAccountSummary>>`
  ///     Matching accounts and their active funding-dependency counts.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If stored account relations are invalid.
  Future<List<ManagedAccountSummary>> listManagedAccounts({
    AccountStatus status = AccountStatus.all,
    AccountType? accountType,
    String? categoryId,
  }) async {
    return _database.raw
        .select('SELECT ID FROM ACCOUNTS ORDER BY NAME,ID')
        .map((r) => _calculateAccount(r['ID'] as String))
        .where(
          (a) =>
              (status == AccountStatus.all ||
                  (status == AccountStatus.archived) == a.isArchived) &&
              (accountType == null || a.accountType == accountType) &&
              (categoryId == null || a.categoryId == categoryId),
        )
        .map((a) {
          final count =
              _database.raw.select(
                    'SELECT COUNT(*) C FROM ACCOUNTS WHERE FUNDING_ACCOUNT_ID=? AND IS_ARCHIVED=0',
                    [a.id],
                  ).first['C']
                  as int;
          return ManagedAccountSummary(
            detail: a,
            fundingDependencyCount: count,
          );
        })
        .toList();
  }

  /// Builds the current TWD asset-allocation report by category.
  ///
  /// Parameters
  /// ----------
  /// `None`
  ///
  /// Returns
  /// -------
  /// `Future<AllocationReport>`
  ///     Category values, percentages, total value, and completeness state.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If stored account or category relations are invalid.
  Future<AllocationReport> getCurrentAllocation() async {
    final overview = await getAssetOverview();
    if (!overview.isValuationComplete) {
      return AllocationReport(
        items: const [],
        totalBaseValue: 0,
        isValuationComplete: false,
      );
    }
    final grouped = <String, int>{};
    for (final a in overview.accounts) {
      final d = a.detail;
      final rate = _rate(d.currencyCode)!;
      grouped[d.categoryId] =
          (grouped[d.categoryId] ?? 0) +
          _toTwd(d.value!.scaledUnits, d.currencyCode, rate);
    }
    final cats = {for (final c in await listCategories()) c.id: c};
    final total = grouped.values.fold(0, (a, b) => a + b);
    return AllocationReport(
      items: grouped.entries
          .map(
            (e) => AllocationItem(
              categoryId: e.key,
              name: cats[e.key]!.name,
              baseValue: e.value,
              percentage: total == 0 ? 0 : e.value / total,
            ),
          )
          .toList(),
      totalBaseValue: total,
      isValuationComplete: true,
    );
  }

  /// Builds the current TWD cost-versus-value report.
  ///
  /// Parameters
  /// ----------
  /// groupBy : `ReportGroupBy`
  ///     Whether rows represent categories or individual accounts.
  ///
  /// Returns
  /// -------
  /// `Future<CostValueReport>`
  ///     Converted cost and value rows for the selected grouping.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If current valuation is incomplete or stored relations are invalid.
  Future<CostValueReport> getCurrentCostValueComparison({
    ReportGroupBy groupBy = ReportGroupBy.category,
  }) async {
    final overview = await getAssetOverview();
    if (!overview.isValuationComplete) {
      throw const DataApiException(
        DataErrorCode.unavailable,
        'Current valuation is incomplete',
      );
    }
    final values = <String, ({String name, int cost, int value})>{};
    final cats = {for (final c in await listCategories()) c.id: c};
    for (final a in overview.accounts) {
      final d = a.detail,
          key = groupBy == ReportGroupBy.account ? d.id : d.categoryId,
          name = groupBy == ReportGroupBy.account
              ? d.name
              : cats[d.categoryId]!.name,
          rate = _rate(d.currencyCode)!;
      final old = values[key];
      values[key] = (
        name: name,
        cost:
            (old?.cost ?? 0) + _toTwd(d.cost.scaledUnits, d.currencyCode, rate),
        value:
            (old?.value ?? 0) +
            _toTwd(d.value!.scaledUnits, d.currencyCode, rate),
      );
    }
    return CostValueReport(
      values.entries
          .map(
            (e) => CostValueItem(
              id: e.key,
              name: e.value.name,
              baseCost: e.value.cost,
              baseValue: e.value.value,
            ),
          )
          .toList(),
    );
  }

  /// Captures at most one valuation snapshot per active account for a week.
  ///
  /// Parameters
  /// ----------
  /// snapshotDate : `String`
  ///     Taipei calendar date in `YYYY-MM-DD` form.
  ///
  /// Returns
  /// -------
  /// `Future<int>`
  ///     Number of new account snapshots written.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the date is invalid or stored account history cannot be calculated.
  Future<int> captureWeeklySnapshots({required String snapshotDate}) async {
    final date = _parseDate(snapshotDate),
        week = date.subtract(Duration(days: date.weekday - 1)),
        weekText = _dateText(week);
    var count = 0;
    _database.atomic(() {
      for (final row in _database.raw.select(
        'SELECT ID,CURRENCY_CODE FROM ACCOUNTS WHERE IS_ARCHIVED=0',
      )) {
        final id = row['ID'] as String,
            currency = row['CURRENCY_CODE'] as String,
            detail = _calculateAccount(id),
            rate = _rate(currency);
        if (!detail.isValuationComplete ||
            detail.value == null ||
            rate == null) {
          continue;
        }
        final existing = _database.raw.select(
          'SELECT 1 FROM ACCOUNT_WEEKLY_SNAPSHOTS WHERE ACCOUNT_ID=? AND WEEK_START_DATE=?',
          [id, weekText],
        );
        if (existing.isNotEmpty) continue;
        _database.insert('ACCOUNT_WEEKLY_SNAPSHOTS', {
          'ID': _uuid.v4(),
          'ACCOUNT_ID': id,
          'SNAPSHOT_DATE': snapshotDate,
          'WEEK_START_DATE': weekText,
          'ACCOUNT_CURRENCY_CODE': currency,
          'COST': detail.cost.scaledUnits,
          'VALUE': detail.value!.scaledUnits,
          'REALIZED_PNL': detail.realizedPnl.scaledUnits,
          'BASE_CURRENCY_CODE': 'TWD',
          'BASE_COST': _toTwd(detail.cost.scaledUnits, currency, rate),
          'BASE_VALUE': _toTwd(detail.value!.scaledUnits, currency, rate),
          'BASE_REALIZED_PNL': _toTwd(
            detail.realizedPnl.scaledUnits,
            currency,
            rate,
          ),
          'CAPTURED_AT': _utcNow(),
        });
        count++;
      }
    });
    return count;
  }

  /// Builds historical snapshot points and an independently calculated current point.
  ///
  /// Parameters
  /// ----------
  /// period : `TrendPeriod`
  ///     Time range used to filter historical snapshot dates.
  ///
  /// Returns
  /// -------
  /// `Future<HistoricalTrendReport>`
  ///     Historical TWD points, current totals, and current completeness state.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If stored snapshots or current account history are invalid.
  Future<HistoricalTrendReport> getHistoricalTrend({
    TrendPeriod period = TrendPeriod.all,
  }) async {
    final snapshots = _database.raw.select(
      'SELECT * FROM ACCOUNT_WEEKLY_SNAPSHOTS ORDER BY SNAPSHOT_DATE',
    );
    final dates =
        snapshots.map((r) => r['SNAPSHOT_DATE'] as String).toSet().toList()
          ..sort();
    final cutoff = _trendCutoff(period);
    final selected = dates
        .where((d) => cutoff == null || !_parseDate(d).isBefore(cutoff))
        .toList();
    final points = <TrendPoint>[];
    for (final date in selected) {
      var cost = 0, value = 0, pnl = 0;
      for (final account in _database.raw.select('SELECT * FROM ACCOUNTS')) {
        if (account['IS_ARCHIVED'] == 1) {
          final archived = _taipeiDate(
            DateTime.parse(account['UPDATED_AT'] as String),
          );
          if (!_parseDate(date).isBefore(archived)) continue;
        }
        final row = _database.raw.select(
          'SELECT * FROM ACCOUNT_WEEKLY_SNAPSHOTS WHERE ACCOUNT_ID=? AND SNAPSHOT_DATE<=? ORDER BY SNAPSHOT_DATE DESC LIMIT 1',
          [account['ID'], date],
        );
        if (row.isNotEmpty) {
          cost += row.first['BASE_COST'] as int;
          value += row.first['BASE_VALUE'] as int;
          pnl += row.first['BASE_REALIZED_PNL'] as int;
        }
      }
      points.add(
        TrendPoint(
          date: date,
          baseCost: cost,
          baseValue: value,
          baseRealizedPnl: pnl,
          isNow: false,
        ),
      );
    }
    final current = await getAssetOverview();
    points.add(
      TrendPoint(
        date: _dateText(_taipeiDate(_now().toUtc())),
        baseCost: current.totalCost?.scaledUnits ?? 0,
        baseValue: current.totalValue?.scaledUnits ?? 0,
        baseRealizedPnl: 0,
        isNow: true,
      ),
    );
    return HistoricalTrendReport(
      points: points,
      isCurrentValuationComplete: current.isValuationComplete,
    );
  }

  static const _tables = [
    'SCHEMA_METADATA',
    'CATEGORIES',
    'ACCOUNTS',
    'SECURITIES',
    'TRANSACTIONS',
    'STOCK_TRANSACTIONS',
    'ACCOUNT_TRANSACTIONS',
    'STOCK_PRICES',
    'EXCHANGE_RATES',
    'ACCOUNT_WEEKLY_SNAPSHOTS',
    'APP_SETTINGS',
  ];

  /// Exports every database table into an application backup archive.
  ///
  /// Parameters
  /// ----------
  /// destination : `String`
  ///     File path at which the backup archive is written.
  ///
  /// Returns
  /// -------
  /// `Future<ExportResult>`
  ///     Destination, archive hash, and exported row count.
  ///
  /// Raises
  /// ------
  /// `FileSystemException`
  ///     If the destination cannot be written.
  Future<ExportResult> exportBackup(String destination) async {
    _ensureOpen();
    final archive = Archive(),
        hashes = <String, String>{},
        counts = <String, int>{};
    for (final table in _tables) {
      final rows = _database.rows(table),
          columns = _tableColumns(table),
          matrix = <List<Object?>>[
            columns,
            ...rows.map((r) => columns.map((c) => r[c]).toList()),
          ],
          content = Csv(lineDelimiter: '\n').encode(matrix);
      final name = '$table.csv';
      archive.addFile(ArchiveFile.string(name, content));
      hashes[name] = sha256.convert(utf8.encode(content)).toString();
      counts[table] = rows.length;
    }
    final manifest = jsonEncode({
      'format': 'assetra-backup',
      'schemaVersion': '1',
      'createdAt': _utcNow(),
      'tables': _tables,
      'sha256': hashes,
      'rowCounts': counts,
    });
    archive.addFile(ArchiveFile.string('manifest.json', manifest));
    final encoded = ZipEncoder().encode(archive);
    await File(destination).writeAsBytes(encoded);
    return ExportResult(path: destination, tableCount: _tables.length);
  }

  /// Validates an application backup without changing the database.
  ///
  /// Parameters
  /// ----------
  /// source : `String`
  ///     Path of the backup archive to inspect.
  ///
  /// Returns
  /// -------
  /// `Future<BackupInspection>`
  ///     Schema version, row count, and verified archive hash.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If the archive, manifest, checksum, schema, or table data is invalid.
  /// `FileSystemException`
  ///     If the source file cannot be read.
  Future<BackupInspection> inspectBackup(String source) async {
    final parsed = await _readBackup(source);
    return BackupInspection(
      sourcePath: source,
      schemaVersion: parsed.version,
      createdAt: parsed.createdAt,
      rowCounts: {for (final e in parsed.rows.entries) e.key: e.value.length},
    );
  }

  /// Replaces all application data with a validated backup.
  ///
  /// Parameters
  /// ----------
  /// source : `String`
  ///     Path of the compatible application backup archive.
  ///
  /// Returns
  /// -------
  /// `Future<ImportResult>`
  ///     Number of rows imported after the atomic replacement succeeds.
  ///
  /// Raises
  /// ------
  /// `DataApiException`
  ///     If validation fails, biometric authentication fails, or imported relations are invalid.
  /// `FileSystemException`
  ///     If the source file cannot be read.
  Future<ImportResult> replaceFromBackup(String source) async {
    final backup = await _readBackup(source);
    final counts = <String, int>{};
    _database.atomic(() {
      for (final table in _tables.reversed) {
        _database.raw.execute('DELETE FROM $table');
      }
      for (final table in _tables) {
        for (final row in backup.rows[table]!) {
          _database.insert(table, row);
        }
        counts[table] = backup.rows[table]!.length;
      }
      _validateAllHistory();
      final version = _database.raw.select(
        "SELECT VALUE FROM SCHEMA_METADATA WHERE KEY='SCHEMA_VERSION'",
      );
      if (version.length != 1 || version.first['VALUE'] != '1') {
        throw const DataApiException(
          DataErrorCode.incompatibleBackup,
          'Invalid schema version',
        );
      }
    });
    return ImportResult(counts);
  }

  Future<_Backup> _readBackup(String source) async {
    try {
      final archive = ZipDecoder().decodeBytes(
            await File(source).readAsBytes(),
          ),
          files = <String, String>{};
      for (final f in archive.where((f) => f.isFile)) {
        final bytes = f.readBytes();
        if (bytes == null) throw const FormatException();
        files[f.name] = utf8.decode(bytes);
      }
      final manifest =
          jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
      if (manifest['format'] != 'assetra-backup' ||
          manifest['schemaVersion'] != '1') {
        throw const FormatException();
      }
      final tables = (manifest['tables'] as List).cast<String>();
      if (tables.length != _tables.length ||
          !tables.toSet().containsAll(_tables)) {
        throw const FormatException();
      }
      final hashes = (manifest['sha256'] as Map).cast<String, dynamic>(),
          rows = <String, List<Map<String, Object?>>>{};
      for (final table in _tables) {
        final name = '$table.csv', content = files[name];
        if (content == null ||
            sha256.convert(utf8.encode(content)).toString() != hashes[name]) {
          throw const FormatException();
        }
        final matrix = Csv().decode(content);
        if (matrix.isEmpty) throw const FormatException();
        final headers = matrix.first.map((v) => v.toString()).toList();
        if (headers.join('|') != _tableColumns(table).join('|')) {
          throw const FormatException();
        }
        rows[table] = matrix
            .skip(1)
            .map(
              (line) => {
                for (var i = 0; i < headers.length; i++)
                  headers[i]: _coerceCsv(table, headers[i], line[i]),
              },
            )
            .toList();
      }
      return _Backup(
        version: manifest['schemaVersion'] as String,
        createdAt: manifest['createdAt'] as String,
        rows: rows,
      );
    } catch (error) {
      if (error is DataApiException) rethrow;
      throw const DataApiException(
        DataErrorCode.incompatibleBackup,
        'Backup is corrupt or incompatible',
      );
    }
  }

  List<String> _tableColumns(String table) => _database.raw
      .select('PRAGMA table_info($table)')
      .map((r) => r['name'] as String)
      .toList();
  Object? _coerceCsv(String table, String column, Object? value) {
    if (value == null || value == '') return null;
    final info = _database.raw
        .select('PRAGMA table_info($table)')
        .firstWhere((r) => r['name'] == column);
    return info['type'] == 'INTEGER'
        ? int.parse(value.toString())
        : value.toString();
  }

  AppSettings _settings(Map<String, Object?> r) => AppSettings(
    themeMode: ThemeModeSetting
        .values[['SYSTEM', 'LIGHT', 'DARK'].indexOf(r['THEME_MODE'] as String)],
    languageCode: r['LANGUAGE_CODE'] as String,
    marketUpdateMode:
        MarketUpdateMode.values[[
          'MANUAL',
          'EVERY_15_MINUTES',
          'AFTER_MARKET_CLOSE',
        ].indexOf(r['MARKET_UPDATE_MODE'] as String)],
    isBiometricLockEnabled: r['IS_BIOMETRIC_LOCK_ENABLED'] == 1,
  );
  void _saveSettings(AppSettings s) {
    if (s.languageCode.trim().isEmpty) _fail('Language code cannot be blank');
    _database.raw.execute(
      'UPDATE APP_SETTINGS SET THEME_MODE=?,LANGUAGE_CODE=?,MARKET_UPDATE_MODE=?,IS_BIOMETRIC_LOCK_ENABLED=?,UPDATED_AT=? WHERE ID=1',
      [
        ['SYSTEM', 'LIGHT', 'DARK'][s.themeMode.index],
        s.languageCode,
        [
          'MANUAL',
          'EVERY_15_MINUTES',
          'AFTER_MARKET_CLOSE',
        ][s.marketUpdateMode.index],
        s.isBiometricLockEnabled ? 1 : 0,
        _utcNow(),
      ],
    );
  }

  DateTime _parseDate(String text) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (match == null) _fail('Date must be YYYY-MM-DD');
    final result = DateTime.utc(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
    if (_dateText(result) != text) _fail('Invalid date');
    return result;
  }

  String _dateText(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  DateTime _taipeiDate(DateTime utc) {
    final d = utc.toUtc().add(const Duration(hours: 8));
    return DateTime.utc(d.year, d.month, d.day);
  }

  DateTime? _trendCutoff(TrendPeriod p) {
    final now = _taipeiDate(_now().toUtc());
    return switch (p) {
      TrendPeriod.all => null,
      TrendPeriod.threeMonths => DateTime.utc(now.year, now.month - 3, now.day),
      TrendPeriod.sixMonths => DateTime.utc(now.year, now.month - 6, now.day),
      TrendPeriod.oneYear => DateTime.utc(now.year - 1, now.month, now.day),
      TrendPeriod.threeYears => DateTime.utc(now.year - 3, now.month, now.day),
    };
  }
}

class _Lot {
  int quantity, cost;
  _Lot(this.quantity, this.cost);
}

class _StockAggregate {
  final int cost, realized, dividends, quantity;
  final int? value;
  final bool complete;
  const _StockAggregate(
    this.cost,
    this.value,
    this.realized,
    this.dividends,
    this.quantity,
    this.complete,
  );
}

class _Backup {
  final String version, createdAt;
  final Map<String, List<Map<String, Object?>>> rows;
  const _Backup({
    required this.version,
    required this.createdAt,
    required this.rows,
  });
}
