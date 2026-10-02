import 'dart:io';

import 'package:assetra/data/data.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCatalogProvider implements StockCatalogProvider {
  final Map<StockCatalogSource, Object> responses;

  const _FakeCatalogProvider(this.responses);

  @override
  Future<List<StockCatalogEntry>> fetch(StockCatalogSource source) async {
    final response = responses[source];
    if (response is Exception) throw response;
    if (response is List<StockCatalogEntry>) return response;
    if (response is List && response.isEmpty) return const [];
    throw StateError('Invalid fake catalog response');
  }
}

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('assetra-catalog-');
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  test('目錄同步新增並更新四個來源且台股保留中文名稱', () async {
    final api = await PortfolioDataApi.open(
      databasePath: '${directory.path}/db.sqlite',
      now: () => DateTime.utc(2030, 1, 1),
      stockCatalogProvider: const _FakeCatalogProvider({
        StockCatalogSource.twse: [
          StockCatalogEntry(
            symbol: '2330',
            name: '台積電',
            marketCode: 'TW',
            currencyCode: 'TWD',
            quoteSymbol: '2330.TW',
          ),
        ],
        StockCatalogSource.tpex: [
          StockCatalogEntry(
            symbol: '6488',
            name: '環球晶',
            marketCode: 'TW',
            currencyCode: 'TWD',
            quoteSymbol: '6488.TWO',
          ),
        ],
        StockCatalogSource.nasdaqListed: [
          StockCatalogEntry(
            symbol: 'AAPL',
            name: 'Apple Inc.',
            marketCode: 'US',
            currencyCode: 'USD',
            quoteSymbol: 'AAPL',
          ),
        ],
        StockCatalogSource.nasdaqOther: [],
      }),
    );
    addTearDown(api.close);

    final result = await api.syncSecurityCatalog();
    expect(result.added, 3);
    expect(result.failures, isEmpty);
    final tw = await api.searchSecurities(query: '台積');
    expect(tw.single.name, '台積電');
    expect(tw.single.isActive, isTrue);
    expect(tw.single.quoteSymbol, '2330.TW');
  });

  test('成功來源停用缺席證券，失敗來源保留舊資料並可恢復', () async {
    final path = '${directory.path}/db.sqlite';
    var api = await PortfolioDataApi.open(
      databasePath: path,
      now: () => DateTime.utc(2030, 1, 1),
      stockCatalogProvider: const _FakeCatalogProvider({
        StockCatalogSource.twse: [
          StockCatalogEntry(
            symbol: '2330',
            name: '台積電',
            marketCode: 'TW',
            currencyCode: 'TWD',
            quoteSymbol: '2330.TW',
          ),
        ],
        StockCatalogSource.tpex: [],
        StockCatalogSource.nasdaqListed: [
          StockCatalogEntry(
            symbol: 'AAPL',
            name: 'Apple',
            marketCode: 'US',
            currencyCode: 'USD',
            quoteSymbol: 'AAPL',
          ),
        ],
        StockCatalogSource.nasdaqOther: [],
      }),
    );
    await api.syncSecurityCatalog();
    await api.close();

    api = await PortfolioDataApi.open(
      databasePath: path,
      now: () => DateTime.utc(2030, 1, 2),
      stockCatalogProvider: _FakeCatalogProvider({
        StockCatalogSource.twse: const <StockCatalogEntry>[],
        StockCatalogSource.tpex: const <StockCatalogEntry>[],
        StockCatalogSource.nasdaqListed: StateError('offline'),
        StockCatalogSource.nasdaqOther: const <StockCatalogEntry>[],
      }),
    );
    final second = await api.syncSecurityCatalog();
    expect(second.deactivated, 1);
    expect(second.failures, hasLength(1));
    expect(await api.searchSecurities(query: '2330'), isEmpty);
    expect((await api.searchSecurities(query: 'AAPL')).single.isActive, isTrue);
    await api.close();

    api = await PortfolioDataApi.open(
      databasePath: path,
      now: () => DateTime.utc(2030, 1, 3),
      stockCatalogProvider: const _FakeCatalogProvider({
        StockCatalogSource.twse: [
          StockCatalogEntry(
            symbol: '2330',
            name: '台積電',
            marketCode: 'TW',
            currencyCode: 'TWD',
            quoteSymbol: '2330.TW',
          ),
        ],
        StockCatalogSource.tpex: [],
        StockCatalogSource.nasdaqListed: [],
        StockCatalogSource.nasdaqOther: [],
      }),
    );
    final third = await api.syncSecurityCatalog();
    expect(third.reactivated, 1);
    expect((await api.searchSecurities(query: '2330')).single.isActive, isTrue);
    await api.close();
  });

  test('HTTP provider 解析台股中文名稱與 NASDAQ 文字目錄', () async {
    expect(
      HttpStockCatalogProvider.nasdaqListedUri.host,
      'www.nasdaqtrader.com',
    );
    expect(
      HttpStockCatalogProvider.nasdaqListedUri.path,
      '/dynamic/symdir/nasdaqlisted.txt',
    );
    expect(
      HttpStockCatalogProvider.nasdaqOtherUri.path,
      '/dynamic/symdir/otherlisted.txt',
    );
    final payloads = <Uri, String>{
      HttpStockCatalogProvider.twseUri: '[{"公司代號":"2330","公司簡稱":"台積電"}]',
      HttpStockCatalogProvider.tpexUri:
          '[{"SecuritiesCompanyCode":"6488","CompanyAbbreviation":"環球晶"}]',
      HttpStockCatalogProvider.nasdaqListedUri: 'Symbol|Security Name|Market Category|Test Issue\nAAPL|Apple Inc.|Q|N\nTEST|Test|Q|Y\nFile Creation Time: x',
      HttpStockCatalogProvider.nasdaqOtherUri: 'ACT Symbol|Security Name|Exchange|CQS Symbol|ETF|Round Lot Size|Test Issue|NASDAQ Symbol\nBRK.B|Berkshire|N|BRK.B|N|100|N|BRK.B\nFile Creation Time: x',
    };
    final provider = HttpStockCatalogProvider(
      fetchText: (uri) async => payloads[uri]!,
    );

    final twse = await provider.fetch(StockCatalogSource.twse);
    final tpex = await provider.fetch(StockCatalogSource.tpex);
    final nasdaq = await provider.fetch(StockCatalogSource.nasdaqListed);
    final other = await provider.fetch(StockCatalogSource.nasdaqOther);

    expect(twse.single.name, '台積電');
    expect(twse.single.quoteSymbol, '2330.TW');
    expect(tpex.single.quoteSymbol, '6488.TWO');
    expect(nasdaq.map((entry) => entry.symbol), ['AAPL']);
    expect(other.single.symbol, 'BRK.B');
  });
}
