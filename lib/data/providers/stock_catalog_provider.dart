import 'dart:convert';
import 'dart:io';

import '../models/domain.dart';

typedef CatalogTextFetcher = Future<String> Function(Uri uri);

class HttpStockCatalogProvider implements StockCatalogProvider {
  static final twseUri = Uri.parse(
    'https://openapi.twse.com.tw/v1/opendata/t187ap03_L',
  );
  static final tpexUri = Uri.parse(
    'https://www.tpex.org.tw/openapi/v1/mopsfin_t187ap03_O',
  );
  static final nasdaqListedUri = Uri.parse(
    'https://www.nasdaqtrader.com/dynamic/symdir/nasdaqlisted.txt',
  );
  static final nasdaqOtherUri = Uri.parse(
    'https://www.nasdaqtrader.com/dynamic/symdir/otherlisted.txt',
  );

  final CatalogTextFetcher _fetchText;

  HttpStockCatalogProvider({CatalogTextFetcher? fetchText})
    : _fetchText = fetchText ?? _defaultFetchText;

  @override
  Future<List<StockCatalogEntry>> fetch(StockCatalogSource source) async {
    final uri = switch (source) {
      StockCatalogSource.twse => twseUri,
      StockCatalogSource.tpex => tpexUri,
      StockCatalogSource.nasdaqListed => nasdaqListedUri,
      StockCatalogSource.nasdaqOther => nasdaqOtherUri,
    };
    final text = await _fetchText(uri);
    return switch (source) {
      StockCatalogSource.twse => _parseTaiwan(text, isListed: true),
      StockCatalogSource.tpex => _parseTaiwan(text, isListed: false),
      StockCatalogSource.nasdaqListed => _parseNasdaq(text, isListed: true),
      StockCatalogSource.nasdaqOther => _parseNasdaq(text, isListed: false),
    };
  }

  static Future<String> _defaultFetchText(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json,text/plain',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Catalog request failed: ${response.statusCode}',
          uri: uri,
        );
      }
      return await utf8.decoder.bind(response).join();
    } finally {
      client.close(force: true);
    }
  }

  static List<StockCatalogEntry> _parseTaiwan(
    String text, {
    required bool isListed,
  }) {
    final decoded = jsonDecode(text);
    if (decoded is! List) throw const FormatException('Expected catalog list');
    final entries = <StockCatalogEntry>[];
    for (final value in decoded) {
      if (value is! Map) continue;
      final code = _string(
        value[isListed ? '公司代號' : 'SecuritiesCompanyCode'] ?? value['公司代號'],
      );
      final name = _string(
        value[isListed ? '公司簡稱' : 'CompanyAbbreviation'] ?? value['公司簡稱'],
      );
      if (code.isEmpty || name.isEmpty) continue;
      entries.add(
        StockCatalogEntry(
          symbol: code,
          name: name,
          marketCode: 'TW',
          currencyCode: 'TWD',
          quoteSymbol: '$code.${isListed ? 'TW' : 'TWO'}',
        ),
      );
    }
    return entries;
  }

  static List<StockCatalogEntry> _parseNasdaq(
    String text, {
    required bool isListed,
  }) {
    final entries = <StockCatalogEntry>[];
    for (final line in const LineSplitter().convert(text).skip(1)) {
      if (line.startsWith('File Creation')) continue;
      final parts = line.split('|');
      final minimum = isListed ? 4 : 7;
      if (parts.length < minimum) continue;
      final symbol = parts[0].trim().toUpperCase();
      final name = parts[1].trim();
      final testIssue = parts[isListed ? 3 : 6].trim().toUpperCase();
      if (symbol.isEmpty || name.isEmpty || testIssue == 'Y') continue;
      entries.add(
        StockCatalogEntry(
          symbol: symbol,
          name: name,
          marketCode: 'US',
          currencyCode: 'USD',
          quoteSymbol: symbol,
        ),
      );
    }
    return entries;
  }

  static String _string(Object? value) => value is String ? value.trim() : '';
}
