import 'dart:io';

import 'package:assetra/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMarketProvider implements StockMarketDataProvider {
  final Map<String, StockQuote> quotes;
  Set<String>? requested;

  _FakeMarketProvider(this.quotes);

  @override
  Future<Map<String, StockQuote>> fetchQuotes(Set<String> quoteSymbols) async {
    requested = quoteSymbols;
    return quotes;
  }
}

void main() {
  late Directory directory;
  late PortfolioDataApi api;
  var hasApi = false;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('assetra-market-');
    hasApi = false;
  });

  tearDown(() async {
    if (hasApi) await api.close();
    directory.deleteSync(recursive: true);
  });

  test('Yahoo provider 解析有效行情並忽略無效價格', () async {
    final provider = YahooMarketDataProvider(
      fetchText: (_) async =>
          '{"quoteResponse":{"result":['
          '{"symbol":"AAPL","regularMarketPrice":123.45,"currency":"USD","regularMarketTime":1893456000},'
          '{"symbol":"BAD","regularMarketPrice":0,"currency":"USD","regularMarketTime":1893456000}'
          ']}}',
    );
    final quotes = await provider.fetchQuotes({'AAPL', 'BAD'});
    expect(quotes.keys, ['AAPL']);
    expect(quotes['AAPL']!.price, 123.45);
    expect(quotes['AAPL']!.quotedAt.isUtc, isTrue);
  });

  test('Yahoo 失敗時改用台股、NASDAQ 與匯率備援來源', () async {
    final provider = YahooMarketDataProvider(
      fetchText: (_) async => throw const HttpException('429'),
      fallbackFetchText: (uri) async {
        if (uri.host == 'mis.twse.com.tw') {
          return '{"msgArray":[{"ch":"2412.tw","z":"145.0","y":"144.5","tlong":"1893456000000"}]}';
        }
        if (uri.host == 'api.nasdaq.com') {
          return '{"data":{"symbol":"AAPL","primaryData":{"lastSalePrice":"\$123.45"}}}';
        }
        if (uri.host == 'open.er-api.com') {
          return '{"result":"success","time_last_update_unix":1893456000,"rates":{"TWD":32.15}}';
        }
        throw StateError('Unexpected fallback URI: $uri');
      },
    );

    final quotes = await provider.fetchQuotes({'2412.TW', 'AAPL', 'USDTWD=X'});

    expect(quotes['2412.TW']!.price, 145);
    expect(quotes['2412.TW']!.currencyCode, 'TWD');
    expect(quotes['AAPL']!.price, 123.45);
    expect(quotes['AAPL']!.currencyCode, 'USD');
    expect(quotes['USDTWD=X']!.price, 32.15);
    expect(quotes['USDTWD=X']!.currencyCode, 'TWD');
  });

  test('NASDAQ 股票查無 QQQ 時改用 ETF asset class', () async {
    final requestedUris = <Uri>[];
    final provider = YahooMarketDataProvider(
      fetchText: (_) async => throw const HttpException('429'),
      fallbackFetchText: (uri) async {
        requestedUris.add(uri);
        if (uri.queryParameters['assetclass'] == 'stocks') {
          return '{"data":null,"status":{"rCode":400}}';
        }
        return '{"data":{"symbol":"QQQ","primaryData":{"lastSalePrice":"\$746.36"}}}';
      },
    );

    final quotes = await provider.fetchQuotes({'QQQ'});

    expect(quotes['QQQ']!.price, 746.36);
    expect(requestedUris.map((uri) => uri.queryParameters['assetclass']), [
      'stocks',
      'etf',
    ]);
  });

  test('只更新曾有買賣的證券並包含零持股與封存帳戶', () async {
    final provider = _FakeMarketProvider({
      'AAPL': StockQuote(
        quoteSymbol: 'AAPL',
        price: 20.1234,
        currencyCode: 'USD',
        quotedAt: DateTime.utc(2029, 12, 31),
      ),
      'USDTWD=X': StockQuote(
        quoteSymbol: 'USDTWD=X',
        price: 32.156,
        currencyCode: 'TWD',
        quotedAt: DateTime.utc(2029, 12, 31),
      ),
    });
    api = await PortfolioDataApi.open(
      databasePath: '${directory.path}/db.sqlite',
      now: () => DateTime.utc(2030, 1, 1),
      stockMarketDataProvider: provider,
    );
    hasApi = true;
    final cash = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
      ),
    );
    final stock = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Broker',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
        accountType: AccountType.stock,
        fundingAccountId: cash,
      ),
    );
    final bought = await api.resolveSecurity(
      const ResolveSecurityInput(
        symbol: 'AAPL',
        name: 'Apple',
        marketCode: 'US',
        currencyCode: 'USD',
        quoteSymbol: 'AAPL',
      ),
    );
    final dividendOnly = await api.resolveSecurity(
      const ResolveSecurityInput(
        symbol: 'MSFT',
        name: 'Microsoft',
        marketCode: 'US',
        currencyCode: 'USD',
        quoteSymbol: 'MSFT',
      ),
    );
    await api.createStockTransaction(
      StockBuyInput(
        occurredAt: '2029-12-30 09:00',
        securityId: bought,
        stockAccountId: stock,
        fundingAccountId: cash,
        quantity: ShareQuantity(units: 1),
        unitPrice: Money(currencyCode: 'USD', units: 10),
        fee: Money(currencyCode: 'USD', units: 0),
      ),
    );
    await api.createStockTransaction(
      StockSellInput(
        occurredAt: '2029-12-30 10:00',
        securityId: bought,
        stockAccountId: stock,
        fundingAccountId: cash,
        quantity: ShareQuantity(units: 1),
        unitPrice: Money(currencyCode: 'USD', units: 12),
        fee: Money(currencyCode: 'USD', units: 0),
      ),
    );
    await api.createStockTransaction(
      StockDividendInput(
        occurredAt: '2029-12-30 11:00',
        securityId: dividendOnly,
        stockAccountId: stock,
        fundingAccountId: cash,
        dividendAmount: Money(currencyCode: 'USD', units: 1),
      ),
    );
    await api.archiveAccount(stock);

    final result = await api.refreshMarketData();
    expect(provider.requested, {'AAPL', 'USDTWD=X'});
    expect(result.quoteSuccesses, 1);
    expect(result.rateSuccesses, 1);
    expect(result.failures, isEmpty);
    expect((await api.getStockDetail(bought)).value, isNotNull);
  });

  test('缺少回傳的行情保留最後成功資料並回報失敗', () async {
    final provider = _FakeMarketProvider({});
    api = await PortfolioDataApi.open(
      databasePath: '${directory.path}/db.sqlite',
      now: () => DateTime.utc(2030, 1, 1),
      stockMarketDataProvider: provider,
    );
    hasApi = true;
    final cash = await api.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 100,
        initialValue: 100,
      ),
    );
    final stock = await api.createInvestmentAccount(
      CreateInvestmentAccountInput(
        name: 'Broker',
        categoryId: 'default',
        currencyCode: 'USD',
        initialCost: 0,
        initialValue: 0,
        accountType: AccountType.stock,
        fundingAccountId: cash,
      ),
    );
    final security = await api.resolveSecurity(
      const ResolveSecurityInput(
        symbol: 'AAPL',
        name: 'Apple',
        marketCode: 'US',
        currencyCode: 'USD',
        quoteSymbol: 'AAPL',
      ),
    );
    await api.createStockTransaction(
      StockBuyInput(
        occurredAt: '2029-12-30 09:00',
        securityId: security,
        stockAccountId: stock,
        fundingAccountId: cash,
        quantity: ShareQuantity(units: 1),
        unitPrice: Money(currencyCode: 'USD', units: 10),
        fee: Money(currencyCode: 'USD', units: 0),
      ),
    );
    await api.saveStockPrice(
      securityId: security,
      price: Money(currencyCode: 'USD', units: 15),
      quotedAt: DateTime.utc(2029, 12, 30),
    );

    final result = await api.refreshMarketData();
    expect(result.quoteSuccesses, 0);
    expect(result.failures, hasLength(2));
    expect(result.quoteFailures, hasLength(1));
    expect(result.rateFailures, hasLength(1));
    expect(result.failures.first, contains('AAPL'));
    expect((await api.getStockDetail(security)).value!.units, 15);
  });
}
