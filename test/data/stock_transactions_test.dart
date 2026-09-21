import 'dart:io';

import 'package:assetra/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late PortfolioDataApi api;
  late DateTime testNow;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('assetra-test-');
    testNow = DateTime.utc(2030, 1, 1);
    api = await PortfolioDataApi.open(
      databasePath: '${directory.path}/db.sqlite',
      now: () => testNow,
    );
  });

  tearDown(() async {
    await api.close();
    directory.deleteSync(recursive: true);
  });

  test('股票買入以單一事件增加股票成本並扣除資金帳戶餘額', () async {
    final cash = await api.createAccount(
      CreateAccountInput(
        name: 'B',
        categoryId: 'default',
        currencyCode: 'TWD',
        initialCost: 35000,
        initialValue: 30000,
      ),
    );
    final stock = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'A',
        categoryId: 'default',
        currencyCode: 'TWD',
        accountType: AccountType.stock,
        fundingAccountId: cash,
        initialCost: 0,
        initialValue: 0,
      ),
    );
    final security = await api.resolveSecurity(
      ResolveSecurityInput(
        symbol: '2330',
        name: '台積電',
        marketCode: 'TW',
        currencyCode: 'TWD',
      ),
    );
    final id = await api.createStockTransaction(
      StockBuyInput(
        occurredAt: '2026-09-11 10:00',
        securityId: security,
        stockAccountId: stock,
        fundingAccountId: cash,
        quantity: ShareQuantity(units: 10),
        unitPrice: Money(currencyCode: 'TWD', units: 2412),
        fee: Money(currencyCode: 'TWD', units: 10),
      ),
    );
    expect(id, isNotEmpty);
    final stockDetail = await api.getAccountDetail(stock);
    final cashDetail = await api.getAccountDetail(cash);
    expect(stockDetail.cost.units, 2412 * 10 + 10);
    expect(stockDetail.value, isNull);
    expect(stockDetail.isValuationComplete, isFalse);
    expect(cashDetail.cost.units, 35000 - (2412 * 10 + 10));
    expect(cashDetail.value!.units, 30000 - (2412 * 10 + 10));
    expect((await api.listAccountTransactions(cash)).items.single.id, id);
  });

  test('股票賣出依 FIFO 計算並分攤買入手續費', () async {
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

  test('股息以單一事件增加現金與股票已實現損益', () async {
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
  });

  test('股票預設名稱依市場與實際股數產生', () async {
    final cash = await api.createAccount(
      const CreateAccountInput(
        name: 'cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
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
    final tw = await api.resolveSecurity(
      const ResolveSecurityInput(
        symbol: '2330',
        name: '台積電',
        marketCode: 'TW',
        currencyCode: 'USD',
      ),
    );
    final us = await api.resolveSecurity(
      const ResolveSecurityInput(
        symbol: 'AAPL',
        name: 'Apple Inc.',
        marketCode: 'US',
        currencyCode: 'USD',
      ),
    );
    final twBuy = await api.createStockTransaction(
      StockBuyInput(
        occurredAt: '2026-09-11 09:00',
        securityId: tw,
        stockAccountId: stock,
        fundingAccountId: cash,
        quantity: ShareQuantity(units: 1.25),
        unitPrice: Money(currencyCode: 'USD', units: 10),
        fee: Money(currencyCode: 'USD', units: 0),
      ),
    );
    await api.createStockTransaction(
      StockDividendInput(
        occurredAt: '2026-09-11 09:01',
        securityId: us,
        stockAccountId: stock,
        fundingAccountId: cash,
        dividendAmount: Money(currencyCode: 'USD', units: 1),
      ),
    );

    expect(
      (await api.listStockTransactions(tw)).items.single.name,
      '買入 台積電 1.25股',
    );
    expect((await api.listStockTransactions(us)).items.single.name, 'AAPL 配息');
    await expectLater(
      api.updateStockTransaction(
        twBuy,
        StockSellInput(
          occurredAt: '2026-09-11 09:00',
          securityId: tw,
          stockAccountId: stock,
          fundingAccountId: cash,
          quantity: ShareQuantity(units: 1.25),
          unitPrice: Money(currencyCode: 'USD', units: 10),
          fee: Money(currencyCode: 'USD', units: 0),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
    final unchanged = (await api.listStockTransactions(tw)).items.single;
    expect(unchanged.kind, TransactionKind.stockBuy);
    expect(unchanged.name, '買入 台積電 1.25股');
  });

  test('股票交易類型拒絕不相容的帳戶類型', () async {
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

  test('刪除早期買入導致後續賣出無效時完整回滾', () async {
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
