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

  test('手動投資賣出依比例平均成本計算', () async {
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

  test('手動買入、利息與損益調整只影響指定帳本', () async {
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
  });

  test('手動投資交易類型只接受投資帳戶', () async {
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
}
