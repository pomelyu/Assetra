import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../../l10n/generated/app_localizations.dart';

enum AccountFlowFilter { all, incoming, outgoing }

class AccountDetailView extends StatefulWidget {
  final PortfolioDataApi api;
  final String accountId;
  final Future<void> Function() onAddTransaction;
  final Future<void> Function(String transactionId) onEditTransaction;
  final Future<void> Function()? onEditAccount;

  const AccountDetailView({
    super.key,
    required this.api,
    required this.accountId,
    required this.onAddTransaction,
    required this.onEditTransaction,
    this.onEditAccount,
  });

  @override
  State<AccountDetailView> createState() => _AccountDetailViewState();
}

class _AccountDetailViewState extends State<AccountDetailView> {
  late Future<
    ({
      AccountDetail detail,
      List<AccountTransactionItem> items,
      Map<String, bool?> transactionIncoming,
    })
  >
  _data;
  AccountFlowFilter _flowFilter = AccountFlowFilter.all;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<
    ({
      AccountDetail detail,
      List<AccountTransactionItem> items,
      Map<String, bool?> transactionIncoming,
    })
  >
  _load() async {
    final detail = await widget.api.getAccountDetail(widget.accountId);
    final items = (await widget.api.listAccountTransactions(widget.accountId))
        .items;
    final transactionIncoming = <String, bool?>{};
    for (final item in items) {
      final form = await widget.api.getAccountTransactionForm(
        transactionId: item.id,
        accountId: widget.accountId,
      );
      final existing = form.existing;
      if (existing != null) {
        transactionIncoming[item.id] = _isIncomingForAccount(
          existing,
          widget.accountId,
        );
      }
    }
    return (
      detail: detail,
      items: items,
      transactionIncoming: transactionIncoming,
    );
  }

  void _refresh() => setState(() {
    _data = _load();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child:
          FutureBuilder<
            ({
              AccountDetail detail,
              List<AccountTransactionItem> items,
              Map<String, bool?> transactionIncoming,
            })
          >(
            future: _data,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              final localizations = AppLocalizations.of(context)!;
              final detail = data.detail;
              final filteredItems = data.items
                  .where(
                    (item) => _matchesFilter(data.transactionIncoming[item.id]),
                  )
                  .toList();
              final rate = detail.cost.units == 0
                  ? null
                  : detail.unrealizedPnl.units / detail.cost.units * 100;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('資產'),
                      ),
                      Expanded(
                        child: Text(
                          detail.name,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onEditAccount,
                        icon: const Icon(Icons.edit_outlined),
                        color: const Color(0xff64748B),
                        tooltip: '編輯帳戶',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _accountTypeBadge(detail.accountType),
                              Flexible(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Flexible(
                                      child: _metric(
                                        '帳戶成本',
                                        _money(
                                          detail.cost.units,
                                          detail.currencyCode,
                                        ),
                                        const Color(0xff475569),
                                        alignEnd: true,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: _metric(
                                        '已實現損益',
                                        _signedMoney(
                                          detail.realizedPnl.units,
                                          detail.currencyCode,
                                        ),
                                        detail.realizedPnl.units >= 0
                                            ? const Color(0xff00A86B)
                                            : const Color(0xffF43F5E),
                                        alignEnd: true,
                                        valueKey: const Key(
                                          'account-realized-pnl',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '帳戶現值',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: const Color(0xff94A3B8)),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              detail.value == null
                                  ? '尚無報價'
                                  : _money(
                                      detail.value!.units,
                                      detail.currencyCode,
                                    ),
                              maxLines: 1,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xffE8FAF2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    '未實現損益',
                                    style: TextStyle(
                                      color: Color(0xff64748B),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      key: const Key('account-unrealized-pnl'),
                                      '${detail.unrealizedPnl.units >= 0 ? '↑ ' : '↓ '}${_signedMoney(detail.unrealizedPnl.units, detail.currencyCode)}${rate == null ? '' : ' (${rate.toStringAsFixed(1)}%)'}',
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: detail.unrealizedPnl.units >= 0
                                            ? const Color(0xff008A5C)
                                            : const Color(0xffF43F5E),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '交易紀錄',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '共 ${filteredItems.length} 筆',
                        style: const TextStyle(color: Color(0xff94A3B8)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xffE8EDF4),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children:
                          <({AccountFlowFilter filter, String label})>[
                                (
                                  filter: AccountFlowFilter.all,
                                  label: localizations.allTransactions,
                                ),
                                (
                                  filter: AccountFlowFilter.incoming,
                                  label: localizations.incomingTransactions,
                                ),
                                (
                                  filter: AccountFlowFilter.outgoing,
                                  label: localizations.outgoingTransactions,
                                ),
                              ]
                              .map(
                                (option) => Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(
                                      () => _flowFilter = option.filter,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _flowFilter == option.filter
                                            ? Colors.white
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        option.label,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontWeight:
                                              _flowFilter == option.filter
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
                  const SizedBox(height: 12),
                  if (filteredItems.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: 8,
                        left: 4,
                        right: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${filteredItems.first.occurredAt.substring(0, 4)} 年',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '共 ${filteredItems.length} 筆明細',
                            style: const TextStyle(color: Color(0xff94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  if (filteredItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('尚未建立資料')),
                    ),
                  if (filteredItems.isNotEmpty)
                    Card(
                      child: Column(
                        children: filteredItems.map(_transactionTile).toList(),
                      ),
                    ),
                ],
              );
            },
          ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () async {
        await widget.onAddTransaction();
        _refresh();
      },
      child: const Icon(Icons.add),
    ),
  );

  String _kindText(TransactionKind kind) => switch (kind) {
    TransactionKind.accountIncome => '收入',
    TransactionKind.accountExpense => '支出',
    TransactionKind.accountTransfer => '轉帳',
    TransactionKind.investmentBuy => '投資買入',
    TransactionKind.investmentSell => '投資賣出',
    TransactionKind.investmentInterest => '利息',
    TransactionKind.investmentPnlAdjustment => '損益調整',
    _ => '交易',
  };

  bool _matchesFilter(bool? isIncoming) {
    return switch (_flowFilter) {
      AccountFlowFilter.all => true,
      AccountFlowFilter.incoming => isIncoming == true,
      AccountFlowFilter.outgoing => isIncoming == false,
    };
  }

  bool? _isIncomingForAccount(AccountTransactionInput input, String accountId) {
    if (input is AccountIncomeInput) return true;
    if (input is AccountExpenseInput) return false;
    if (input is AccountTransferInput) {
      return input.targetAccountId == accountId;
    }
    if (input is InvestmentBuyInput) {
      return input.investmentAccountId == accountId;
    }
    if (input is InvestmentSellInput) {
      return input.targetAccountId == accountId;
    }
    if (input is InvestmentInterestInput) {
      return input.investmentAccountId == accountId ? null : true;
    }
    if (input is InvestmentPnlAdjustmentInput) {
      return input.valueAdjustment.units > 0;
    }
    return false;
  }

  Widget _transactionTile(
    AccountTransactionItem item,
  ) => FutureBuilder<({String? amount, IconData icon, Color color})>(
    future: _transactionPresentation(item),
    builder: (context, snapshot) {
      final presentation = snapshot.data;
      final amount = presentation?.amount;
      final positive = amount == null || !amount.startsWith('-');
      return InkWell(
        onTap: () async {
          await widget.onEditTransaction(item.id);
          _refresh();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: (presentation?.color ?? _kindColor(item.kind))
                    .withValues(alpha: 0.12),
                child: Icon(
                  presentation?.icon ?? _kindIcon(item.kind),
                  color: presentation?.color ?? _kindColor(item.kind),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                item.occurredAt.substring(5, 10).replaceAll('-', '.'),
                style: const TextStyle(
                  color: Color(0xff94A3B8),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.note?.isNotEmpty == true
                      ? item.note!
                      : _kindText(item.kind),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              if (amount != null)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      amount,
                      maxLines: 1,
                      style: TextStyle(
                        color: positive
                            ? const Color(0xff00A86B)
                            : const Color(0xff1E293B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xffCBD5E1)),
            ],
          ),
        ),
      );
    },
  );

  Future<({String? amount, IconData icon, Color color})>
  _transactionPresentation(AccountTransactionItem item) async {
    final input = (await widget.api.getAccountTransactionForm(
      transactionId: item.id,
      accountId: widget.accountId,
    )).existing;
    if (input is AccountIncomeInput) {
      return (
        amount:
            '+${_formatUnits(input.targetAmount.units, input.targetAmount.currencyCode)}',
        icon: Icons.arrow_forward_rounded,
        color: const Color(0xff00A86B),
      );
    }
    if (input is AccountExpenseInput) {
      return (
        amount:
            '-${_formatUnits(input.sourceAmount.units, input.sourceAmount.currencyCode)}',
        icon: Icons.arrow_back_rounded,
        color: const Color(0xffF43F5E),
      );
    }
    if (input is AccountTransferInput) {
      final incoming = input.targetAccountId == widget.accountId;
      final money = incoming ? input.targetAmount : input.sourceAmount;
      return (
        amount:
            '${incoming ? '+' : '-'}${_formatUnits(money.units, money.currencyCode)}',
        icon: incoming ? Icons.south_east_rounded : Icons.north_west_rounded,
        color: const Color(0xff0EA5E9),
      );
    }
    if (input is InvestmentBuyInput) {
      final isInvestment = input.investmentAccountId == widget.accountId;
      final value = isInvestment
          ? input.amount.units
          : -(input.amount.units + input.fee.units);
      return (
        amount: _signedMoney(value, input.amount.currencyCode),
        icon: Icons.add_chart_rounded,
        color: value >= 0 ? const Color(0xff00A86B) : const Color(0xffF43F5E),
      );
    }
    if (input is InvestmentSellInput) {
      final isInvestment = input.investmentAccountId == widget.accountId;
      final value = isInvestment
          ? -input.amount.units
          : input.amount.units - input.fee.units;
      return (
        amount: _signedMoney(value, input.amount.currencyCode),
        icon: Icons.currency_exchange_rounded,
        color: value >= 0 ? const Color(0xff00A86B) : const Color(0xffF43F5E),
      );
    }
    if (input is InvestmentInterestInput) {
      return (
        amount: _signedMoney(input.amount.units, input.amount.currencyCode),
        icon: Icons.savings_outlined,
        color: const Color(0xff00A86B),
      );
    }
    if (input is InvestmentPnlAdjustmentInput) {
      return (
        amount: _signedMoney(
          input.valueAdjustment.units,
          input.valueAdjustment.currencyCode,
        ),
        icon: Icons.tune_rounded,
        color: input.valueAdjustment.units >= 0
            ? const Color(0xff00A86B)
            : const Color(0xffF43F5E),
      );
    }
    return (
      amount: null,
      icon: _kindIcon(item.kind),
      color: _kindColor(item.kind),
    );
  }

  String _formatUnits(num value, String currency) => _money(value, currency);

  String _money(num value, String currency) {
    final digits = currency == 'TWD' || currency == 'JPY' ? 0 : 2;
    final fixed = value.toStringAsFixed(digits);
    final parts = fixed.split('.');
    final integer = parts.first.replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final formatted = digits == 0 ? integer : '$integer.${parts.last}';
    return '${currency == 'TWD' ? 'NT\$' : '$currency '}$formatted';
  }

  String _signedMoney(num value, String currency) =>
      '${value >= 0 ? '+' : '-'}${_money(value.abs(), currency)}';

  Widget _accountTypeBadge(AccountType type) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xffE8FAF2),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      type == AccountType.investment ? '●  投資帳戶' : '●  一般帳戶',
      style: const TextStyle(
        color: Color(0xff05875A),
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _metric(
    String label,
    String value,
    Color color, {
    bool alignEnd = false,
    Key? valueKey,
  }) => Column(
    crossAxisAlignment: alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(color: Color(0xff94A3B8)),
        ),
      ),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          key: valueKey,
          value,
          maxLines: 1,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
  IconData _kindIcon(TransactionKind kind) => switch (kind) {
    TransactionKind.accountIncome ||
    TransactionKind.investmentInterest => Icons.arrow_forward_rounded,
    TransactionKind.accountExpense ||
    TransactionKind.investmentSell => Icons.arrow_back_rounded,
    TransactionKind.investmentBuy => Icons.add_chart_rounded,
    TransactionKind.investmentPnlAdjustment => Icons.tune_rounded,
    _ => Icons.south_east_rounded,
  };
  Color _kindColor(TransactionKind kind) => switch (kind) {
    TransactionKind.accountIncome ||
    TransactionKind.investmentInterest => const Color(0xff00A86B),
    TransactionKind.accountExpense ||
    TransactionKind.investmentSell => const Color(0xffF43F5E),
    _ => const Color(0xff0EA5E9),
  };
}
