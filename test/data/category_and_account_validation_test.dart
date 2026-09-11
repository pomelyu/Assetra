import 'dart:io';

import 'package:assetra/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late PortfolioDataApi api;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('assetra-validation-');
    api = await PortfolioDataApi.open(
      databasePath: '${directory.path}/test.sqlite',
      now: () => DateTime.utc(2026, 9, 12, 4),
    );
  });

  tearDown(() async {
    await api.close();
    directory.deleteSync(recursive: true);
  });

  group('category validation', () {
    test('blank category names are rejected on create and update', () async {
      final categoryId = await api.createCategory(
        const CreateCategoryInput(name: 'Growth', colorArgb: 0xff10b981),
      );

      await expectLater(
        api.createCategory(
          const CreateCategoryInput(name: '   ', colorArgb: 0xff10b981),
        ),
        throwsA(
          isA<DataApiException>().having(
            (error) => error.code,
            'code',
            DataErrorCode.validation,
          ),
        ),
      );
      await expectLater(
        api.updateCategory(
          categoryId,
          const UpdateCategoryInput(name: '\t', colorArgb: 0xff112233),
        ),
        throwsA(
          isA<DataApiException>().having(
            (error) => error.code,
            'code',
            DataErrorCode.validation,
          ),
        ),
      );

      expect(
        (await api.listCategories())
            .singleWhere((c) => c.id == categoryId)
            .name,
        'Growth',
      );
    });

    test('duplicate category names are rejected after trimming', () async {
      final categoryId = await api.createCategory(
        const CreateCategoryInput(name: 'Growth', colorArgb: 0xff10b981),
      );

      await expectLater(
        api.createCategory(
          const CreateCategoryInput(name: ' Growth ', colorArgb: 0xff112233),
        ),
        throwsA(
          isA<DataApiException>().having(
            (error) => error.code,
            'code',
            DataErrorCode.conflict,
          ),
        ),
      );

      final otherCategoryId = await api.createCategory(
        const CreateCategoryInput(name: 'Income', colorArgb: 0xff112233),
      );
      await expectLater(
        api.updateCategory(
          otherCategoryId,
          const UpdateCategoryInput(name: 'Growth', colorArgb: 0xffabcdef),
        ),
        throwsA(
          isA<DataApiException>().having(
            (error) => error.code,
            'code',
            DataErrorCode.conflict,
          ),
        ),
      );

      final categories = await api.listCategories();
      expect(categories.where((c) => c.name == 'Growth').single.id, categoryId);
      expect(
        categories.singleWhere((c) => c.id == otherCategoryId).name,
        'Income',
      );
    });
  });

  group('account archive and funding validation', () {
    test('an account cannot select itself as its funding account', () async {
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

    test('an archived general account cannot be modified', () async {
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

    test('an active funding dependency prevents account archival', () async {
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
  });
}
