import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/data.dart';

enum AccountTransactionFormKind { income, expense, transfer }

class AccountTransactionView extends StatefulWidget {
  final PortfolioDataApi? api;
  final String? transactionId;
  final String? accountId;

  const AccountTransactionView({
    super.key,
    this.api,
    this.transactionId,
    this.accountId,
  });

  @override
  State<AccountTransactionView> createState() => _AccountTransactionViewState();
}

class _AccountTransactionViewState extends State<AccountTransactionView> {
  static final TextInputFormatter _amountInputFormatter =
      TextInputFormatter.withFunction((oldValue, newValue) {
        return RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text)
            ? newValue
            : oldValue;
      });

  AccountTransactionFormKind _kind = AccountTransactionFormKind.income;
  String? _source, _target;
  final _amount = TextEditingController();
  final _targetAmount = TextEditingController();
  final _note = TextEditingController();
  late final TextEditingController _occurredAt = TextEditingController(
    text: _nowText(),
  );
  bool _saving = false;
  bool _initialized = false;
  List<AccountDetail>? _availableAccounts;

  @override
  void dispose() {
    _amount.dispose();
    _targetAmount.dispose();
    _note.dispose();
    _occurredAt.dispose();
    super.dispose();
  }

  String _nowText() {
    final d = DateTime.now();
    return _dateTimeText(d);
  }

  String _dateTimeText(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickOccurredAt() async {
    final now = DateTime.now();
    final parsed = DateTime.tryParse(_occurredAt.text.replaceFirst(' ', 'T'));
    final current = parsed == null || parsed.isAfter(now) ? now : parsed;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (selected.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('交易時間不可晚於現在')));
      return;
    }
    setState(() => _occurredAt.text = _dateTimeText(selected));
  }

  Future<void> _save(List<AccountDetail> accounts) async {
    final api = widget.api;
    final amount = double.tryParse(_amount.text);
    final targetAmount = double.tryParse(_targetAmount.text);
    if (api == null ||
        amount == null ||
        amount <= 0 ||
        (_kind == AccountTransactionFormKind.income && _target == null) ||
        (_kind == AccountTransactionFormKind.expense && _source == null) ||
        (_kind == AccountTransactionFormKind.transfer &&
            (_source == null ||
                _target == null ||
                targetAmount == null ||
                targetAmount <= 0))) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請完成帳戶、日期與正數金額')));
      return;
    }
    final byId = {for (final a in accounts) a.id: a};
    try {
      setState(() => _saving = true);
      final input = switch (_kind) {
        AccountTransactionFormKind.income => AccountIncomeInput(
          occurredAt: _occurredAt.text,
          targetAccountId: _target!,
          targetAmount: Money(
            currencyCode: byId[_target]!.currencyCode,
            units: amount,
          ),
          note: _note.text,
        ),
        AccountTransactionFormKind.expense => AccountExpenseInput(
          occurredAt: _occurredAt.text,
          sourceAccountId: _source!,
          sourceAmount: Money(
            currencyCode: byId[_source]!.currencyCode,
            units: amount,
          ),
          note: _note.text,
        ),
        _ => AccountTransferInput(
          occurredAt: _occurredAt.text,
          sourceAccountId: _source!,
          targetAccountId: _target!,
          sourceAmount: Money(
            currencyCode: byId[_source]!.currencyCode,
            units: amount,
          ),
          targetAmount: Money(
            currencyCode: byId[_target]!.currencyCode,
            units: targetAmount!,
          ),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        ),
      };
      if (widget.transactionId == null) {
        await api.createAccountTransaction(input);
      } else {
        await api.updateAccountTransaction(widget.transactionId!, input);
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _initializeForm(
    AccountTransactionInput? input,
    List<AccountDetail> accounts,
  ) {
    if (_initialized) return;
    if (input == null) {
      final accountId = widget.accountId;
      if (accountId != null &&
          accounts.any((account) => account.id == accountId)) {
        _target = accountId;
      }
      _initialized = true;
      return;
    }
    if (input is AccountIncomeInput) {
      _kind = AccountTransactionFormKind.income;
      _target = input.targetAccountId;
      _amount.text = input.targetAmount.units.toString();
    }
    if (input is AccountExpenseInput) {
      _kind = AccountTransactionFormKind.expense;
      _source = input.sourceAccountId;
      _amount.text = input.sourceAmount.units.toString();
    }
    if (input is AccountTransferInput) {
      _kind = AccountTransactionFormKind.transfer;
      _source = input.sourceAccountId;
      _target = input.targetAccountId;
      _amount.text = input.sourceAmount.units.toString();
      _targetAmount.text = input.targetAmount.units.toString();
    }
    _note.text = input.note ?? '';
    _occurredAt.text = input.occurredAt;
    _initialized = true;
  }

  void _changeKind(AccountTransactionFormKind kind) {
    setState(() {
      _kind = kind;
      if (widget.transactionId != null || widget.accountId == null) return;
      switch (kind) {
        case AccountTransactionFormKind.income:
          _source = null;
          _target = widget.accountId;
        case AccountTransactionFormKind.expense:
          _source = widget.accountId;
          _target = null;
        case AccountTransactionFormKind.transfer:
          _source = widget.accountId;
          _target = null;
      }
    });
  }

  Future<void> _delete() async {
    if (widget.api == null || widget.transactionId == null) return;
    try {
      await widget.api!.deleteAccountTransaction(widget.transactionId!);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.api == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('新增交易紀錄')),
        body: const Center(child: Text('尚未建立資料')),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        title: Text(widget.transactionId == null ? '新增交易紀錄' : '編輯交易'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xff0F172A),
        ),
        leadingWidth: 72,
        leading: TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: const Color(0xff64748B),
          ),
          child: const Text('取消'),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    final accounts = _availableAccounts;
                    if (accounts != null) _save(accounts);
                  },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              foregroundColor: const Color(0xff059669),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
            child: const Text('儲存'),
          ),
        ],
      ),
      body: FutureBuilder<List<Object?>>(
        future: Future.wait<Object?>([
          widget.api!.listManagedAccounts(accountType: AccountType.general),
          widget.api!.getAccountTransactionForm(
            transactionId: widget.transactionId,
            accountId: widget.accountId,
          ),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final accounts = (snapshot.data![0] as List<ManagedAccountSummary>)
              .where((a) => !a.detail.isArchived)
              .map((a) => a.detail)
              .toList();
          _availableAccounts = accounts;
          _initializeForm(
            (snapshot.data![1] as AccountTransactionFormData).existing,
            accounts,
          );
          if (accounts.isEmpty) return const Center(child: Text('尚未建立資料'));
          final amountCurrency = _currencyLabel(accounts, switch (_kind) {
            AccountTransactionFormKind.income => _target,
            AccountTransactionFormKind.expense => _source,
            AccountTransactionFormKind.transfer => _source,
          });
          final ids = accounts
              .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              _section('交易屬性', [
                _dropdownRow<AccountTransactionFormKind>(
                  label: '交易類型',
                  value: _kind,
                  items: AccountTransactionFormKind.values
                      .map(
                        (kind) => DropdownMenuItem(
                          value: kind,
                          child: Text(_kindLabel(kind)),
                        ),
                      )
                      .toList(),
                  onChanged: (kind) {
                    if (kind != null) _changeKind(kind);
                  },
                ),
                _textRow(
                  label: '交易日期與時間',
                  controller: _occurredAt,
                  suffixIcon: Icons.calendar_today_outlined,
                  readOnly: true,
                  onTap: _pickOccurredAt,
                ),
              ]),
              const SizedBox(height: 12),
              _section('帳戶關聯', [
                if (_kind != AccountTransactionFormKind.expense)
                  _dropdownRow<String>(
                    dropdownKey: const Key(
                      'account-transaction-target-account',
                    ),
                    label: '存入 / 目標帳戶',
                    value: _target,
                    items: ids,
                    onChanged: (id) => setState(() => _target = id),
                  ),
                if (_kind != AccountTransactionFormKind.income)
                  _dropdownRow<String>(
                    dropdownKey: const Key(
                      'account-transaction-source-account',
                    ),
                    label: '來源 / 對象帳戶',
                    value: _source,
                    items: ids,
                    onChanged: (id) => setState(() => _source = id),
                  ),
              ]),
              const SizedBox(height: 12),
              _section('金額與幣別設定', [
                _textRow(
                  label: _kind == AccountTransactionFormKind.transfer
                      ? '來源金額'
                      : '交易金額',
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [_amountInputFormatter],
                  prefixText: amountCurrency,
                ),
                if (_kind == AccountTransactionFormKind.transfer)
                  _textRow(
                    label: '目標金額',
                    controller: _targetAmount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_amountInputFormatter],
                    prefixText: _currencyLabel(accounts, _target),
                  ),
              ]),
              const SizedBox(height: 12),
              _section('備註與說明', [
                TextField(
                  controller: _note,
                  minLines: 1,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: '例如：從其他帳戶轉入生活備用金',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ]),
              if (widget.transactionId != null) _deleteButton(),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 6),
        child: Text(
          title,
          style: const TextStyle(
            color: Color(0xff94A3B8),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Card(
        margin: EdgeInsets.zero,
        elevation: 1,
        shadowColor: const Color(0x120F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xffEEF2F7)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: children
              .expand(
                (child) => [
                  child,
                  if (child != children.last) const Divider(height: 1),
                ],
              )
              .toList(),
        ),
      ),
    ],
  );

  Widget _dropdownRow<T>({
    Key? dropdownKey,
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => SizedBox(
    height: 56,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xff1E293B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                key: dropdownKey,
                value: value,
                hint: const Align(
                  alignment: Alignment.centerRight,
                  child: Text('請選擇'),
                ),
                items: items,
                selectedItemBuilder: (context) => items
                    .map(
                      (item) => Align(
                        alignment: Alignment.centerRight,
                        child: item.child,
                      ),
                    )
                    .toList(),
                onChanged: onChanged,
                isExpanded: true,
                alignment: Alignment.centerRight,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xff64748B),
                ),
                style: const TextStyle(
                  color: Color(0xff334155),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _textRow({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
    IconData? suffixIcon,
    bool readOnly = false,
    VoidCallback? onTap,
  }) => SizedBox(
    height: 56,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xff1E293B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              readOnly: readOnly,
              onTap: onTap,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xff334155),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                prefixText: prefixText == null ? null : '$prefixText ',
                prefixStyle: const TextStyle(color: Color(0xff94A3B8)),
                suffixIcon: suffixIcon == null
                    ? null
                    : Icon(
                        suffixIcon,
                        size: 18,
                        color: const Color(0xff64748B),
                      ),
                suffixIconConstraints: const BoxConstraints(minWidth: 28),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 17),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _deleteButton() => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: OutlinedButton.icon(
      onPressed: _saving ? null : _delete,
      icon: const Icon(Icons.delete_outline_rounded),
      label: const Text('刪除這筆交易紀錄'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: const Color(0xffF43F5E),
        side: const BorderSide(color: Color(0xffFDA4AF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );

  String? _currencyLabel(List<AccountDetail> accounts, String? id) {
    String? code;
    for (final account in accounts) {
      if (account.id == id) {
        code = account.currencyCode;
        break;
      }
    }
    return code == null ? null : (code == 'TWD' ? 'NT\$' : code);
  }

  String _kindLabel(AccountTransactionFormKind kind) => switch (kind) {
    AccountTransactionFormKind.income => '收入',
    AccountTransactionFormKind.expense => '支出',
    AccountTransactionFormKind.transfer => '轉帳',
  };
}
