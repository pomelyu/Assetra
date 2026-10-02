import 'dart:convert';
import 'dart:io';

import '../models/domain.dart';

typedef MarketTextFetcher = Future<String> Function(Uri uri);

class YahooMarketDataProvider implements StockMarketDataProvider {
  final MarketTextFetcher _fetchText;
  final MarketTextFetcher? _fallbackFetchText;

  YahooMarketDataProvider({
    MarketTextFetcher? fetchText,
    MarketTextFetcher? fallbackFetchText,
  }) : _fetchText = fetchText ?? _defaultFetchText,
       _fallbackFetchText =
           fallbackFetchText ?? (fetchText == null ? _defaultFetchText : null);

  @override
  Future<Map<String, StockQuote>> fetchQuotes(Set<String> quoteSymbols) async {
    if (quoteSymbols.isEmpty) return const {};
    final normalized = quoteSymbols
        .map((symbol) => symbol.trim().toUpperCase())
        .toSet();
    final quotes = <String, StockQuote>{};
    try {
      quotes.addAll(await _fetchYahoo(normalized));
    } on Object {
      if (_fallbackFetchText == null) rethrow;
    }
    if (_fallbackFetchText != null) {
      await _fetchFallback(normalized.difference(quotes.keys.toSet()), quotes);
    }
    return quotes;
  }

  Future<Map<String, StockQuote>> _fetchYahoo(Set<String> symbols) async {
    final encoded = symbols.map(Uri.encodeQueryComponent).join(',');
    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v7/finance/quote?symbols=$encoded',
    );
    final decoded = jsonDecode(await _fetchText(uri));
    if (decoded is! Map) throw const FormatException('Invalid quote response');
    final quoteResponse = decoded['quoteResponse'];
    if (quoteResponse is! Map || quoteResponse['result'] is! List) {
      throw const FormatException('Invalid quote response');
    }
    final quotes = <String, StockQuote>{};
    for (final value in quoteResponse['result'] as List) {
      if (value is! Map) continue;
      final symbol = value['symbol'];
      final price = value['regularMarketPrice'];
      final currency = value['currency'];
      final timestamp = value['regularMarketTime'];
      if (symbol is! String ||
          price is! num ||
          !price.isFinite ||
          price <= 0 ||
          currency is! String ||
          timestamp is! num) {
        continue;
      }
      final normalized = symbol.trim().toUpperCase();
      quotes[normalized] = StockQuote(
        quoteSymbol: normalized,
        price: price,
        currencyCode: currency.trim().toUpperCase(),
        quotedAt: DateTime.fromMillisecondsSinceEpoch(
          timestamp.toInt() * 1000,
          isUtc: true,
        ),
      );
    }
    return quotes;
  }

  Future<void> _fetchFallback(
    Set<String> symbols,
    Map<String, StockQuote> quotes,
  ) async {
    final fetch = _fallbackFetchText!;
    final taiwan = symbols
        .where((symbol) => symbol.endsWith('.TW') || symbol.endsWith('.TWO'))
        .toList();
    if (taiwan.isNotEmpty) {
      try {
        final channels = taiwan
            .map((symbol) {
              final otc = symbol.endsWith('.TWO');
              final code = symbol.substring(0, symbol.lastIndexOf('.'));
              return '${otc ? 'otc' : 'tse'}_$code.tw';
            })
            .join('|');
        final uri = Uri.https(
          'mis.twse.com.tw',
          '/stock/api/getStockInfo.jsp',
          {'ex_ch': channels, 'json': '1', 'delay': '0'},
        );
        final decoded = jsonDecode(await fetch(uri));
        if (decoded is Map && decoded['msgArray'] is List) {
          for (final value in decoded['msgArray'] as List) {
            if (value is! Map) continue;
            final channel = value['ch'];
            if (channel is! String) continue;
            final suffix = channel.toLowerCase().contains('.tw') ? '.TW' : '';
            final code = channel.split('.').first.toUpperCase();
            final requested = taiwan.firstWhere(
              (symbol) => symbol.startsWith('$code.'),
              orElse: () => '$code$suffix',
            );
            final price = _number(value['z']) ?? _number(value['y']);
            final millis = int.tryParse('${value['tlong'] ?? ''}');
            if (price == null || price <= 0) continue;
            quotes[requested] = StockQuote(
              quoteSymbol: requested,
              price: price,
              currencyCode: 'TWD',
              quotedAt: millis == null
                  ? DateTime.now().toUtc()
                  : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
            );
          }
        }
      } on Object {
        // A failed fallback remains a missing quote for the caller to report.
      }
    }

    for (final symbol in symbols.where(
      (value) =>
          !value.endsWith('.TW') &&
          !value.endsWith('.TWO') &&
          !value.endsWith('=X'),
    )) {
      for (final assetClass in const ['stocks', 'etf']) {
        try {
          final uri = Uri.https(
            'api.nasdaq.com',
            '/api/quote/${Uri.encodeComponent(symbol)}/info',
            {'assetclass': assetClass},
          );
          final decoded = jsonDecode(await fetch(uri));
          final data = decoded is Map ? decoded['data'] : null;
          final primary = data is Map ? data['primaryData'] : null;
          final price = primary is Map
              ? _number(
                  '${primary['lastSalePrice'] ?? ''}'.replaceAll(r'$', ''),
                )
              : null;
          if (price == null || price <= 0) continue;
          quotes[symbol] = StockQuote(
            quoteSymbol: symbol,
            price: price,
            currencyCode: 'USD',
            quotedAt: DateTime.now().toUtc(),
          );
          break;
        } on Object {
          // Try the next supported Nasdaq asset class.
        }
      }
    }

    if (symbols.contains('USDTWD=X')) {
      try {
        final decoded = jsonDecode(
          await fetch(Uri.parse('https://open.er-api.com/v6/latest/USD')),
        );
        final rates = decoded is Map ? decoded['rates'] : null;
        final price = rates is Map ? _number(rates['TWD']) : null;
        final seconds = decoded is Map
            ? int.tryParse('${decoded['time_last_update_unix'] ?? ''}')
            : null;
        if (price != null && price > 0) {
          quotes['USDTWD=X'] = StockQuote(
            quoteSymbol: 'USDTWD=X',
            price: price,
            currencyCode: 'TWD',
            quotedAt: seconds == null
                ? DateTime.now().toUtc()
                : DateTime.fromMillisecondsSinceEpoch(
                    seconds * 1000,
                    isUtc: true,
                  ),
          );
        }
      } on Object {
        // A failed fallback remains a missing rate for the caller to report.
      }
    }
  }

  static double? _number(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is! String) return null;
    return double.tryParse(value.replaceAll(',', '').trim());
  }

  static Future<String> _defaultFetchText(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
        'AppleWebKit/605.1.15 Mobile/15E148 Assetra/1.0',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Quote request failed: ${response.statusCode}',
          uri: uri,
        );
      }
      return await utf8.decoder.bind(response).join();
    } finally {
      client.close(force: true);
    }
  }
}
