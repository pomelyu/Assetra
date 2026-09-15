import 'package:flutter/material.dart';

import '../../data/data.dart';

class AccountEditView extends StatefulWidget {
  final PortfolioDataApi? api;
  final String? accountId;

  const AccountEditView({super.key, this.api, this.accountId});

  @override
  State<AccountEditView> createState() => _AccountEditViewState();
}

class _AccountEditViewState extends State<AccountEditView> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cost = TextEditingController(text: '0');
  final _value = TextEditingController(text: '0');
  final _note = TextEditingController();
  String? _categoryId;
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
    if (!_formKey.currentState!.validate() || _categoryId == null) return;
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
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (widget.accountId == null) {
        await api.createAccount(
          CreateAccountInput(
            name: input.name,
            categoryId: input.categoryId,
            currencyCode: input.currencyCode,
            initialCost: input.initialCost,
            initialValue: input.initialValue,
            note: input.note,
          ),
        );
      } else {
        await api.updateAccount(widget.accountId!, input);
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

  Future<void> _archive() async {
    if (widget.api == null || widget.accountId == null) return;
    try {
      await widget.api!.archiveAccount(widget.accountId!);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.accountId == null ? '新增一般帳戶' : '編輯帳戶'),
        leading: TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('儲存'),
          ),
        ],
      ),
      body: FutureBuilder<AccountEditorData>(
        future: widget.api?.getAccountEditor(accountId: widget.accountId),
        builder: (context, snapshot) {
          final categories =
              snapshot.data?.categories ?? const <CategorySummary>[];
          if (widget.api != null &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!_initialized) {
            final existing = snapshot.data?.existing;
            _categoryId =
                existing?.categoryId ??
                (categories.isEmpty ? null : categories.first.id);
            _currency = existing?.currencyCode ?? _currency;
            _name.text = existing?.name ?? _name.text;
            _cost.text =
                snapshot.data?.initialCost?.units.toString() ?? _cost.text;
            _value.text =
                snapshot.data?.initialValue?.units.toString() ?? _value.text;
            _note.text = snapshot.data?.note ?? _note.text;
            _initialized = true;
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
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '必填' : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: '帳戶分類'),
                    items: categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(labelText: '幣別'),
                    items: const ['TWD', 'USD', 'JPY', 'EUR']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _currency = v!),
                  ),
                ]),
                const SizedBox(height: 16),
                _section(context, '初始數值', [
                  TextFormField(
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '初始成本'),
                    validator: (v) =>
                        double.tryParse(v ?? '') == null ? '請輸入金額' : null,
                  ),
                  TextFormField(
                    controller: _value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: '初始價值'),
                    validator: (v) =>
                        double.tryParse(v ?? '') == null ? '請輸入金額' : null,
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
                  onPressed: _saving ? null : _save,
                  child: const Text('儲存'),
                ),
                if (widget.accountId != null)
                  TextButton(onPressed: _archive, child: const Text('封存此帳戶')),
              ],
            ),
          );
        },
      ),
    );
  }

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
