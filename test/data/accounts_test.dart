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

  test('一般帳戶沒有資金來源，股票及投資帳戶會回傳已儲存的資金來源', () async {
    final cashId = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
      ),
    );
    final investmentId = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Fund',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 200,
        initialValue: 250,
        accountType: AccountType.investment,
        fundingAccountId: cashId,
      ),
    );
    final stockId = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Broker',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
        accountType: AccountType.stock,
        fundingAccountId: cashId,
      ),
    );

    expect((await api.getAccountDetail(cashId)).fundingAccountId, isNull);
    expect((await api.getAccountDetail(investmentId)).fundingAccountId, cashId);
    expect((await api.getAccountDetail(stockId)).fundingAccountId, cashId);
  });

  test('修改股票或投資帳戶後會回傳新的預設資金來源', () async {
    final firstCashId = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash 1',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
      ),
    );
    final secondCashId = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash 2',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
      ),
    );
    final investmentId = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Fund',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 200,
        initialValue: 250,
        accountType: AccountType.investment,
        fundingAccountId: firstCashId,
      ),
    );
    final stockId = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Broker',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
        accountType: AccountType.stock,
        fundingAccountId: firstCashId,
      ),
    );

    await api.updateInvestmentAccount(
      investmentId,
      UpdateAccountInput(
        name: 'Fund',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 200,
        initialValue: 250,
        fundingAccountId: secondCashId,
      ),
    );
    await api.updateInvestmentAccount(
      stockId,
      UpdateAccountInput(
        name: 'Broker',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
        fundingAccountId: secondCashId,
      ),
    );

    expect(
      (await api.getAccountDetail(investmentId)).fundingAccountId,
      secondCashId,
    );
    expect(
      (await api.getAccountDetail(stockId)).fundingAccountId,
      secondCashId,
    );
  });

  test('建立股票或投資帳戶時未指定資金來源會拒絕儲存', () async {
    for (final accountType in [AccountType.stock, AccountType.investment]) {
      await expectLater(
        api.createInvestmentAccount(
          CreateInvestmentAccountInput(
            name: accountType.name,
            categoryId: 'default',
            currencyCode: 'USD',
            initialCost: 0,
            initialValue: 0,
            accountType: accountType,
            fundingAccountId: '',
          ),
        ),
        throwsA(isA<DataApiException>()),
      );
    }
  });

  test('建立股票或投資帳戶時資金來源不是有效的一般帳戶會拒絕儲存', () async {
    final cashId = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
      ),
    );
    final investmentId = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Existing Fund',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
        accountType: AccountType.investment,
        fundingAccountId: cashId,
      ),
    );
    final stockId = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Existing Broker',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
        accountType: AccountType.stock,
        fundingAccountId: cashId,
      ),
    );
    final archivedCashId = await api.createAccount(
      const CreateAccountInput(
        name: 'Archived Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
      ),
    );
    await api.archiveAccount(archivedCashId);

    for (final invalidFundingId in [investmentId, stockId, archivedCashId]) {
      for (final accountType in [AccountType.stock, AccountType.investment]) {
        await expectLater(
          api.createInvestmentAccount(
            CreateInvestmentAccountInput(
              name: accountType.name,
              categoryId: 'default',
              currencyCode: 'USD',
              initialCost: 0,
              initialValue: 0,
              accountType: accountType,
              fundingAccountId: invalidFundingId,
            ),
          ),
          throwsA(isA<DataApiException>()),
        );
      }
    }
  });

  test('更新股票或投資帳戶時未指定資金來源會拒絕且保留原資料', () async {
    final cashId = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
      ),
    );
    for (final accountType in [AccountType.stock, AccountType.investment]) {
      final accountId = await api.createInvestmentAccount(
        CreateInvestmentAccountInput(
          name: accountType.name,
          categoryId: 'default',
          currencyCode: 'USD',
          initialCost: 0,
          initialValue: 0,
          accountType: accountType,
          fundingAccountId: cashId,
        ),
      );

      await expectLater(
        api.updateInvestmentAccount(
          accountId,
          const UpdateAccountInput(
            name: 'Changed',
            categoryId: 'default',
            currencyCode: 'USD',
            initialCost: 0,
            initialValue: 0,
          ),
        ),
        throwsA(isA<DataApiException>()),
      );

      final detail = await api.getAccountDetail(accountId);
      expect(detail.name, accountType.name);
      expect(detail.fundingAccountId, cashId);
    }
  });

  test('更新股票或投資帳戶時資金來源不是有效的一般帳戶會拒絕且保留原資料', () async {
    final cashId = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
      ),
    );
    final investmentId = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Invalid Funding',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
        accountType: AccountType.investment,
        fundingAccountId: cashId,
      ),
    );
    final stockId = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Invalid Broker',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
        accountType: AccountType.stock,
        fundingAccountId: cashId,
      ),
    );
    final archivedCashId = await api.createAccount(
      const CreateAccountInput(
        name: 'Archived Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
      ),
    );
    await api.archiveAccount(archivedCashId);

    for (final accountType in [AccountType.stock, AccountType.investment]) {
      final accountId = await api.createInvestmentAccount(
        CreateInvestmentAccountInput(
          name: accountType.name,
          categoryId: 'default',
          currencyCode: 'USD',
          initialCost: 0,
          initialValue: 0,
          accountType: accountType,
          fundingAccountId: cashId,
        ),
      );

      for (final invalidFundingId in [investmentId, stockId, archivedCashId]) {
        await expectLater(
          api.updateInvestmentAccount(
            accountId,
            UpdateAccountInput(
              name: 'Changed',
              categoryId: 'default',
              currencyCode: 'USD',
              initialCost: 0,
              initialValue: 0,
              fundingAccountId: invalidFundingId,
            ),
          ),
          throwsA(isA<DataApiException>()),
        );
      }

      final detail = await api.getAccountDetail(accountId);
      expect(detail.name, accountType.name);
      expect(detail.fundingAccountId, cashId);
    }
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
