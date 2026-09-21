import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';

class PortfolioDatabase {
  final Database _database;
  bool _closed = false;
  PortfolioDatabase._(this._database);

  static PortfolioDatabase open(String path) {
    final database = sqlite3.open(path);
    database.execute('PRAGMA foreign_keys = ON');
    database.execute('BEGIN IMMEDIATE');
    try {
      for (final statement in createSchemaStatements) {
        database.execute(statement);
      }
      _migrate(database);
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        "INSERT OR IGNORE INTO SCHEMA_METADATA(KEY,VALUE) VALUES('SCHEMA_VERSION',?)",
        ['$schemaVersion'],
      );
      database.execute(
        "INSERT OR IGNORE INTO CATEGORIES(ID,NAME,COLOR_ARGB,SORT_ORDER,UPDATED_AT) VALUES('default','未分類',4288585374,0,?)",
        [now],
      );
      database.execute(
        "INSERT OR IGNORE INTO CATEGORIES(ID,NAME,COLOR_ARGB,SORT_ORDER,UPDATED_AT) VALUES('deposit','存款',4283215696,1,?)",
        [now],
      );
      database.execute(
        "INSERT OR IGNORE INTO CATEGORIES(ID,NAME,COLOR_ARGB,SORT_ORDER,UPDATED_AT) VALUES('investment','投資',4280391411,2,?)",
        [now],
      );
      database.execute(
        "INSERT OR IGNORE INTO APP_SETTINGS(ID,THEME_MODE,LANGUAGE_CODE,MARKET_UPDATE_MODE,IS_BIOMETRIC_LOCK_ENABLED,UPDATED_AT) VALUES(1,'SYSTEM','zh-TW','MANUAL',0,?)",
        [now],
      );
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      database.close();
      rethrow;
    }
    return PortfolioDatabase._(database);
  }

  static void _migrate(Database database) {
    final rows = database.select(
      "SELECT VALUE FROM SCHEMA_METADATA WHERE KEY='SCHEMA_VERSION'",
    );
    if (rows.isEmpty) return;
    final version = int.tryParse(rows.single['VALUE'] as String);
    if (version == schemaVersion) return;
    if (version != 1) {
      throw StateError('Unsupported schema version: $version');
    }
    database.execute(
      "ALTER TABLE TRANSACTIONS ADD COLUMN NAME TEXT NOT NULL DEFAULT '交易' "
      "CHECK(trim(NAME) <> '' AND length(NAME) <= 30)",
    );
    const simpleNames = {
      'ACCOUNT_TRANSFER': '轉帳',
      'ACCOUNT_INCOME': '收入',
      'ACCOUNT_EXPENSE': '支出',
      'INVESTMENT_BUY': '投資買入',
      'INVESTMENT_SELL': '投資賣出',
      'INVESTMENT_INTEREST': '利息',
      'INVESTMENT_PNL_ADJUSTMENT': '損益調整',
    };
    for (final entry in simpleNames.entries) {
      database.execute('UPDATE TRANSACTIONS SET NAME=? WHERE KIND=?', [
        entry.value,
        entry.key,
      ]);
    }
    final stockRows = database.select('''
      SELECT T.ID,T.KIND,S.QUANTITY,E.SYMBOL,E.NAME,E.MARKET_CODE
      FROM TRANSACTIONS T
      JOIN STOCK_TRANSACTIONS S ON S.TRANSACTION_ID=T.ID
      JOIN SECURITIES E ON E.ID=S.SECURITY_ID
      WHERE T.KIND IN ('STOCK_BUY','STOCK_SELL','STOCK_DIVIDEND')''');
    for (final row in stockRows) {
      final label = row['MARKET_CODE'] == 'TW'
          ? row['NAME'] as String
          : row['SYMBOL'] as String;
      final kind = row['KIND'] as String;
      final name = kind == 'STOCK_DIVIDEND'
          ? '$label 配息'
          : '${kind == 'STOCK_BUY' ? '買入' : '賣出'} $label ${_shareText(row['QUANTITY'] as int)}股';
      if (name.length > 30) {
        throw StateError('Generated transaction name exceeds 30 characters');
      }
      database.execute('UPDATE TRANSACTIONS SET NAME=? WHERE ID=?', [
        name,
        row['ID'],
      ]);
    }
    final unresolved =
        database
                .select(
                  "SELECT COUNT(*) AS N FROM TRANSACTIONS WHERE NAME='交易'",
                )
                .single['N']
            as int;
    if (unresolved != 0) {
      throw StateError('Some transaction names could not be migrated');
    }
    database.execute(
      "UPDATE SCHEMA_METADATA SET VALUE=? WHERE KEY='SCHEMA_VERSION'",
      ['$schemaVersion'],
    );
  }

  static String _shareText(int scaledUnits) {
    final whole = scaledUnits ~/ 10000;
    final fraction = (scaledUnits % 10000).toString().padLeft(4, '0');
    final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.isEmpty ? '$whole' : '$whole.$trimmed';
  }

  List<Map<String, Object?>> rows(String table) {
    _ensureOpen();
    final allowed = {
      'SCHEMA_METADATA',
      'CATEGORIES',
      'ACCOUNTS',
      'SECURITIES',
      'TRANSACTIONS',
      'STOCK_TRANSACTIONS',
      'ACCOUNT_TRANSACTIONS',
      'STOCK_PRICES',
      'EXCHANGE_RATES',
      'ACCOUNT_WEEKLY_SNAPSHOTS',
      'APP_SETTINGS',
    };
    if (!allowed.contains(table)) throw ArgumentError.value(table, 'table');
    return _database
        .select('SELECT * FROM $table')
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  void insert(String table, Map<String, Object?> values) {
    _ensureOpen();
    final columns = values.keys.toList(growable: false);
    final placeholders = List.filled(columns.length, '?').join(',');
    _database.execute(
      'INSERT INTO $table (${columns.join(',')}) VALUES ($placeholders)',
      columns.map((key) => values[key]).toList(),
    );
  }

  T atomic<T>(T Function() action) {
    _ensureOpen();
    _database.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      _database.execute('COMMIT');
      return result;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Database get raw => _database;
  void close() {
    if (!_closed) {
      _closed = true;
      _database.close();
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Database is closed');
  }
}
