import 'dart:io';

import 'package:assetra/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late PortfolioDataApi api;
  var biometricCalls = 0;
  var refreshCalls = 0;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('assetra-public-api-');
    biometricCalls = 0;
    refreshCalls = 0;
    api = await PortfolioDataApi.open(
      databasePath: '${directory.path}/db.sqlite',
      now: () => DateTime.utc(2030, 1, 1),
      authenticateBiometric: () async {
        biometricCalls++;
        return true;
      },
      marketDataRefresher: (_) async {
        refreshCalls++;
        return const MarketRefreshResult(
          quoteSuccesses: 2,
          rateSuccesses: 1,
          failures: [],
        );
      },
    );
  });

  tearDown(() async {
    await api.close();
    directory.deleteSync(recursive: true);
  });

  test('category settings market refresh and account lifecycle APIs', () async {
    final secondCategory = await api.createCategory(
      const CreateCategoryInput(name: 'Growth', colorArgb: 0xff00ff00),
    );
    await api.updateCategory(
      secondCategory,
      const UpdateCategoryInput(name: 'Long-term', colorArgb: 0xff112233),
    );
    await api.reorderCategories([secondCategory, 'default']);
    final categories = await api.listCategories();
    expect(categories.map((category) => category.id), [
      secondCategory,
      'default',
    ]);
    expect(categories.first.name, 'Long-term');

    final cash = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100.25,
        initialValue: 90.75,
      ),
    );
    await api.updateAccount(
      cash,
      const UpdateAccountInput(
        name: 'Updated cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 120.50,
        initialValue: 95.25,
      ),
    );
    final investment = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Fund',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 200.25,
        initialValue: 300.75,
        accountType: AccountType.investment,
        fundingAccountId: cash,
      ),
    );
    await api.updateInvestmentAccount(
      investment,
      UpdateAccountInput(
        name: 'Updated fund',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 210.50,
        initialValue: 310.25,
        fundingAccountId: cash,
      ),
    );
    expect((await api.getAccountDetail(cash)).cost.units, 120.50);
    expect((await api.getAccountDetail(investment)).value!.units, 310.25);

    await api.saveExchangeRate(
      fromCurrencyCode: 'USD',
      rate: 32.15,
      quotedAt: DateTime.utc(2029, 12, 31),
    );
    final allocation = await api.getCurrentAllocation();
    expect(allocation.isValuationComplete, isTrue);
    // Each account is converted and rounded independently:
    // round(USD 95.25 * 32.15) + round(USD 310.25 * 32.15).
    expect(allocation.totalBaseValue, 3062 + 9975);
    expect((await api.getCurrentCostValueComparison()).items, hasLength(1));
    expect(
      (await api.getCurrentCostValueComparison(groupBy: ReportGroupBy.account))
          .items,
      hasLength(2),
    );

    final editor = await api.getAccountEditor(accountId: cash);
    expect(editor.existing!.name, 'Updated cash');
    final investmentEditor = await api.getInvestmentAccountEditor(
      accountId: investment,
    );
    expect(investmentEditor.fundingAccounts.single.id, cash);
    expect((await api.listManagedAccounts()).length, 2);

    await api.archiveAccount(investment);
    expect(
      () => api.updateInvestmentAccount(
        investment,
        UpdateAccountInput(
          name: 'Blocked',
          categoryId: 'default',
          currencyCode: 'USD',
          initialCost: 1,
          initialValue: 2,
          fundingAccountId: cash,
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
    await api.reactivateAccount(investment);
    expect((await api.getAccountDetail(investment)).isArchived, isFalse);

    final oldSettings = await api.getAppSettings();
    expect(oldSettings.themeMode, ThemeModeSetting.system);
    final settings = await api.updateAppSettings(
      const AppSettingsPatch(
        themeMode: ThemeModeSetting.dark,
        languageCode: 'en',
        marketUpdateMode: MarketUpdateMode.every15Minutes,
      ),
    );
    expect(settings.themeMode, ThemeModeSetting.dark);
    expect(
      (await api.setBiometricLockEnabled(true)).isBiometricLockEnabled,
      isTrue,
    );
    expect(biometricCalls, 1);
    final refresh = await api.refreshMarketData();
    expect(refresh.quoteSuccesses, 2);
    expect(refreshCalls, 1);

    await api.deleteCategory(secondCategory);
    expect((await api.listCategories()).map((category) => category.id), [
      'default',
    ]);
  });

  test('stock mutation preview form query and quote APIs', () async {
    final cash = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 500.25,
        initialValue: 450.75,
      ),
    );
    final stock = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Broker',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
        accountType: AccountType.stock,
        fundingAccountId: cash,
      ),
    );
    final security = await api.resolveSecurity(
      const ResolveSecurityInput(
        symbol: 'AAPL',
        name: 'Apple',
        marketCode: 'US',
        currencyCode: 'USD',
      ),
    );
    final original = StockBuyInput(
      occurredAt: '2029-12-30 10:00',
      securityId: security,
      stockAccountId: stock,
      fundingAccountId: cash,
      quantity: ShareQuantity(units: 2.5),
      unitPrice: Money(currencyCode: 'USD', units: 10.20),
      fee: Money(currencyCode: 'USD', units: 0.25),
    );
    expect(
      (await api.previewStockTransaction(original)).settlementAmount.units,
      2.5 * 10.20 + 0.25,
    );
    final transaction = await api.createStockTransaction(original);
    await api.updateStockTransaction(
      transaction,
      StockBuyInput(
        occurredAt: '2029-12-30 10:00',
        securityId: security,
        stockAccountId: stock,
        fundingAccountId: cash,
        quantity: ShareQuantity(units: 3.25),
        unitPrice: Money(currencyCode: 'USD', units: 10.20),
        fee: Money(currencyCode: 'USD', units: 0.25),
      ),
    );
    await api.saveStockPrice(
      securityId: security,
      price: Money(currencyCode: 'USD', units: 12.40),
      quotedAt: DateTime.utc(2029, 12, 31),
    );

    final form = await api.getStockTransactionForm(transactionId: transaction);
    expect((form.existing as StockBuyInput).quantity.units, 3.25);
    expect((await api.searchSecurities(query: 'app')).single.id, security);
    expect((await api.listStockPositions()).items.single.quantityUnits, 3.25);
    expect((await api.getStockOverview()).positions, hasLength(1));
    expect(
      (await api.listStockTransactions(security)).items.single.id,
      transaction,
    );
    expect((await api.listAssetAccounts()).items, hasLength(2));
    expect((await api.getAssetOverview()).accounts, hasLength(2));

    await api.deleteStockTransaction(transaction);
    expect((await api.listStockTransactions(security)).items, isEmpty);
  });

  test('account transaction mutation preview form and deletion APIs', () async {
    final cash = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100.25,
        initialValue: 90.75,
      ),
    );
    final income = AccountIncomeInput(
      occurredAt: '2029-12-30 10:00',
      targetAccountId: cash,
      targetAmount: Money(currencyCode: 'USD', units: 10.25),
    );
    expect(
      (await api.previewAccountTransaction(income)).targetChange!.units,
      10.25,
    );
    final transaction = await api.createAccountTransaction(income);
    await api.updateAccountTransaction(
      transaction,
      AccountIncomeInput(
        occurredAt: '2029-12-30 10:01',
        targetAccountId: cash,
        targetAmount: Money(currencyCode: 'USD', units: 20.50),
      ),
    );
    final form = await api.getAccountTransactionForm(
      transactionId: transaction,
      accountId: cash,
    );
    expect((form.existing as AccountIncomeInput).targetAmount.units, 20.50);
    await api.deleteAccountTransaction(transaction);
    expect((await api.listAccountTransactions(cash)).items, isEmpty);
  });
}
