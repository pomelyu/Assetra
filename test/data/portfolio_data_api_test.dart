import 'dart:io';

import 'package:assetra/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late PortfolioDataApi api;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('assetra-api-');
    api = await PortfolioDataApi.open(
      databasePath: '${directory.path}/test.sqlite',
      now: () => DateTime.utc(2026, 9, 11, 4),
    );
  });
  tearDown(() async {
    await api.close();
    directory.deleteSync(recursive: true);
  });

  test(
    'stock buy is one event and changes stock cost plus funding balance',
    () async {
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
    },
  );

  test('cross currency transfer stores actual amounts for both ends', () async {
    final usd = await api.createAccount(
      CreateAccountInput(
        name: 'C',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 120.75,
        initialValue: 100.25,
      ),
    );
    final twd = await api.createAccount(
      CreateAccountInput(
        name: 'B',
        categoryId: 'default',
        currencyCode: 'TWD',
        initialCost: 1000,
        initialValue: 900,
      ),
    );
    await api.createAccountTransaction(
      AccountTransferInput(
        occurredAt: '2026-09-11 10:00',
        sourceAccountId: usd,
        targetAccountId: twd,
        sourceAmount: Money(currencyCode: 'USD', units: 25.25),
        targetAmount: Money(currencyCode: 'TWD', units: 810),
      ),
    );
    final usdDetail = await api.getAccountDetail(usd);
    final twdDetail = await api.getAccountDetail(twd);
    expect(usdDetail.cost.units, 120.75 - 25.25);
    expect(usdDetail.value!.units, 100.25 - 25.25);
    expect(twdDetail.cost.units, 1000 + 810);
    expect(twdDetail.value!.units, 900 + 810);
  });

  test('archived participant prevents transaction mutation', () async {
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
}
