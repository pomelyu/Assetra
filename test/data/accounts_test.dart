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

  test('帳戶不可指定自己為資金來源帳戶', () async {
    final cashId = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100.25,
        initialValue: 90.75,
      ),
    );
    final investmentId = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Fund',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 200.50,
        initialValue: 250.75,
        accountType: AccountType.investment,
        fundingAccountId: cashId,
      ),
    );

    await expectLater(
      api.updateInvestmentAccount(
        investmentId,
        UpdateAccountInput(
          name: 'Fund',
          categoryId: 'default',
          currencyCode: 'USD',
          initialCost: 200.50,
          initialValue: 250.75,
          fundingAccountId: investmentId,
        ),
      ),
      throwsA(isA<DataApiException>()),
    );

    expect((await api.getAccountDetail(investmentId)).name, 'Fund');
  });

  test('封存的一般帳戶不可修改', () async {
    final accountId = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100.25,
        initialValue: 90.75,
      ),
    );
    await api.archiveAccount(accountId);

    await expectLater(
      api.updateAccount(
        accountId,
        const UpdateAccountInput(
          name: 'Changed',
          categoryId: 'default',
          currencyCode: 'USD',
          initialCost: 1.25,
          initialValue: 2.50,
        ),
      ),
      throwsA(isA<DataApiException>()),
    );

    final detail = await api.getAccountDetail(accountId);
    expect(detail.name, 'Cash');
    expect(detail.isArchived, isTrue);
    expect(detail.cost.units, 100.25);
    expect(detail.value!.units, 90.75);
  });

  test('一般帳戶被啟用帳戶作為資金來源時不可封存', () async {
    final cashId = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100.25,
        initialValue: 90.75,
      ),
    );
    await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Fund',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 200.50,
        initialValue: 250.75,
        accountType: AccountType.investment,
        fundingAccountId: cashId,
      ),
    );

    await expectLater(
      api.archiveAccount(cashId),
      throwsA(
        isA<DataApiException>().having(
          (error) => error.code,
          'code',
          DataErrorCode.conflict,
        ),
      ),
    );

    expect((await api.getAccountDetail(cashId)).isArchived, isFalse);
  });
}
