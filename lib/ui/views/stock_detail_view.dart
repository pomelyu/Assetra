import 'package:flutter/material.dart';

import '../../data/data.dart';

class StockDetailView extends StatefulWidget {
  final PortfolioDataApi api;
  final String securityId;
  final Future<void> Function(String? stockAccountId)? onAddTransaction;
  final Future<void> Function(String transactionId)? onEditTransaction;

  const StockDetailView({
    super.key,
    required this.api,
    required this.securityId,
    this.onAddTransaction,
    this.onEditTransaction,
  });

  @override
  State<StockDetailView> createState() => _StockDetailViewState();
}

class _StockDetailViewState extends State<StockDetailView> {
  late Future<
    ({
      StockDetail detail,
      List<AccountTransactionItem> items,
      List<AccountDetail> accounts,
    })
  >
  _data;
  TransactionKind? _kind;
  String? _stockAccountId;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<
    ({
      StockDetail detail,
      List<AccountTransactionItem> items,
      List<AccountDetail> accounts,
    })
  >
  _load() async => (
    detail: await widget.api.getStockDetail(
      widget.securityId,
      stockAccountId: _stockAccountId,
    ),
    items: (await widget.api.listStockTransactions(
      widget.securityId,
      stockAccountId: _stockAccountId,
      kinds: _kind == null ? null : {_kind!},
    )).items,
    accounts: (await widget.api.listManagedAccounts(
      accountType: AccountType.stock,
    )).map((item) => item.detail).toList(),
  );

  void _reload() {
    setState(() {
      _data = _load();
    });
  }

  String _money(Money? money) => money == null
      ? '尚無報價'
      : '${money.currencyCode} ${money.units.toStringAsFixed(2)}';

  Color _kindColor(TransactionKind kind) => switch (kind) {
    TransactionKind.stockBuy => const Color(0xff00A972),
    TransactionKind.stockSell => const Color(0xffEF4444),
    TransactionKind.stockDividend => const Color(0xffF59E0B),
    _ => const Color(0xff64748B),
  };

  IconData _kindIcon(TransactionKind kind) => switch (kind) {
    TransactionKind.stockBuy => Icons.south_east,
    TransactionKind.stockSell => Icons.north_west,
    TransactionKind.stockDividend => Icons.paid_outlined,
    _ => Icons.receipt_long_outlined,
  };

  Widget _pill({
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
      side: BorderSide.none,
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xff475569),
        fontWeight: FontWeight.w700,
      ),
    ),
  );

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
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child:
          FutureBuilder<
            ({
              StockDetail detail,
              List<AccountTransactionItem> items,
              List<AccountDetail> accounts,
            })
          >(
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
              final detail = data.detail;
              final rate =
                  detail.unrealizedPnl == null || detail.cost.units == 0
                  ? null
                  : detail.unrealizedPnl!.units / detail.cost.units * 100;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.chevron_left_rounded),
                          label: const Text('股票'),
                        ),
                        Expanded(
                          child: Text(
                            '${detail.marketCode == 'TW' ? detail.name : detail.symbol} ${detail.symbol}',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 72),
                      ],
                    ),
                    const SizedBox(height: 8),
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
                                    '持股總現值',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: const Color(0xff94A3B8),
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _money(detail.value),
                                      maxLines: 1,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineLarge
                                          ?.copyWith(
                                            fontSize: 34,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.8,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '持有 ${detail.quantityUnits} 股',
                                    style: const TextStyle(
                                      color: Color(0xff64748B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
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
                                    '成本',
                                    _money(detail.cost),
                                    const Color(0xff475569),
                                  ),
                                  const SizedBox(height: 3),
                                  _summaryValueRow(
                                    '未實現',
                                    detail.unrealizedPnl == null
                                        ? '—'
                                        : '${detail.unrealizedPnl!.units >= 0 ? '+' : ''}${detail.unrealizedPnl!.units.toStringAsFixed(2)}${rate == null ? '' : ' (${rate.toStringAsFixed(1)}%)'}',
                                    detail.unrealizedPnl != null &&
                                            detail.unrealizedPnl!.units < 0
                                        ? const Color(0xffF43F5E)
                                        : const Color(0xff00A86B),
                                  ),
                                  const SizedBox(height: 3),
                                  _summaryValueRow(
                                    '已實現',
                                    _money(detail.realizedPnl),
                                    const Color(0xff00A86B),
                                  ),
                                  const SizedBox(height: 3),
                                  _summaryValueRow(
                                    '配息',
                                    _money(detail.dividendIncome),
                                    const Color(0xff00A86B),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              key: const Key('stock-detail-account-filter'),
                              children: [
                                _pill(
                                  label: '全部',
                                  selected: _stockAccountId == null,
                                  onTap: () {
                                    _stockAccountId = null;
                                    _reload();
                                  },
                                ),
                                ...data.accounts.map(
                                  (account) => _pill(
                                    label:
                                        '${account.name}${account.isArchived ? '（已封存）' : ''}',
                                    selected: _stockAccountId == account.id,
                                    onTap: () {
                                      _stockAccountId = account.id;
                                      _reload();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      key: const Key('stock-detail-kind-filter'),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xffE8EDF4),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children:
                            <({TransactionKind? kind, String label})>[
                                  (kind: null, label: '全部'),
                                  (kind: TransactionKind.stockBuy, label: '買入'),
                                  (
                                    kind: TransactionKind.stockSell,
                                    label: '賣出',
                                  ),
                                  (
                                    kind: TransactionKind.stockDividend,
                                    label: '股息',
                                  ),
                                ]
                                .map(
                                  (option) => Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        _kind = option.kind;
                                        _reload();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _kind == option.kind
                                              ? Colors.white
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Text(
                                          option.label,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontWeight: _kind == option.kind
                                                ? FontWeight.w800
                                                : FontWeight.w500,
                                            color: const Color(0xff475569),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '交易紀錄',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '共 ${data.items.length} 筆明細',
                          style: const TextStyle(color: Color(0xff9AA5B7)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (data.items.isEmpty)
                      const Expanded(child: Center(child: Text('尚未建立資料'))),
                    if (data.items.isNotEmpty)
                      Expanded(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListView.separated(
                            padding: const EdgeInsets.only(bottom: 72),
                            itemCount: data.items.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = data.items[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: _kindColor(item.kind)
                                      .withValues(alpha: 0.12),
                                  foregroundColor: _kindColor(item.kind),
                                  child: Icon(_kindIcon(item.kind), size: 20),
                                ),
                                title: Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  '${item.occurredAt.substring(0, 10)} · ${_kindLabel(item.kind)}${item.isReadOnly ? ' · 已封存，只可瀏覽' : ''}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap:
                                    widget.onEditTransaction == null ||
                                        item.isReadOnly
                                    ? null
                                    : () async {
                                        await widget.onEditTransaction!(
                                          item.id,
                                        );
                                        _reload();
                                      },
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
    ),
    floatingActionButton: widget.onAddTransaction == null
        ? null
        : FloatingActionButton(
            key: const Key('stock-detail-add-transaction'),
            onPressed: () async {
              await widget.onAddTransaction!(_stockAccountId);
              _reload();
            },
            child: const Icon(Icons.add),
          ),
  );

  String _kindLabel(TransactionKind kind) => switch (kind) {
    TransactionKind.stockBuy => '投資買入',
    TransactionKind.stockSell => '投資賣出',
    TransactionKind.stockDividend => '股息',
    _ => '',
  };
}
