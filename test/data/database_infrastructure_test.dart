import 'dart:io';

import 'package:assetra/data/src/database/portfolio_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('資料庫 schema 可持久化並強制外鍵及交易回滾', () {
    final directory = Directory.systemTemp.createTempSync('assetra-db-');
    final path = '${directory.path}/test.sqlite';
    final db = PortfolioDatabase.open(path);
    try {
      expect(db.rows('SCHEMA_METADATA').single['VALUE'], '1');
      expect(db.rows('CATEGORIES'), hasLength(1));
      expect(
        () => db.atomic(() {
          db.insert('TRANSACTIONS', {
            'ID': 'event',
            'KIND': 'STOCK_BUY',
            'OCCURRED_AT': '2026-01-01 10:00',
            'ENTRY_ORDER': 1,
            'UPDATED_AT': '2026-01-01T02:00:00.000Z',
          });
          db.insert('STOCK_TRANSACTIONS', {
            'TRANSACTION_ID': 'event',
            'SECURITY_ID': 'missing',
            'STOCK_ACCOUNT_ID': 'missing',
            'FUNDING_ACCOUNT_ID': 'missing',
            'QUANTITY': 100,
            'UNIT_PRICE': 10,
            'FEE': 0,
          });
        }),
        throwsA(anything),
      );
      expect(db.rows('TRANSACTIONS'), isEmpty);
      db.close();
      final reopened = PortfolioDatabase.open(path);
      expect(reopened.rows('APP_SETTINGS'), hasLength(1));
      reopened.close();
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
