import 'package:flutter/material.dart';

import '../../data/data.dart';

class AccountManagerView extends StatefulWidget {
  final PortfolioDataApi? api;
  final Future<void> Function(AccountType accountType) onCreateAccount;
  final Future<void> Function(String accountId, AccountType accountType)
  onEditAccount;

  const AccountManagerView({
    super.key,
    this.api,
    required this.onCreateAccount,
    required this.onEditAccount,
  });

  @override
  State<AccountManagerView> createState() => _AccountManagerViewState();
}

class _AccountManagerViewState extends State<AccountManagerView> {
  late Future<_ManagedAccountsData> _accounts;

  @override
  void initState() {
    super.initState();
    _accounts = _load();
  }

  Future<_ManagedAccountsData> _load() async {
    final api = widget.api;
    if (api == null) return const _ManagedAccountsData([], {}, {});
    final allAccounts = await api.listManagedAccounts();
    final accounts = allAccounts
        .where((account) => account.detail.accountType != AccountType.stock)
        .toList();
    final categoryNames = {
      for (final category in await api.listCategories())
        category.id: category.name,
    };
    final accountNames = {
      for (final account in allAccounts) account.detail.id: account.detail.name,
    };
    return _ManagedAccountsData(accounts, categoryNames, accountNames);
  }

  void _refresh() {
    setState(() {
      _accounts = _load();
    });
  }

  void _showError(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('帳戶管理')),
      body: FutureBuilder<_ManagedAccountsData>(
        future: _accounts,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? const _ManagedAccountsData([], {}, {});
          final accounts = data.accounts;
          if (accounts.isEmpty) return const Center(child: Text('尚未建立資料'));
          final active = accounts.where((a) => !a.detail.isArchived);
          final archived = accounts.where((a) => a.detail.isArchived);
          Widget section(
            String label,
            Iterable<ManagedAccountSummary> rows,
          ) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 10),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text('尚未建立資料'),
                ),
              ...rows.map(
                (account) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      title: Text(account.detail.name),
                      subtitle: Text(
                        [
                          _accountTypeLabel(account.detail.accountType),
                          data.categoryNames[account.detail.categoryId] ??
                              account.detail.categoryId,
                          account.detail.currencyCode,
                          account.detail.isArchived ? '已封存' : '使用中',
                          if (account.detail.fundingAccountId != null)
                            '資金來源：${data.accountNames[account.detail.fundingAccountId] ?? account.detail.fundingAccountId}',
                        ].join(' · '),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          account.detail.isArchived
                              ? Icons.unarchive
                              : Icons.archive,
                        ),
                        tooltip: account.detail.isArchived ? '重新啟用' : '封存',
                        onPressed: () async {
                          try {
                            if (account.detail.isArchived) {
                              await widget.api?.reactivateAccount(
                                account.detail.id,
                              );
                            } else {
                              await widget.api?.archiveAccount(
                                account.detail.id,
                              );
                            }
                            _refresh();
                          } on Object catch (error) {
                            _showError(error);
                          }
                        },
                      ),
                      onTap: account.detail.isArchived
                          ? null
                          : () async {
                              await widget.onEditAccount(
                                account.detail.id,
                                account.detail.accountType,
                              );
                              _refresh();
                            },
                    ),
                  ),
                ),
              ),
            ],
          );
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [section('使用中', active), section('已封存', archived)],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('account-manager-add-account'),
        onPressed: () async {
          final accountType = await showModalBottomSheet<AccountType>(
            context: context,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(title: Text('選擇帳戶類型')),
                  ListTile(
                    title: const Text('一般帳戶'),
                    onTap: () => Navigator.of(context).pop(AccountType.general),
                  ),
                  ListTile(
                    title: const Text('投資帳戶'),
                    onTap: () =>
                        Navigator.of(context).pop(AccountType.investment),
                  ),
                ],
              ),
            ),
          );
          if (accountType == null) return;
          await widget.onCreateAccount(accountType);
          _refresh();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  String _accountTypeLabel(AccountType type) => switch (type) {
    AccountType.general => '一般帳戶',
    AccountType.investment => '投資帳戶',
    AccountType.stock => '股票帳戶',
  };
}

class _ManagedAccountsData {
  final List<ManagedAccountSummary> accounts;
  final Map<String, String> categoryNames;
  final Map<String, String> accountNames;

  const _ManagedAccountsData(
    this.accounts,
    this.categoryNames,
    this.accountNames,
  );
}
