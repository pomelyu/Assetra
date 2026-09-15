import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/data.dart';

class AssetView extends StatefulWidget {
  final String title;
  final PortfolioDataApi? api;
  final Future<void> Function() onAddTransaction;
  final Future<void> Function(String accountId)? onOpenAccount;

  const AssetView({
    super.key,
    required this.title,
    this.api,
    required this.onAddTransaction,
    this.onOpenAccount,
  });

  @override
  State<AssetView> createState() => _AssetViewState();
}

class _AssetViewState extends State<AssetView> {
  late Future<
    ({List<AccountSummary> accounts, List<CategorySummary> categories})
  >
  _data;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<({List<AccountSummary> accounts, List<CategorySummary> categories})>
  _load() async {
    final api = widget.api;
    if (api == null) {
      return (accounts: <AccountSummary>[], categories: <CategorySummary>[]);
    }
    final accounts = (await api.listAssetAccounts(categoryId: _categoryId))
        .items
        .where((a) => a.detail.accountType == AccountType.general)
        .toList();
    return (accounts: accounts, categories: await api.listCategories());
  }

  void _selectCategory(String? id) {
    setState(() {
      _categoryId = id;
      _data = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child:
                FutureBuilder<
                  ({
                    List<AccountSummary> accounts,
                    List<CategorySummary> categories,
                  })
                >(
                  future: _data,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _pageHeader(context),
                          const Expanded(
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ],
                      );
                    }
                    final data = snapshot.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _pageHeader(context),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '總現值',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                  color: const Color(
                                                    0xff94A3B8,
                                                  ),
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              _summary(data.accounts),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          _summaryValueRow(
                                            '總成本',
                                            _summaryTotalCost(data.accounts),
                                            const Color(0xff475569),
                                          ),
                                          const SizedBox(height: 3),
                                          _summaryValueRow(
                                            '總收益',
                                            _signed(_totalPnl(data.accounts)),
                                            _totalPnl(data.accounts) >= 0
                                                ? const Color(0xff00A86B)
                                                : const Color(0xffF43F5E),
                                          ),
                                          const SizedBox(height: 3),
                                          _summaryValueRow(
                                            '收益率',
                                            _totalRate(data.accounts)
                                                .replaceFirst('收益率 ', ''),
                                            _totalPnl(data.accounts) >= 0
                                                ? const Color(0xff00A86B)
                                                : const Color(0xffF43F5E),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 40,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              ChoiceChip(
                                label: const Text('全部'),
                                selected: _categoryId == null,
                                showCheckmark: false,
                                selectedColor: const Color(0xff059669),
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                labelStyle: TextStyle(
                                  color: _categoryId == null
                                      ? Colors.white
                                      : const Color(0xff475569),
                                  fontWeight: FontWeight.w700,
                                ),
                                onSelected: (_) => _selectCategory(null),
                              ),
                              ...data.categories.map(
                                (c) => Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: ChoiceChip(
                                    label: Text(c.name),
                                    selected: _categoryId == c.id,
                                    showCheckmark: false,
                                    selectedColor: const Color(0xff059669),
                                    shape: const StadiumBorder(),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    labelStyle: TextStyle(
                                      color: _categoryId == c.id
                                          ? Colors.white
                                          : const Color(0xff475569),
                                      fontWeight: FontWeight.w700,
                                    ),
                                    onSelected: (_) => _selectCategory(c.id),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: data.accounts.isEmpty
                              ? const Center(child: Text('尚未建立資料'))
                              : Column(
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        14,
                                        10,
                                        14,
                                        8,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 4,
                                            child: Text(
                                              '名稱',
                                              style: TextStyle(
                                                color: Color(0xff94A3B8),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 4,
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
                                    Expanded(
                                      child: Card(
                                        child: ListView.separated(
                                          padding: const EdgeInsets.only(
                                            bottom: 92,
                                          ),
                                          itemCount: data.accounts.length,
                                          separatorBuilder: (_, _) =>
                                              const Divider(height: 1),
                                          itemBuilder: (context, index) =>
                                              _accountRow(
                                                data.accounts[index].detail,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    );
                  },
                ),
          ),
          Positioned(
            right: 20,
            bottom: 24,
            child: FloatingActionButton(
              key: const Key('asset-add-transaction'),
              onPressed: () async {
                await widget.onAddTransaction();
                setState(() {
                  _data = _load();
                });
              },
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  String _summary(List<AccountSummary> accounts) {
    if (accounts.isEmpty) return '0 個帳戶';
    final currencies = accounts
        .map((account) => account.detail.currencyCode)
        .toSet();
    return currencies.length == 1
        ? _money(
            accounts.fold<num>(
              0,
              (sum, account) => sum + (account.detail.value?.units ?? 0),
            ),
            currencies.single,
          )
        : '${accounts.length} 個帳戶';
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

  Widget _accountRow(AccountDetail detail) {
    final value = detail.value?.units;
    final rate = detail.cost.units == 0
        ? null
        : detail.unrealizedPnl.units / detail.cost.units * 100;
    final pnlColor = detail.unrealizedPnl.units > 0
        ? const Color(0xff00A86B)
        : detail.unrealizedPnl.units < 0
        ? const Color(0xffF43F5E)
        : const Color(0xff64748B);
    return InkWell(
      onTap: widget.onOpenAccount == null
          ? null
          : () async {
              await widget.onOpenAccount!(detail.id);
              setState(() {
                _data = _load();
              });
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                detail.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _money(detail.cost.units, detail.currencyCode),
                      maxLines: 1,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      value == null
                          ? '尚無報價'
                          : _money(value, detail.currencyCode),
                      maxLines: 1,
                      style: const TextStyle(color: Color(0xff94A3B8)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          _signed(detail.unrealizedPnl.units),
                          maxLines: 1,
                          style: TextStyle(
                            color: pnlColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rate == null
                            ? '—'
                            : '${rate >= 0 ? '+' : ''}${rate.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: pnlColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
    );
  }

  num _totalCost(List<AccountSummary> accounts) =>
      accounts.fold<num>(0, (sum, item) => sum + item.detail.cost.units);
  String _summaryTotalCost(List<AccountSummary> accounts) {
    final currencies = accounts.map((item) => item.detail.currencyCode).toSet();
    return currencies.length == 1
        ? _money(_totalCost(accounts), currencies.single)
        : '—';
  }

  num _totalPnl(List<AccountSummary> accounts) => accounts.fold<num>(
    0,
    (sum, item) => sum + item.detail.unrealizedPnl.units,
  );
  String _totalRate(List<AccountSummary> accounts) => _totalCost(accounts) == 0
      ? '收益率 —'
      : '收益率 ${_totalPnl(accounts) >= 0 ? '+' : ''}${(_totalPnl(accounts) / _totalCost(accounts) * 100).toStringAsFixed(1)}%';
  String _money(num units, String currency) {
    final pattern = currency == 'TWD' || currency == 'JPY'
        ? '#,##0'
        : '#,##0.##';
    return '${currency == 'TWD' ? 'NT\$' : '$currency '}${NumberFormat(pattern, 'en_US').format(units)}';
  }

  String _signed(num value) =>
      '${value > 0 ? '+' : ''}${NumberFormat('#,##0.##', 'en_US').format(value)}';

  Widget _pageHeader(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          widget.title,
          style: Theme.of(context).textTheme.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      const Text('最後更新', style: TextStyle(color: Color(0xff94A3B8))),
      IconButton(
        onPressed: () => setState(() {
          _data = _load();
        }),
        icon: const Icon(Icons.refresh_rounded, color: Color(0xff64748B)),
      ),
    ],
  );
}
