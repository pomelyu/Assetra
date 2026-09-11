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
