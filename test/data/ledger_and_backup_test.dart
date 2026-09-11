import 'dart:io';

import 'package:assetra/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late PortfolioDataApi api;
  late DateTime testNow;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('assetra-ledger-');
    testNow = DateTime.now().toUtc();
    api = await PortfolioDataApi.open(
      databasePath: '${directory.path}/db.sqlite',
      now: () => testNow,
    );
  });
  tearDown(() async {
    await api.close();
    directory.deleteSync(recursive: true);
  });

  test('stock sales use FIFO including allocated buy fee', () async {
    final cash = await api.createAccount(
      const CreateAccountInput(
        name: 'cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 1000.75,
        initialValue: 900.25,
      ),
    );
    final stock = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'stock',
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
        symbol: '2330',
        name: '台積電',
        marketCode: 'TW',
        currencyCode: 'USD',
      ),
    );
    await api.createStockTransaction(
      StockBuyInput(
        occurredAt: '2026-09-10 09:00',
        securityId: security,
        stockAccountId: stock,
        fundingAccountId: cash,
        quantity: ShareQuantity(units: 10.25),
        unitPrice: Money(currencyCode: 'USD', units: 10.12),
        fee: Money(currencyCode: 'USD', units: 0.25),
      ),
    );
    await api.createStockTransaction(
      StockBuyInput(
        occurredAt: '2026-09-10 10:00',
        securityId: security,
        stockAccountId: stock,
        fundingAccountId: cash,
        quantity: ShareQuantity(units: 5.5),
        unitPrice: Money(currencyCode: 'USD', units: 12.34),
        fee: Money(currencyCode: 'USD', units: 0.10),
      ),
    );
    await api.createStockTransaction(
      StockSellInput(
        occurredAt: '2026-09-11 09:00',
        securityId: security,
        stockAccountId: stock,
        fundingAccountId: cash,
        quantity: ShareQuantity(units: 12),
        unitPrice: Money(currencyCode: 'USD', units: 15.55),
        fee: Money(currencyCode: 'USD', units: 0.20),
      ),
    );
    final detail = await api.getStockDetail(security, stockAccountId: stock);
    // Remaining shares: 10.25 + 5.5 - 12.
    expect(detail.quantityUnits, 3.75);
    // Second lot cost is 5.5 * 12.34 + 0.10 = 67.97. Selling 1.75 of
    // that lot disposes 21.63, leaving 46.34.
    expect(detail.cost.units, closeTo(67.97 - 21.63, 0.000001));
    // Sale proceeds are 12 * 15.55 - 0.20 = 186.40. FIFO cost disposed
    // is the complete first lot (103.98) plus 21.63 from the second lot.
    expect(
      detail.realizedPnl.units,
      closeTo(186.40 - (103.98 + 21.63), 0.000001),
    );
  });

  test('manual investment sale uses proportional average cost', () async {
    final cash = await api.createAccount(
      const CreateAccountInput(
        name: 'cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100.25,
        initialValue: 80.75,
      ),
    );
    final investment = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'fund',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 1000.50,
        initialValue: 1200.75,
        accountType: AccountType.investment,
        fundingAccountId: cash,
      ),
    );
    await api.createAccountTransaction(
      InvestmentSellInput(
        occurredAt: '2026-09-11 10:00',
        investmentAccountId: investment,
        targetAccountId: cash,
        amount: Money(currencyCode: 'USD', units: 600.25),
        fee: Money(currencyCode: 'USD', units: 10.15),
      ),
    );
    final detail = await api.getAccountDetail(investment);
    // round(1000.50 cost * 600.25 sale / 1200.75 value) = 500.15.
    expect(detail.cost.units, closeTo(1000.50 - 500.15, 0.000001));
    expect(detail.value!.units, closeTo(1200.75 - 600.25, 0.000001));
    expect(
      detail.realizedPnl.units,
      closeTo(600.25 - 10.15 - 500.15, 0.000001),
    );
    expect(
      detail.unrealizedPnl.units,
      closeTo((1200.75 - 600.25) - (1000.50 - 500.15), 0.000001),
    );
    final cashDetail = await api.getAccountDetail(cash);
    expect(cashDetail.cost.units, closeTo(100.25 + (600.25 - 10.15), 0.000001));
    expect(
      cashDetail.value!.units,
      closeTo(80.75 + (600.25 - 10.15), 0.000001),
    );
  });

  test('same-minute entries are returned newest insertion first', () async {
    final account = await api.createAccount(
      const CreateAccountInput(
        name: 'cash',
        categoryId: 'default',
        currencyCode: 'TWD',
        initialCost: 0,
        initialValue: 0,
      ),
    );
    final first = await api.createAccountTransaction(
      AccountIncomeInput(
        occurredAt: '2026-09-11 10:00',
        targetAccountId: account,
        targetAmount: Money(currencyCode: 'TWD', units: 1),
      ),
    );
    final second = await api.createAccountTransaction(
      AccountIncomeInput(
        occurredAt: '2026-09-11 10:00',
        targetAccountId: account,
        targetAmount: Money(currencyCode: 'TWD', units: 2),
      ),
    );
    expect(
      (await api.listAccountTransactions(account)).items.map((e) => e.id),
      [second, first],
    );
  });

  test(
    'account income increases cost and value and rejects negatives',
    () async {
      final account = await api.createAccount(
        const CreateAccountInput(
          name: 'USD cash',
          categoryId: 'default',
          currencyCode: 'USD',
          initialCost: 120.25,
          initialValue: 95.75,
        ),
      );

      await api.createAccountTransaction(
        AccountIncomeInput(
          occurredAt: '2026-09-11 09:00',
          targetAccountId: account,
          targetAmount: Money(currencyCode: 'USD', units: 25.50),
        ),
      );

      final detail = await api.getAccountDetail(account);
      expect(detail.cost.units, closeTo(120.25 + 25.50, 0.000001));
      expect(detail.value!.units, closeTo(95.75 + 25.50, 0.000001));

      expect(
        () => api.createAccountTransaction(
          AccountIncomeInput(
            occurredAt: '2026-09-11 09:01',
            targetAccountId: account,
            targetAmount: Money(currencyCode: 'USD', units: -0.01),
          ),
        ),
        throwsA(isA<DataApiException>()),
      );
    },
  );

  test(
    'account expense decreases cost and value and rejects negatives',
    () async {
      final account = await api.createAccount(
        const CreateAccountInput(
          name: 'USD cash',
          categoryId: 'default',
          currencyCode: 'USD',
          initialCost: 120.25,
          initialValue: 95.75,
        ),
      );

      await api.createAccountTransaction(
        AccountExpenseInput(
          occurredAt: '2026-09-11 09:00',
          sourceAccountId: account,
          sourceAmount: Money(currencyCode: 'USD', units: 25.50),
        ),
      );

      final detail = await api.getAccountDetail(account);
      expect(detail.cost.units, closeTo(120.25 - 25.50, 0.000001));
      expect(detail.value!.units, closeTo(95.75 - 25.50, 0.000001));

      expect(
        () => api.createAccountTransaction(
          AccountExpenseInput(
            occurredAt: '2026-09-11 09:01',
            sourceAccountId: account,
            sourceAmount: Money(currencyCode: 'USD', units: -0.01),
          ),
        ),
        throwsA(isA<DataApiException>()),
      );
    },
  );

  test('weekly snapshots are unique and backup restores all data', () async {
    final account = await api.createAccount(
      const CreateAccountInput(
        name: 'cash',
        categoryId: 'default',
        currencyCode: 'TWD',
        initialCost: 100,
        initialValue: 100,
      ),
    );
    expect(await api.captureWeeklySnapshots(snapshotDate: '2026-09-07'), 1);
    expect(await api.captureWeeklySnapshots(snapshotDate: '2026-09-10'), 0);
    final backup = '${directory.path}/backup.zip';
    await api.exportBackup(backup);
    await api.createAccountTransaction(
      AccountExpenseInput(
        occurredAt: '2026-09-11 10:00',
        sourceAccountId: account,
        sourceAmount: Money(currencyCode: 'TWD', units: 50),
      ),
    );
    final inspection = await api.inspectBackup(backup);
    expect(inspection.schemaVersion, '1');
    await api.replaceFromBackup(backup);
    expect((await api.getAccountDetail(account)).value!.units, 100);
    final trend = await api.getHistoricalTrend();
    expect(trend.points.first.baseValue, 100);
    expect(trend.points.last.isNow, isTrue);
  });

  test('future transaction is rejected', () async {
    final account = await api.createAccount(
      const CreateAccountInput(
        name: 'cash',
        categoryId: 'default',
        currencyCode: 'TWD',
        initialCost: 0,
        initialValue: 0,
      ),
    );
    final tomorrowInTaipei = testNow.add(const Duration(days: 1, hours: 8));
    final tomorrow =
        '${tomorrowInTaipei.year.toString().padLeft(4, '0')}-'
        '${tomorrowInTaipei.month.toString().padLeft(2, '0')}-'
        '${tomorrowInTaipei.day.toString().padLeft(2, '0')} 00:00';
    expect(
      () => api.createAccountTransaction(
        AccountIncomeInput(
          occurredAt: tomorrow,
          targetAccountId: account,
          targetAmount: Money(currencyCode: 'TWD', units: 1),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
  });

  test(
    'dividend is one event that credits cash and realized stock profit',
    () async {
      final cash = await api.createAccount(
        const CreateAccountInput(
          name: 'cash',
          categoryId: 'default',
          currencyCode: 'TWD',
          initialCost: 0,
          initialValue: 0,
        ),
      );
      final stock = await api.createInvestmentAccount(
        CreateInvestmentAccountInput(
          name: 'stock',
          categoryId: 'default',
          currencyCode: 'TWD',
          initialCost: 0,
          initialValue: 0,
          accountType: AccountType.stock,
          fundingAccountId: cash,
        ),
      );
      final security = await api.resolveSecurity(
        const ResolveSecurityInput(
          symbol: '2330',
          name: '台積電',
          marketCode: 'TW',
          currencyCode: 'TWD',
        ),
      );
      await api.createStockTransaction(
        StockDividendInput(
          occurredAt: '2026-09-11 10:00',
          securityId: security,
          stockAccountId: stock,
          fundingAccountId: cash,
          dividendAmount: Money(currencyCode: 'TWD', units: 50),
        ),
      );
      expect((await api.getAccountDetail(cash)).value!.units, 50);
      expect(
        (await api.getStockDetail(
          security,
          stockAccountId: stock,
        )).realizedPnl.units,
        50,
      );
    },
  );

  test(
    'manual buy interest and adjustment affect only their specified ledgers',
    () async {
      final cash = await api.createAccount(
        const CreateAccountInput(
          name: 'cash',
          categoryId: 'default',
          currencyCode: 'TWD',
          initialCost: 1000,
          initialValue: 900,
        ),
      );
      final investment = await api.createInvestmentAccount(
        CreateInvestmentAccountInput(
          name: 'fund',
          categoryId: 'default',
          currencyCode: 'TWD',
          initialCost: 200,
          initialValue: 100,
          accountType: AccountType.investment,
          fundingAccountId: cash,
        ),
      );
      await api.createAccountTransaction(
        InvestmentBuyInput(
          occurredAt: '2026-09-11 09:00',
          investmentAccountId: investment,
          sourceAccountId: cash,
          amount: Money(currencyCode: 'TWD', units: 500),
          fee: Money(currencyCode: 'TWD', units: 10),
        ),
      );
      await api.createAccountTransaction(
        InvestmentInterestInput(
          occurredAt: '2026-09-11 10:00',
          investmentAccountId: investment,
          targetAccountId: cash,
          amount: Money(currencyCode: 'TWD', units: 20),
        ),
      );
      await api.createAccountTransaction(
        InvestmentPnlAdjustmentInput(
          occurredAt: '2026-09-11 11:00',
          investmentAccountId: investment,
          valueAdjustment: Money(currencyCode: 'TWD', units: 100),
        ),
      );
      final detail = await api.getAccountDetail(investment);
      // Initial cost 200 + investment amount 500 + buy fee 10.
      expect(detail.cost.units, 200 + 500 + 10);
      // Initial value 100 + investment amount 500 + P/L adjustment 100.
      expect(detail.value!.units, 100 + 500 + 100);
      // Interest changes realized profit but does not change investment value.
      expect(detail.realizedPnl.units, 20);
      final cashDetail = await api.getAccountDetail(cash);
      // Funding cost: initial 1000 - (500 + 10) + interest 20.
      expect(cashDetail.cost.units, 1000 - (500 + 10) + 20);
      // Funding value uses its different initial value and the same cash flows.
      expect(cashDetail.value!.units, 900 - (500 + 10) + 20);
    },
  );

  test('buy and sell APIs reject negative quantities and amounts', () async {
    final cash = await api.createAccount(
      const CreateAccountInput(
        name: 'USD cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 1000.25,
        initialValue: 900.75,
      ),
    );
    final stock = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'USD stock',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
        accountType: AccountType.stock,
        fundingAccountId: cash,
      ),
    );
    final investment = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'USD fund',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 200.50,
        initialValue: 300.75,
        accountType: AccountType.investment,
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

    StockBuyInput stockBuy({required double shares, required double price}) =>
        StockBuyInput(
          occurredAt: '2026-09-11 09:00',
          securityId: security,
          stockAccountId: stock,
          fundingAccountId: cash,
          quantity: ShareQuantity(units: shares),
          unitPrice: Money(currencyCode: 'USD', units: price),
          fee: Money(currencyCode: 'USD', units: 0.15),
        );
    StockSellInput stockSell({required double shares, required double price}) =>
        StockSellInput(
          occurredAt: '2026-09-11 09:00',
          securityId: security,
          stockAccountId: stock,
          fundingAccountId: cash,
          quantity: ShareQuantity(units: shares),
          unitPrice: Money(currencyCode: 'USD', units: price),
          fee: Money(currencyCode: 'USD', units: 0.15),
        );

    expect(
      () => api.createStockTransaction(stockBuy(shares: -1.25, price: 10.50)),
      throwsA(isA<DataApiException>()),
    );
    expect(
      () => api.createStockTransaction(stockBuy(shares: 1.25, price: -10.50)),
      throwsA(isA<DataApiException>()),
    );
    expect(
      () => api.createStockTransaction(stockSell(shares: -1.25, price: 10.50)),
      throwsA(isA<DataApiException>()),
    );
    expect(
      () => api.createStockTransaction(stockSell(shares: 1.25, price: -10.50)),
      throwsA(isA<DataApiException>()),
    );
    expect(
      () => api.createAccountTransaction(
        InvestmentBuyInput(
          occurredAt: '2026-09-11 09:00',
          investmentAccountId: investment,
          sourceAccountId: cash,
          amount: Money(currencyCode: 'USD', units: -10.25),
          fee: Money(currencyCode: 'USD', units: 0.10),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
    expect(
      () => api.createAccountTransaction(
        InvestmentSellInput(
          occurredAt: '2026-09-11 09:00',
          investmentAccountId: investment,
          targetAccountId: cash,
          amount: Money(currencyCode: 'USD', units: -10.25),
          fee: Money(currencyCode: 'USD', units: 0.10),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
  });

  test('stock transaction kinds reject incompatible account types', () async {
    final general = await api.createAccount(
      const CreateAccountInput(
        name: 'General',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100.25,
        initialValue: 90.75,
      ),
    );
    final investment = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Investment',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 20.25,
        initialValue: 30.75,
        accountType: AccountType.investment,
        fundingAccountId: general,
      ),
    );
    final stock = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Stock',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
        accountType: AccountType.stock,
        fundingAccountId: general,
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

    await expectLater(
      api.createStockTransaction(
        StockBuyInput(
          occurredAt: '2026-09-11 09:00',
          securityId: security,
          stockAccountId: general,
          fundingAccountId: general,
          quantity: ShareQuantity(units: 1.25),
          unitPrice: Money(currencyCode: 'USD', units: 10.50),
          fee: Money(currencyCode: 'USD', units: 0.10),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
    await expectLater(
      api.createStockTransaction(
        StockSellInput(
          occurredAt: '2026-09-11 09:01',
          securityId: security,
          stockAccountId: investment,
          fundingAccountId: general,
          quantity: ShareQuantity(units: 1.25),
          unitPrice: Money(currencyCode: 'USD', units: 10.50),
          fee: Money(currencyCode: 'USD', units: 0.10),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
    await expectLater(
      api.createStockTransaction(
        StockDividendInput(
          occurredAt: '2026-09-11 09:02',
          securityId: security,
          stockAccountId: stock,
          fundingAccountId: investment,
          dividendAmount: Money(currencyCode: 'USD', units: 5.25),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
  });

  test(
    'general transaction kinds reject stock and investment accounts',
    () async {
      final general = await api.createAccount(
        const CreateAccountInput(
          name: 'General',
          categoryId: 'default',
          currencyCode: 'USD',
          initialCost: 100.25,
          initialValue: 90.75,
        ),
      );
      final stock = await api.createInvestmentAccount(
        CreateInvestmentAccountInput(
          name: 'Stock',
          categoryId: 'default',
          currencyCode: 'USD',
          initialCost: 0,
          initialValue: 0,
          accountType: AccountType.stock,
          fundingAccountId: general,
        ),
      );
      final investment = await api.createInvestmentAccount(
        CreateInvestmentAccountInput(
          name: 'Investment',
          categoryId: 'default',
          currencyCode: 'USD',
          initialCost: 20.25,
          initialValue: 30.75,
          accountType: AccountType.investment,
          fundingAccountId: general,
        ),
      );

      await expectLater(
        api.createAccountTransaction(
          AccountTransferInput(
            occurredAt: '2026-09-11 09:00',
            sourceAccountId: stock,
            targetAccountId: general,
            sourceAmount: Money(currencyCode: 'USD', units: 10.25),
            targetAmount: Money(currencyCode: 'USD', units: 10.25),
          ),
        ),
        throwsA(isA<DataApiException>()),
      );
      await expectLater(
        api.createAccountTransaction(
          AccountIncomeInput(
            occurredAt: '2026-09-11 09:01',
            targetAccountId: investment,
            targetAmount: Money(currencyCode: 'USD', units: 10.25),
          ),
        ),
        throwsA(isA<DataApiException>()),
      );
      await expectLater(
        api.createAccountTransaction(
          AccountExpenseInput(
            occurredAt: '2026-09-11 09:02',
            sourceAccountId: stock,
            sourceAmount: Money(currencyCode: 'USD', units: 10.25),
          ),
        ),
        throwsA(isA<DataApiException>()),
      );
    },
  );

  test('investment transaction kinds require an investment account', () async {
    final general = await api.createAccount(
      const CreateAccountInput(
        name: 'General',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100.25,
        initialValue: 90.75,
      ),
    );
    final stock = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Stock',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
        accountType: AccountType.stock,
        fundingAccountId: general,
      ),
    );

    await expectLater(
      api.createAccountTransaction(
        InvestmentBuyInput(
          occurredAt: '2026-09-11 09:00',
          investmentAccountId: general,
          sourceAccountId: general,
          amount: Money(currencyCode: 'USD', units: 10.25),
          fee: Money(currencyCode: 'USD', units: 0.10),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
    await expectLater(
      api.createAccountTransaction(
        InvestmentSellInput(
          occurredAt: '2026-09-11 09:01',
          investmentAccountId: stock,
          targetAccountId: general,
          amount: Money(currencyCode: 'USD', units: 10.25),
          fee: Money(currencyCode: 'USD', units: 0.10),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
    await expectLater(
      api.createAccountTransaction(
        InvestmentInterestInput(
          occurredAt: '2026-09-11 09:02',
          investmentAccountId: general,
          targetAccountId: general,
          amount: Money(currencyCode: 'USD', units: 5.25),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
    await expectLater(
      api.createAccountTransaction(
        InvestmentPnlAdjustmentInput(
          occurredAt: '2026-09-11 09:03',
          investmentAccountId: stock,
          valueAdjustment: Money(currencyCode: 'USD', units: 5.25),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
  });

  test('deleting an earlier buy rolls back when it would make a later sale invalid', () async {
    final cash = await api.createAccount(
      const CreateAccountInput(
        name: 'cash',
        categoryId: 'default',
        currencyCode: 'TWD',
        initialCost: 0,
        initialValue: 0,
      ),
    );
    final stock = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'stock',
        categoryId: 'default',
        currencyCode: 'TWD',
        initialCost: 0,
        initialValue: 0,
        accountType: AccountType.stock,
        fundingAccountId: cash,
      ),
    );
    final security = await api.resolveSecurity(
      const ResolveSecurityInput(
        symbol: '2330',
        name: '台積電',
        marketCode: 'TW',
        currencyCode: 'TWD',
      ),
    );
    final buy = await api.createStockTransaction(
      StockBuyInput(
        occurredAt: '2026-09-10 09:00',
        securityId: security,
        stockAccountId: stock,
        fundingAccountId: cash,
        quantity: ShareQuantity(units: 1),
        unitPrice: Money(currencyCode: 'TWD', units: 10),
        fee: Money(currencyCode: 'TWD', units: 0),
      ),
    );
    await api.createStockTransaction(
      StockSellInput(
        occurredAt: '2026-09-11 09:00',
        securityId: security,
        stockAccountId: stock,
        fundingAccountId: cash,
        quantity: ShareQuantity(units: 1),
        unitPrice: Money(currencyCode: 'TWD', units: 11),
        fee: Money(currencyCode: 'TWD', units: 0),
      ),
    );
    expect(
      () => api.deleteStockTransaction(buy),
      throwsA(isA<DataApiException>()),
    );
    expect((await api.listStockTransactions(security)).items, hasLength(2));
  });
}
