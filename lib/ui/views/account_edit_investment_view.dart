import 'package:flutter/material.dart';

import '../../data/data.dart';

class AccountEditInvestmentView extends StatefulWidget {
  final PortfolioDataApi? api;
  final String? accountId;

  const AccountEditInvestmentView({super.key, this.api, this.accountId});

  @override
  State<AccountEditInvestmentView> createState() =>
      _AccountEditInvestmentViewState();
}

class _AccountEditInvestmentViewState extends State<AccountEditInvestmentView> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cost = TextEditingController(text: '0');
  final _value = TextEditingController(text: '0');
  final _note = TextEditingController();
  String? _categoryId;
  String? _fundingAccountId;
  String _currency = 'TWD';
  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _name.dispose();
    _cost.dispose();
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        _categoryId == null ||
        _fundingAccountId == null) {
      return;
    }
    final api = widget.api;
    if (api == null) return;
    setState(() => _saving = true);
    try {
      final input = UpdateAccountInput(
        name: _name.text.trim(),
        categoryId: _categoryId!,
        currencyCode: _currency,
        initialCost: double.parse(_cost.text),
        initialValue: double.parse(_value.text),
        fundingAccountId: _fundingAccountId,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (widget.accountId == null) {
        await api.createInvestmentAccount(
          CreateInvestmentAccountInput(
            name: input.name,
            categoryId: input.categoryId,
            currencyCode: input.currencyCode,
            initialCost: input.initialCost,
            initialValue: input.initialValue,
            accountType: AccountType.investment,
            fundingAccountId: _fundingAccountId!,
            note: input.note,
          ),
        );
      } else {
        await api.updateInvestmentAccount(widget.accountId!, input);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.accountId == null ? '新增投資帳戶' : '編輯投資帳戶'),
        leading: TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        actions: [
          TextButton(
            key: const Key('investment-account-save'),
            onPressed: _saving || _fundingAccountId == null ? null : _save,
            child: const Text('儲存'),
          ),
        ],
      ),
      body: FutureBuilder<InvestmentAccountEditorData>(
        future: widget.api?.getInvestmentAccountEditor(
          accountId: widget.accountId,
          createAccountType: widget.accountId == null
              ? AccountType.investment
              : null,
        ),
        builder: (context, snapshot) {
          if (widget.api != null &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          final categories = data?.categories ?? const <CategorySummary>[];
          if (!_initialized) {
            final existing = data?.existing;
            _categoryId =
                existing?.categoryId ??
                (categories.isEmpty ? null : categories.first.id);
            _currency = existing?.currencyCode ?? _currency;
            _fundingAccountId = existing?.fundingAccountId;
            _name.text = existing?.name ?? _name.text;
            _cost.text = data?.initialCost?.units.toString() ?? _cost.text;
            _value.text = data?.initialValue?.units.toString() ?? _value.text;
            _note.text = data?.note ?? _note.text;
            _initialized = true;
          }
          final fundingAccounts =
              (data?.fundingAccounts ?? const <AccountDetail>[])
                  .where((account) => account.currencyCode == _currency)
                  .toList();
          if (!fundingAccounts.any(
            (account) => account.id == _fundingAccountId,
          )) {
            _fundingAccountId = null;
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _section(context, '基本資訊', [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: '帳戶名稱'),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? '必填' : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: '帳戶分類'),
                    items: categories
                        .map(
                          (category) => DropdownMenuItem(
                            value: category.id,
                            child: Text(category.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _categoryId = value),
                  ),
                  DropdownButtonFormField<String>(
                    key: const Key('investment-account-currency'),
                    initialValue: _currency,
                    decoration: const InputDecoration(labelText: '幣別'),
                    items: const ['TWD', 'USD', 'JPY', 'EUR']
                        .map(
                          (currency) => DropdownMenuItem(
                            value: currency,
                            child: Text(currency),
                          ),
                        )
                        .toList(),
                    onChanged: widget.accountId != null
                        ? null
                        : (value) {
                            setState(() {
                              _currency = value!;
                              _fundingAccountId = null;
                            });
                          },
                  ),
                  DropdownButtonFormField<String>(
                    key: const Key('investment-account-funding-account'),
                    initialValue: _fundingAccountId,
                    decoration: InputDecoration(
                      labelText: '資金來源',
                      hintText: fundingAccounts.isEmpty ? '無符合帳戶' : null,
                    ),
                    items: fundingAccounts
                        .map(
                          (account) => DropdownMenuItem(
                            value: account.id,
                            child: Text(account.name),
                          ),
                        )
                        .toList(),
                    onChanged: fundingAccounts.isEmpty
                        ? null
                        : (value) => setState(() => _fundingAccountId = value),
                    validator: (value) => value == null ? '必填' : null,
                  ),
                ]),
                const SizedBox(height: 16),
                _section(context, '初始數值', [
                  TextFormField(
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: '初始成本'),
                    validator: _moneyValidator,
                  ),
                  TextFormField(
                    controller: _value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: '初始價值'),
                    validator: _moneyValidator,
                  ),
                ]),
                const SizedBox(height: 16),
                _section(context, '備註', [
                  TextFormField(
                    controller: _note,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: '選填'),
                  ),
                ]),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving || _fundingAccountId == null
                      ? null
                      : _save,
                  child: const Text('儲存'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String? _moneyValidator(String? value) =>
      double.tryParse(value ?? '') == null ? '請輸入金額' : null;

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xff94A3B8),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:
                    children
                        .expand((child) => [child, const SizedBox(height: 12)])
                        .toList()
                      ..removeLast(),
              ),
            ),
          ),
        ],
      );
}
