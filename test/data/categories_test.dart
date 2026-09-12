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

  test('建立及修改分類時拒絕空白名稱', () async {
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
      (await api.listCategories()).singleWhere((c) => c.id == categoryId).name,
      'Growth',
    );
  });

  test('建立及修改分類時拒絕去除空白後的重複名稱', () async {
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
}
