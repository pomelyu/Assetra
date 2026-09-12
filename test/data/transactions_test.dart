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

  test('交易涉及封存帳戶時拒絕新增', () async {
    final source = await api.createAccount(
      CreateAccountInput(
        name: 'S',
        categoryId: 'default',
        currencyCode: 'TWD',
        initialCost: 0,
        initialValue: 0,
      ),
    );
    final target = await api.createAccount(
      CreateAccountInput(
        name: 'T',
        categoryId: 'default',
        currencyCode: 'TWD',
        initialCost: 0,
        initialValue: 0,
      ),
    );
    await api.archiveAccount(source);
    expect(
      () => api.createAccountTransaction(
        AccountTransferInput(
          occurredAt: '2026-09-11 10:00',
          sourceAccountId: source,
          targetAccountId: target,
          sourceAmount: Money(currencyCode: 'TWD', units: 10),
          targetAmount: Money(currencyCode: 'TWD', units: 10),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
  });

  test('同分鐘交易依建立順序由新到舊回傳', () async {
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

  test('拒絕建立未來時間的交易', () async {
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

  test('股票及手動投資買賣拒絕負股數、負價格與負金額', () async {
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
}
