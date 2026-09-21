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

  test('每週快照不重複且備份可還原完整資料', () async {
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
    final namedTransaction = await api.createAccountTransaction(
      AccountIncomeInput(
        name: '備份測試收入',
        occurredAt: '2026-09-10 10:00',
        targetAccountId: account,
        targetAmount: Money(currencyCode: 'TWD', units: 10),
      ),
    );
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
    expect(inspection.schemaVersion, '2');
    await api.replaceFromBackup(backup);
    expect((await api.getAccountDetail(account)).value!.units, 110);
    expect(
      (await api.getAccountTransactionForm(transactionId: namedTransaction))
          .existing!
          .name,
      '備份測試收入',
    );
    final trend = await api.getHistoricalTrend();
    expect(trend.points.first.baseValue, 100);
    expect(trend.points.last.isNow, isTrue);
  });
}
