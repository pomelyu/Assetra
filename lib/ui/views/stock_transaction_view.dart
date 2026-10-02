import 'package:flutter/material.dart';

import '../../data/data.dart';

enum StockTransactionFormKind { buy, sell, dividend }

class StockTransactionView extends StatefulWidget {
  final PortfolioDataApi? api;
  final String? transactionId, securityId, stockAccountId;
  final VoidCallback? onOpenSettings;

  const StockTransactionView({
    super.key,
    this.api,
    this.transactionId,
    this.securityId,
    this.stockAccountId,
    this.onOpenSettings,
  });

  @override
  State<StockTransactionView> createState() => _StockTransactionViewState();
}

class _StockTransactionViewState extends State<StockTransactionView> {
  final _name = TextEditingController();
  final _quantity = TextEditingController();
  final _price = TextEditingController();
  final _fee = TextEditingController(text: '0');
  final _dividend = TextEditingController();
  final _note = TextEditingController();
  final _securitySearch = TextEditingController();
  late final _occurredAt = TextEditingController(text: _nowText());
  late Future<({StockTransactionFormData form, List<AccountDetail> accounts})>
  _data;
  StockTransactionFormKind _kind = StockTransactionFormKind.buy;
  String? _securityId, _stockAccountId, _fundingAccountId;
  bool _initialized = false, _saving = false;
  List<SecurityOption>? _searchResults;
  List<SecurityOption>? _availableSecurities;
  List<AccountDetail>? _availableAccounts;
  final ValueNotifier<bool> _canSave = ValueNotifier(false);
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<({StockTransactionFormData form, List<AccountDetail> accounts})>
  _load() async {
    final api = widget.api;
    if (api == null) {
      return (
        form: const StockTransactionFormData(securities: []),
        accounts: <AccountDetail>[],
      );
    }
    final form = await api.getStockTransactionForm(
      transactionId: widget.transactionId,
    );
    final accounts = (await api.listManagedAccounts())
        .map((item) => item.detail)
        .toList();
    _availableSecurities = form.securities;
    _availableAccounts = accounts;
    _canSave.value =
        form.securities.any((item) => item.isActive) ||
        widget.transactionId != null;
    return (form: form, accounts: accounts);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _quantity,
      _price,
      _fee,
      _dividend,
      _note,
      _occurredAt,
      _securitySearch,
    ]) {
      controller.dispose();
    }
    _canSave.dispose();
    super.dispose();
  }

  String _nowText() {
    final value = DateTime.now();
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _search(String query) async {
    final api = widget.api;
    if (api == null) return;
    final generation = ++_searchGeneration;
    try {
      final results = await api.searchSecurities(query: query, limit: 200);
      if (mounted && generation == _searchGeneration) {
        setState(() => _searchResults = results);
      }
    } on Object catch (error) {
      _error('$error');
    }
  }

  void _initialize(StockTransactionInput? input, List<AccountDetail> accounts) {
    if (_initialized) return;
    _securityId = input?.securityId ?? widget.securityId;
    _stockAccountId = input?.stockAccountId ?? widget.stockAccountId;
    _fundingAccountId = input?.fundingAccountId;
    if (input != null) {
      _name.text = input.name ?? '';
      _occurredAt.text = input.occurredAt;
      _note.text = input.note ?? '';
      if (input is StockBuyInput) {
        _kind = StockTransactionFormKind.buy;
        _quantity.text = '${input.quantity.units}';
        _price.text = '${input.unitPrice.units}';
        _fee.text = '${input.fee.units}';
      } else if (input is StockSellInput) {
        _kind = StockTransactionFormKind.sell;
        _quantity.text = '${input.quantity.units}';
        _price.text = '${input.unitPrice.units}';
        _fee.text = '${input.fee.units}';
      } else if (input is StockDividendInput) {
        _kind = StockTransactionFormKind.dividend;
        _dividend.text = '${input.dividendAmount.units}';
      }
    } else if (_stockAccountId != null) {
      _fundingAccountId = accounts
          .where((account) => account.id == _stockAccountId)
          .firstOrNull
          ?.fundingAccountId;
    }
    _initialized = true;
  }

  Future<void> _save(
    List<SecurityOption> securities,
    List<AccountDetail> accounts,
  ) async {
    final api = widget.api;
    final security = securities
        .where((item) => item.id == _securityId)
        .firstOrNull;
    final stock = accounts
        .where((account) => account.id == _stockAccountId)
        .firstOrNull;
    if (api == null ||
        security == null ||
        stock == null ||
        _fundingAccountId == null ||
        _name.text.trim().length > 30) {
      _error(_name.text.trim().length > 30 ? '交易名稱不可超過 30 個字元' : '請完成所有必填欄位');
      return;
    }
    final quantity = double.tryParse(_quantity.text);
    final price = double.tryParse(_price.text);
    final fee = double.tryParse(_fee.text);
    final dividend = double.tryParse(_dividend.text);
    if ((_kind == StockTransactionFormKind.dividend &&
            (dividend == null || dividend <= 0)) ||
        (_kind != StockTransactionFormKind.dividend &&
            (quantity == null ||
                quantity <= 0 ||
                price == null ||
                price <= 0 ||
                fee == null ||
                fee < 0))) {
      _error('請輸入有效的正數金額與股數');
      return;
    }
    final common = (
      name: _name.text,
      occurredAt: _occurredAt.text,
      securityId: security.id,
      stockAccountId: stock.id,
      fundingAccountId: _fundingAccountId!,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    final input = switch (_kind) {
      StockTransactionFormKind.buy => StockBuyInput(
        name: common.name,
        occurredAt: common.occurredAt,
        securityId: common.securityId,
        stockAccountId: common.stockAccountId,
        fundingAccountId: common.fundingAccountId,
        note: common.note,
        quantity: ShareQuantity(units: quantity!),
        unitPrice: Money(currencyCode: stock.currencyCode, units: price!),
        fee: Money(currencyCode: stock.currencyCode, units: fee!),
      ),
      StockTransactionFormKind.sell => StockSellInput(
        name: common.name,
        occurredAt: common.occurredAt,
        securityId: common.securityId,
        stockAccountId: common.stockAccountId,
        fundingAccountId: common.fundingAccountId,
        note: common.note,
        quantity: ShareQuantity(units: quantity!),
        unitPrice: Money(currencyCode: stock.currencyCode, units: price!),
        fee: Money(currencyCode: stock.currencyCode, units: fee!),
      ),
      StockTransactionFormKind.dividend => StockDividendInput(
        name: common.name,
        occurredAt: common.occurredAt,
        securityId: common.securityId,
        stockAccountId: common.stockAccountId,
        fundingAccountId: common.fundingAccountId,
        note: common.note,
        dividendAmount: Money(
          currencyCode: stock.currencyCode,
          units: dividend!,
        ),
      ),
    };
    try {
      setState(() => _saving = true);
      if (widget.transactionId == null) {
        await api.createStockTransaction(input);
      } else {
        await api.updateStockTransaction(widget.transactionId!, input);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      _error('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.transactionId;
    if (id == null || widget.api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除交易'),
        content: const Text('確定刪除這筆交易？兩個帳戶的效果會一起回復。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api!.deleteStockTransaction(id);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      _error('$error');
    }
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _section({required String title, required List<Widget> children}) =>
      Column(
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
          Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: const InputDecorationTheme(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                labelStyle: TextStyle(
                  color: Color(0xff64748B),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            child: Card(
              margin: EdgeInsets.zero,
              elevation: 1,
              shadowColor: const Color(0x120F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: const BorderSide(color: Color(0xffEEF2F7)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: children.indexed
                    .expand(
                      (entry) => [
                        entry.$2,
                        if (entry.$1 < children.length - 1)
                          const Divider(height: 1),
                      ],
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xffF8FAFC),
    appBar: AppBar(
      centerTitle: true,
      title: Text(widget.transactionId == null ? '新增股票交易' : '編輯股票交易'),
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
        ValueListenableBuilder<bool>(
          valueListenable: _canSave,
          builder: (context, canSave, _) => TextButton(
            onPressed: _saving || !canSave
                ? null
                : () {
                    final securities = _availableSecurities;
                    final accounts = _availableAccounts;
                    if (securities != null && accounts != null) {
                      _save(securities, accounts);
                    }
                  },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              foregroundColor: const Color(0xff059669),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
            child: Text(_saving ? '儲存中…' : '儲存'),
          ),
        ),
      ],
    ),
    body:
        FutureBuilder<
          ({StockTransactionFormData form, List<AccountDetail> accounts})
        >(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            final data = snapshot.data!;
            _initialize(data.form.existing, data.accounts);
            final availableSecurities = _searchResults ?? data.form.securities;
            final selectedSecurity = data.form.securities
                .where((item) => item.id == _securityId)
                .firstOrNull;
            final securities = [
              if (selectedSecurity != null &&
                  !availableSecurities.any(
                    (item) => item.id == selectedSecurity.id,
                  ))
                selectedSecurity,
              ...availableSecurities,
            ];
            final security = securities
                .where((item) => item.id == _securityId)
                .firstOrNull;
            final stockAccounts = data.accounts
                .where(
                  (account) =>
                      !account.isArchived &&
                      account.accountType == AccountType.stock &&
                      (security == null ||
                          account.currencyCode == security.currencyCode),
                )
                .toList();
            final fundingAccounts = data.accounts
                .where(
                  (account) =>
                      !account.isArchived &&
                      account.accountType == AccountType.general &&
                      (security == null ||
                          account.currencyCode == security.currencyCode),
                )
                .toList();
            final noSecurities =
                securities.where((item) => item.isActive).isEmpty &&
                widget.transactionId == null;
            _availableSecurities = securities;
            _availableAccounts = data.accounts;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    TextField(
                      key: const Key('stock-transaction-name'),
                      controller: _name,
                      maxLength: 30,
                      decoration: const InputDecoration(
                        labelText: '交易名稱（選填）',
                        hintText: '未填寫時將依交易內容自動產生',
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      title: '股票',
                      children: [
                        if (widget.transactionId == null)
                          TextField(
                            key: const Key('stock-transaction-security-search'),
                            controller: _securitySearch,
                            decoration: const InputDecoration(
                              labelText: '搜尋股票代號或名稱',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: _search,
                          ),
                        DropdownButtonFormField<String>(
                          key: const Key('stock-transaction-security'),
                          initialValue: _securityId,
                          decoration: InputDecoration(
                            labelText: '股票',
                            hintText: noSecurities ? '無符合股票' : null,
                            prefixIcon: const Icon(Icons.show_chart),
                          ),
                          items: securities
                              .where(
                                (item) =>
                                    item.isActive || item.id == _securityId,
                              )
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.id,
                                  child: Text(
                                    '${item.marketCode == 'TW' ? item.name : item.symbol}${item.isActive ? '' : '（已停用）'}',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged:
                              noSecurities || widget.transactionId != null
                              ? null
                              : (value) => setState(() {
                                  _securityId = value;
                                  _stockAccountId = null;
                                  _fundingAccountId = null;
                                }),
                        ),
                        if (noSecurities)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: widget.onOpenSettings,
                              icon: const Icon(Icons.settings_outlined),
                              label: const Text('前往設定更新股票代號'),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _section(
                      title: '帳戶關聯',
                      children: [
                        DropdownButtonFormField<String>(
                          key: const Key('stock-transaction-stock-account'),
                          initialValue:
                              stockAccounts.any(
                                (item) => item.id == _stockAccountId,
                              )
                              ? _stockAccountId
                              : null,
                          decoration: InputDecoration(
                            labelText: '股票帳戶',
                            hintText: stockAccounts.isEmpty ? '無符合帳戶' : null,
                            prefixIcon: const Icon(
                              Icons.account_balance_wallet_outlined,
                            ),
                          ),
                          items: stockAccounts
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.id,
                                  child: Text(item.name),
                                ),
                              )
                              .toList(),
                          onChanged: stockAccounts.isEmpty
                              ? null
                              : (value) => setState(() {
                                  _stockAccountId = value;
                                  _fundingAccountId = stockAccounts
                                      .where((item) => item.id == value)
                                      .firstOrNull
                                      ?.fundingAccountId;
                                }),
                        ),
                        DropdownButtonFormField<String>(
                          key: const Key('stock-transaction-funding-account'),
                          initialValue:
                              fundingAccounts.any(
                                (item) => item.id == _fundingAccountId,
                              )
                              ? _fundingAccountId
                              : null,
                          decoration: InputDecoration(
                            labelText: '資金來源',
                            hintText: fundingAccounts.isEmpty ? '無符合帳戶' : null,
                            prefixIcon: const Icon(Icons.payments_outlined),
                          ),
                          items: fundingAccounts
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.id,
                                  child: Text(item.name),
                                ),
                              )
                              .toList(),
                          onChanged: fundingAccounts.isEmpty
                              ? null
                              : (value) =>
                                    setState(() => _fundingAccountId = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _section(
                      title: '交易屬性',
                      children: [
                        DropdownButtonFormField<StockTransactionFormKind>(
                          key: const Key('stock-transaction-kind'),
                          initialValue: _kind,
                          decoration: const InputDecoration(
                            labelText: '交易類型',
                            prefixIcon: Icon(Icons.swap_vert),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: StockTransactionFormKind.buy,
                              child: Text('投資買入'),
                            ),
                            DropdownMenuItem(
                              value: StockTransactionFormKind.sell,
                              child: Text('投資賣出'),
                            ),
                            DropdownMenuItem(
                              value: StockTransactionFormKind.dividend,
                              child: Text('股息'),
                            ),
                          ],
                          onChanged: widget.transactionId == null
                              ? (value) => setState(() => _kind = value!)
                              : null,
                        ),
                        TextField(
                          controller: _occurredAt,
                          decoration: const InputDecoration(
                            labelText: '交易時間（台北）',
                            prefixIcon: Icon(Icons.schedule),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _section(
                      title: '財務數值',
                      children: [
                        if (_kind == StockTransactionFormKind.dividend)
                          TextField(
                            key: const Key('stock-transaction-dividend'),
                            controller: _dividend,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '股息金額',
                              prefixIcon: Icon(Icons.savings_outlined),
                            ),
                          )
                        else ...[
                          TextField(
                            key: const Key('stock-transaction-quantity'),
                            controller: _quantity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '股數',
                              prefixIcon: Icon(Icons.numbers),
                            ),
                          ),
                          TextField(
                            key: const Key('stock-transaction-price'),
                            controller: _price,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '每股價格',
                              prefixIcon: Icon(Icons.attach_money),
                            ),
                          ),
                          TextField(
                            key: const Key('stock-transaction-fee'),
                            controller: _fee,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '手續費與稅',
                              prefixIcon: Icon(Icons.receipt_long_outlined),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    _section(
                      title: '備註',
                      children: [
                        TextField(
                          controller: _note,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: '備註（選填）',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                    if (widget.transactionId != null) ...[
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _delete,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('刪除這筆交易紀錄'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: const Color(0xffF43F5E),
                          side: const BorderSide(color: Color(0xffFDA4AF)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
  );
}
