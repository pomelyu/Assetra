import 'package:flutter/material.dart';

import '../../data/data.dart';
import 'stock_detail_view.dart';
import 'stock_transaction_view.dart';

class StockView extends StatefulWidget {
  final String title;
  final PortfolioDataApi? api;
  final VoidCallback? onOpenSettings;

  const StockView({
    super.key,
    required this.title,
    this.api,
    this.onOpenSettings,
  });

  @override
  State<StockView> createState() => _StockViewState();
}

class _StockViewState extends State<StockView> {
  late Future<({StockOverview overview, List<AccountDetail> accounts})> _data;
  String? _marketCode, _stockAccountId;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<({StockOverview overview, List<AccountDetail> accounts})>
  _load() async {
    final api = widget.api;
    if (api == null) {
      return (
        overview: const StockOverview(
          positions: [],
          totalCost: null,
          totalValue: null,
          isValuationComplete: false,
        ),
        accounts: <AccountDetail>[],
      );
    }
    return (
      overview: await api.getStockOverview(
        marketCode: _marketCode,
        stockAccountId: _stockAccountId,
      ),
      accounts: (await api.listManagedAccounts(
        status: AccountStatus.active,
        accountType: AccountType.stock,
      )).map((item) => item.detail).toList(),
    );
  }

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  Future<void> _refresh() async {
    final api = widget.api;
    if (api == null || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      final result = await api.refreshMarketData();
      if (mounted) {
        final parts = <String>['更新 ${result.quoteSuccesses} 檔股票'];
        if (result.quoteFailures.isNotEmpty) {
          parts.add('${result.quoteFailures.length} 檔股票失敗');
        }
        if (result.rateSuccesses > 0) parts.add('匯率已更新');
        if (result.rateFailures.isNotEmpty) parts.add('匯率更新失敗');
        if (result.failures.isNotEmpty) parts.add('保留最後行情');
        final message = parts.join('；');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      _reload();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('更新失敗，已保留最後行情：$error')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openTransaction({
    String? securityId,
    String? transactionId,
    String? stockAccountId,
  }) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => StockTransactionView(
          api: widget.api,
          securityId: securityId,
          transactionId: transactionId,
          stockAccountId: stockAccountId,
          onOpenSettings: widget.onOpenSettings,
        ),
      ),
    );
    _reload();
  }

  Future<void> _openDetail(String securityId) async {
    final api = widget.api;
    if (api == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => StockDetailView(
          api: api,
          securityId: securityId,
          onAddTransaction: (stockAccountId) => _openTransaction(
            securityId: securityId,
            stockAccountId: stockAccountId,
          ),
          onEditTransaction: (id) =>
              _openTransaction(securityId: securityId, transactionId: id),
        ),
      ),
    );
    _reload();
  }

  String _money(Money? money) => money == null
      ? '—'
      : '${money.currencyCode} ${money.units.toStringAsFixed(2)}';

  String _amount(Money? money) =>
      money == null ? '—' : money.units.toStringAsFixed(2);

  double? _returnRate(StockPositionSummary position) =>
      position.unrealizedPnl == null || position.cost.units == 0
      ? null
      : position.unrealizedPnl!.units / position.cost.units * 100;

  Color _profitColor(Money? money) => money != null && money.units < 0
      ? const Color(0xffEF4444)
      : const Color(0xff00A972);

  String _signed(Money? money) {
    if (money == null) return '—';
    final prefix = money.units > 0 ? '+' : '';
    return '$prefix${money.units.toStringAsFixed(2)}';
  }

  Widget _summaryValueRow(String label, String value, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xff94A3B8), fontSize: 11),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      key: key,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: const Color(0xff059669),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xff475569),
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide.none,
      shape: const StadiumBorder(),
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: FutureBuilder<({StockOverview overview, List<AccountDetail> accounts})>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: FilledButton(
              onPressed: _reload,
              child: Text('載入失敗，點此重試\n${snapshot.error}'),
            ),
          );
        }
        final data = snapshot.data!;
        final overview = data.overview;
        final active = overview.positions
            .where((position) => position.quantityUnits > 0)
            .toList();
        final closed = overview.positions
            .where((position) => position.quantityUnits == 0)
            .toList();
        final totalPnl =
            overview.totalCost == null || overview.totalValue == null
            ? null
            : Money(
                currencyCode: overview.totalValue!.currencyCode,
                units: overview.totalValue!.units - overview.totalCost!.units,
              );
        final totalRate = totalPnl == null || overview.totalCost!.units == 0
            ? null
            : totalPnl.units / overview.totalCost!.units * 100;
        final updatedAt = overview.lastQuoteRetrievedAt?.toLocal();
        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (updatedAt != null)
                      Text(
                        '最後更新 ${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Color(0xff9AA5B7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    IconButton(
                      key: const Key('stock-refresh-market-data'),
                      onPressed: _refreshing ? null : _refresh,
                      icon: _refreshing
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '總現值',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: const Color(0xff94A3B8)),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _money(overview.totalValue),
                                  maxLines: 1,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(
                                        fontSize: 38,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.8,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _summaryValueRow(
                                '總成本',
                                _amount(overview.totalCost),
                                const Color(0xff475569),
                              ),
                              const SizedBox(height: 3),
                              _summaryValueRow(
                                '總收益',
                                _signed(totalPnl),
                                _profitColor(totalPnl),
                              ),
                              const SizedBox(height: 3),
                              _summaryValueRow(
                                '收益率',
                                totalRate == null
                                    ? '—'
                                    : '${totalRate >= 0 ? '+' : ''}${totalRate.toStringAsFixed(1)}%',
                                _profitColor(totalPnl),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!overview.isValuationComplete)
                  const Padding(
                    padding: EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      '估值未齊全',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip(
                        label: '全部',
                        selected: _marketCode == null,
                        onTap: () {
                          _marketCode = null;
                          _reload();
                        },
                      ),
                      _filterChip(
                        label: '台股',
                        selected: _marketCode == 'TW',
                        onTap: () {
                          _marketCode = 'TW';
                          _reload();
                        },
                      ),
                      _filterChip(
                        label: '美股',
                        selected: _marketCode == 'US',
                        onTap: () {
                          _marketCode = 'US';
                          _reload();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (overview.positions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('尚未建立資料')),
                  ),
                if (active.isNotEmpty)
                  Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(14, 10, 14, 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                '名稱 / 代號',
                                style: TextStyle(
                                  color: Color(0xff94A3B8),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '成本 / 現值',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: Color(0xff94A3B8),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '收益 / 率',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: Color(0xff94A3B8),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: active.indexed.expand((entry) {
                            final index = entry.$1;
                            final position = entry.$2;
                            final rate = _returnRate(position);
                            return [
                              if (index > 0) const Divider(height: 1),
                              InkWell(
                                onTap: () => _openDetail(position.securityId),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 4,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              position.marketCode == 'TW'
                                                  ? position.name
                                                  : position.symbol,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            Text(
                                              '${position.symbol} · ${position.marketCode == 'TW' ? '台股' : '美股'}',
                                              style: const TextStyle(
                                                color: Color(0xff94A3B8),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              _amount(position.cost),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _amount(position.value),
                                              style: const TextStyle(
                                                color: Color(0xff94A3B8),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Flexible(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    _signed(
                                                      position.unrealizedPnl,
                                                    ),
                                                    style: TextStyle(
                                                      color: _profitColor(
                                                        position.unrealizedPnl,
                                                      ),
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    rate == null
                                                        ? '—'
                                                        : '${rate >= 0 ? '+' : ''}${rate.toStringAsFixed(1)}%',
                                                    style: TextStyle(
                                                      color: _profitColor(
                                                        position.unrealizedPnl,
                                                      ),
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                              Icons.chevron_right_rounded,
                                              size: 18,
                                              color: Color(0xffCBD5E1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ];
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                if (closed.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Card(
                      child: ExpansionTile(
                        key: const Key('stock-closed-positions'),
                        shape: const Border(),
                        title: Text(
                          '已結清持股 (${closed.length})',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        initiallyExpanded: false,
                        children: closed
                            .map(
                              (position) => ListTile(
                                title: Text(
                                  position.marketCode == 'TW'
                                      ? position.name
                                      : position.symbol,
                                ),
                                subtitle: Text(
                                  '已實現 ${_money(position.realizedPnl)} · 股息 ${_money(position.dividendIncome)}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _openDetail(position.securityId),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
              ],
            ),
            Positioned(
              right: 20,
              bottom: 20,
              child: FloatingActionButton(
                key: const Key('stock-add-transaction'),
                onPressed: _openTransaction,
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
    ),
  );
}
