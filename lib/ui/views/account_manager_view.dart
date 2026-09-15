import 'package:flutter/material.dart';

import '../../data/data.dart';

class AccountManagerView extends StatefulWidget {
  final PortfolioDataApi? api;
  final Future<void> Function() onCreateAccount;
  final Future<void> Function(String accountId) onEditAccount;

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
  late Future<List<ManagedAccountSummary>> _accounts;

  @override
  void initState() {
    super.initState();
    _accounts = _load();
  }

  Future<List<ManagedAccountSummary>> _load() async {
    final api = widget.api;
    if (api == null) return [];
    return (await api.listManagedAccounts(accountType: AccountType.general));
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
      body: FutureBuilder<List<ManagedAccountSummary>>(
        future: _accounts,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final accounts = snapshot.data ?? [];
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
                        '${account.detail.currencyCode} · ${account.detail.isArchived ? '已封存' : '使用中'}',
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
                              await widget.onEditAccount(account.detail.id);
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
          await widget.onCreateAccount();
          _refresh();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
