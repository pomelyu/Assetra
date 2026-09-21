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

  test('跨幣別轉帳分別保存兩端的實際金額', () async {
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

  test('一般帳戶收入增加成本與現值並拒絕負數', () async {
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
  });

  test('交易名稱會正規化、空白時產生預設值並限制三十字', () async {
    final account = await api.createAccount(
      const CreateAccountInput(
        name: 'cash',
        categoryId: 'default',
        currencyCode: 'TWD',
        initialCost: 0,
        initialValue: 0,
      ),
    );
    final custom = await api.createAccountTransaction(
      AccountIncomeInput(
        name: '  薪資收入  ',
        occurredAt: '2026-09-11 09:00',
        targetAccountId: account,
        targetAmount: Money(currencyCode: 'TWD', units: 100),
      ),
    );
    final generated = await api.createAccountTransaction(
      AccountExpenseInput(
        name: '   ',
        occurredAt: '2026-09-11 09:01',
        sourceAccountId: account,
        sourceAmount: Money(currencyCode: 'TWD', units: 10),
      ),
    );

    final items = (await api.listAccountTransactions(account)).items;
    expect(items.singleWhere((item) => item.id == custom).name, '薪資收入');
    expect(items.singleWhere((item) => item.id == generated).name, '支出');
    expect(
      (await api.getAccountTransactionForm(transactionId: custom))
          .existing!
          .name,
      '薪資收入',
    );
    await expectLater(
      api.createAccountTransaction(
        AccountIncomeInput(
          name: 'a' * 31,
          occurredAt: '2026-09-11 09:02',
          targetAccountId: account,
          targetAmount: Money(currencyCode: 'TWD', units: 1),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
  });

  test('既有一般交易不可透過 update 變更類型', () async {
    final account = await api.createAccount(
      const CreateAccountInput(
        name: 'cash',
        categoryId: 'default',
        currencyCode: 'TWD',
        initialCost: 100,
        initialValue: 100,
      ),
    );
    final id = await api.createAccountTransaction(
      AccountIncomeInput(
        occurredAt: '2026-09-11 09:00',
        targetAccountId: account,
        targetAmount: Money(currencyCode: 'TWD', units: 10),
      ),
    );

    await expectLater(
      api.updateAccountTransaction(
        id,
        AccountExpenseInput(
          occurredAt: '2026-09-11 09:00',
          sourceAccountId: account,
          sourceAmount: Money(currencyCode: 'TWD', units: 10),
        ),
      ),
      throwsA(isA<DataApiException>()),
    );
    final item = (await api.listAccountTransactions(account)).items.single;
    expect(item.kind, TransactionKind.accountIncome);
    expect(item.name, '收入');
    expect((await api.getAccountDetail(account)).value!.units, 110);
  });

  test('一般帳戶支出降低成本與現值並拒絕負數', () async {
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
  });

  test('一般帳戶交易類型拒絕股票及投資帳戶', () async {
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
  });
}
